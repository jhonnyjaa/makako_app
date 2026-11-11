import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/theme.dart';
import '../../data/app_paths.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'reader_chrome.dart';
import 'reading_tracker.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  const PdfReaderScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  late Book _book = widget.book;
  late final PdfDocumentRef _docRef = PdfDocumentRefFile(AppPaths.abs(widget.book.path));
  late final AppDatabase _db = ref.read(databaseProvider);
  late final LibraryNotifier _library = ref.read(libraryProvider.notifier);
  late final ProviderContainer _container;
  late final ReadingTracker _tracker;

  final _pdfController = PdfViewerController();
  PageController? _pageController;
  PdfDocument? _doc;

  late ReaderMode _mode = ref.read(settingsProvider).readerMode;
  late int _page = math.max(1, widget.book.currentPage);
  late int _total = widget.book.totalPages;
  double? _sliderValue;
  bool _chrome = true;
  bool _zoomed = false;
  Set<int> _bookmarked = {};
  Timer? _hideTimer;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    // Resolve eagerly: the tracker may report after this widget is unmounted.
    _container = ProviderScope.containerOf(context, listen: false);
    _tracker = ReadingTracker(
      db: _db,
      bookId: _book.id,
      onSaved: () => _container.invalidate(activityProvider),
    )..start(_page);
    _pageController = PageController(initialPage: _page - 1);
    _book = _book.copyWith(lastOpenedAt: DateTime.now());
    _library.save(_book);
    _loadBookmarks();
    // Show controls briefly so the user discovers them, then go immersive.
    _hideTimer = Timer(const Duration(milliseconds: 2200), () => _setChrome(false));
  }

  Future<void> _loadBookmarks() async {
    final list = await _db.bookmarks(_book.id);
    if (mounted) setState(() => _bookmarked = list.map((b) => b.page).toSet());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _persist();
    _tracker.dispose();
    _pageController?.dispose();
    restoreSystemUi();
    super.dispose();
  }

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

  void _onPage(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    _tracker.page(page);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _persist);
  }

  void _persist() {
    if (_total <= 0) return;
    final progress = (_page / _total).clamp(0.0, 1.0);
    _book = _book.copyWith(
      currentPage: _page,
      totalPages: _total,
      progress: progress,
      finished: _book.finished || _page >= _total,
    );
    _library.save(_book);
  }

  void _setTotal(int total) {
    if (total == _total) return;
    // Called during build callbacks: defer the rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _total = total);
    });
    _total = total;
  }

  void _goTo(int page) {
    final p = page.clamp(1, math.max(1, _total)).toInt();
    if (_mode == ReaderMode.paged) {
      _pageController?.jumpToPage(p - 1);
    } else {
      _pdfController.goToPage(pageNumber: p);
    }
    _onPage(p);
  }

  void _turn(int delta) {
    final target = _page + delta;
    if (target < 1 || target > _total) return;
    HapticFeedback.selectionClick();
    _pageController?.animateToPage(
      target - 1,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _switchMode() {
    final next = _mode == ReaderMode.paged ? ReaderMode.scroll : ReaderMode.paged;
    _pageController?.dispose();
    _pageController = next == ReaderMode.paged ? PageController(initialPage: _page - 1) : null;
    setState(() {
      _mode = next;
      _zoomed = false;
    });
    ref.read(settingsProvider.notifier).setReaderMode(next);
  }

  Future<void> _toggleBookmark() async {
    HapticFeedback.lightImpact();
    await _db.toggleBookmark(_book.id, _page, 'Página $_page');
    await _loadBookmarks();
    if (mounted) {
      showToast(context, _bookmarked.contains(_page) ? 'Marcador añadido' : 'Marcador eliminado');
    }
  }

  Color get _paper =>
      ref.watch(settingsProvider.select((s) => s.paperTone)) == PaperTone.sepia ? AppColors.sepia : const Color(0xFFEDEDF0);

  @override
  Widget build(BuildContext context) {
    final shownPage = _sliderValue?.round() ?? _page;
    return Scaffold(
      backgroundColor: _paper,
      body: Stack(
        children: [
          Positioned.fill(
            child: KeyedSubtree(
              key: ValueKey(_mode),
              child: _mode == ReaderMode.paged ? _buildPaged() : _buildScroll(),
            ),
          ),
          ReaderChrome(
            visible: _chrome,
            title: _book.title,
            subtitle: _total > 0 ? '${(_page / _total * 100).round()}% · quedan ${_total - _page} páginas' : 'PDF',
            progress: _total > 0 ? _page / _total : 0,
            pageLabel: '$_page / $_total',
            onBack: () => Navigator.of(context).maybePop(),
            topActions: [
              GlassIconButton(
                icon: _bookmarked.contains(_page) ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
                active: _bookmarked.contains(_page),
                onTap: _toggleBookmark,
              ),
            ],
            bottom: Row(
              children: [
                IconButton(
                  tooltip: _mode == ReaderMode.paged ? 'Cambiar a scroll' : 'Cambiar a páginas',
                  onPressed: _switchMode,
                  icon: Icon(
                    _mode == ReaderMode.paged ? CupertinoIcons.book : CupertinoIcons.arrow_up_arrow_down,
                    size: 21,
                  ),
                ),
                Expanded(
                  child: _total > 1
                      ? Slider(
                          min: 1,
                          max: _total.toDouble(),
                          value: shownPage.clamp(1, _total).toDouble(),
                          onChanged: (v) => setState(() => _sliderValue = v),
                          onChangeEnd: (v) {
                            setState(() => _sliderValue = null);
                            _goTo(v.round());
                          },
                        )
                      : const SizedBox(height: 40),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$shownPage/$_total',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
                IconButton(
                  tooltip: 'Índice y marcadores',
                  onPressed: _showContents,
                  icon: const Icon(CupertinoIcons.list_bullet, size: 21),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ paged mode

  Widget _buildPaged() {
    return PdfDocumentViewBuilder(
      documentRef: _docRef,
      loadingBuilder: (_) => const Center(child: CupertinoActivityIndicator()),
      errorBuilder: (_, error, _) => Center(child: Text('No se pudo abrir el PDF\n$error', textAlign: TextAlign.center)),
      builder: (context, doc) {
        if (doc == null) return const Center(child: CupertinoActivityIndicator());
        _doc = doc;
        _setTotal(doc.pages.length);
        final controller = _pageController!;
        return LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              _tracker.touch();
              if (_zoomed) return _toggleChrome();
              final x = d.localPosition.dx / box.maxWidth;
              if (x < 0.25) {
                _turn(-1);
              } else if (x > 0.75) {
                _turn(1);
              } else {
                _toggleChrome();
              }
            },
            child: PageView.builder(
              controller: controller,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
              itemCount: doc.pages.length,
              onPageChanged: (i) => _onPage(i + 1),
              itemBuilder: (context, i) => AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  // Gentle 3D "page turn": pages rotate around the spine as they slide.
                  var delta = 0.0;
                  if (controller.hasClients && controller.position.haveDimensions) {
                    delta = (controller.page ?? i.toDouble()) - i;
                  }
                  delta = delta.clamp(-1.0, 1.0);
                  return Transform(
                    alignment: delta > 0 ? Alignment.centerRight : Alignment.centerLeft,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0011)
                      ..rotateY(delta * 0.45),
                    child: Opacity(opacity: (1 - delta.abs() * 0.35).clamp(0.0, 1.0), child: child),
                  );
                },
                child: _ZoomablePage(
                  onZoomChanged: (z) {
                    if (z != _zoomed) setState(() => _zoomed = z);
                  },
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      MediaQuery.paddingOf(context).top + 8,
                      8,
                      MediaQuery.paddingOf(context).bottom + 22,
                    ),
                    child: PdfPageView(
                      document: doc,
                      pageNumber: i + 1,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 18, offset: Offset(0, 6))],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------- scroll mode

  Widget _buildScroll() {
    return PdfViewer(
      _docRef,
      controller: _pdfController,
      initialPageNumber: _page,
      params: PdfViewerParams(
        backgroundColor: _paper,
        margin: 10,
        onViewerReady: (doc, controller) {
          _doc = doc;
          _setTotal(doc.pages.length);
        },
        onPageChanged: (p) {
          if (p != null) _onPage(p);
        },
        onInteractionStart: (_) => _tracker.touch(),
        onGeneralTap: (context, controller, details) {
          if (details.type == PdfViewerGeneralTapType.tap) {
            _toggleChrome();
            return true;
          }
          return false;
        },
        viewerOverlayBuilder: (context, size, handleLinkTap) => [
          PdfViewerScrollThumb(
            controller: _pdfController,
            orientation: ScrollbarOrientation.right,
            thumbSize: const Size(44, 26),
            thumbBuilder: (context, thumbSize, pageNumber, controller) => Container(
              decoration: BoxDecoration(
                color: AppColors.ink.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text(
                '${pageNumber ?? ''}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- contents sheet

  Future<void> _showContents() async {
    final outline = await (_doc?.loadOutline() ?? Future.value(const <PdfOutlineNode>[]));
    final bookmarks = await _db.bookmarks(_book.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ContentsSheet(
        outline: outline,
        bookmarks: bookmarks,
        onSelect: (page) {
          Navigator.pop(ctx);
          _goTo(page);
        },
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({required this.child, required this.onZoomChanged});

  final Widget child;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final _ctrl = TransformationController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _ctrl,
      minScale: 1,
      maxScale: 5,
      onInteractionEnd: (_) => widget.onZoomChanged(_ctrl.value.getMaxScaleOnAxis() > 1.02),
      child: widget.child,
    );
  }
}

class _ContentsSheet extends StatefulWidget {
  const _ContentsSheet({required this.outline, required this.bookmarks, required this.onSelect});

  final List<PdfOutlineNode> outline;
  final List<Bookmark> bookmarks;
  final ValueChanged<int> onSelect;

  @override
  State<_ContentsSheet> createState() => _ContentsSheetState();
}

class _ContentsSheetState extends State<_ContentsSheet> {
  int _tab = 0;

  List<Widget> _outlineTiles(List<PdfOutlineNode> nodes, int depth) => [
    for (final n in nodes) ...[
      ReaderSheetTile(
        title: n.title,
        trailing: n.dest?.pageNumber.toString(),
        indent: depth * 16.0,
        bold: depth == 0,
        onTap: n.dest == null ? null : () => widget.onSelect(n.dest!.pageNumber),
      ),
      ..._outlineTiles(n.children, depth + 1),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _tab,
                onValueChanged: (v) => setState(() => _tab = v ?? 0),
                children: const {
                  0: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Índice')),
                  1: Text('Marcadores'),
                },
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: _tab == 0
                  ? (widget.outline.isEmpty
                        ? [const _EmptyHint('Este PDF no incluye índice')]
                        : _outlineTiles(widget.outline, 0))
                  : (widget.bookmarks.isEmpty
                        ? [const _EmptyHint('Toca el marcador arriba para guardar una página')]
                        : [
                            for (final b in widget.bookmarks)
                              ReaderSheetTile(
                                title: b.label,
                                trailing: 'p. ${b.page}',
                                onTap: () => widget.onSelect(b.page),
                              ),
                          ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(40),
    child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSecondary)),
  );
}
