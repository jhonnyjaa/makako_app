import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Thin SQLite layer. Everything is local, no accounts, no network.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'makako.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        final batch = db.batch()
          ..execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              path TEXT NOT NULL,
              format TEXT NOT NULL,
              cover_path TEXT,
              total_pages INTEGER NOT NULL DEFAULT 0,
              current_page INTEGER NOT NULL DEFAULT 1,
              progress REAL NOT NULL DEFAULT 0,
              position TEXT,
              added_at INTEGER NOT NULL,
              last_opened_at INTEGER,
              favorite INTEGER NOT NULL DEFAULT 0,
              finished INTEGER NOT NULL DEFAULT 0
            )''')
          ..execute('''
            CREATE TABLE reading_sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              start INTEGER NOT NULL,
              seconds INTEGER NOT NULL,
              pages INTEGER NOT NULL DEFAULT 0
            )''')
          ..execute('CREATE INDEX idx_sessions_start ON reading_sessions(start)')
          ..execute('''
            CREATE TABLE bookmarks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              page INTEGER NOT NULL,
              label TEXT,
              created_at INTEGER NOT NULL
            )''')
          ..execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)')
          ..execute('''
            CREATE TABLE sticker_packs (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              publisher TEXT,
              animated INTEGER NOT NULL DEFAULT 0,
              tray_path TEXT,
              version INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL
            )''')
          ..execute('''
            CREATE TABLE stickers (
              id TEXT PRIMARY KEY,
              pack_id TEXT NOT NULL REFERENCES sticker_packs(id) ON DELETE CASCADE,
              file_path TEXT NOT NULL,
              emoji TEXT,
              created_at INTEGER NOT NULL
            )''');
        await batch.commit(noResult: true);
      },
    );
    return AppDatabase._(db);
  }

  // ---------------------------------------------------------------- books
  Future<List<Book>> books() async {
    final rows = await _db.query('books', orderBy: 'COALESCE(last_opened_at, added_at) DESC');
    return rows.map(Book.fromRow).toList();
  }

  Future<void> upsertBook(Book b) =>
      _db.insert('books', b.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteBook(String id) => _db.delete('books', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------- sessions
  Future<void> addSession(ReadingSession s) => _db.insert('reading_sessions', s.toRow());

  Future<List<ReadingSession>> sessionsSince(DateTime since) async {
    final rows = await _db.query(
      'reading_sessions',
      where: 'start >= ?',
      whereArgs: [since.millisecondsSinceEpoch],
      orderBy: 'start ASC',
    );
    return rows.map(ReadingSession.fromRow).toList();
  }

  Future<({int seconds, int pages})> totals() async {
    final r = await _db.rawQuery(
      'SELECT COALESCE(SUM(seconds),0) AS s, COALESCE(SUM(pages),0) AS p FROM reading_sessions',
    );
    return (seconds: (r.first['s'] as num).toInt(), pages: (r.first['p'] as num).toInt());
  }

  /// Distinct local days (yyyy-mm-dd) with any reading, newest first.
  Future<List<DateTime>> readingDays() async {
    final rows = await _db.rawQuery(
      "SELECT DISTINCT date(start / 1000, 'unixepoch', 'localtime') AS d "
      'FROM reading_sessions ORDER BY d DESC',
    );
    return rows.map((r) => DateTime.parse(r['d']! as String)).toList();
  }

  // ------------------------------------------------------------ bookmarks
  Future<List<Bookmark>> bookmarks(String bookId) async {
    final rows = await _db.query('bookmarks', where: 'book_id = ?', whereArgs: [bookId], orderBy: 'page ASC');
    return rows.map(Bookmark.fromRow).toList();
  }

  Future<void> toggleBookmark(String bookId, int page, String label) async {
    final n = await _db.delete('bookmarks', where: 'book_id = ? AND page = ?', whereArgs: [bookId, page]);
    if (n == 0) {
      await _db.insert('bookmarks', {
        'book_id': bookId,
        'page': page,
        'label': label,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  // ------------------------------------------------------------- settings
  Future<Map<String, String>> settings() async {
    final rows = await _db.query('settings');
    return {for (final r in rows) r['key']! as String: (r['value'] as String?) ?? ''};
  }

  Future<void> setSetting(String key, String value) =>
      _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ------------------------------------------------------------- stickers
  Future<List<StickerPack>> stickerPacks() async {
    final packs = await _db.query('sticker_packs', orderBy: 'created_at DESC');
    final stickers = await _db.query('stickers', orderBy: 'created_at ASC');
    final byPack = <String, List<Sticker>>{};
    for (final s in stickers.map(Sticker.fromRow)) {
      byPack.putIfAbsent(s.packId, () => []).add(s);
    }
    return packs.map((r) {
      final pack = StickerPack.fromRow(r);
      return pack.withStickers(byPack[pack.id] ?? const []);
    }).toList();
  }

  Future<void> insertPack(StickerPack pack) => _db.insert('sticker_packs', {
    'id': pack.id,
    'name': pack.name,
    'publisher': pack.publisher,
    'animated': pack.animated ? 1 : 0,
    'tray_path': pack.trayPath,
    'version': pack.version,
    'created_at': pack.createdAt.millisecondsSinceEpoch,
  });

  Future<void> updatePack(String id, {String? trayPath, bool bumpVersion = true}) => _db.rawUpdate(
    'UPDATE sticker_packs SET tray_path = COALESCE(?, tray_path), version = version + ? WHERE id = ?',
    [trayPath, bumpVersion ? 1 : 0, id],
  );

  Future<void> deletePack(String id) => _db.delete('sticker_packs', where: 'id = ?', whereArgs: [id]);

  Future<void> insertSticker(Sticker s) => _db.insert('stickers', {
    'id': s.id,
    'pack_id': s.packId,
    'file_path': s.filePath,
    'emoji': s.emoji,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });

  Future<void> deleteSticker(String id) => _db.delete('stickers', where: 'id = ?', whereArgs: [id]);
}
