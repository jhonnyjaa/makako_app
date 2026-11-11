import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'sticker_service.dart';
import 'sticker_widgets.dart';

/// Video -> trim (<= 8 s) -> square crop / fit -> captions -> animated WebP sticker.
class VideoStickerEditor extends StatefulWidget {
  const VideoStickerEditor({super.key, required this.pack, required this.service});

  final StickerPack pack;
  final StickerService service;

  @override
  State<VideoStickerEditor> createState() => _VideoStickerEditorState();
}

class _VideoStickerEditorState extends State<VideoStickerEditor> {
  final _textKey = GlobalKey();
  final _busy = ValueNotifier<String?>(null);
  VideoPlayerController? _video;
  String? _path;

  RangeValues _range = const RangeValues(0, 3);
  VideoFit _fit = VideoFit.crop;
  double _align = 0.5;
  String _emoji = '😂';
  final List<StickerText> _texts = [];

  double get _durationSec => (_video?.value.duration.inMilliseconds ?? 0) / 1000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _video?.removeListener(_loop);
    _video?.dispose();
    _busy.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    if (file == null) {
      if (mounted && _video == null) Navigator.pop(context);
      return;
    }
    final old = _video;
    old?.removeListener(_loop);
    final c = VideoPlayerController.file(File(file.path));
    await c.initialize();
    await c.setVolume(0);
    await c.setLooping(false);
    c.addListener(_loop);
    await c.play();
    if (!mounted) return c.dispose();
    setState(() {
      _video = c;
      _path = file.path;
      final d = c.value.duration.inMilliseconds / 1000;
      _range = RangeValues(0, math.min(3, d));
    });
    await old?.dispose();
  }

  /// Keeps playback looping inside the selected range.
  void _loop() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position.inMilliseconds / 1000;
    if (pos >= _range.end || pos < _range.start - 0.3 || c.value.isCompleted) {
      c.seekTo(Duration(milliseconds: (_range.start * 1000).round()));
      if (!c.value.isPlaying) c.play();
    }
  }

  void _onRange(RangeValues v) {
    var start = v.start;
    var end = v.end;
    const maxLen = StickerService.maxAnimatedSeconds;
    if (end - start > maxLen) {
      // Keep the window at most 8 s, moving whichever thumb wasn't dragged.
      if ((start - _range.start).abs() > (end - _range.end).abs()) {
        end = start + maxLen;
      } else {
        start = end - maxLen;
      }
    }
    if (end - start < 0.5) return;
    setState(() => _range = RangeValues(start, end));
    _video?.seekTo(Duration(milliseconds: (start * 1000).round()));
  }

  Future<void> _save() async {
    final c = _video;
    if (c == null || _path == null) return;
    await c.pause();
    _busy.value = 'Preparando…';
    try {
      final overlay = _texts.isEmpty ? null : await captureBoundary512(_textKey);
      await widget.service.addAnimatedSticker(
        widget.pack,
        videoPath: _path!,
        start: Duration(milliseconds: (_range.start * 1000).round()),
        duration: Duration(milliseconds: ((_range.end - _range.start) * 1000).round()),
        videoSize: c.value.size,
        fit: _fit,
        cropAlign: _align,
        emoji: _emoji,
        overlayPng: overlay,
        onStatus: (s) => _busy.value = s,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, '$e');
      await c.play();
    } finally {
      _busy.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _video;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(context)),
        title: const Text('Sticker animado'),
        actions: [
          if (c != null)
            TextButton(
              onPressed: _save,
              child: const Text('Crear', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (c == null) const Center(child: CupertinoActivityIndicator()) else _buildEditor(c),
          BusyOverlay(status: _busy),
        ],
      ),
    );
  }

  Widget _buildEditor(VideoPlayerController c) {
    final size = c.value.size;
    final landscape = size.width >= size.height;
    final alignment = landscape ? Alignment(_align * 2 - 1, 0) : Alignment(0, _align * 2 - 1);
    final len = _range.end - _range.start;

    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    // Drag to choose which part of the video stays in the square.
                    onPanUpdate: _fit == VideoFit.crop
                        ? (d) {
                            final delta = landscape ? -d.delta.dx : -d.delta.dy;
                            setState(() => _align = (_align + delta / box.maxWidth).clamp(0.0, 1.0));
                          }
                        : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const Checkerboard(),
                          FittedBox(
                            fit: _fit == VideoFit.crop ? BoxFit.cover : BoxFit.contain,
                            alignment: alignment,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(c)),
                          ),
                          RepaintBoundary(
                            key: _textKey,
                            child: StickerTextLayer(
                              items: _texts,
                              onChanged: () {},
                              onTapItem: (t) async {
                                await editStickerText(context, existing: t);
                                setState(() {
                                  if (t.text.trim().isEmpty) _texts.remove(t);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_fit == VideoFit.crop)
          const Center(
            child: Text(
              'Arrastra el video para encuadrar',
              style: TextStyle(color: AppColors.inkSecondary, fontSize: 12),
            ),
          ),
        const _Label('Fragmento'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: RangeSlider(
            min: 0,
            max: math.max(_durationSec, 0.5),
            values: RangeValues(
              _range.start.clamp(0, _durationSec),
              _range.end.clamp(0, math.max(_durationSec, 0.5)),
            ),
            activeColor: AppColors.accent,
            inactiveColor: AppColors.accentSoft,
            onChanged: _onRange,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text('${_range.start.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 12)),
              const Spacer(),
              Text(
                '${len.toStringAsFixed(1)}s de máx. ${StickerService.maxAnimatedSeconds.toStringAsFixed(0)}s',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const Spacer(),
              Text('${_range.end.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const _Label('Encuadre'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: CupertinoSlidingSegmentedControl<VideoFit>(
            groupValue: _fit,
            onValueChanged: (v) => setState(() => _fit = v ?? VideoFit.crop),
            children: const {
              VideoFit.crop: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Recortar cuadrado')),
              VideoFit.contain: Text('Ajustar completo'),
            },
          ),
        ),
        const _Label('Texto'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  final t = await editStickerText(context);
                  if (t != null && t.text.trim().isNotEmpty) setState(() => _texts.add(t));
                },
                icon: const Icon(CupertinoIcons.textformat),
                label: const Text('Añadir texto'),
              ),
              const Spacer(),
              TextButton.icon(onPressed: _pick, icon: const Icon(CupertinoIcons.film), label: const Text('Otro video')),
            ],
          ),
        ),
        const _Label('Emoji'),
        EmojiPicker(selected: _emoji, onSelected: (e) => setState(() => _emoji = e)),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.inkSecondary),
    ),
  );
}
