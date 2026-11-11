import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../app/theme.dart';
import '../../data/app_paths.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'epub_document.dart';
import 'reader_chrome.dart';
import 'reading_tracker.dart';

/// EPUB reader: swipe horizontally between chapters (like turning a page),
/// scroll vertically inside a chapter. Position is stored as "section:fraction".
class EpubReaderScreen extends ConsumerStatefulWidget {
  const EpubReaderScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  late Book _book = widget.book;
  late final AppDatabase _db = ref.read(databaseProvider);
  late final LibraryNotifier _library = ref.read(libraryProvider.notifier);
  late final ProviderContainer _container;
  late final ReadingTracker _tracker;

  EpubDoc? _doc;
  Object? _error;
  PageController? _pages;
  int _section = 0;
  double _fraction = 0;
  double _initialFraction = 0;
  bool _chrome = true;
  Timer? _hideTimer;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    // Resolve eagerly: the tracker may report after this widget is unmounted.
    _container = ProviderScope.containerOf(context, listen: false);
    final pos = (widget.book.position ?? '').split(':');
    _section = int.tryParse(pos.first) ?? 0;
    _initialFraction = pos.length > 1 ? double.tryParse(pos[1]) ?? 0 : 0;
    _fraction = _initialFraction;
    _tracker = ReadingTracker(
      db: _db,
      bookId: _book.id,
      onSaved: () => _container.invalidate(activityProvider),
    )..start(_section);
    _book = _book.copyWith(lastOpenedAt: DateTime.now());
    _library.save(_book);
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await EpubDoc.load(AppPaths.abs(widget.book.path));
      if (!mounted) return;
      final section = _section.clamp(0, doc.sections.isEmpty ? 0 : doc.sections.length - 1);
      setState(() {
        _doc = doc;
        _section = section;
        _pages = PageController(initialPage: section);
      });
      _hideTimer = Timer(const Duration(milliseconds: 2200), () => _setChrome(false));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _persist();
    _tracker.dispose();
    _pages?.dispose();
    restoreSystemUi();
    super.dispose();
  }

  int get _count => _doc?.sections.length ?? 0;

  double get _progress => _count == 0 ? 0 : ((_section + _fraction) / _count).clamp(0.0, 1.0);

  void _setChrome(bool v) {
    if (!mounted || _chrome == v) return;
    setState(() => _chrome = v);
    applyImmersive(v);
  }

  void _toggleChrome() {
    _hideTimer?.cancel();
    _tracker.touch();
    _setChrome(!_chrome);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _persist);
  }

  void _persist() {
    if (_count == 0) return;
    _book = _book.copyWith(
      currentPage: _section + 1,
      totalPages: _count,
      progress: _progress,
      position: '$_section:${_fraction.toStringAsFixed(4)}',
      finished: _book.finished || (_section == _count - 1 && _fraction > 0.97),
    );
    _library.save(_book);
  }

  void _goToSection(int i) {
    _pages?.animateToPage(i, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  void _showToc() {
    final doc = _doc;
    if (doc == null) return;
    final entries = doc.toc.isNotEmpty
        ? doc.toc
        : [for (var i = 0; i < doc.sections.length; i++) EpubTocEntry(doc.sections[i].title, i, 0)];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => ListView.builder(
          controller: scroll,
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final e = entries[i];
            return ReaderSheetTile(
              title: e.title,
              indent: e.depth * 16.0,
              bold: e.depth == 0,
              trailing: e.section == _section ? '•' : null,
              onTap: () {
                Navigator.pop(ctx);
                _goToSection(e.section);
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final paper = settings.paperTone == PaperTone.sepia ? AppColors.sepia : AppColors.paper;
    final notifier = ref.read(settingsProvider.notifier);
    final doc = _doc;

    return Scaffold(
      backgroundColor: paper,
      body: Stack(
        children: [
          Positioned.fill(
            child: _error != null
                ? Center(child: Text('No se pudo abrir el EPUB\n$_error', textAlign: TextAlign.center))
                : doc == null
                ? const Center(child: CupertinoActivityIndicator())
                : PageView.builder(
                    controller: _pages,
                    itemCount: doc.sections.length,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _section = i;
                        _fraction = 0;
                      });
                      _tracker.page(i);
                      _scheduleSave();
                    },
                    itemBuilder: (_, i) => _SectionView(
                      key: ValueKey('s$i'),
                      doc: doc,
                      index: i,
                      fontSize: settings.epubFontSize,
                      initialFraction: i == _section ? _initialFraction : 0,
                      onTap: _toggleChrome,
                      onNext: i < doc.sections.length - 1 ? () => _goToSection(i + 1) : null,
                      onScrollFraction: (f) {
                        _tracker.touch();
                        if (i != _section) return;
                        _initialFraction = f;
                        if ((f - _fraction).abs() > 0.01) {
                          setState(() => _fraction = f);
                          _scheduleSave();
                        }
                      },
                    ),
                  ),
          ),
          ReaderChrome(
            visible: _chrome,
            title: _book.title,
            subtitle: doc == null ? 'Cargando…' : doc.sections[_section].title,
            progress: _progress,
            pageLabel: _count > 0 ? '${(_progress * 100).round()}% · ${_section + 1}/$_count' : '',
            onBack: () => Navigator.of(context).maybePop(),
            topActions: const [],
            bottom: Row(
              children: [
                IconButton(
                  tooltip: 'Texto más pequeño',
                  onPressed: settings.epubFontSize <= 13
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          notifier.setEpubFontSize(settings.epubFontSize - 1);
                        },
                  icon: const Text('A', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text('${settings.epubFontSize.round()}', style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(
                  tooltip: 'Texto más grande',
                  onPressed: settings.epubFontSize >= 30
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          notifier.setEpubFontSize(settings.epubFontSize + 1);
                        },
                  icon: const Text('A', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                _ToneDot(
                  color: AppColors.paper,
                  selected: settings.paperTone == PaperTone.white,
                  onTap: () => notifier.setPaperTone(PaperTone.white),
                ),
                const SizedBox(width: 8),
                _ToneDot(
                  color: AppColors.sepia,
                  selected: settings.paperTone == PaperTone.sepia,
                  onTap: () => notifier.setPaperTone(PaperTone.sepia),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Índice',
                  onPressed: _showToc,
                  icon: const Icon(CupertinoIcons.list_bullet, size: 21),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionView extends StatefulWidget {
  const _SectionView({
    super.key,
    required this.doc,
    required this.index,
    required this.fontSize,
    required this.initialFraction,
    required this.onTap,
    required this.onNext,
    required this.onScrollFraction,
  });

  final EpubDoc doc;
  final int index;
  final double fontSize;
  final double initialFraction;
  final VoidCallback onTap;
  final VoidCallback? onNext;
  final ValueChanged<double> onScrollFraction;

  @override
  State<_SectionView> createState() => _SectionViewState();
}

class _SectionViewState extends State<_SectionView> {
  final _scroll = ScrollController();
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) widget.onScrollFraction((_scroll.offset / max).clamp(0.0, 1.0));
    });
    if (widget.initialFraction > 0) _tryRestore(0);
  }

  /// HTML renders asynchronously; retry until the content has its final height.
  void _tryRestore(int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _restored || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) {
        _scroll.jumpTo(max * widget.initialFraction);
        _restored = true;
      } else if (attempt < 30) {
        Future.delayed(const Duration(milliseconds: 60), () => _tryRestore(attempt + 1));
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static const _mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier'], fontSize: 13.5, height: 1.45);

  @override
  Widget build(BuildContext context) {
    final section = widget.doc.sections[widget.index];
    final pad = MediaQuery.paddingOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTap,
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(0, pad.top + 36, 0, pad.bottom + 60),
          child: Center(
            child: ConstrainedBox(
              // Comfortable line length on tablets.
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HtmlWidget(
                      section.html,
                      buildAsync: true,
                      enableCaching: true,
                      textStyle: TextStyle(fontSize: widget.fontSize, height: 1.65, color: AppColors.ink),
                      onLoadingBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CupertinoActivityIndicator()),
                      ),
                      customStylesBuilder: (e) => switch (e.localName) {
                        'code' => {'background-color': '#F1F1F4', 'font-family': 'monospace', 'font-size': '0.88em'},
                        'blockquote' => {'border-left': '3px solid #FF6B35', 'padding-left': '12px', 'color': '#55555C'},
                        'h1' || 'h2' || 'h3' => {'line-height': '1.25'},
                        _ => null,
                      },
                      customWidgetBuilder: (e) {
                        switch (e.localName) {
                          case 'pre':
                            // Code blocks: monospaced, horizontally scrollable, never wrapped.
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F4F7),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.hairline),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.all(14),
                                child: SelectableText(e.text, style: _mono.copyWith(color: AppColors.ink)),
                              ),
                            );
                          case 'img':
                          case 'image':
                            final src = e.attributes['src'] ?? e.attributes['xlink:href'] ?? e.attributes['href'];
                            final bytes = src == null ? null : widget.doc.image(src);
                            if (bytes == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(bytes, fit: BoxFit.contain),
                              ),
                            );
                        }
                        return null;
                      },
                    ),
                    if (widget.onNext != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 36),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: widget.onNext,
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(CupertinoIcons.arrow_right),
                            label: const Text('Siguiente capítulo', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToneDot extends StatelessWidget {
  const _ToneDot({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? AppColors.accent : AppColors.hairline, width: selected ? 2.5 : 1),
        ),
      ),
    );
  }
}
