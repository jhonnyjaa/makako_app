import 'dart:io';

import 'package:epub_plus/epub_plus.dart';
import 'package:flutter/foundation.dart';

class EpubSection {
  const EpubSection(this.title, this.html);
  final String title;
  final String html;
}

class EpubTocEntry {
  const EpubTocEntry(this.title, this.section, this.depth);
  final String title;
  final int section;
  final int depth;
}

/// Plain, isolate-friendly representation of an EPUB: spine sections in
/// reading order, a flattened table of contents and the embedded images.
class EpubDoc {
  const EpubDoc({required this.title, required this.sections, required this.toc, required this.images});

  final String? title;
  final List<EpubSection> sections;
  final List<EpubTocEntry> toc;
  final Map<String, Uint8List> images;

  static Future<EpubDoc> load(String path) async {
    final bytes = await File(path).readAsBytes();
    return compute(_parse, bytes);
  }

  /// Resolves an <img src> (often "../images/x.png") against the image map.
  Uint8List? image(String src) {
    var key = Uri.decodeFull(src.split('#').first);
    while (key.startsWith('../') || key.startsWith('./')) {
      key = key.substring(key.indexOf('/') + 1);
    }
    final direct = images[key];
    if (direct != null) return direct;
    for (final e in images.entries) {
      if (e.key.endsWith(key) || key.endsWith(e.key)) return e.value;
    }
    return null;
  }
}

final _bodyRe = RegExp(r'<body[^>]*>([\s\S]*)</body>', caseSensitive: false);

String _body(String html) => _bodyRe.firstMatch(html)?.group(1) ?? html;

String _stripFragment(String href) => href.split('#').first;

Future<EpubDoc> _parse(Uint8List bytes) async {
  final book = await EpubReader.readBook(bytes);
  final content = book.content;
  final htmlFiles = content?.html ?? const {};

  // Titles from the navigation tree, keyed by file.
  final titles = <String, String>{};
  final tocRaw = <(String, String, int)>[];
  void walk(List<EpubChapter> chapters, int depth) {
    for (final c in chapters) {
      final file = c.contentFileName == null ? null : _stripFragment(c.contentFileName!);
      final t = (c.title ?? '').trim();
      if (file != null) {
        if (t.isNotEmpty) titles.putIfAbsent(file, () => t);
        tocRaw.add((t.isEmpty ? 'Sin título' : t, file, depth));
      }
      walk(c.subChapters, depth + 1);
    }
  }

  walk(book.chapters, 0);

  // Reading order from the spine (falls back to chapter order).
  final manifest = {
    for (final m in book.schema?.package?.manifest?.items ?? const <EpubManifestItem>[])
      if (m.id != null && m.href != null) m.id!: m.href!,
  };
  final order = <String>[
    for (final s in book.schema?.package?.spine?.items ?? const <EpubSpineItemRef>[])
      if (s.idRef != null && manifest[s.idRef] != null && htmlFiles.containsKey(manifest[s.idRef])) manifest[s.idRef]!,
  ];
  if (order.isEmpty) {
    order.addAll(tocRaw.map((e) => e.$2).where(htmlFiles.containsKey).toSet());
  }

  final sections = <EpubSection>[];
  final indexOf = <String, int>{};
  for (final file in order) {
    if (indexOf.containsKey(file)) continue;
    final html = _body(htmlFiles[file]?.content ?? '');
    if (html.trim().isEmpty) continue;
    indexOf[file] = sections.length;
    sections.add(EpubSection(titles[file] ?? 'Sección ${sections.length + 1}', html));
  }

  final toc = [
    for (final (title, file, depth) in tocRaw)
      if (indexOf[file] != null) EpubTocEntry(title, indexOf[file]!, depth),
  ];

  final images = <String, Uint8List>{
    for (final e in (content?.images ?? const <String, EpubByteContentFile>{}).entries)
      if (e.value.content != null) e.key: Uint8List.fromList(e.value.content!),
  };

  return EpubDoc(title: book.title, sections: sections, toc: toc, images: images);
}
