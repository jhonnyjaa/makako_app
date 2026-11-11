import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Every file path stored in the database is *relative* to [root].
/// iOS changes the sandbox path on each install/update, so absolute paths would break.
abstract final class AppPaths {
  static late final String root;

  static Future<void> init() async {
    // Android: context.filesDir  (also read by the native StickerContentProvider)
    // iOS: Library/Application Support
    final dir = await getApplicationSupportDirectory();
    root = dir.path;
    for (final sub in ['books', 'covers', 'stickers']) {
      await Directory(p.join(root, sub)).create(recursive: true);
    }
  }

  static String abs(String relative) => p.join(root, relative);
  static File file(String relative) => File(abs(relative));
  static String rel(String absolute) => p.relative(absolute, from: root);
}
