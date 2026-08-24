import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'makaw_audio_handler.dart';
import 'music_db_service.dart';
import '../../domain/entities/entities.dart';
export '../../domain/entities/entities.dart';

class MusicPlayerService extends ChangeNotifier {
  MusicPlayerService();

  MakawAudioHandler? _audioHandler;
  AudioPlayer? _standalonePlayer;

  AudioPlayer get _activePlayer => _audioHandler?.player ?? _ensureStandalonePlayer();

  AudioPlayer _ensureStandalonePlayer() {
    _standalonePlayer ??= AudioPlayer();
    return _standalonePlayer!;
  }

  Timer? _sleepTimer;
  StreamSubscription? _indexStreamSub;
  StreamSubscription? _positionStreamSub;
  StreamSubscription? _durationStreamSub;
  StreamSubscription? _stateStreamSub;

  void attachAudioHandler(MakawAudioHandler handler) {
    _audioHandler = handler;
    _standalonePlayer?.dispose();
    _standalonePlayer = null;

    _indexStreamSub?.cancel();
    _positionStreamSub?.cancel();
    _durationStreamSub?.cancel();
    _stateStreamSub?.cancel();

    final p = handler.player;

    _indexStreamSub = p.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _queue.length) {
        if (_currentIndex != index) {
          _currentIndex = index;
          notifyListeners();
        }
      }
    });

    _positionStreamSub = p.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durationStreamSub = p.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    });

    _stateStreamSub = p.playerStateStream.listen((s) {
      _isPlaying = s.playing;
      notifyListeners();
    });

    _setupHandlerListeners();
  }

  void _setupHandlerListeners() {
    _audioHandler?.queue.listen((queue) {
      if (queue.isNotEmpty && _audioHandler != null) {
        final items = _audioHandler!.queueList;
        if (items.length == queue.length) {
          _queue = List.from(items);
        }
      }
    });
  }

  Future<void> init() async {
    await _loadCachedSongs();
  }

  Future<void> _loadCachedSongs() async {
    try {
      final rows = await MusicDbService.instance.loadSongs();
      _allSongs = rows.map((r) => SongInfo(
        id: r['id'] as int,
        title: r['title'] as String? ?? '',
        artist: r['artist'] as String? ?? '',
        album: r['album'] as String? ?? '',
        filePath: r['file_path'] as String,
        duration: r['duration'] as int? ?? 0,
        albumId: r['album_id'] as int? ?? -1,
        size: r['size'] as int? ?? 0,
      )).toList();
      _applySort();
    } catch (_) {}
  }

  Future<void> _saveSongsToCache() async {
    try {
      final maps = _allSongs.map((s) => {
        'file_path': s.filePath,
        'id': s.id,
        'title': s.title,
        'artist': s.artist,
        'album': s.album,
        'duration': s.duration,
        'album_id': s.albumId,
        'size': s.size,
      }).toList();
      await MusicDbService.instance.saveSongs(maps);
    } catch (_) {}
  }

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

  static const List<String> _blacklistedDirs = [
    'whatsapp/media/whatsapp voice notes',
    'whatsapp/media/whatsapp animated gifs',
    'whatsapp/media/whatsapp stickers',
    'telegram',
    'recordings',
    'notifications',
    'alarms',
    'ringtones',
    'call_recorder',
    'voice_recorder',
    '.thumbnails',
    'status',
  ];

  static const int _minDurationMs = 30000;
  static const int _minFileSizeBytes = 800 * 1024;

  static const _metadataChannel = MethodChannel('com.hexadigitall.makaw/metadata');

  final Map<String, Uint8List?> _artworkCache = {};

  Future<Uint8List?> getAlbumArt(String filePath) async {
    if (_artworkCache.containsKey(filePath)) return _artworkCache[filePath];
    if (Platform.isAndroid) {
      try {
        final result = await _metadataChannel.invokeMethod<Uint8List>(
          'getAlbumArt',
          {'path': filePath},
        );
        _artworkCache[filePath] = result;
        return result;
      } catch (_) {}
    }
    _artworkCache[filePath] = null;
    return null;
  }

  String _cleanTitle(String raw) {
    final name = raw.split('.').first.trim();
    return name.replaceAll(RegExp(r'^[\d\s\-\_\.]+'), '').trim();
  }

  int _fileIdCounter = 0;

  Future<void> scanAllSongs() async {
    _isScanning = true;
    _scanError = '';
    notifyListeners();

    try {
      final foundRaw = <MapEntry<int, String>>[];
      final seen = <String>{};
      _fileIdCounter = _allSongs.isNotEmpty
          ? _allSongs.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1
          : 1;

      String normalizePath(String path) {
        var n = path.replaceAll('\\', '/').toLowerCase();
        while (n.contains('//')) n = n.replaceAll('//', '/');
        return n;
      }

      List<String> musicDirs;
      List<String> rootScanPaths;

      if (Platform.isAndroid) {
        musicDirs = [
          '/storage/emulated/0/Music', '/storage/emulated/0/music',
          '/storage/emulated/0/Download', '/storage/emulated/0/download',
        ];
        rootScanPaths = ['/storage/emulated/0/'];
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? '';
        final home = Platform.environment['HOMEPATH'] ?? '';
        final drive = Platform.environment['HOMEDRIVE'] ?? 'C:';
        final homeDir = '$drive$home';
        musicDirs = [
          '$userProfile\\Music', '$userProfile\\Downloads',
          '$homeDir\\Music', '$homeDir\\Downloads',
        ];
        rootScanPaths = [];
      } else if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        musicDirs = [
          '$home/Music', '$home/Downloads',
          '$home/.local/share/Music',
        ];
        rootScanPaths = [];
      } else {
        musicDirs = [];
        rootScanPaths = [];
      }

      for (final dirPath in musicDirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final path = entity.path;
            final pathLower = path.toLowerCase();
            if (_blacklistedDirs.any((d) => pathLower.contains(d))) continue;
            if (_audioExts.any((e) => pathLower.endsWith(e)) && seen.add(normalizePath(path))) {
              foundRaw.add(MapEntry(_fileIdCounter++, path));
            }
          }
        }
      }

      for (final rootPath in rootScanPaths) {
        final root = Directory(rootPath);
        if (!await root.exists()) continue;
        await for (final entity in root.list(recursive: false, followLinks: false)) {
          if (entity is File && seen.add(normalizePath(entity.path))) {
            final ext = entity.path.toLowerCase();
            if (_audioExts.any((e) => ext.endsWith(e))) {
              foundRaw.add(MapEntry(_fileIdCounter++, entity.path));
            }
          }
        }
      }

      final batchSize = 50;
      final metaMap = <String, Map<String, dynamic>>{};
      final isAndroid = Platform.isAndroid;
      if (isAndroid) {
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
          } catch (_) {}
        }
      }

      Map<String, Map<String, dynamic>>? cache;
      try {
        cache = await MusicDbService.instance.loadSongMetadata();
      } catch (_) {}

      final found = <SongInfo>[];
      for (final entry in foundRaw) {
        final path = entry.value;
        var meta = metaMap[path] ?? cache?[path];

        final title = (meta?['title'] as String? ?? '').trim();
        final artist = (meta?['artist'] as String? ?? '').trim();
        final album = (meta?['album'] as String? ?? '').trim();
        final durationMs = meta?['duration'] as int? ?? 0;
        final fileSize = meta?['size'] as int? ?? 0;

        final fileSizeFromStat = fileSize == 0
            ? await _getFileSize(path)
            : fileSize;

        if (durationMs > 0 && durationMs < _minDurationMs) continue;
        if (fileSizeFromStat > 0 && fileSizeFromStat < _minFileSizeBytes) continue;

        final fileName = p.basenameWithoutExtension(path);

        found.add(SongInfo(
          id: entry.key,
          title: title.isNotEmpty ? title : _cleanTitle(fileName),
          artist: artist,
          album: album,
          filePath: path,
          duration: durationMs,
          size: fileSizeFromStat,
        ));
      }

      _allSongs = found;
      if (_allSongs.isEmpty) _scanError = 'No music files found. Tap Scan to try again.';

      final goodMeta = <String, Map<String, dynamic>>{};
      for (final entry in metaMap.entries) {
        if ((entry.value['title'] as String? ?? '').trim().isNotEmpty ||
            (entry.value['artist'] as String? ?? '').trim().isNotEmpty) {
          goodMeta[entry.key] = entry.value;
        }
      }
      if (goodMeta.isNotEmpty) {
        try {
          await MusicDbService.instance.saveSongMetadata(goodMeta);
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

  Future<int> _getFileSize(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.size;
      }
    } catch (_) {}
    return 0;
  }

  void playSong(int index, {List<SongInfo>? fromList}) {
    final list = fromList ?? _allSongs;
    if (index < 0 || index >= list.length) return;
    _queue = List.from(list);
    _currentIndex = index;
    _duration = Duration(milliseconds: _queue[_currentIndex].duration);
    _position = Duration.zero;
    _playThroughHandler();
  }

  void playShuffled(List<SongInfo> list) {
    if (list.isEmpty) return;
    _savedQueue = List.from(list);
    _isShuffled = true;
    _queue = List.from(list)..shuffle(Random());
    _currentIndex = 0;
    _duration = Duration(milliseconds: _queue[_currentIndex].duration);
    _position = Duration.zero;
    _playThroughHandler();
  }

  void playSongInfo(SongInfo song) {
    final idx = _allSongs.indexWhere((s) => s.id == song.id);
    if (idx >= 0) {
      playSong(idx);
      return;
    }
    _queue = [song];
    _currentIndex = 0;
    _duration = Duration(milliseconds: song.duration);
    _position = Duration.zero;
    _playThroughHandler();
  }

  void _playThroughHandler() {
    if (_queue.isEmpty || _currentIndex < 0) return;

    final p = _activePlayer;
    if (_audioHandler != null) {
      _audioHandler!.loadQueue(
        _queue,
        initialIndex: _currentIndex,
        shuffle: false,
      );
      _audioHandler!.setLoopMode(_loopMode);
    } else {
      _isPlaying = true;
      final song = _queue[_currentIndex];
      p.setAudioSource(AudioSource.uri(Uri.file(song.filePath)));
      p.setLoopMode(_loopMode);
      p.play();
    }
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
  }

  void togglePlayPause() {
    final p = _activePlayer;
    if (p.playing) {
      p.pause();
    } else {
      p.play();
    }
    _isPlaying = p.playing;
    notifyNowPlaying();
  }

  void play() {
    _activePlayer.play();
    _isPlaying = true;
    notifyNowPlaying();
  }

  void pause() {
    _activePlayer.pause();
    _isPlaying = false;
    notifyNowPlaying();
  }

  void _nextSong() {
    _ensureQueued();
    if (_queue.isEmpty) return;

    if (_loopMode == LoopMode.one) {
      _activePlayer.seek(Duration.zero);
      return;
    }

    int next = _currentIndex + 1;
    if (next >= _queue.length) {
      if (_loopMode == LoopMode.all) {
        next = 0;
      } else {
        _activePlayer.stop();
        _isPlaying = false;
        notifyListeners();
        return;
      }
    }
    _currentIndex = next;
    _playThroughHandler();
  }

  void nextSong() => _nextSong();

  void previousSong() {
    _ensureQueued();
    if (_queue.isEmpty) return;
    final p = _activePlayer;
    if (p.position.inSeconds > 3) {
      p.seek(Duration.zero);
      return;
    }
    int prev = _currentIndex - 1;
    if (prev < 0) {
      prev = _loopMode == LoopMode.all ? _queue.length - 1 : 0;
    }
    _currentIndex = prev;
    _playThroughHandler();
  }

  void seek(Duration d) => _activePlayer.seek(d);

  double get speed => _activePlayer.speed;

  void setSpeed(double speed) => _activePlayer.setSpeed(speed);

  void toggleShuffle() {
    _ensureQueued();
    if (_queue.isEmpty) return;
    final cur = currentSong;
    if (_isShuffled) {
      if (_savedQueue != null) {
        _queue = List.from(_savedQueue!);
        _savedQueue = null;
      }
      if (cur != null) {
        _currentIndex = _queue.indexWhere((s) => s.id == cur.id);
        if (_currentIndex < 0) _currentIndex = 0;
      }
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

    if (_audioHandler != null) {
      _audioHandler!.loadQueue(_queue, initialIndex: _currentIndex, shuffle: false);
    }
    notifyListeners();
  }

  void cycleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off: _loopMode = LoopMode.all; break;
      case LoopMode.all: _loopMode = LoopMode.one; break;
      case LoopMode.one: _loopMode = LoopMode.off; break;
    }
    _activePlayer.setLoopMode(_loopMode);
    notifyListeners();
  }

  void setSortMode(String mode) {
    _sortMode = mode;
    _applySort();
    notifyListeners();
  }

  void _applySort() {
    switch (_sortMode) {
      case 'name': _allSongs.sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase())); break;
      case 'name_desc': _allSongs.sort((a, b) => b.displayTitle.toLowerCase().compareTo(a.displayTitle.toLowerCase())); break;
      case 'date': _allSongs.sort((a, b) => b.size.compareTo(a.size)); break;
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
    _sleepTimer?.cancel();
    _timerMinutes = minutes;
    notifyListeners();
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        if (_timerMinutes > 0) {
          _activePlayer.stop();
          _timerMinutes = 0;
          _sleepTimer = null;
          notifyListeners();
        }
      });
    }
  }

  void addToPlaylist(String name, int songId) {
    final existing = _playlists.where((p) => p.name == name).firstOrNull;
    if (existing != null) {
      if (!existing.songIds.contains(songId)) existing.songIds.add(songId);
    } else {
      _playlists.add(Playlist(name: name, songIds: [songId]));
    }
    _savePlaylists();
    notifyListeners();
  }

  void deletePlaylist(String name) {
    _playlists.removeWhere((p) => p.name == name);
    MusicDbService.instance.deletePlaylist(name);
    _savePlaylists();
    notifyListeners();
  }

  bool renamePlaylist(String oldName, String newName) {
    if (oldName == newName || newName.trim().isEmpty) return false;
    if (_playlists.any((p) => p.name == newName)) return false;
    final pl = _playlists.where((p) => p.name == oldName).firstOrNull;
    if (pl == null) return false;
    pl.name = newName;
    MusicDbService.instance.renamePlaylist(oldName, newName);
    _savePlaylists();
    notifyListeners();
    return true;
  }

  void removeSongsFromPlaylist(String name, List<int> songIds) {
    final pl = _playlists.where((p) => p.name == name).firstOrNull;
    if (pl == null) return;
    pl.songIds.removeWhere((id) => songIds.contains(id));
    _savePlaylists();
    notifyListeners();
  }

  void addSongsToPlaylist(String name, List<int> songIds) {
    final pl = _playlists.where((p) => p.name == name).firstOrNull;
    if (pl == null) return;
    for (final id in songIds) {
      if (!pl.songIds.contains(id)) pl.songIds.add(id);
    }
    _savePlaylists();
    notifyListeners();
  }

  List<SongInfo> getPlaylistSongs(String name) {
    final pl = _playlists.where((p) => p.name == name).firstOrNull;
    if (pl == null) return [];
    return pl.songIds.map((id) => _allSongs.where((s) => s.id == id).firstOrNull).whereType<SongInfo>().toList();
  }

  List<int> getPlaylistSongIds(String name) {
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
      final dir = p.dirname(s.filePath);
      if (dir.isNotEmpty && dir != '.') {
        map.putIfAbsent(dir, () => []).add(s);
      }
    }
    return map;
  }

  void addToQueue(SongInfo song) {
    _queue.add(song);
    _audioHandler?.addToQueue(song);
    notifyListeners();
  }

  void playNext(SongInfo song) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, song);
    } else {
      _queue.add(song);
    }
    _audioHandler?.playNext(song);
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length && index != _currentIndex) {
      _queue.removeAt(index);
      _audioHandler?.removeFromQueue(index);
      if (index < _currentIndex) _currentIndex--;
      notifyListeners();
    }
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _audioHandler?.clearQueue();
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == _currentIndex || newIndex == _currentIndex) return;

    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    _audioHandler?.reorderQueue(oldIndex, newIndex);
    notifyListeners();
  }

  void playFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      _duration = Duration(milliseconds: _queue[_currentIndex].duration);
      _position = Duration.zero;
      _playThroughHandler();
    }
  }

  Future<void> loadPlaylists() async {
    try {
      final dbPlaylists = await MusicDbService.instance.loadPlaylists();
      _playlists = dbPlaylists.map((dbPl) {
        final songIds = dbPl.filePaths.map((filePath) {
          final match = _allSongs.where((s) => s.filePath == filePath);
          return match.isNotEmpty ? match.first.id : -1;
        }).where((id) => id >= 0).toList();
        return Playlist(name: dbPl.name, songIds: songIds);
      }).toList();
    } catch (_) {}
  }

  Future<void> _savePlaylists() async {
    try {
      final db = MusicDbService.instance;
      final existingNames = (await db.loadPlaylists()).map((p) => p.name).toSet();
      for (final pl in _playlists) {
        if (!existingNames.contains(pl.name)) {
          await db.createPlaylist(pl.name);
        }
        final filePaths = pl.songIds.map((id) {
          final match = _allSongs.where((s) => s.id == id);
          return match.isNotEmpty ? match.first.filePath : '';
        }).where((p) => p.isNotEmpty).toList();
        await db.setPlaylistSongs(pl.name, filePaths);
      }
    } catch (_) {}
  }

  Future<void> loadFavorites() async {
    try {
      final favoritePaths = await MusicDbService.instance.loadFavoritePaths();
      _favoriteIds = _allSongs
          .where((s) => favoritePaths.contains(s.filePath))
          .map((s) => s.id)
          .toList();
    } catch (_) {}
  }

  Future<void> _saveFavorites() async {
    try {
      final paths = _favoriteIds.map((id) {
        final match = _allSongs.where((s) => s.id == id);
        return match.isNotEmpty ? match.first.filePath : '';
      }).where((p) => p.isNotEmpty).toSet();
      await MusicDbService.instance.saveFavorites(paths);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _indexStreamSub?.cancel();
    _positionStreamSub?.cancel();
    _durationStreamSub?.cancel();
    _stateStreamSub?.cancel();
    _standalonePlayer?.dispose();
    super.dispose();
  }
}
