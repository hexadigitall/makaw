import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/platform/platform_paths.dart';

/// A single entry in a directory listing produced by [DeviceFileBrowser].
class DeviceEntry {
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String ext;
  const DeviceEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.size = 0,
    required this.modified,
    this.ext = '',
  });

  /// Display-friendly file size (B/KB/MB/GB).
  String get sizeLabel {
    if (isDirectory) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double s = size.toDouble();
    int u = 0;
    while (s >= 1024 && u < units.length - 1) {
      s /= 1024;
      u++;
    }
    return s.toStringAsFixed(s < 10 && u > 0 ? 1 : 0) + ' ' + units[u];
  }
}

/// A "quick access" root shown at the top of the device File Explorer.
class QuickAccessRoot {
  final String label;
  final String path;
  final IconKind kind;
  const QuickAccessRoot(this.label, this.path, this.kind);
}

enum IconKind { home, download, doc, picture, music, video, android, root }

/// Full-device file explorer helper.
///
/// Uses Android's All-Files-Access (MANAGE_EXTERNAL_STORAGE) permission to
/// browse the entire filesystem tree (including root-level system directories),
/// listing **all** file types — not just documents.
class DeviceFileBrowser {
  DeviceFileBrowser._();

  /// Convenience quick-access roots pointing at common storage locations,
  /// resolved per platform (Android legacy emulated storage, or the OS-native
  /// user folders + drives on desktop).
  static List<QuickAccessRoot> quickAccessRoots() {
    const names = {
      'download': IconKind.download,
      'doc': IconKind.doc,
      'picture': IconKind.picture,
      'music': IconKind.music,
      'video': IconKind.video,
      'android': IconKind.android,
      'root': IconKind.root,
      'home': IconKind.home,
    };
    return PlatformPaths.quickAccessRoots()
        .map((r) => QuickAccessRoot(r.label, r.path, names[r.kind] ?? IconKind.home))
        .toList();
  }

  /// Whether the device root (/) is reachable for browsing.
  static bool get canBrowseRoot {
    if (!Platform.isAndroid) return true;
    try {
      return Directory('/').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Ensures All-Files-Access is granted. Returns `true` if usable.
  static Future<bool> ensureManageStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      var status = await Permission.manageExternalStorage.status;
      if (status.isGranted) return true;
      status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasManageStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await Permission.manageExternalStorage.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Lists the immediate contents of [dirPath]. Directories first (sorted
  /// alphabetically), then files (sorted alphabetically). Throws on error.
  static List<DeviceEntry> listDirectory(String dirPath) {
    final out = <DeviceEntry>[];
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return out;
    final dirs = <DeviceEntry>[];
    final files = <DeviceEntry>[];
    final entities = dir.listSync(followLinks: false);
    for (final entity in entities) {
      try {
        final name = _nameOf(entity.path);
        if (name.startsWith('.') && name != '.') continue;
        if (entity is Directory) {
          dirs.add(DeviceEntry(
            path: entity.path,
            name: name,
            isDirectory: true,
            modified: entity.statSync().modified,
          ));
        } else if (entity is File) {
          final stat = entity.statSync();
          final fname = name;
          final dot = fname.lastIndexOf('.');
          files.add(DeviceEntry(
            path: entity.path,
            name: fname,
            isDirectory: false,
            size: stat.size,
            modified: stat.modified,
            ext: dot >= 0 ? fname.substring(dot + 1).toLowerCase() : '',
          ));
        }
      } catch (_) {}
    }
    dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    out.addAll(dirs);
    out.addAll(files);
    return out;
  }

  static String _nameOf(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isNotEmpty ? parts.last : path;
  }
}