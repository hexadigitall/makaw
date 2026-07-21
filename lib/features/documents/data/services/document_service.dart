import 'dart:io';
import 'dart:convert';
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

  static const _skipDocDirs = {'Android', 'data', 'obb', 'cache', 'tmp', 'app',
    'media', 'Music', 'music', 'Alarms', 'Notifications', 'Ringtones',
    'DCIM', 'Pictures', 'Screenshots'};

  static const Map<String, String> _extCategory = {
    'pdf': 'pdf', 'epub': 'epub',
    'doc': 'doc', 'docx': 'doc',
    'txt': 'text', 'md': 'text', 'csv': 'text', 'log': 'text', 'ini': 'text', 'cfg': 'text',
    'html': 'html', 'htm': 'html', 'xhtml': 'html',
    'json': 'code', 'xml': 'code', 'yaml': 'code', 'yml': 'code',
  };

  static const List<String> _allExts = [
    '.pdf', '.epub', '.doc', '.docx',
    '.txt', '.md', '.csv', '.log', '.ini', '.cfg',
    '.html', '.htm', '.xhtml',
    '.json', '.xml', '.yaml', '.yml',
  ];

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

  void _scanFile(File entity, Set<DocumentFileInfo> found, Set<String> seenPaths) {
    try {
      final ext = entity.path.toLowerCase().split('.').last;
      if (_allExts.any((e) => e.substring(1) == ext) && seenPaths.add(entity.path)) {
        final stat = entity.statSync();
        found.add(DocumentFileInfo(
          id: entity.path.hashCode,
          filePath: entity.path,
          fileName: entity.uri.pathSegments.last,
          folder: entity.parent.uri.pathSegments.last,
          dateTime: stat.modified,
          fileSize: stat.size,
          category: getCategoryForExt(ext),
        ));
      }
    } catch (_) {}
  }

  Future<void> scanAllDocuments() async {
    _isScanning = true;
    notifyListeners();
    final found = <DocumentFileInfo>{};
    final seenPaths = <String>{};
    for (final dirPath in _scanDirs) {
      await _scanDocDir(dirPath, found, seenPaths, depth: 0);
    }
    _allDocuments = found.toList();
    _organize();
    _isScanning = false;
    notifyListeners();
  }

  Future<void> _scanDocDir(String path, Set<DocumentFileInfo> found, Set<String> seenPaths, {required int depth}) async {
    if (depth > 5) return;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is Directory) {
          final name = entity.uri.pathSegments.last;
          if (_skipDocDirs.contains(name)) continue;
          await _scanDocDir(entity.path, found, seenPaths, depth: depth + 1);
        } else if (entity is File) {
          _scanFile(entity, found, seenPaths);
        }
      }
    } catch (_) {}
  }

  void _organize() {
    _byCategory = {};
    _folders = {};
    for (final doc in _allDocuments) {
      _byCategory.putIfAbsent(doc.category, () => []).add(doc);
      _folders.putIfAbsent(doc.folder, () => []).add(doc);
    }
    for (final f in _folders.values) {
      f.sort((a, b) => (b.dateTime ?? DateTime.now()).compareTo(a.dateTime ?? DateTime.now()));
    }
    _allDocuments.sort((a, b) => (b.dateTime ?? DateTime.now()).compareTo(a.dateTime ?? DateTime.now()));
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
}
