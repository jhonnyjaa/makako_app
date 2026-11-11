import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_paths.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../features/library/import_service.dart';

/// Overridden in main() once the database is open.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());

/// Raw key/value settings loaded at startup (overridden in main()).
final initialSettingsProvider = Provider<Map<String, String>>((ref) => const {});

// ------------------------------------------------------------------ settings

enum ReaderMode { paged, scroll }

enum PaperTone { white, sepia }

class AppSettings {
  const AppSettings({
    this.dailyGoalMinutes = 30,
    this.readerMode = ReaderMode.paged,
    this.paperTone = PaperTone.white,
    this.epubFontSize = 18,
    this.stickerLabUnlocked = false,
  });

  final int dailyGoalMinutes;
  final ReaderMode readerMode;
  final PaperTone paperTone;
  final double epubFontSize;
  final bool stickerLabUnlocked;

  AppSettings copyWith({
    int? dailyGoalMinutes,
    ReaderMode? readerMode,
    PaperTone? paperTone,
    double? epubFontSize,
    bool? stickerLabUnlocked,
  }) => AppSettings(
    dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
    readerMode: readerMode ?? this.readerMode,
    paperTone: paperTone ?? this.paperTone,
    epubFontSize: epubFontSize ?? this.epubFontSize,
    stickerLabUnlocked: stickerLabUnlocked ?? this.stickerLabUnlocked,
  );
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final m = ref.read(initialSettingsProvider);
    return AppSettings(
      dailyGoalMinutes: int.tryParse(m['daily_goal'] ?? '') ?? 30,
      readerMode: m['reader_mode'] == 'scroll' ? ReaderMode.scroll : ReaderMode.paged,
      paperTone: m['paper_tone'] == 'sepia' ? PaperTone.sepia : PaperTone.white,
      epubFontSize: double.tryParse(m['epub_font'] ?? '') ?? 18,
      stickerLabUnlocked: m['sticker_lab'] == '1',
    );
  }

  AppDatabase get _db => ref.read(databaseProvider);

  void setDailyGoal(int minutes) {
    state = state.copyWith(dailyGoalMinutes: minutes);
    _db.setSetting('daily_goal', '$minutes');
  }

  void setReaderMode(ReaderMode mode) {
    state = state.copyWith(readerMode: mode);
    _db.setSetting('reader_mode', mode.name);
  }

  void setPaperTone(PaperTone tone) {
    state = state.copyWith(paperTone: tone);
    _db.setSetting('paper_tone', tone.name);
  }

  void setEpubFontSize(double size) {
    state = state.copyWith(epubFontSize: size);
    _db.setSetting('epub_font', size.toStringAsFixed(0));
  }

  void unlockStickerLab() {
    state = state.copyWith(stickerLabUnlocked: true);
    _db.setSetting('sticker_lab', '1');
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ------------------------------------------------------------------- library

class LibraryNotifier extends AsyncNotifier<List<Book>> {
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<List<Book>> build() => _db.books();

  /// Opens the system picker; returns how many books were imported.
  Future<int> importFromPicker() async {
    final imported = await ImportService.pickAndImport();
    for (final b in imported) {
      await _db.upsertBook(b);
    }
    if (imported.isNotEmpty) state = AsyncData(await _db.books());
    return imported.length;
  }

  Future<void> save(Book book) async {
    await _db.upsertBook(book);
    final current = state.value ?? const <Book>[];
    state = AsyncData([
      for (final b in current) b.id == book.id ? book : b,
    ]..sort((a, b) => (b.lastOpenedAt ?? b.addedAt).compareTo(a.lastOpenedAt ?? a.addedAt)));
  }

  Future<void> toggleFavorite(Book book) => save(book.copyWith(favorite: !book.favorite));

  Future<void> markFinished(Book book, bool finished) =>
      save(book.copyWith(finished: finished, progress: finished ? 1 : book.progress));

  Future<void> rename(Book book, String title) => save(book.copyWith(title: title));

  Future<void> delete(Book book) async {
    await _db.deleteBook(book.id);
    for (final rel in [book.path, ?book.coverPath]) {
      final f = AppPaths.file(rel);
      if (await f.exists()) await f.delete();
    }
    state = AsyncData([...?state.value?.where((b) => b.id != book.id)]);
    ref.invalidate(activityProvider);
  }
}

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<Book>>(LibraryNotifier.new);

final bookByIdProvider = Provider.family<Book?, String>((ref, id) {
  final books = ref.watch(libraryProvider).value ?? const [];
  for (final b in books) {
    if (b.id == id) return b;
  }
  return null;
});

// ------------------------------------------------------------------ activity

class DayStat {
  const DayStat(this.day, this.seconds, this.pages);
  final DateTime day;
  final int seconds;
  final int pages;
  double get minutes => seconds / 60;
}

class ActivityStats {
  const ActivityStats({
    required this.days,
    required this.todaySeconds,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalSeconds,
    required this.totalPages,
    required this.secondsByBook,
  });

  /// Last [ActivityStats.heatmapDays] days, oldest first, including today.
  final List<DayStat> days;
  final int todaySeconds;
  final int currentStreak;
  final int bestStreak;
  final int totalSeconds;
  final int totalPages;

  /// Book id -> seconds over the last 30 days.
  final Map<String, int> secondsByBook;

  static const heatmapDays = 7 * 20;

  List<DayStat> get lastWeek => days.sublist(days.length - 7);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

final activityProvider = FutureProvider<ActivityStats>((ref) async {
  final db = ref.read(databaseProvider);
  final today = dateOnly(DateTime.now());
  final from = today.subtract(const Duration(days: ActivityStats.heatmapDays - 1));
  final sessions = await db.sessionsSince(from);

  final secs = <DateTime, int>{};
  final pages = <DateTime, int>{};
  final byBook = <String, int>{};
  final monthAgo = today.subtract(const Duration(days: 30));
  for (final s in sessions) {
    final d = dateOnly(s.start);
    secs[d] = (secs[d] ?? 0) + s.seconds;
    pages[d] = (pages[d] ?? 0) + s.pages;
    if (!d.isBefore(monthAgo)) byBook[s.bookId] = (byBook[s.bookId] ?? 0) + s.seconds;
  }

  final days = [
    for (var i = 0; i < ActivityStats.heatmapDays; i++)
      () {
        final d = DateTime(from.year, from.month, from.day + i);
        return DayStat(d, secs[d] ?? 0, pages[d] ?? 0);
      }(),
  ];

  // Streaks from the full history.
  final readDays = (await db.readingDays()).map(dateOnly).toSet();
  var current = 0;
  var cursor = readDays.contains(today) ? today : today.subtract(const Duration(days: 1));
  while (readDays.contains(cursor)) {
    current++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  var best = 0;
  var run = 0;
  DateTime? prev;
  for (final d in readDays.toList()..sort()) {
    run = (prev != null && d.difference(prev).inHours.round() <= 24 + 1) ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }

  final totals = await db.totals();
  return ActivityStats(
    days: days,
    todaySeconds: secs[today] ?? 0,
    currentStreak: current,
    bestStreak: best,
    totalSeconds: totals.seconds,
    totalPages: totals.pages,
    secondsByBook: byBook,
  );
});

// ------------------------------------------------------------------ stickers

final stickerPacksProvider = FutureProvider<List<StickerPack>>((ref) {
  return ref.read(databaseProvider).stickerPacks();
});

bool fileExists(String? rel) => rel != null && File(AppPaths.abs(rel)).existsSync();
