import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';

/// Floating, auto-hiding reader controls. When hidden, only a hairline progress
/// bar and a tiny page counter remain so 100% of the screen is for reading.
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.pageLabel,
    required this.onBack,
    required this.topActions,
    required this.bottom,
  });

  final bool visible;
  final String title;
  final String subtitle;
  final double progress;
  final String pageLabel;
  final VoidCallback onBack;
  final List<Widget> topActions;
  final Widget bottom;

  static const _dur = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        // Minimal always-on indicators (immersive mode).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: visible ? 0 : 1,
              duration: _dur,
              child: Column(
                children: [
                  Text(
                    pageLabel,
                    style: const TextStyle(fontSize: 11, color: AppColors.inkTertiary, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: pad.bottom > 0 ? pad.bottom - 4 : 6),
                  ProgressLine(value: progress, height: 2, color: AppColors.accent),
                ],
              ),
            ),
          ),
        ),
        // Top bar
        AnimatedPositioned(
          duration: _dur,
          curve: Curves.easeOutCubic,
          top: visible ? pad.top + 8 : -90,
          left: 12,
          right: 12,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: _dur,
            child: Row(
              children: [
                GlassIconButton(icon: CupertinoIcons.chevron_back, onTap: onBack),
                const SizedBox(width: 8),
                Expanded(
                  child: Glass(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final a in topActions) ...[const SizedBox(width: 8), a],
              ],
            ),
          ),
        ),
        // Bottom bar
        AnimatedPositioned(
          duration: _dur,
          curve: Curves.easeOutCubic,
          bottom: visible ? pad.bottom + 12 : -140,
          left: 12,
          right: 12,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: _dur,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Glass(
                  radius: 26,
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: bottom,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Toggle system bars together with the reader chrome.
void applyImmersive(bool chromeVisible) {
  SystemChrome.setEnabledSystemUIMode(chromeVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
}

void restoreSystemUi() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

class ReaderSheetTile extends StatelessWidget {
  const ReaderSheetTile({super.key, required this.title, this.trailing, this.onTap, this.indent = 0, this.bold = false});

  final String title;
  final String? trailing;
  final VoidCallback? onTap;
  final double indent;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20 + indent, 13, 20, 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
              ),
            ),
            if (trailing != null)
              Text(trailing!, style: const TextStyle(color: AppColors.inkSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
