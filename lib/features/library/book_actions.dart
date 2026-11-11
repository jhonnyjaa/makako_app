import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

Future<void> showBookActions(BuildContext context, WidgetRef ref, Book book) {
  final lib = ref.read(libraryProvider.notifier);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(width: 56, height: 80, child: BookCover(book: book, radius: 6)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title, maxLines: 2, style: Theme.of(ctx).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${book.format.name.toUpperCase()}'
                        '${book.totalPages > 0 && book.format == BookFormat.pdf ? ' · ${book.totalPages} páginas' : ''}'
                        ' · ${(book.progress * 100).round()}% leído',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ActionGroup(
              children: [
                _Action(
                  icon: book.favorite ? CupertinoIcons.heart_slash : CupertinoIcons.heart,
                  label: book.favorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
                  onTap: () {
                    Navigator.pop(ctx);
                    lib.toggleFavorite(book);
                  },
                ),
                _Action(
                  icon: book.finished ? CupertinoIcons.arrow_counterclockwise : CupertinoIcons.checkmark_seal,
                  label: book.finished ? 'Marcar como no terminado' : 'Marcar como terminado',
                  onTap: () {
                    Navigator.pop(ctx);
                    lib.markFinished(book, !book.finished);
                  },
                ),
                _Action(
                  icon: CupertinoIcons.pencil,
                  label: 'Renombrar',
                  onTap: () async {
                    Navigator.pop(ctx);
                    final title = await _askTitle(context, book.title);
                    if (title != null && title.trim().isNotEmpty) lib.rename(book, title.trim());
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ActionGroup(
              children: [
                _Action(
                  icon: CupertinoIcons.trash,
                  label: 'Eliminar de la biblioteca',
                  destructive: true,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await showCupertinoDialog<bool>(
                      context: context,
                      builder: (d) => CupertinoAlertDialog(
                        title: const Text('¿Eliminar libro?'),
                        content: const Text('Se borrará el archivo y su historial de lectura.'),
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
                    if (ok ?? false) lib.delete(book);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _askTitle(BuildContext context, String current) {
  final ctrl = TextEditingController(text: current);
  return showCupertinoDialog<String>(
    context: context,
    builder: (d) => CupertinoAlertDialog(
      title: const Text('Renombrar'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(controller: ctrl, autofocus: true),
      ),
      actions: [
        CupertinoDialogAction(child: const Text('Cancelar'), onPressed: () => Navigator.pop(d)),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: const Text('Guardar'),
          onPressed: () => Navigator.pop(d, ctrl.text),
        ),
      ],
    ),
  );
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 0.5, thickness: 0.5, indent: 52, color: AppColors.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.destructive = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFFF3B30) : AppColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(color: color, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
