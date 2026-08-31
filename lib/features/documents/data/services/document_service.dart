import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/document_file_info.dart';
export '../../domain/entities/document_file_info.dart';

class DocumentService extends ChangeNotifier {
  List<DocumentFileInfo> _allDocuments = [];
  List<DocumentFileInfo> get allDocuments => _allDocuments;

  Map<String, List<DocumentFileInfo>> _byCategory = {};
  Map<String, List<DocumentFileInfo>> get byCategory => _byCategory;

  Map<String, List<DocumentFileInfo>> _folders = {};
  Map<String, List<DocumentFileInfo>> get folders => _folders;

  List<int> _favoriteIds = [];
  List<int> get favoriteIds => _favoriteIds;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  static const Map<String, String> _extCategory = {
    'pdf': 'pdf', 'epub': 'epub',
    'doc': 'doc', 'docx': 'doc', 'odt': 'doc', 'rtf': 'doc', 'pages': 'doc',
    'txt': 'text', 'md': 'text', 'csv': 'text', 'log': 'text', 'ini': 'text', 'cfg': 'text',
    'html': 'html', 'htm': 'html', 'xhtml': 'html',
    'json': 'code', 'xml': 'code', 'yaml': 'code', 'yml': 'code',
  };

  static const List<String> _scanDirs = [
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Books',
    '/storage/emulated/0/eBooks',
    '/storage/emulated/0/PDF',
    '/storage/emulated/0/Notes',
  ];

  String getCategoryForExt(String ext) {
    final key = ext.replaceAll('.', '').toLowerCase();
    return _extCategory[key] ?? 'other';
  }

  Future<bool> _checkPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.manageExternalStorage.status;
      if (status.isGranted) return true;
      final result = await Permission.manageExternalStorage.request();
      return result.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Scans all document directories in a background isolate to avoid blocking UI.
  Future<void> scanAllDocuments() async {
    _isScanning = true;
    notifyListeners();
    try {
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        _isScanning = false;
        notifyListeners();
        return;
      }
      final result = await compute(_scanInBackground, _scanDirs);
      _allDocuments = result.map((m) => DocumentFileInfo(
        id: m['filePath'].hashCode,
        filePath: m['filePath'] as String,
        fileName: m['fileName'] as String,
        folder: m['folder'] as String,
        dateTime: m['dateTime'] != null ? DateTime.tryParse(m['dateTime'] as String) : null,
        fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
        category: m['category'] as String,
      )).toList();
      _organize();
    } catch (_) {}
    _isScanning = false;
    notifyListeners();
  }

  static const Map<String, String> _staticExtCategory = {
    'pdf': 'pdf', 'epub': 'epub',
    'doc': 'doc', 'docx': 'doc',
    'txt': 'text', 'md': 'text', 'csv': 'text', 'log': 'text', 'ini': 'text', 'cfg': 'text',
    'html': 'html', 'htm': 'html', 'xhtml': 'html',
    'json': 'code', 'xml': 'code', 'yaml': 'code', 'yml': 'code',
  };

  static const List<String> _staticAllExts = [
    '.pdf', '.epub', '.doc', '.docx',
    '.txt', '.md', '.csv', '.log', '.ini', '.cfg',
    '.html', '.htm', '.xhtml',
    '.json', '.xml', '.yaml', '.yml',
  ];

  static const Set<String> _staticSkipDirs = {'Android', 'data', 'obb', 'cache', 'tmp', 'app',
    'media', 'Music', 'music', 'Alarms', 'Notifications', 'Ringtones',
    'DCIM', 'Pictures', 'Screenshots'};

  /// Top-level function for compute() — runs in a background isolate.
  static List<Map<String, dynamic>> _scanInBackground(List<String> scanDirs) {
    final found = <Map<String, dynamic>>[];
    final seenPaths = <String>{};
    for (final dirPath in scanDirs) {
      _scanDirStatic(dirPath, found, seenPaths, 0);
    }
    // Sort newest first
    found.sort((a, b) {
      final da = a['dateTime'] != null ? DateTime.tryParse(a['dateTime'] as String) : null;
      final db = b['dateTime'] != null ? DateTime.tryParse(b['dateTime'] as String) : null;
      return (db ?? DateTime(0)).compareTo(da ?? DateTime(0));
    });
    return found;
  }

  static void _scanDirStatic(String path, List<Map<String, dynamic>> found, Set<String> seenPaths, int depth) {
    if (depth > 5) return;
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      final entities = dir.listSync(recursive: false, followLinks: false);
      for (final entity in entities) {
        if (entity is Directory) {
          final name = entity.uri.pathSegments.isNotEmpty ? entity.uri.pathSegments.last : '';
          if (_staticSkipDirs.contains(name)) continue;
          _scanDirStatic(entity.path, found, seenPaths, depth + 1);
        } else if (entity is File) {
          try {
            final ext = entity.path.toLowerCase().split('.').last;
            if (_staticAllExts.any((e) => e.substring(1) == ext) && seenPaths.add(entity.path)) {
              final stat = entity.statSync();
              final folderPath = entity.parent.path;
              found.add({
                'filePath': entity.path,
                'fileName': entity.uri.pathSegments.isNotEmpty ? entity.uri.pathSegments.last : entity.path.split('/').last,
                'folder': folderPath,
                'dateTime': stat.modified.toIso8601String(),
                'fileSize': stat.size,
                'category': _staticExtCategory[ext] ?? 'other',
              });
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  void _organize() {
    _byCategory = {};
    _folders = {};
    for (final doc in _allDocuments) {
      _byCategory.putIfAbsent(doc.category, () => []).add(doc);
      // Use full folder path as key to avoid name collisions
      _folders.putIfAbsent(doc.folder, () => []).add(doc);
    }
    for (final f in _folders.values) {
      f.sort((a, b) => (b.dateTime ?? DateTime.now()).compareTo(a.dateTime ?? DateTime.now()));
    }
  }

  void toggleFavorite(int id) {
    if (_favoriteIds.contains(id)) { _favoriteIds.remove(id); }
    else { _favoriteIds.add(id); }
    _saveFavorites();
    notifyListeners();
  }

  bool isFavorite(int id) => _favoriteIds.contains(id);
  List<DocumentFileInfo> get favorites => _allDocuments.where((d) => _favoriteIds.contains(d.id)).toList();

  Map<String, List<DocumentFileInfo>> get favoriteFolders {
    final map = <String, List<DocumentFileInfo>>{};
    for (final d in favorites) {
      map.putIfAbsent(d.folder, () => []).add(d);
    }
    return map;
  }

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('document_favorites');
    if (data != null) _favoriteIds = (jsonDecode(data) as List).cast<int>();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('document_favorites', jsonEncode(_favoriteIds));
  }

  // ── Reading position tracking ────────────────────────────────────────────

  Future<void> saveReadingPosition(String filePath, int page, {double? progress}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'doc_pos_${filePath.hashCode}';
    await prefs.setString(key, jsonEncode({'page': page, 'progress': progress, 'ts': DateTime.now().toIso8601String()}));
  }

  Future<Map<String, dynamic>?> getReadingPosition(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'doc_pos_${filePath.hashCode}';
    final data = prefs.getString(key);
    if (data != null) return jsonDecode(data) as Map<String, dynamic>;
    return null;
  }

  /// Display-friendly folder name (extracts basename from full path).
  static String folderDisplayName(String fullPath) {
    final segs = fullPath.split(RegExp(r'[/\\]'));
    return segs.isNotEmpty ? segs.last : fullPath;
  }
}
