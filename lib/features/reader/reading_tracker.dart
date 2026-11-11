import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/models.dart';

/// Measures *active* reading time: the clock only runs while the app is in the
/// foreground and the user interacted recently (page turn, tap, scroll).
/// Sessions are persisted when the reader closes or the app goes to background,
/// so nothing is lost if the OS kills the process.
class ReadingTracker with WidgetsBindingObserver {
  ReadingTracker({required this.db, required this.bookId, required this.onSaved});

  final AppDatabase db;
  final String bookId;
  final VoidCallback onSaved;

  static const _idleTimeout = Duration(minutes: 3);
  static const _minSessionSeconds = 20;

  Timer? _timer;
  bool _foreground = true;
  int _activeSeconds = 0;
  DateTime _sessionStart = DateTime.now();
  DateTime _lastInteraction = DateTime.now();
  final Set<int> _pages = {};

  int get activeSeconds => _activeSeconds;

  void start(int initialPage) {
    WidgetsBinding.instance.addObserver(this);
    _pages.add(initialPage);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_foreground && DateTime.now().difference(_lastInteraction) < _idleTimeout) {
        _activeSeconds++;
      }
    });
  }

  void touch() => _lastInteraction = DateTime.now();

  void page(int page) {
    _pages.add(page);
    touch();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (_foreground && !fg) unawaited(flush());
    if (fg) touch();
    _foreground = fg;
  }

  Future<void> flush() async {
    final seconds = _activeSeconds;
    final pages = _pages.length;
    final start = _sessionStart;
    _activeSeconds = 0;
    _pages.clear();
    _sessionStart = DateTime.now();
    if (seconds < _minSessionSeconds) return;
    await db.addSession(ReadingSession(bookId: bookId, start: start, seconds: seconds, pages: pages));
    onSaved();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    await flush();
  }
}
