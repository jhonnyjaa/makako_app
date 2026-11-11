import 'dart:io';
import 'dart:ui' as ui;

import 'package:epub_plus/epub_plus.dart' show EpubReader;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../../data/app_paths.dart';
import '../../data/models.dart';

abstract final class ImportService {
  static const _uuid = Uuid();

  static Future<List<Book>> pickAndImport() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Importar libros',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'epub'],
    );
    final out = <Book>[];
    for (final f in files) {
      try {
        final book = await _import(f);
        if (book != null) out.add(book);
      } catch (e, st) {
        debugPrint('Import failed for ${f.name}: $e\n$st');
      }
    }
    return out;
  }

  static Future<Book?> _import(PlatformFile picked) async {
    final ext = (picked.extension ?? '').toLowerCase();
    if (ext != 'pdf' && ext != 'epub') return null;
    final id = _uuid.v4();
    final relPath = 'books/$id.$ext';
    await picked.xFile.saveTo(AppPaths.abs(relPath));

    final fallbackTitle = _prettyTitle(p.basenameWithoutExtension(picked.name));
    final now = DateTime.now();

    if (ext == 'pdf') {
      final meta = await _pdfMeta(AppPaths.abs(relPath), id);
      return Book(
        id: id,
        title: fallbackTitle,
        author: null,
        path: relPath,
        format: BookFormat.pdf,
        coverPath: meta.cover,
        totalPages: meta.pages,
        currentPage: 1,
        progress: 0,
        position: null,
        addedAt: now,
        lastOpenedAt: null,
        favorite: false,
        finished: false,
      );
    }

    final meta = await _epubMeta(AppPaths.abs(relPath), id);
    return Book(
      id: id,
      title: (meta.title?.trim().isNotEmpty ?? false) ? meta.title!.trim() : fallbackTitle,
      author: meta.author,
      path: relPath,
      format: BookFormat.epub,
      coverPath: meta.cover,
      totalPages: 0,
      currentPage: 0,
      progress: 0,
      position: null,
      addedAt: now,
      lastOpenedAt: null,
      favorite: false,
      finished: false,
    );
  }

  static String _prettyTitle(String raw) {
    final t = raw.replaceAll(RegExp(r'[_\-.]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return 'Sin título';
    return t[0].toUpperCase() + t.substring(1);
  }

  static Future<({int pages, String? cover})> _pdfMeta(String path, String id) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final pages = doc.pages.length;
      String? cover;
      if (pages > 0) {
        final page = doc.pages.first;
        const w = 420;
        final h = (w * page.height / page.width).round();
        final rendered = await page.render(
          width: w,
          height: h,
          fullWidth: w.toDouble(),
          fullHeight: h.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
        if (rendered != null) {
          final image = await rendered.createImage();
          rendered.dispose();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (png != null) {
            cover = 'covers/$id.png';
            await AppPaths.file(cover).writeAsBytes(png.buffer.asUint8List());
          }
        }
      }
      return (pages: pages, cover: cover);
    } finally {
      await doc.dispose();
    }
  }

  static Future<({String? title, String? author, String? cover})> _epubMeta(String path, String id) async {
    final bytes = await File(path).readAsBytes();
    // Parsing + PNG encoding is CPU heavy: keep it off the UI isolate.
    final result = await compute(_parseEpub, bytes);
    String? cover;
    if (result.cover != null) {
      cover = 'covers/$id.png';
      await AppPaths.file(cover).writeAsBytes(result.cover!);
    }
    return (title: result.title, author: result.author, cover: cover);
  }
}

Future<({String? title, String? author, Uint8List? cover})> _parseEpub(Uint8List bytes) async {
  final book = await EpubReader.readBook(bytes);
  Uint8List? cover;
  final c = book.coverImage;
  if (c != null) {
    final resized = c.width > 600 ? img.copyResize(c, width: 600) : c;
    cover = img.encodePng(resized);
  }
  return (title: book.title, author: book.author, cover: cover);
}
