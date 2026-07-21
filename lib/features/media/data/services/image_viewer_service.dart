import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/image_file_info.dart';
export '../../domain/entities/image_file_info.dart';

class ImageViewerService extends ChangeNotifier {
  List<ImageFileInfo> _allImages = [];
  List<ImageFileInfo> get allImages => _allImages;

  Map<String, List<ImageFileInfo>> _folders = {};
  Map<String, List<ImageFileInfo>> get folders => _folders;

  Map<String, Map<String, List<ImageFileInfo>>> _byDate = {};
  Map<String, Map<String, List<ImageFileInfo>>> get byDate => _byDate;

  List<int> _favoriteIds = [];
  List<int> get favoriteIds => _favoriteIds;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  final List<String> _imgExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif'];

  Future<void> scanAllImages() async {
    _isScanning = true;
    notifyListeners();
    final found = <ImageFileInfo>{};
    final seenPaths = <String>{};
    final dirs = [
      '/storage/emulated/0/DCIM', '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Screenshots', '/storage/emulated/0/Download',
    ];
    for (final dirPath in dirs) {
      await _scanDir(dirPath, found, seenPaths, depth: 0);
    }
    _allImages = found.toList();
    _organize();
    _isScanning = false;
    notifyListeners();
  }

  Future<void> _scanDir(String path, Set<ImageFileInfo> found, Set<String> seenPaths, {required int depth}) async {
    if (depth > 5) return;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is Directory) {
          await _scanDir(entity.path, found, seenPaths, depth: depth + 1);
        } else if (entity is File && _imgExts.any((e) => entity.path.toLowerCase().endsWith(e)) && seenPaths.add(entity.path)) {
          try {
            final stat = entity.statSync();
            found.add(ImageFileInfo(
              id: entity.path.hashCode,
              filePath: entity.path,
              fileName: entity.uri.pathSegments.last,
              folder: entity.parent.uri.pathSegments.last,
              dateTime: stat.modified,
              fileSize: stat.size,
            ));
          } catch (_) { }
        }
      }
    } catch (_) {}
  }

  void _organize() {
    _folders = {};
    _byDate = {};
    for (final img in _allImages) {
      _folders.putIfAbsent(img.folder, () => []).add(img);
      final date = img.dateTime ?? DateTime.now();
      final year = DateFormat('yyyy').format(date);
      final month = DateFormat('MMMM yyyy').format(date);
      _byDate.putIfAbsent(year, () => {}).putIfAbsent(month, () => []).add(img);
    }
    for (final f in _folders.values) {
      f.sort((a, b) => (b.dateTime ?? DateTime.now()).compareTo(a.dateTime ?? DateTime.now()));
    }
    _byDate.forEach((_, months) {
      months.forEach((_, imgs) {
        imgs.sort((a, b) => (b.dateTime ?? DateTime.now()).compareTo(a.dateTime ?? DateTime.now()));
      });
    });
    _allImages.sort((a, b) => (b.dateTime ?? DateTime.now()).compareTo(a.dateTime ?? DateTime.now()));
  }

  void toggleFavorite(int id) {
    if (_favoriteIds.contains(id)) { _favoriteIds.remove(id); }
    else { _favoriteIds.add(id); }
    _saveFavorites();
    notifyListeners();
  }

  bool isFavorite(int id) => _favoriteIds.contains(id);
  List<ImageFileInfo> get favorites => _allImages.where((i) => _favoriteIds.contains(i.id)).toList();

  void moveToTrash(ImageFileInfo image) {
    _allImages.removeWhere((i) => i.id == image.id);
    _organize();
    _saveTrash();
    notifyListeners();
  }

  void restoreFromTrash(ImageFileInfo image) {
    _allImages.add(image);
    _organize();
    _saveTrash();
    notifyListeners();
  }

  void emptyTrash() { _saveTrash(); notifyListeners(); }

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('image_favorites');
    if (data != null) _favoriteIds = (jsonDecode(data) as List).cast<int>();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('image_favorites', jsonEncode(_favoriteIds));
  }

  List<Map<String, dynamic>> _trash = [];

  List<Map<String, dynamic>> get trash => _trash;

  List<ImageFileInfo> get trashImages {
    return _trash.map((e) => ImageFileInfo(
      id: e['id'] as int,
      filePath: e['path'] as String,
      fileName: e['name'] as String,
      folder: e['folder'] as String,
      fileSize: e['size'] as int,
    )).toList();
  }

  Future<void> loadTrash() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('image_trash');
    if (data != null) _trash = (jsonDecode(data) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _saveTrash() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('image_trash', jsonEncode(_trash));
  }

  void addTrashEntry(ImageFileInfo img) {
    _trash.add({'id': img.id, 'path': img.filePath, 'name': img.fileName, 'folder': img.folder, 'size': img.fileSize});
    _saveTrash();
  }

  void removeTrashEntry(int id) {
    _trash.removeWhere((e) => e['id'] == id);
    _saveTrash();
  }
}
