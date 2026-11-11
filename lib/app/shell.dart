import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/activity/activity_screen.dart';
import '../features/library/library_screen.dart';
import '../features/stickers/sticker_lab_screen.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'theme.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _importing = false;

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final n = await ref.read(libraryProvider.notifier).importFromPicker();
      if (mounted && n > 0) showToast(context, n == 1 ? 'Libro añadido' : '$n libros añadidos');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo importar: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(settingsProvider.select((s) => s.stickerLabUnlocked));
    final tabs = [
      const _Tab('Biblioteca', CupertinoIcons.book, CupertinoIcons.book_fill),
      const _Tab('Actividad', CupertinoIcons.chart_bar, CupertinoIcons.chart_bar_fill),
      if (unlocked) const _Tab('Stickers', CupertinoIcons.smiley, CupertinoIcons.smiley_fill),
    ];
    final index = _index.clamp(0, tabs.length - 1);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: index,
            children: [
              LibraryScreen(onImport: _import),
              const ActivityScreen(),
              if (unlocked) const StickerLabScreen(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FloatingNavBar(
                  tabs: tabs,
                  index: index,
                  onTap: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => _index = i);
                  },
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: index == 0
                      ? Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Pressable(
                            onTap: _import,
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: const BoxDecoration(
                                color: AppColors.ink,
                                shape: BoxShape.circle,
                                boxShadow: softShadow,
                              ),
                              child: _importing
                                  ? const CupertinoActivityIndicator(color: Colors.white)
                                  : const Icon(CupertinoIcons.add, color: Colors.white, size: 26),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.tabs, required this.index, required this.onTap});

  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Glass(
      opacity: 0.8,
      padding: const EdgeInsets.all(5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                height: 48,
                padding: EdgeInsets.symmetric(horizontal: i == index ? 18 : 16),
                decoration: BoxDecoration(
                  color: i == index ? AppColors.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  children: [
                    Icon(
                      i == index ? tabs[i].activeIcon : tabs[i].icon,
                      size: 21,
                      color: i == index ? Colors.white : AppColors.inkSecondary,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: i == index
                          ? Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                tabs[i].label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
