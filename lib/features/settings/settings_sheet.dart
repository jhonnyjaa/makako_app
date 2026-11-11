import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

Future<void> showSettingsSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => const _SettingsSheet(),
);

class _SettingsSheet extends ConsumerStatefulWidget {
  const _SettingsSheet();

  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet> {
  int _taps = 0;

  /// Easter egg: tap the version row 7 times (Android developer-options style).
  void _onVersionTap() {
    final notifier = ref.read(settingsProvider.notifier);
    if (ref.read(settingsProvider).stickerLabUnlocked) {
      showToast(context, '🐒 El Sticker Lab ya está desbloqueado');
      return;
    }
    _taps++;
    HapticFeedback.selectionClick();
    final left = 7 - _taps;
    if (left <= 0) {
      HapticFeedback.heavyImpact();
      notifier.unlockStickerLab();
      Navigator.pop(context);
      showToast(context, '🐒 ¡Sticker Lab desbloqueado! Mira la barra inferior');
    } else if (left <= 3) {
      showToast(context, 'Estás a $left ${left == 1 ? 'toque' : 'toques'} de algo secreto…');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ajustes', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            const _Label('Meta diaria'),
            Wrap(
              spacing: 8,
              children: [
                for (final m in const [10, 15, 20, 30, 45, 60, 90])
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: s.dailyGoalMinutes == m,
                    showCheckmark: false,
                    selectedColor: AppColors.ink,
                    labelStyle: TextStyle(
                      color: s.dailyGoalMinutes == m ? Colors.white : AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide.none,
                    backgroundColor: AppColors.background,
                    shape: const StadiumBorder(),
                    onSelected: (_) => n.setDailyGoal(m),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _Label('Modo de lectura PDF por defecto'),
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<ReaderMode>(
                groupValue: s.readerMode,
                onValueChanged: (v) => n.setReaderMode(v ?? ReaderMode.paged),
                children: const {
                  ReaderMode.paged: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('📖  Pasar página'),
                  ),
                  ReaderMode.scroll: Text('📜  Scroll continuo'),
                },
              ),
            ),
            const SizedBox(height: 20),
            const _Label('Papel'),
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<PaperTone>(
                groupValue: s.paperTone,
                onValueChanged: (v) => n.setPaperTone(v ?? PaperTone.white),
                children: const {
                  PaperTone.white: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Blanco')),
                  PaperTone.sepia: Text('Sepia'),
                },
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(CupertinoIcons.lock_shield),
                    title: Text('100% local'),
                    subtitle: Text('Sin cuentas ni internet. Todo vive en este dispositivo.'),
                  ),
                  const Divider(height: 0.5, indent: 56, color: AppColors.hairline),
                  ListTile(
                    leading: const Icon(CupertinoIcons.info),
                    title: const Text('Versión'),
                    trailing: const Text('1.0.0', style: TextStyle(color: AppColors.inkSecondary)),
                    onTap: _onVersionTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.inkSecondary),
    ),
  );
}
