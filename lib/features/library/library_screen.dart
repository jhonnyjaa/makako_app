import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../reader/open_book.dart';
import '../settings/settings_sheet.dart';
import 'book_actions.dart';

enum _Filter { all, pdf, epub, favorites }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, required this.onImport});

  final VoidCallback onImport;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';

  List<Book> _apply(List<Book> books) {
    final q = _query.trim().toLowerCase();
    return books.where((b) {
      final f = switch (_filter) {
        _Filter.all => true,
        _Filter.pdf => b.format == BookFormat.pdf,
        _Filter.epub => b.format == BookFormat.epub,
        _Filter.favorites => b.favorite,
      };
      if (!f) return false;
      if (q.isEmpty) return true;
      return b.title.toLowerCase().contains(q) || (b.author?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(libraryProvider);
    final books = booksAsync.value ?? const <Book>[];
    final reading = books.where((b) => b.started && !b.finished && b.lastOpenedAt != null).take(6).toList();
    final filtered = _apply(books);
    final topPad = MediaQuery.paddingOf(context).top;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 0),
          sliver: SliverToBoxAdapter(child: _Header(onSettings: () => showSettingsSheet(context))),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          sliver: SliverToBoxAdapter(
            child: CupertinoSearchTextField(
              placeholder: 'Buscar en tu biblioteca',
              onChanged: (v) => setState(() => _query = v),
              backgroundColor: const Color(0x0F000000),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (reading.isNotEmpty && _query.isEmpty) ...[
          const _SectionTitle('Continuar leyendo'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 190,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: reading.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _ContinueCard(book: reading[i]),
              ),
            ),
          ),
        ],
        const _SectionTitle('Todos los libros'),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<_Filter>(
                groupValue: _filter,
                backgroundColor: const Color(0x0F000000),
                onValueChanged: (v) => setState(() => _filter = v ?? _Filter.all),
                children: const {
                  _Filter.all: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Todos')),
                  _Filter.pdf: Text('PDF'),
                  _Filter.epub: Text('EPUB'),
                  _Filter.favorites: Icon(CupertinoIcons.heart_fill, size: 16),
                },
              ),
            ),
          ),
        ),
        if (booksAsync.isLoading && books.isEmpty)
          const SliverFillRemaining(child: Center(child: CupertinoActivityIndicator()))
        else if (books.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _EmptyState(onImport: widget.onImport))
        else if (filtered.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Text('Nada por aquí', style: TextStyle(color: AppColors.inkSecondary)),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                mainAxisSpacing: 22,
                crossAxisSpacing: 16,
                childAspectRatio: 0.52,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _BookTile(book: filtered[i]),
                childCount: filtered.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateFormat("EEEE, d 'de' MMMM", 'es').format(DateTime.now()).toUpperCase();
    final stats = ref.watch(activityProvider).value;
    final goal = ref.watch(settingsProvider.select((s) => s.dailyGoalMinutes));
    final todayMin = (stats?.todaySeconds ?? 0) / 60;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                today,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text('Biblioteca', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 36)),
            ],
          ),
        ),
        Tooltip(
          message: 'Meta diaria',
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: (todayMin / goal).clamp(0, 1).toDouble(),
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.accentSoft,
                  color: AppColors.accent,
                ),
                Text(
                  todayMin.floor().toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GlassIconButton(icon: CupertinoIcons.slider_horizontal_3, onTap: onSettings),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
      sliver: SliverToBoxAdapter(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageLabel = book.format == BookFormat.pdf
        ? 'Página ${book.currentPage} de ${book.totalPages}'
        : (book.totalPages > 0 ? 'Capítulo ${book.currentPage} de ${book.totalPages}' : 'EPUB');
    return Pressable(
      onTap: () => openBook(context, ref, book),
      onLongPress: () => showBookActions(context, ref, book),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: softShadow,
        ),
        child: Row(
          children: [
            AspectRatio(aspectRatio: 0.7, child: BookCover(book: book)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FormatBadge(format: book.format),
                  const SizedBox(height: 8),
                  Text(
                    book.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.15),
                  ),
                  if (book.author != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      book.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const Spacer(),
                  Text(pageLabel, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: ProgressLine(value: book.progress, color: AppColors.accent)),
                      const SizedBox(width: 8),
                      Text(
                        '${(book.progress * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
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

class _BookTile extends ConsumerWidget {
  const _BookTile({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Pressable(
      onTap: () => openBook(context, ref, book),
      onLongPress: () => showBookActions(context, ref, book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.7,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(tag: 'cover-${book.id}', child: BookCover(book: book)),
                if (book.favorite)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(CupertinoIcons.heart_fill, color: Colors.white, size: 18, shadows: [
                      Shadow(color: Color(0x66000000), blurRadius: 6),
                    ]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.2),
          ),
          const SizedBox(height: 6),
          if (book.finished)
            const Text(
              'Terminado ✓',
              style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w600, fontSize: 12),
            )
          else if (book.started)
            Row(
              children: [
                Expanded(child: ProgressLine(value: book.progress, height: 3)),
                const SizedBox(width: 6),
                Text('${(book.progress * 100).round()}%', style: Theme.of(context).textTheme.labelSmall),
              ],
            )
          else
            _FormatBadge(format: book.format),
        ],
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge({required this.format});

  final BookFormat format;

  @override
  Widget build(BuildContext context) {
    final pdf = format == BookFormat.pdf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: pdf ? AppColors.accentSoft : const Color(0xFFE3F0FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        pdf ? 'PDF' : 'EPUB',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: pdf ? AppColors.accent : AppColors.blue,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 140),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(28)),
            child: const Icon(CupertinoIcons.book_fill, size: 44, color: AppColors.accent),
          ),
          const SizedBox(height: 20),
          Text('Tu estantería está vacía', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Importa PDFs de documentación, libros técnicos o EPUBs y empieza a construir tu hábito de lectura.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSecondary),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(CupertinoIcons.add),
            label: const Text('Importar PDF o EPUB'),
          ),
        ],
      ),
    );
  }
}
