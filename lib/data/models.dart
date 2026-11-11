enum BookFormat {
  pdf,
  epub;

  static BookFormat fromExtension(String ext) => ext.toLowerCase() == 'epub' ? epub : pdf;
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.path,
    required this.format,
    required this.coverPath,
    required this.totalPages,
    required this.currentPage,
    required this.progress,
    required this.position,
    required this.addedAt,
    required this.lastOpenedAt,
    required this.favorite,
    required this.finished,
  });

  final String id;
  final String title;
  final String? author;
  final String path;
  final BookFormat format;
  final String? coverPath;
  final int totalPages;

  /// 1-based page for PDFs; chapter/paragraph index for EPUBs.
  final int currentPage;

  /// 0..1
  final double progress;

  /// Format specific position (EPUB CFI).
  final String? position;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final bool favorite;
  final bool finished;

  bool get started => progress > 0.001;

  Book copyWith({
    String? title,
    String? author,
    int? totalPages,
    int? currentPage,
    double? progress,
    String? position,
    DateTime? lastOpenedAt,
    bool? favorite,
    bool? finished,
  }) => Book(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    path: path,
    format: format,
    coverPath: coverPath,
    totalPages: totalPages ?? this.totalPages,
    currentPage: currentPage ?? this.currentPage,
    progress: progress ?? this.progress,
    position: position ?? this.position,
    addedAt: addedAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    favorite: favorite ?? this.favorite,
    finished: finished ?? this.finished,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'author': author,
    'path': path,
    'format': format.name,
    'cover_path': coverPath,
    'total_pages': totalPages,
    'current_page': currentPage,
    'progress': progress,
    'position': position,
    'added_at': addedAt.millisecondsSinceEpoch,
    'last_opened_at': lastOpenedAt?.millisecondsSinceEpoch,
    'favorite': favorite ? 1 : 0,
    'finished': finished ? 1 : 0,
  };

  factory Book.fromRow(Map<String, Object?> r) => Book(
    id: r['id']! as String,
    title: r['title']! as String,
    author: r['author'] as String?,
    path: r['path']! as String,
    format: BookFormat.values.byName(r['format']! as String),
    coverPath: r['cover_path'] as String?,
    totalPages: (r['total_pages'] as int?) ?? 0,
    currentPage: (r['current_page'] as int?) ?? 1,
    progress: ((r['progress'] as num?) ?? 0).toDouble(),
    position: r['position'] as String?,
    addedAt: DateTime.fromMillisecondsSinceEpoch(r['added_at']! as int),
    lastOpenedAt: r['last_opened_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r['last_opened_at']! as int),
    favorite: r['favorite'] == 1,
    finished: r['finished'] == 1,
  );
}

class ReadingSession {
  const ReadingSession({
    this.id,
    required this.bookId,
    required this.start,
    required this.seconds,
    required this.pages,
  });

  final int? id;
  final String bookId;
  final DateTime start;
  final int seconds;
  final int pages;

  Map<String, Object?> toRow() => {
    'book_id': bookId,
    'start': start.millisecondsSinceEpoch,
    'seconds': seconds,
    'pages': pages,
  };

  factory ReadingSession.fromRow(Map<String, Object?> r) => ReadingSession(
    id: r['id'] as int?,
    bookId: r['book_id']! as String,
    start: DateTime.fromMillisecondsSinceEpoch(r['start']! as int),
    seconds: r['seconds']! as int,
    pages: (r['pages'] as int?) ?? 0,
  );
}

class Bookmark {
  const Bookmark({this.id, required this.bookId, required this.page, required this.label, required this.createdAt});

  final int? id;
  final String bookId;
  final int page;
  final String label;
  final DateTime createdAt;

  factory Bookmark.fromRow(Map<String, Object?> r) => Bookmark(
    id: r['id'] as int?,
    bookId: r['book_id']! as String,
    page: r['page']! as int,
    label: (r['label'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
  );
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    required this.publisher,
    required this.animated,
    required this.trayPath,
    required this.version,
    required this.createdAt,
    this.stickers = const [],
  });

  final String id;
  final String name;
  final String publisher;
  final bool animated;
  final String? trayPath;
  final int version;
  final DateTime createdAt;
  final List<Sticker> stickers;

  static const minStickers = 3;
  static const maxStickers = 30;

  bool get readyForWhatsApp => stickers.length >= minStickers && trayPath != null;

  StickerPack withStickers(List<Sticker> s) => StickerPack(
    id: id,
    name: name,
    publisher: publisher,
    animated: animated,
    trayPath: trayPath,
    version: version,
    createdAt: createdAt,
    stickers: s,
  );

  factory StickerPack.fromRow(Map<String, Object?> r) => StickerPack(
    id: r['id']! as String,
    name: r['name']! as String,
    publisher: (r['publisher'] as String?) ?? 'Makako',
    animated: r['animated'] == 1,
    trayPath: r['tray_path'] as String?,
    version: (r['version'] as int?) ?? 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
  );
}

class Sticker {
  const Sticker({required this.id, required this.packId, required this.filePath, required this.emoji});

  final String id;
  final String packId;
  final String filePath;
  final String emoji;

  factory Sticker.fromRow(Map<String, Object?> r) => Sticker(
    id: r['id']! as String,
    packId: r['pack_id']! as String,
    filePath: r['file_path']! as String,
    emoji: (r['emoji'] as String?) ?? '😀',
  );
}
