import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/app_paths.dart';
import '../../data/database.dart';
import '../../data/models.dart';

class StickerException implements Exception {
  StickerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// How a non-square video is fitted into the 512x512 sticker.
enum VideoFit { crop, contain }

/// Builds WhatsApp-compliant stickers:
/// - static: 512x512 WebP, <= 100 KB
/// - animated: 512x512 animated WebP, <= 500 KB, <= 10 s
/// - tray icon: 96x96 PNG, <= 50 KB
/// and publishes them to the native StickerContentProvider via `contents.json`.
class StickerService {
  StickerService(this.db);

  final AppDatabase db;
  static const _uuid = Uuid();
  static const _channel = MethodChannel('makako/whatsapp_stickers');

  static const staticMaxBytes = 100 * 1024;
  static const animatedMaxBytes = 500 * 1024;
  static const maxAnimatedSeconds = 8.0;

  String _packDir(String packId) => 'stickers/$packId';

  Future<StickerPack> createPack(String name, {required bool animated}) async {
    final id = _uuid.v4().replaceAll('-', '');
    final pack = StickerPack(
      id: id,
      name: name.trim().isEmpty ? 'Makako pack' : name.trim(),
      publisher: 'Makako',
      animated: animated,
      trayPath: null,
      version: 1,
      createdAt: DateTime.now(),
    );
    await Directory(AppPaths.abs(_packDir(id))).create(recursive: true);
    await db.insertPack(pack);
    await syncContents();
    return pack;
  }

  Future<void> deletePack(StickerPack pack) async {
    await db.deletePack(pack.id);
    final dir = Directory(AppPaths.abs(_packDir(pack.id)));
    if (await dir.exists()) await dir.delete(recursive: true);
    await syncContents();
  }

  Future<void> deleteSticker(StickerPack pack, Sticker sticker) async {
    await db.deleteSticker(sticker.id);
    final f = AppPaths.file(sticker.filePath);
    if (await f.exists()) await f.delete();
    await db.updatePack(pack.id);
    await syncContents();
  }

  // ---------------------------------------------------------------- static

  /// [png] must be a 512x512 PNG (transparency allowed).
  Future<void> addStaticSticker(StickerPack pack, Uint8List png, String emoji) async {
    if (pack.stickers.length >= StickerPack.maxStickers) throw StickerException('El pack ya tiene 30 stickers');
    final tmp = await _tmpFile('png');
    await tmp.writeAsBytes(png);
    final stickerId = _uuid.v4().replaceAll('-', '');
    final rel = '${_packDir(pack.id)}/$stickerId.webp';
    final out = AppPaths.abs(rel);

    var ok = false;
    for (final q in const [90, 75, 60, 45, 30, 20]) {
      await _run(['-y', '-i', tmp.path, '-vf', 'scale=512:512', '-c:v', 'libwebp', '-lossless', '0', '-q:v', '$q', '-frames:v', '1', out]);
      final f = File(out);
      if (await f.exists() && await f.length() <= staticMaxBytes) {
        ok = true;
        break;
      }
    }
    if (!ok) throw StickerException('No se pudo comprimir el sticker por debajo de 100 KB');

    await _ensureTray(pack, tmp.path, []);
    await db.insertSticker(Sticker(id: stickerId, packId: pack.id, filePath: rel, emoji: emoji));
    await db.updatePack(pack.id);
    await syncContents();
    await tmp.delete();
  }

  // -------------------------------------------------------------- animated

  /// Converts a video segment into an animated sticker.
  /// [cropAlign] 0..1 positions the square crop along the long side.
  /// [overlayPng] is an optional 512x512 transparent PNG (text layer).
  Future<void> addAnimatedSticker(
    StickerPack pack, {
    required String videoPath,
    required Duration start,
    required Duration duration,
    required Size videoSize,
    required VideoFit fit,
    required double cropAlign,
    required String emoji,
    Uint8List? overlayPng,
    void Function(String status)? onStatus,
  }) async {
    if (pack.stickers.length >= StickerPack.maxStickers) throw StickerException('El pack ya tiene 30 stickers');
    final secs = (duration.inMilliseconds / 1000).clamp(0.5, maxAnimatedSeconds);
    final ss = (start.inMilliseconds / 1000).toStringAsFixed(3);
    final t = secs.toStringAsFixed(3);

    String geometry;
    if (fit == VideoFit.crop) {
      final w = videoSize.width.round();
      final h = videoSize.height.round();
      final side = w < h ? w : h;
      final x = w > h ? ((w - side) * cropAlign).round() : 0;
      final y = h > w ? ((h - side) * cropAlign).round() : 0;
      geometry = 'crop=$side:$side:$x:$y,scale=512:512:flags=lanczos';
    } else {
      geometry =
          'scale=512:512:force_original_aspect_ratio=decrease:flags=lanczos,format=rgba,'
          'pad=512:512:(ow-iw)/2:(oh-ih)/2:color=black@0';
    }

    File? overlay;
    if (overlayPng != null) {
      overlay = await _tmpFile('png');
      await overlay.writeAsBytes(overlayPng);
    }

    final stickerId = _uuid.v4().replaceAll('-', '');
    final rel = '${_packDir(pack.id)}/$stickerId.webp';
    final out = AppPaths.abs(rel);

    var ok = false;
    // Try progressively cheaper encodings until we fit WhatsApp's 500 KB limit.
    const attempts = [(15, 70), (15, 50), (12, 40), (10, 30), (10, 20), (8, 15)];
    for (final (fps, q) in attempts) {
      onStatus?.call('Codificando ($fps fps, calidad $q)…');
      final filter = overlay == null
          ? '[0:v]fps=$fps,$geometry,format=yuva420p[out]'
          : '[0:v]fps=$fps,$geometry,format=rgba[v];[v][1:v]overlay=0:0,format=yuva420p[out]';
      final args = [
        '-y', '-ss', ss, '-t', t, '-i', videoPath,
        if (overlay != null) ...['-i', overlay.path],
        '-filter_complex', filter, '-map', '[out]',
        '-c:v', 'libwebp_anim', '-lossless', '0', '-q:v', '$q', '-compression_level', '6',
        '-loop', '0', '-an', out,
      ];
      final success = await _run(args, throwOnError: false);
      final f = File(out);
      if (success && await f.exists() && await f.length() <= animatedMaxBytes) {
        ok = true;
        break;
      }
    }
    if (!ok) throw StickerException('El sticker animado supera 500 KB. Prueba un fragmento más corto.');

    // Tray icon from the first frame of the segment.
    final frame = await _tmpFile('png');
    await _run(['-y', '-ss', ss, '-i', videoPath, '-frames:v', '1', '-vf', geometry, frame.path]);
    await _ensureTray(pack, frame.path, overlay == null ? [] : [overlay.path]);

    await db.insertSticker(Sticker(id: stickerId, packId: pack.id, filePath: rel, emoji: emoji));
    await db.updatePack(pack.id);
    await syncContents();
    await frame.delete();
    await overlay?.delete();
  }

  // --------------------------------------------------------------- helpers

  Future<void> _ensureTray(StickerPack pack, String sourcePng, List<String> overlays) async {
    if (pack.trayPath != null && AppPaths.file(pack.trayPath!).existsSync()) return;
    final rel = '${_packDir(pack.id)}/tray.png';
    final args = overlays.isEmpty
        ? ['-y', '-i', sourcePng, '-vf', 'scale=96:96', AppPaths.abs(rel)]
        : [
            '-y', '-i', sourcePng, '-i', overlays.first,
            '-filter_complex', '[0:v]scale=512:512[b];[b][1:v]overlay=0:0,scale=96:96',
            AppPaths.abs(rel),
          ];
    await _run(args);
    await db.updatePack(pack.id, trayPath: rel, bumpVersion: false);
  }

  Future<File> _tmpFile(String ext) async {
    final dir = await getTemporaryDirectory();
    return File(p.join(dir.path, 'stk_${_uuid.v4()}.$ext'));
  }

  Future<bool> _run(List<String> args, {bool throwOnError = true}) async {
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) return true;
    final logs = await session.getAllLogsAsString();
    debugPrint('ffmpeg failed (${rc?.getValue()}): ${args.join(' ')}\n$logs');
    if (throwOnError) throw StickerException('Error procesando el archivo (ffmpeg ${rc?.getValue()})');
    return false;
  }

  /// Writes the manifest read by the Android StickerContentProvider.
  Future<void> syncContents() async {
    final packs = await db.stickerPacks();
    final json = {
      'android_play_store_link': '',
      'ios_app_store_link': '',
      'sticker_packs': [
        for (final pk in packs)
          if (pk.trayPath != null)
            {
              'identifier': pk.id,
              'name': pk.name,
              'publisher': pk.publisher,
              'tray_image_file': p.basename(pk.trayPath!),
              'image_data_version': '${pk.version}',
              'avoid_cache': false,
              'animated_sticker_pack': pk.animated,
              'stickers': [
                for (final s in pk.stickers)
                  {
                    'image_file': p.basename(s.filePath),
                    'emojis': [s.emoji],
                    'accessibility_text': '${pk.name} sticker',
                  },
              ],
            },
      ],
    };
    await AppPaths.file('stickers/contents.json').writeAsString(jsonEncode(json));
  }

  // -------------------------------------------------------------- WhatsApp

  static Future<bool> isWhatsAppInstalled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isWhatsAppInstalled') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns 'added', 'cancelled' or throws [StickerException].
  Future<String> addToWhatsApp(StickerPack pack) async {
    if (!Platform.isAndroid) {
      throw StickerException('Añadir a WhatsApp está disponible en Android');
    }
    if (pack.stickers.length < StickerPack.minStickers) {
      throw StickerException('WhatsApp necesita al menos 3 stickers en el pack');
    }
    await syncContents();
    try {
      final r = await _channel.invokeMethod<String>('addStickerPack', {'identifier': pack.id, 'name': pack.name});
      return r ?? 'cancelled';
    } on PlatformException catch (e) {
      throw StickerException(e.message ?? e.code);
    }
  }
}
