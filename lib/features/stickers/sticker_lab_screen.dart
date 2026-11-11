import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/app_paths.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'image_sticker_editor.dart';
import 'sticker_service.dart';
import 'video_sticker_editor.dart';

final stickerServiceProvider = Provider<StickerService>((ref) => StickerService(ref.read(databaseProvider)));

class StickerLabScreen extends ConsumerWidget {
  const StickerLabScreen({super.key});

  Future<void> _newPack(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    var animated = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nuevo pack', style: Theme.of(ctx).textTheme.headlineMedium),
              const SizedBox(height: 16),
              CupertinoTextField(
                controller: ctrl,
                autofocus: true,
                placeholder: 'Nombre del pack',
                padding: const EdgeInsets.all(14),
                maxLength: 128,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _TypeOption(
                      icon: CupertinoIcons.photo,
                      title: 'Estático',
                      subtitle: 'Desde fotos',
                      selected: !animated,
                      onTap: () => setSheet(() => animated = false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TypeOption(
                      icon: CupertinoIcons.film,
                      title: 'Animado',
                      subtitle: 'Desde videos',
                      selected: animated,
                      onTap: () => setSheet(() => animated = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'WhatsApp no permite mezclar stickers animados y estáticos en un mismo pack.',
                style: TextStyle(color: AppColors.inkSecondary, fontSize: 12),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear pack')),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    await ref.read(stickerServiceProvider).createPack(ctrl.text, animated: animated);
    ref.invalidate(stickerPacksProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(stickerPacksProvider);
    final topPad = MediaQuery.paddingOf(context).top;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🐒 MODO SECRETO',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text('Sticker Lab', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 36)),
                    ],
                  ),
                ),
                GlassIconButton(icon: CupertinoIcons.add, onTap: () => _newPack(context, ref)),
              ],
            ),
          ),
        ),
        ...packs.when(
          loading: () => [const SliverFillRemaining(child: Center(child: CupertinoActivityIndicator()))],
          error: (e, _) => [SliverFillRemaining(child: Center(child: Text('$e')))],
          data: (list) => list.isEmpty
              ? [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 140),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🐒', style: TextStyle(fontSize: 72)),
                          const SizedBox(height: 12),
                          Text('Crea tus propios stickers', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          const Text(
                            'Recorta fotos, añade texto o convierte un video en sticker animado y envíalo a WhatsApp.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.inkSecondary),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => _newPack(context, ref),
                            icon: const Icon(CupertinoIcons.add),
                            label: const Text('Crear mi primer pack'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]
              : [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    sliver: SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (_, i) => _PackCard(pack: list[i]),
                    ),
                  ),
                ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.accent : Colors.transparent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? AppColors.accent : AppColors.ink),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

class _PackCard extends ConsumerWidget {
  const _PackCard({required this.pack});

  final StickerPack pack;

  Future<void> _addSticker(BuildContext context, WidgetRef ref) async {
    if (pack.stickers.length >= StickerPack.maxStickers) {
      showToast(context, 'Máximo 30 stickers por pack');
      return;
    }
    final service = ref.read(stickerServiceProvider);
    final created = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => pack.animated
            ? VideoStickerEditor(pack: pack, service: service)
            : ImageStickerEditor(pack: pack, service: service),
      ),
    );
    if (created == true) ref.invalidate(stickerPacksProvider);
  }

  Future<void> _sendToWhatsApp(BuildContext context, WidgetRef ref) async {
    try {
      final r = await ref.read(stickerServiceProvider).addToWhatsApp(pack);
      if (context.mounted && r == 'added') showToast(context, '¡Pack añadido a WhatsApp! 🎉');
    } catch (e) {
      if (context.mounted) showToast(context, '$e');
    }
  }

  Future<void> _deletePack(BuildContext context, WidgetRef ref) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: Text('¿Eliminar "${pack.name}"?'),
        content: const Text('Si ya está en WhatsApp, allí seguirá hasta que lo borres.'),
        actions: [
          CupertinoDialogAction(child: const Text('Cancelar'), onPressed: () => Navigator.pop(d, false)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Eliminar'),
            onPressed: () => Navigator.pop(d, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(stickerServiceProvider).deletePack(pack);
    ref.invalidate(stickerPacksProvider);
  }

  Future<void> _deleteSticker(BuildContext context, WidgetRef ref, Sticker s) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: const Text('¿Eliminar sticker?'),
        actions: [
          CupertinoDialogAction(child: const Text('Cancelar'), onPressed: () => Navigator.pop(d, false)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Eliminar'),
            onPressed: () => Navigator.pop(d, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(stickerServiceProvider).deleteSticker(pack, s);
    ref.invalidate(stickerPacksProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = StickerPack.minStickers - pack.stickers.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: fileExists(pack.trayPath)
                    ? Image.file(File(AppPaths.abs(pack.trayPath!)), fit: BoxFit.cover)
                    : const Center(child: Text('🐒', style: TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pack.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '${pack.animated ? 'Animado' : 'Estático'} · ${pack.stickers.length}/${StickerPack.maxStickers}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _deletePack(context, ref),
                icon: const Icon(CupertinoIcons.trash, size: 20, color: AppColors.inkSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 84,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: pack.stickers.length + 1,
            itemBuilder: (_, i) {
              if (i == pack.stickers.length) {
                return Pressable(
                  onTap: () => _addSticker(context, ref),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(CupertinoIcons.add, color: AppColors.accent),
                  ),
                );
              }
              final s = pack.stickers[i];
              return Pressable(
                onLongPress: () => _deleteSticker(context, ref, s),
                child: Container(
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.all(6),
                  // Flutter decodes animated WebP natively, so animated stickers play here.
                  child: Image.file(File(AppPaths.abs(s.filePath)), fit: BoxFit.contain, gaplessPlayback: true),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                disabledBackgroundColor: AppColors.background,
              ),
              onPressed: missing > 0 ? null : () => _sendToWhatsApp(context, ref),
              icon: const Icon(CupertinoIcons.paperplane_fill, size: 18),
              label: Text(
                missing > 0
                    ? 'Faltan $missing ${missing == 1 ? 'sticker' : 'stickers'} para WhatsApp'
                    : 'Añadir a WhatsApp',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
