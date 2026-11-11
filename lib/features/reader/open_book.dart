import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_paths.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'epub_reader_screen.dart';
import 'pdf_reader_screen.dart';

Future<void> openBook(BuildContext context, WidgetRef ref, Book book) async {
  if (!AppPaths.file(book.path).existsSync()) {
    showToast(context, 'No se encontró el archivo de este libro');
    return;
  }
  final screen = book.format == BookFormat.pdf ? PdfReaderScreen(book: book) : EpubReaderScreen(book: book);
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => screen,
      transitionsBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
        );
      },
    ),
  );
}
