import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../data/app_paths.dart';
import '../data/models.dart';

/// Frosted-glass surface (iOS "material" look).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = AppRadii.pill,
    this.padding = EdgeInsets.zero,
    this.opacity = 0.72,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double opacity;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: shadow ? softShadow : null),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: opacity),
              borderRadius: r,
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 0.6),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Scales down slightly while pressed, like iOS buttons/cards.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.96});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Round icon button with glass background, used in readers and headers.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onTap, this.size = 44, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Glass(
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.45, color: active ? AppColors.accent : AppColors.ink),
        ),
      ),
    );
  }
}

/// Book cover: rendered first page / EPUB cover, or a generated typographic cover.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.radius = AppRadii.cover});

  final Book book;
  final double radius;

  static const _palettes = [
    [Color(0xFF1E1E24), Color(0xFF3A3A46)],
    [Color(0xFFFF6B35), Color(0xFFFF9F68)],
    [Color(0xFF0A84FF), Color(0xFF64B5FF)],
    [Color(0xFF8E5CF7), Color(0xFFB794FF)],
    [Color(0xFF30B26B), Color(0xFF7ED9A0)],
    [Color(0xFFE5484D), Color(0xFFFF8A8E)],
  ];

  @override
  Widget build(BuildContext context) {
    final cover = book.coverPath;
    Widget child;
    if (cover != null && File(AppPaths.abs(cover)).existsSync()) {
      child = Image.file(
        File(AppPaths.abs(cover)),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: 500,
      );
    } else {
      final colors = _palettes[book.title.hashCode.abs() % _palettes.length];
      child = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                book.format == BookFormat.pdf ? CupertinoIcons.doc_text : CupertinoIcons.book,
                color: Colors.white70,
                size: 18,
              ),
              const Spacer(),
              Text(
                book.title,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.1, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            // Subtle spine highlight for a physical-book feel.
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0x33000000), Color(0x00000000)]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.color = AppColors.ink, this.height = 4});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: const Color(0x14000000)),
            FractionallySizedBox(widthFactor: value.clamp(0, 1), child: Container(color: color)),
          ],
        ),
      ),
    );
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        // Float above the floating nav bar.
        margin: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 84),
      ),
    );
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '$m min';
  return '${seconds}s';
}
