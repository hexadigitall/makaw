import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoFileInfo {
  final int id;
  final String filePath;
  final String fileName;
  final String folder;
  final DateTime? dateTime;
  final int fileSize;
  VideoFileInfo({
    required this.id, required this.filePath, required this.fileName,
    required this.folder, this.dateTime, required this.fileSize,
  });
}

class VideoPlayerService extends ChangeNotifier {
  List<VideoFileInfo> _allVideos = [];
  List<VideoFileInfo> get allVideos => _allVideos;

  Map<String, List<VideoFileInfo>> _folders = {};
  Map<String, List<VideoFileInfo>> get folders => _folders;

  Set<String> _favoriteFolders = {};
  Set<String> get favoriteFolderPaths => _favoriteFolders;

  List<int> _favoriteIds = [];
  List<int> get favoriteIds => _favoriteIds;

  List<Map<String, dynamic>> _playlists = [];
  List<Map<String, dynamic>> get playlists => _playlists;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  final List<String> _videoExts = ['.mp4', '.mkv', '.webm', '.avi', '.mov', '.flv', '.wmv', '.3gp'];

  final Map<String, Map<String, int>> _resumeData = {};

  int resumePosition(String filePath) => _resumeData[filePath]?['pos'] ?? 0;
  int videoDuration(String filePath) => _resumeData[filePath]?['dur'] ?? 0;
  bool hasResume(String filePath) => _resumeData.containsKey(filePath) && (_resumeData[filePath]?['pos'] ?? 0) > 0;

  double resumeProgress(String filePath) {
    final d = _resumeData[filePath];
    if (d == null) return 0;
    final pos = d['pos'] ?? 0;
    final dur = d['dur'] ?? 1;
    return dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
  }

  bool isCompleted(String filePath, {int thresholdSec = 45}) {
    final d = _resumeData[filePath];
    if (d == null) return false;
    final pos = d['pos'] ?? 0;
    final dur = d['dur'] ?? 0;
    return dur > 0 && (dur - pos) <= (thresholdSec * 1000);
  }

  bool isNewFile(String filePath, {int hours = 48}) {
    final f = File(filePath);
    if (!f.existsSync()) return false;
    try {
      final modified = f.statSync().modified;
      return DateTime.now().difference(modified).inHours < hours;
    } catch (_) {
      return false;
    }
  }

  void saveResume(String filePath, int positionMs, int durationMs) {
    if (positionMs <= 0) return;
    _resumeData[filePath] = {'pos': positionMs, 'dur': durationMs};
    _saveResumePositions();
    notifyListeners();
  }

  void clearResume(String filePath) {
    _resumeData.remove(filePath);
    _saveResumePositions();
    notifyListeners();
  }

  Future<void> scanAllVideos() async {
    _isScanning = true;
    notifyListeners();
    final found = <VideoFileInfo>{};
    final seenPaths = <String>{};
    final dirsToScan = <String>{};

    // Discover all top-level directories under root (fast — not recursive)
    try {
      final root = Directory('/storage/emulated/0');
      if (await root.exists()) {
        await for (final entity in root.list(recursive: false, followLinks: false)) {
          if (entity is Directory) dirsToScan.add(entity.path);
        }
      }
    } catch (_) {}

    // Ensure common media dirs are always included (may be nested deeper)
    for (final d in ['DCIM', 'Movies', 'Download', 'WhatsApp', 'Pictures',
                     'Camera', 'Music', 'Videos', 'Video', 'Filmora',
                     'WhatsApp Business', 'Podcasts', 'Recordings', 'ScreenRecorder',
                     'Screenshots', 'Edited', 'Insave', 'ShareChat', 'MX Player',
                     'VMate', 'Likee', 'Clip', 'TikTok', 'CapCut', 'KineMaster',
                     'Alight Motion', 'PowerDirector', 'FilmoraGo', 'VLLO',
                     'Snapchat', 'Instagram', 'Facebook', 'Telegram']) {
      dirsToScan.add('/storage/emulated/0/$d');
    }

    // Scan each directory async with streaming
    for (final dirPath in dirsToScan) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      await _scanDirStream(dir, found, seenPaths);
    }

    // SD card if accessible
    for (final sd in ['/storage/0000-0000', '/storage/extSdCard', '/sdcard1', '/external_sd']) {
      final dir = Directory(sd);
      if (await dir.exists()) {
        try {
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File && seenPaths.add(entity.path) && _videoExts.any((e) => entity.path.toLowerCase().endsWith(e))) {
              try {
                final stat = await entity.stat();
                final f = entity.parent.uri.pathSegments.last;
                found.add(VideoFileInfo(
                  id: entity.path.hashCode, filePath: entity.path,
                  fileName: entity.uri.pathSegments.last,
                  folder: f == 'emulated' ? entity.parent.parent.uri.pathSegments.last : f,
                  dateTime: stat.modified, fileSize: stat.size,
                ));
              } catch (_) {}
              if (found.length % 3 == 0) { _allVideos = found.toList(); _organize(); notifyListeners(); }
            }
          }
        } catch (_) {}
      }
    }

    _allVideos = found.toList();
    _organize();
    _isScanning = false;
    notifyListeners();
  }

  Future<void> _scanDirStream(Directory dir, Set<VideoFileInfo> found, Set<String> seenPaths, {int depth = 0}) async {
    if (depth > 6) return;
    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is Directory) {
          await _scanDirStream(entity, found, seenPaths, depth: depth + 1);
        } else if (entity is File && seenPaths.add(entity.path) && _videoExts.any((e) => entity.path.toLowerCase().endsWith(e))) {
          try {
            final stat = await entity.stat();
            final f = entity.parent.uri.pathSegments.last;
            found.add(VideoFileInfo(
              id: entity.path.hashCode, filePath: entity.path,
              fileName: entity.uri.pathSegments.last,
              folder: f == 'emulated' ? entity.parent.parent.uri.pathSegments.last : f,
              dateTime: stat.modified, fileSize: stat.size,
            ));
          } catch (_) {}
          if (found.length % 5 == 0) { _allVideos = found.toList(); _organize(); notifyListeners(); }
        }
      }
    } catch (_) {}
  }

  void _organize() {
    _folders = {};
    for (final v in _allVideos) {
      _folders.putIfAbsent(v.folder, () => []).add(v);
    }
    for (final f in _folders.values) {
      f.sort((a, b) => (b.dateTime ?? DateTime.now()).compareTo(a.dateTime ?? DateTime.now()));
    }
    _allVideos.sort((a, b) => (b.dateTime ?? DateTime.now()).compareTo(a.dateTime ?? DateTime.now()));
  }

  void toggleFavorite(int id) {
    if (_favoriteIds.contains(id)) { _favoriteIds.remove(id); }
    else { _favoriteIds.add(id); }
    _saveFavorites();
    notifyListeners();
  }

  bool isFavorite(int id) => _favoriteIds.contains(id);
  List<VideoFileInfo> get favorites => _allVideos.where((v) => _favoriteIds.contains(v.id)).toList();

  Map<String, List<VideoFileInfo>> get favoriteFolders {
    final map = <String, List<VideoFileInfo>>{};
    // Include folders with favourited videos
    for (final v in favorites) {
      map.putIfAbsent(v.folder, () => []).add(v);
    }
    // Also include explicitly favourited folders
    for (final f in _favoriteFolders) {
      if (_folders.containsKey(f) && !map.containsKey(f)) {
        map[f] = _folders[f]!;
      }
    }
    // Also auto-include common media folders that have videos
    for (final common in ['DCIM', 'Download', 'Movies', 'Music', 'Pictures', 'Camera', 'WhatsApp', 'Videos', 'Video', 'Filmora']) {
      if (_folders.containsKey(common) && !map.containsKey(common)) {
        map[common] = _folders[common]!;
      }
    }
    return map;
  }

  bool isFavoriteFolder(String path) => _favoriteFolders.contains(path);
  void toggleFavoriteFolder(String path) {
    if (_favoriteFolders.contains(path)) { _favoriteFolders.remove(path); }
    else { _favoriteFolders.add(path); }
    _saveFavorites();
    notifyListeners();
  }

  void setQueue(List<VideoFileInfo> videos, int index) {
    _currentQueue = videos;
    _queueIndex = index;
    notifyListeners();
  }

  void addToQueue(List<VideoFileInfo> videos) {
    _currentQueue.addAll(videos);
    notifyListeners();
  }

  List<VideoFileInfo> _currentQueue = [];
  List<VideoFileInfo> get currentQueue => _currentQueue;
  int _queueIndex = 0;
  int get queueIndex => _queueIndex;

  void createPlaylist(String name) {
    if (_playlists.any((p) => p['name'] == name)) return;
    _playlists.add({'name': name, 'videoIds': <int>[]});
    _savePlaylists();
    notifyListeners();
  }

  void addToPlaylist(String name, int videoId) {
    final pl = _playlists.where((p) => p['name'] == name).firstOrNull;
    if (pl != null && !(pl['videoIds'] as List).contains(videoId)) {
      (pl['videoIds'] as List).add(videoId);
      _savePlaylists();
      notifyListeners();
    }
  }

  void removeFromPlaylist(String name, int videoId) {
    final pl = _playlists.where((p) => p['name'] == name).firstOrNull;
    if (pl != null) {
      (pl['videoIds'] as List).remove(videoId);
      _savePlaylists();
      notifyListeners();
    }
  }

  void deletePlaylist(String name) {
    _playlists.removeWhere((p) => p['name'] == name);
    _savePlaylists();
    notifyListeners();
  }

  List<VideoFileInfo> getPlaylistVideos(String name) {
    final pl = _playlists.where((p) => p['name'] == name).firstOrNull;
    if (pl == null) return [];
    return (pl['videoIds'] as List).map<int>((e) => e as int)
        .map((id) => _allVideos.where((v) => v.id == id).firstOrNull)
        .whereType<VideoFileInfo>().toList();
  }

  Future<void> _saveResumePositions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_resume', jsonEncode(_resumeData));
  }

  Future<void> loadResumePositions() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('video_resume');
    if (data != null) {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final v = entry.value;
          if (v is Map) {
            _resumeData[entry.key.toString()] = v.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
          }
        }
      }
    }
  }

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getString('video_favorites');
    if (ids != null) _favoriteIds = (jsonDecode(ids) as List).cast<int>();
    final dirs = prefs.getString('video_favorite_folders');
    if (dirs != null) _favoriteFolders = (jsonDecode(dirs) as List).cast<String>().toSet();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_favorites', jsonEncode(_favoriteIds));
    await prefs.setString('video_favorite_folders', jsonEncode(_favoriteFolders.toList()));
  }

  Future<void> loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('video_playlists');
    if (data != null) _playlists = (jsonDecode(data) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_playlists', jsonEncode(_playlists));
  }
}
