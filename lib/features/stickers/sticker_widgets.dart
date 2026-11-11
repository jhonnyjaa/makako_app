import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/theme.dart';

/// A movable / scalable caption on top of a sticker.
class StickerText {
  StickerText({required this.text, this.pos = const Offset(0.5, 0.82), this.scale = 1, this.color = Colors.white});

  String text;

  /// Center, normalized 0..1 in the 512x512 canvas.
  Offset pos;
  double scale;
  Color color;
}

const stickerTextColors = [
  Colors.white,
  Colors.black,
  Color(0xFFFFD60A),
  AppColors.accent,
  Color(0xFF30D158),
  Color(0xFF0A84FF),
  Color(0xFFFF375F),
];

const stickerEmojis = ['😀', '😂', '😍', '🤔', '😎', '👍', '🔥', '💯', '🎉', '😭', '🙏', '❤️', '🐒', '🤯', '😴', '💻'];

/// Renders and lets the user drag / pinch the captions.
/// Sizes are expressed relative to a 512 px canvas so the export matches the preview.
class StickerTextLayer extends StatefulWidget {
  const StickerTextLayer({super.key, required this.items, required this.onChanged, this.onTapItem});

  final List<StickerText> items;
  final VoidCallback onChanged;
  final ValueChanged<StickerText>? onTapItem;

  @override
  State<StickerTextLayer> createState() => _StickerTextLayerState();
}

class _StickerTextLayerState extends State<StickerTextLayer> {
  double _startScale = 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth;
        final unit = side / 512;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final item in widget.items)
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment(item.pos.dx * 2 - 1, item.pos.dy * 2 - 1),
                  child: GestureDetector(
                    onTap: () => widget.onTapItem?.call(item),
                    onScaleStart: (_) => _startScale = item.scale,
                    onScaleUpdate: (d) {
                      setState(() {
                        item.scale = (_startScale * d.scale).clamp(0.4, 3.5);
                        item.pos = Offset(
                          (item.pos.dx + d.focalPointDelta.dx / side).clamp(0.05, 0.95),
                          (item.pos.dy + d.focalPointDelta.dy / side).clamp(0.05, 0.95),
                        );
                      });
                      widget.onChanged();
                    },
                    child: OutlinedText(text: item.text, size: 56 * unit * item.scale, color: item.color),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Bold caption with a contrasting outline, the classic sticker look.
class OutlinedText extends StatelessWidget {
  const OutlinedText({super.key, required this.text, required this.size, required this.color});

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final stroke = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    final style = TextStyle(fontSize: size, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -0.5);
    return Stack(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.16
              ..strokeJoin = StrokeJoin.round
              ..color = stroke,
          ),
        ),
        Text(text, textAlign: TextAlign.center, style: style.copyWith(color: color)),
      ],
    );
  }
}

/// Checkerboard used behind stickers to show transparency.
class Checkerboard extends StatelessWidget {
  const Checkerboard({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CheckerPainter());
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const s = 14.0;
    final a = Paint()..color = const Color(0xFFF2F2F4);
    final b = Paint()..color = const Color(0xFFE4E4E8);
    for (var y = 0.0; y < size.height; y += s) {
      for (var x = 0.0; x < size.width; x += s) {
        final even = ((x / s).floor() + (y / s).floor()).isEven;
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), even ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Captures a RepaintBoundary as a 512x512 PNG.
Future<Uint8List> captureBoundary512(GlobalKey key) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ratio = 512 / boundary.size.width;
  final image = await boundary.toImage(pixelRatio: ratio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<StickerText?> editStickerText(BuildContext context, {StickerText? existing}) async {
  final ctrl = TextEditingController(text: existing?.text ?? '');
  var color = existing?.color ?? Colors.white;
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF8E8E93), borderRadius: BorderRadius.circular(16)),
              child: ValueListenableBuilder(
                valueListenable: ctrl,
                builder: (_, v, _) => OutlinedText(text: v.text.isEmpty ? 'Tu texto' : v.text, size: 34, color: color),
              ),
            ),
            const SizedBox(height: 14),
            CupertinoTextField(
              controller: ctrl,
              autofocus: true,
              placeholder: 'Escribe algo épico',
              padding: const EdgeInsets.all(14),
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in stickerTextColors)
                  GestureDetector(
                    onTap: () => setSheet(() => color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == c ? AppColors.ink : AppColors.hairline,
                          width: color == c ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Listo')),
            ),
          ],
        ),
      ),
    ),
  );
  if (result == null) return null;
  if (existing != null) {
    existing
      ..text = result
      ..color = color;
    return existing;
  }
  return StickerText(text: result, color: color);
}

class EmojiPicker extends StatelessWidget {
  const EmojiPicker({super.key, required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: stickerEmojis.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final e = stickerEmojis[i];
          final sel = e == selected;
          return GestureDetector(
            onTap: () => onSelected(e),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? AppColors.accentSoft : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? AppColors.accent : AppColors.hairline, width: sel ? 2 : 1),
              ),
              child: Text(e, style: const TextStyle(fontSize: 22)),
            ),
          );
        },
      ),
    );
  }
}

/// Modal progress overlay while ffmpeg works.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, required this.status});

  final ValueNotifier<String?> status;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: status,
      builder: (_, s, _) => s == null
          ? const SizedBox.shrink()
          : Positioned.fill(
              child: ColoredBox(
                color: const Color(0x66000000),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.all(40),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CupertinoActivityIndicator(radius: 14),
                        const SizedBox(height: 14),
                        Text(s, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
