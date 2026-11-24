import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform_paths.dart';

/// Resolves OS-owned, user-visible storage for desktop platforms.
///
/// Desktop builds write user data to the real user folders (Downloads,
/// Documents, ...) so files are reachable from Explorer, survive reinstalls
/// and behave like any native application. Mobile/web keep their sandboxed
/// roots so behavior is unchanged there.
class SessionPaths {
  SessionPaths._();

  static bool get isDesktop => PlatformPaths.isDesktop;

  /// The real OS Downloads folder on desktop, and the default device Download directory on Android.
  static Future<String> downloadsDir() async {
    if (Platform.isAndroid) {
      for (final base in ['/storage/emulated/0/Download', '/sdcard/Download', '/storage/emulated/0/Downloads']) {
        final d = Directory(base);
        if (d.existsSync()) return base;
      }
      return '/storage/emulated/0/Download';
    }
    if (isDesktop) {
      final hint = PlatformPaths.defaultDownloadsHint();
      if (hint.isNotEmpty) return hint;
    }
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  /// Creates (if missing) a named subfolder inside the real Downloads folder
  /// and returns its path. Falls back to the app documents directory.
  static Future<String> downloadsSubDir(String name) async {
    final base = await downloadsDir();
    final dir = Directory(p.join(base, name));
    await dir.create(recursive: true);
    return dir.path;
  }
}