import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/platform/platform_paths.dart';
import '../../../../core/services/media_notification_service.dart';
import '../../../../core/utils/natural_sort.dart';
import '../../domain/entities/entities.dart';
export '../../domain/entities/entities.dart';

class MusicPlayerService extends ChangeNotifier {
  MusicPlayerService() {
    _setupPlayer();
  }

  Future<void> init() async {
    await _loadCachedSongs();
  }

  Future<void> _loadCachedSongs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('songList');
      if (cached != null) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        _allSongs = decoded.map((e) => SongInfo.fromJson(e as Map<String, dynamic>)).toList();
        _applySort();
      }
    } catch (_) {}
  }

  Future<void> _saveSongsToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_allSongs.map((s) => s.toJson()).toList());
      await prefs.setString('songList', encoded);
    } catch (_) {}
  }

  final AudioPlayer player = AudioPlayer();

  VoidCallback? onNowPlaying;

  List<SongInfo> _allSongs = [];
  List<SongInfo> get allSongs => _allSongs;

  List<Playlist> _playlists = [];
  List<Playlist> get playlists => _playlists;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  String _scanError = '';
  String get scanError => _scanError;

  List<SongInfo> _queue = [];
  List<SongInfo> get queue => _queue;

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;
  set currentIndex(int v) { _currentIndex = v; notifyListeners(); }
  SongInfo? get currentSong => _currentIndex >= 0 && _currentIndex < _queue.length ? _queue[_currentIndex] : null;

  bool _isShuffled = false;
  bool get isShuffled => _isShuffled;
  List<SongInfo>? _savedQueue;

  LoopMode _loopMode = LoopMode.all;
  LoopMode get loopMode => _loopMode;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Duration _position = Duration.zero;
  Duration get position => _position;
  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  int _bufferMs = 2000;
  int get bufferMs => _bufferMs;
  void setBufferMs(int ms) { _bufferMs = ms; notifyListeners(); }

  List<int> _favoriteIds = [];
  List<int> get favoriteIds => _favoriteIds;

  String _sortMode = 'name';
  String get sortMode => _sortMode;

  String _selectedTab = 'Songs';
  String get selectedTab => _selectedTab;

  bool get hasQueue => _queue.isNotEmpty;
  int get queueLength => _queue.length;

  bool _showNowPlaying = false;
  bool get showNowPlaying => _showNowPlaying;

  int _timerMinutes = 0;
  int get timerMinutes => _timerMinutes;
  bool get hasTimer => _timerMinutes > 0;

  String notificationStatus = 'unknown';

  final List<String> _audioExts = ['.mp3', '.flac', '.wav', '.ogg', '.aac', '.m4a', '.wma', '.opus'];
  final Set<String> _multiFormatKeys = {};
  DateTime? _lastScanTime;

  bool hasMultipleFormats(SongInfo song) {
    final normTitle = song.displayTitle.trim().toLowerCase();
    final normArtist = song.displayArtist.trim().toLowerCase();
    return _multiFormatKeys.contains('$normTitle|$normArtist');
  }

  void registerNewDownload(String path) {
    scanAllSongs(force: true);
  }

  bool _isValidAudioFile(String path, int size) {
    if (size <= 1024) return false; // Exclude 0-byte or corrupted dud files
    final lower = path.toLowerCase();
    final fileName = lower.split(Platform.pathSeparator).last;
    if (fileName.startsWith('.')) return false; // Exclude hidden files
    if (fileName.endsWith('.crdownload') ||
        fileName.endsWith('.part') ||
        fileName.endsWith('.tmp') ||
        fileName.endsWith('.download') ||
        fileName.endsWith('.pending')) {
      return false; // Exclude partial / temporary downloads
    }
    return _audioExts.any((ext) => lower.endsWith(ext));
  }

  void _setupPlayer() {
    player.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });
    player.durationStream.listen((d) {
      _duration = d ?? Duration.zero;
      notifyListeners();
    });
    player.playerStateStream.listen((s) {
      _isPlaying = s.playing;
      if (s.processingState == ProcessingState.completed) {
        if (_loopMode == LoopMode.one) {
          player.seek(Duration.zero);
          _isPlaying = true;
          player.play();
          notifyNowPlaying();
        } else {
          _nextSong();
        }
      }
      notifyListeners();
    });
  }

  void _startPositionTimer() {
    if (_positionTimer != null) return;
    _positionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (player.playing) {
        MediaNotificationService.instance.syncPlaybackState(
          isPlaying: true,
          position: _position,
        );
      }
    });
  }

  Timer? _positionTimer;

  static const _metadataChannel = MethodChannel('com.hexadigitall.makaw/metadata');

  String _cleanTitle(String raw) {
    final name = raw.split('.').first.trim();
    return name.replaceAll(RegExp(r'^[\d\s\-\_\.]+'), '').trim();
  }

  Future<void> scanAllSongs({bool force = false}) async {
    if (_isScanning) return;
    if (!force && _lastScanTime != null && DateTime.now().difference(_lastScanTime!).inSeconds < 5) {
      return;
    }
    _isScanning = true;
    _scanError = '';
    notifyListeners();

    try {
      final dirs = PlatformPaths.musicScanRoots();
      final foundRaw = <MapEntry<int, String>>[];
      final seen = <String>{};
      int idCounter = 1;

      for (final dirPath in dirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final p = entity.path;
            try {
              final stat = await entity.stat();
              if (_isValidAudioFile(p, stat.size) && seen.add(p)) {
                foundRaw.add(MapEntry(idCounter++, p));
              }
            } catch (_) {}
          }
        }
      }

      if (Platform.isAndroid) {
        final root = Directory('/storage/emulated/0/');
        if (await root.exists()) {
          await for (final entity in root.list(recursive: false, followLinks: false)) {
            if (entity is File) {
              try {
                final stat = await entity.stat();
                if (_isValidAudioFile(entity.path, stat.size) && seen.add(entity.path)) {
                  foundRaw.add(MapEntry(idCounter++, entity.path));
                }
              } catch (_) {}
            }
          }
        }
      }

      // Extract metadata in batches
      final batchSize = 50;
      final metaMap = <String, Map<String, dynamic>>{};
      for (int i = 0; i < foundRaw.length; i += batchSize) {
        final batch = foundRaw.skip(i).take(batchSize).map((e) => e.value).toList();
        try {
          final results = await _metadataChannel.invokeMethod<List<dynamic>>(
            'extractMetadataBatch',
            {'paths': batch},
          );
          if (results != null) {
            for (final r in results) {
              final m = Map<String, dynamic>.from(r as Map);
              metaMap[m['path'] as String] = m;
            }
          }
        } catch (e) {
          print('MakawMetadata: batch invoke failed: $e');
        }
      }

      // Preload cached metadata
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('songMeta');
      Map<String, Map<String, dynamic>>? cache;
      if (cached != null) {
        try {
          final decoded = jsonDecode(cached) as Map<String, dynamic>;
          cache = decoded.map((k, v) => MapEntry(k, v as Map<String, dynamic>));
        } catch (_) {}
      }

      final found = <SongInfo>[];
      for (final entry in foundRaw) {
        final p = entry.value;
        var meta = metaMap[p];
        if (meta != null) {
          final t = (meta['title'] as String? ?? '').trim();
          if (t.isEmpty) meta = cache?[p];
        } else {
          meta = cache?[p];
        }
        final title = (meta?['title'] as String? ?? '').trim();
        final artist = (meta?['artist'] as String? ?? '').trim();
        final album = (meta?['album'] as String? ?? '').trim();
        final durationMs = (meta?['duration'] as int? ?? 0);
        int fileSize = 0;
        try {
          fileSize = File(p).lengthSync();
        } catch (_) {}

        found.add(SongInfo(
          id: entry.key,
          title: title.isNotEmpty ? title : _cleanTitle(p.split(Platform.pathSeparator).last),
          artist: artist,
          album: album,
          filePath: p,
          duration: durationMs,
          size: fileSize,
        ));
      }

      // Deduplicate identical title + artist + format tracks
      final deduped = <String, SongInfo>{};
      for (final song in found) {
        final normTitle = song.displayTitle.trim().toLowerCase();
        final normArtist = song.displayArtist.trim().toLowerCase();
        final format = song.formatBadge.toUpperCase();
        final formatKey = '$normTitle|$normArtist|$format';

        if (deduped.containsKey(formatKey)) {
          final existing = deduped[formatKey]!;
          if (song.size > existing.size || (song.size == existing.size && song.duration > existing.duration)) {
            deduped[formatKey] = song;
          }
        } else {
          deduped[formatKey] = song;
        }
      }

      // Identify multi-format tracks (e.g., MP3 vs FLAC vs WAV for same song)
      _multiFormatKeys.clear();
      final songCounts = <String, int>{};
      for (final song in deduped.values) {
        final normTitle = song.displayTitle.trim().toLowerCase();
        final normArtist = song.displayArtist.trim().toLowerCase();
        final baseKey = '$normTitle|$normArtist';
        songCounts[baseKey] = (songCounts[baseKey] ?? 0) + 1;
      }
      for (final e in songCounts.entries) {
        if (e.value > 1) {
          _multiFormatKeys.add(e.key);
        }
      }

      _allSongs = deduped.values.toList();
      _lastScanTime = DateTime.now();
      if (_allSongs.isEmpty) _scanError = 'No music files found. Tap Scan to try again.';

      // Cache only entries that have actual metadata
      final goodMeta = <String, Map<String, dynamic>>{};
      for (final entry in metaMap.entries) {
        if ((entry.value['title'] as String? ?? '').trim().isNotEmpty ||
            (entry.value['artist'] as String? ?? '').trim().isNotEmpty) {
          goodMeta[entry.key] = entry.value;
        }
      }
      if (goodMeta.isNotEmpty) {
        try {
          await prefs.setString('songMeta', jsonEncode(goodMeta));
        } catch (_) {}
      }
    } catch (e) {
      _scanError = 'Scan failed: $e';
    }

    _applySort();
    await _saveSongsToCache();
    _isScanning = false;
    notifyListeners();
  }

  void playSong(int index, {List<SongInfo>? fromList}) {
    final list = fromList ?? _allSongs;
    if (index < 0 || index >= list.length) return;
    if (fromList != null || _queue.isEmpty) {
      _queue = List.from(list);
      if (fromList != null) {
        _isShuffled = false;
        _savedQueue = null;
      }
    }
    _currentIndex = index;
    _playSource(_queue[_currentIndex]);
  }

  void playShuffled(List<SongInfo> list) {
    if (list.isEmpty) return;
    _savedQueue = List.from(list);
    _isShuffled = true;
    _queue = List.from(list);
    _queue.shuffle(Random());
    _currentIndex = 0;
    _playSource(_queue[_currentIndex]);
  }

  void playSongInfo(SongInfo song) {
    final idx = _allSongs.indexOf(song);
    if (idx >= 0) { playSong(idx); return; }
    _queue = [song];
    _currentIndex = 0;
    _playSource(song);
  }

  void _playSource(SongInfo song) {
    _duration = Duration(milliseconds: song.duration);
    _position = Duration.zero;
    player.setAudioSource(AudioSource.file(song.filePath));
    _isPlaying = true;
    player.play();
    notifyNowPlaying();
  }

  void _ensureQueued() {
    if (_queue.isEmpty && _allSongs.isNotEmpty) {
      _queue = List.from(_allSongs);
      _currentIndex = 0;
    }
  }

  void notifyNowPlaying() {
    onNowPlaying?.call();
    notifyListeners();
    MediaNotificationService.instance.syncPlaybackState(isPlaying: _isPlaying, position: _position);
    _startPositionTimer();
  }

  void togglePlayPause() {
    if (player.playing) {
      player.pause();
      _isPlaying = false;
    } else {
      player.play();
      _isPlaying = true;
    }
    notifyNowPlaying();
  }

  void _nextSong() {
    _ensureQueued();
    if (_queue.isEmpty) return;
    int next = _currentIndex + 1;
    if (next >= _queue.length) {
      if (_loopMode == LoopMode.all) { next = 0; } else { player.stop(); return; }
    }
    _currentIndex = next;
    _playSource(_queue[_currentIndex]);
  }

  void nextSong() => _nextSong();

  void previousSong() {
    _ensureQueued();
    if (_queue.isEmpty) return;
    int prev = _currentIndex - 1;
    if (prev < 0) { prev = _loopMode == LoopMode.all ? _queue.length - 1 : 0; }
    _currentIndex = prev;
    _playSource(_queue[_currentIndex]);
  }

  void seek(Duration d) => player.seek(d);

  void toggleShuffle() {
    _ensureQueued();
    if (_queue.isEmpty) return;
    final cur = currentSong;
    if (_isShuffled) {
      if (_savedQueue != null) {
        _queue = List.from(_savedQueue!);
        _savedQueue = null;
      }
      if (cur != null) _currentIndex = _queue.indexWhere((s) => s.id == cur.id);
      _isShuffled = false;
    } else {
      _savedQueue = List.from(_queue);
      if (cur != null) {
        _queue.removeWhere((s) => s.id == cur.id);
        _queue.shuffle(Random());
        _queue.insert(0, cur);
        _currentIndex = 0;
      } else {
        _queue.shuffle(Random());
        _currentIndex = 0;
      }
      _isShuffled = true;
    }
    notifyListeners();
  }

  void cycleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off: _loopMode = LoopMode.all; break;
      case LoopMode.all: _loopMode = LoopMode.one; break;
      case LoopMode.one: _loopMode = LoopMode.off; break;
    }
    notifyListeners();
  }

  void setSortMode(String mode) { _sortMode = mode; _applySort(); notifyListeners(); }

  void _applySort() {
    switch (_sortMode) {
      case 'name':
        _allSongs.sort((a, b) {
          final titleCmp = naturalCompare(a.displayTitle, b.displayTitle);
          if (titleCmp != 0) return titleCmp;
          final artistCmp = naturalCompare(a.displayArtist, b.displayArtist);
          if (artistCmp != 0) return artistCmp;
          return a.formatBadge.compareTo(b.formatBadge);
        });
        break;
      case 'name_desc':
        _allSongs.sort((a, b) {
          final titleCmp = naturalCompare(b.displayTitle, a.displayTitle);
          if (titleCmp != 0) return titleCmp;
          return naturalCompare(b.displayArtist, a.displayArtist);
        });
        break;
      case 'date': _allSongs.sort((a, b) => b.id.compareTo(a.id)); break;
      case 'duration': _allSongs.sort((a, b) => b.duration.compareTo(a.duration)); break;
      case 'size': _allSongs.sort((a, b) => b.size.compareTo(a.size)); break;
    }
  }

  void setSelectedTab(String tab) { _selectedTab = tab; notifyListeners(); }

  void setShowNowPlaying(bool show) { _showNowPlaying = show; notifyListeners(); }

  void toggleFavorite(int songId) {
    if (_favoriteIds.contains(songId)) { _favoriteIds.remove(songId); }
    else { _favoriteIds.add(songId); }
    _saveFavorites();
    notifyListeners();
  }

  bool isFavorite(int songId) => _favoriteIds.contains(songId);
  List<SongInfo> get favorites => _allSongs.where((s) => _favoriteIds.contains(s.id)).toList();

  void setTimer(int minutes) {
    _timerMinutes = minutes;
    notifyListeners();
    if (minutes > 0) {
      Future.delayed(Duration(minutes: minutes), () {
        if (_timerMinutes > 0) { player.stop(); _timerMinutes = 0; notifyListeners(); }
      });
    }
  }

  void addToPlaylist(String name, int songId) {
    final existing = _playlists.where((p) => p.name == name).firstOrNull;
    if (existing != null) { if (!existing.songIds.contains(songId)) existing.songIds.add(songId); }
    else { _playlists.add(Playlist(name: name, songIds: [songId])); }
    _savePlaylists(); notifyListeners();
  }

  void deletePlaylist(String name) { _playlists.removeWhere((p) => p.name == name); _savePlaylists(); notifyListeners(); }

  bool renamePlaylist(String oldName, String newName) {
    if (oldName == newName || newName.trim().isEmpty) return false;
    if (_playlists.any((p) => p.name == newName)) return false;
    final pl = _playlists.where((p) => p.name == oldName).firstOrNull;
    if (pl == null) return false;
    pl.name = newName;
    _savePlaylists(); notifyListeners();
    return true;
  }

  void removeSongsFromPlaylist(String name, List<int> songIds) {
    if (name.toLowerCase() == 'favourites' || name.toLowerCase() == 'favorites') {
      for (final id in songIds) {
        if (_favoriteIds.contains(id)) toggleFavorite(id);
      }
      return;
    }
    final pl = _playlists.where((p) => p.name == name).firstOrNull;
    if (pl == null) return;
    pl.songIds.removeWhere((id) => songIds.contains(id));
    _savePlaylists(); notifyListeners();
  }

  void addSongsToPlaylist(String name, List<int> songIds) {
    if (name.toLowerCase() == 'favourites' || name.toLowerCase() == 'favorites') {
      for (final id in songIds) {
        if (!_favoriteIds.contains(id)) toggleFavorite(id);
      }
      return;
    }
    final pl = _playlists.where((p) => p.name == name).firstOrNull;
    if (pl == null) return;
    for (final id in songIds) {
      if (!pl.songIds.contains(id)) pl.songIds.add(id);
    }
    _savePlaylists(); notifyListeners();
  }

  List<SongInfo> getPlaylistSongs(String name) {
    if (name.toLowerCase() == 'favourites' || name.toLowerCase() == 'favorites') {
      return favorites;
    }
    final pl = _playlists.where((p) => p.name == name).firstOrNull;
    if (pl == null) return [];
    return pl.songIds.map((id) => _allSongs.where((s) => s.id == id).firstOrNull).whereType<SongInfo>().toList();
  }

  List<int> getPlaylistSongIds(String name) {
    if (name.toLowerCase() == 'favourites' || name.toLowerCase() == 'favorites') {
      return _favoriteIds.toList();
    }
    final pl = _playlists.where((p) => p.name == name).firstOrNull;
    return pl?.songIds.toList() ?? [];
  }

  Map<String, List<SongInfo>> get albums {
    final map = <String, List<SongInfo>>{};
    for (final s in _allSongs) { map.putIfAbsent(s.displayAlbum, () => []).add(s); }
    return map;
  }

  Map<String, List<SongInfo>> get artists {
    final map = <String, List<SongInfo>>{};
    for (final s in _allSongs) { map.putIfAbsent(s.displayArtist, () => []).add(s); }
    return map;
  }

  Map<String, List<SongInfo>> get folders {
    final map = <String, List<SongInfo>>{};
    for (final s in _allSongs) {
      final folder = s.filePath.substring(0, s.filePath.lastIndexOf(Platform.pathSeparator));
      map.putIfAbsent(folder, () => []).add(s);
    }
    return map;
  }

  void addToQueue(SongInfo song) { _queue.add(song); notifyListeners(); }

  void playNext(SongInfo song) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) { _queue.insert(_currentIndex + 1, song); }
    else { _queue.add(song); }
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length && index != _currentIndex) { _queue.removeAt(index); notifyListeners(); }
  }

  void clearQueue() { _queue.clear(); _currentIndex = -1; player.stop(); notifyListeners(); }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    notifyListeners();
  }

  void playFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      _playSource(_queue[index]);
    }
  }

  Future<void> loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('music_playlists');
    if (data != null) _playlists = (jsonDecode(data) as List).map((e) => Playlist.fromJson(e)).toList();
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('music_playlists', jsonEncode(_playlists.map((p) => p.toJson()).toList()));
  }

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('music_favorites');
    if (data != null) _favoriteIds = (jsonDecode(data) as List).cast<int>();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('music_favorites', jsonEncode(_favoriteIds));
  }

  @override
  void dispose() { _positionTimer?.cancel(); player.dispose(); MediaNotificationService.instance.hide(); super.dispose(); }
}
