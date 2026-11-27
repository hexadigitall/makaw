import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../domain/entities/document_file_info.dart';
import '../../domain/document_format_registry.dart';
import '../../../../core/platform/platform_paths.dart';
import '../../../../core/platform/file_exclusion_filter.dart';
import '../../../../core/storage/file_recents_service.dart';
import 'document_state_service.dart';
export '../../domain/entities/document_file_info.dart';
export '../../domain/document_format_registry.dart';

class DocumentService extends ChangeNotifier {
  List<DocumentFileInfo> _allDocuments = [];
  List<DocumentFileInfo> get allDocuments => _allDocuments;

  Map<String, List<DocumentFileInfo>> _byCategory = {};
  Map<String, List<DocumentFileInfo>> get byCategory => _byCategory;

  Map<DocumentFamily, List<DocumentFileInfo>> _byFamily = {};
  Map<DocumentFamily, List<DocumentFileInfo>> get byFamily => _byFamily;

  Map<String, List<DocumentFileInfo>> _folders = {};
  Map<String, List<DocumentFileInfo>> get folders => _folders;

  List<int> _favoriteIds = [];
  List<int> get favoriteIds => _favoriteIds;

  List<String> _customScanDirs = [];
  List<String> get customScanDirs => List.unmodifiable(_customScanDirs);

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  static const List<String> _androidScanDirs = [
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Books',
    '/storage/emulated/0/eBooks',
    '/storage/emulated/0/PDF',
    '/storage/emulated/0/Notes',
    '/storage/emulated/0/Comics',
    '/storage/emulated/0/Makaw',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Documents',
  ];

  String getCategoryForExt(String ext) => DocumentFormatRegistry.categoryFor(ext);

  DocumentFamily getFamilyForDoc(DocumentFileInfo doc) =>
      DocumentFormatRegistry.familyFor(doc.fileName);

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

  /// Platform-aware document scan roots (Android curated dirs + user custom dirs
  /// on mobile, OS-native user folders + custom dirs on desktop).
  List<String> _scanDirsForPlatform() {
    final base = PlatformPaths.isDesktop
        ? PlatformPaths.documentScanDirs()
        : _androidScanDirs;
    final combined = <String>{...base, ..._customScanDirs};
    return combined.toList();
  }

  Future<void> addCustomScanDir(String dirPath) async {
    if (dirPath.trim().isEmpty) return;
    if (_customScanDirs.contains(dirPath)) return;
    _customScanDirs = [..._customScanDirs, dirPath];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('document_custom_dirs', _customScanDirs);
    } catch (_) {}
    notifyListeners();
    await scanAllDocuments();
  }

  Future<void> removeCustomScanDir(String dirPath) async {
    _customScanDirs = _customScanDirs.where((d) => d != dirPath).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('document_custom_dirs', _customScanDirs);
    } catch (_) {}
    notifyListeners();
    await scanAllDocuments();
  }

  /// Scans all document directories in a background isolate to avoid blocking UI.
  Future<void> scanAllDocuments() async {
    _isScanning = true;
    notifyListeners();
    try {
      await _loadCustomDirs();
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        _isScanning = false;
        notifyListeners();
        return;
      }
      final result = await compute(_scanInBackground, _scanDirsForPlatform());
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

  Future<void> _loadCustomDirs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customScanDirs = prefs.getStringList('document_custom_dirs') ?? [];
    } catch (_) {}
  }

  static const Set<String> _staticSkipDirs = {
    'Android', 'data', 'obb', 'cache', 'tmp', 'app',
    'media', 'Music', 'music', 'Alarms', 'Notifications', 'Ringtones',
    'DCIM', 'Pictures', 'Screenshots', 'node_modules', '.git', 'build',
    '.dart_tool', '.venv', 'venv', 'target', 'dist', 'pub_cache', '.gradle',
    'makaw_projects',
  };

  /// Seeds in-memory documents in unit/widget tests without scanning disk.
  @visibleForTesting
  void seedDocumentsForTest(List<DocumentFileInfo> docs) {
    _allDocuments = List<DocumentFileInfo>.from(docs);
    _organize();
    notifyListeners();
  }

  /// Top-level function for compute() — runs in a background isolate.
  static List<Map<String, dynamic>> _scanInBackground(List<String> scanDirs) {
    final found = <Map<String, dynamic>>[];
    final seenPaths = <String>{};
    for (final dirPath in scanDirs) {
      if (found.length >= 4000) break;
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
    if (depth > 4 || found.length >= 4000) return;
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      final entities = dir.listSync(recursive: false, followLinks: false);
      for (final entity in entities) {
        if (entity is Directory) {
          final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
          if (_staticSkipDirs.contains(name) || FileExclusionFilter.isSystemDirectory(name)) continue;
          _scanDirStatic(entity.path, found, seenPaths, depth + 1);
        } else if (entity is File) {
          try {
            if (FileExclusionFilter.shouldExclude(entity.path)) continue;
            final ext = DocumentFormatRegistry.normalizeExtension(entity.path);
            if (DocumentFormatRegistry.isSupportedExtension(ext) && seenPaths.add(entity.path)) {
              final stat = entity.statSync();
              if (stat.size == 0) continue;
              final folderPath = entity.parent.path;
              found.add({
                'filePath': entity.path,
                'fileName': entity.uri.pathSegments.isNotEmpty
                    ? entity.uri.pathSegments.last
                    : entity.path.split('/').last,
                'folder': folderPath,
                'dateTime': stat.modified.toIso8601String(),
                'fileSize': stat.size,
                'category': DocumentFormatRegistry.categoryFor(ext),
              });
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  void _organize() {
    _byCategory = {};
    _byFamily = {};
    _folders = {};
    for (final doc in _allDocuments) {
      _byCategory.putIfAbsent(doc.category, () => []).add(doc);
      final family = DocumentFormatRegistry.familyFor(doc.fileName);
      _byFamily.putIfAbsent(family, () => []).add(doc);
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
    await DocumentStateService.saveProgress(
      filePath,
      currentPage: page + 1,
      scrollProgress: progress,
    );
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

  /// Record an "open" of a document file so it surfaces in recent activity.
  Future<void> recordRecentOpen(String filePath) async {
    try {
      await FileRecentsService.record(filePath);
    } catch (_) {}
  }

  /// Recently-opened document files (intersected with the scanned document list),
  /// most recently opened first.
  Future<List<DocumentFileInfo>> recentDocuments() async {
    try {
      final recents = await FileRecentsService.getRecents(limit: 50);
      final byPath = <String, DocumentFileInfo>{};
      for (final d in _allDocuments) {
        byPath[d.filePath] = d;
      }
      final result = <DocumentFileInfo>[];
      for (final r in recents) {
        if (r.isDirectory) continue;
        final doc = byPath[r.path];
        if (doc != null) result.add(doc);
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// Display-friendly folder name (extracts basename from full path).
  static String folderDisplayName(String fullPath) {
    final segs = fullPath.split(RegExp(r'[/\\]'));
    return segs.isNotEmpty ? segs.last : fullPath;
  }
}
