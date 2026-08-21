import 'package:sqflite/sqflite.dart';

class PlaylistData {
  final String name;
  final List<String> filePaths;
  const PlaylistData({required this.name, required this.filePaths});
}

class MusicDbService {
  static MusicDbService? _instance;
  Database? _db;

  MusicDbService._();
  static MusicDbService get instance => _instance ??= MusicDbService._();

  static const _dbName = 'makaw_music.db';
  static const _dbVersion = 1;

  Future<void> init(Database db) async {
    _db = db;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    throw StateError('MusicDbService.init() must be called before accessing database');
  }

  // ─── Schema Creation ────────────────────────────────────────────────────

  static Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS songs (
        file_path TEXT PRIMARY KEY,
        id INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        artist TEXT NOT NULL DEFAULT '',
        album TEXT NOT NULL DEFAULT '',
        duration INTEGER NOT NULL DEFAULT 0,
        album_id INTEGER NOT NULL DEFAULT -1,
        size INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS song_metadata (
        file_path TEXT PRIMARY KEY,
        title TEXT,
        artist TEXT,
        album TEXT,
        duration INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (file_path) REFERENCES songs(file_path) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        file_path TEXT PRIMARY KEY,
        added_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist ON playlist_tracks(playlist_id, position)');
  }

  // ─── Songs CRUD ─────────────────────────────────────────────────────────

  Future<void> saveSongs(List<Map<String, dynamic>> songs) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete('songs');
      for (final song in songs) {
        batch.insert('songs', song, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> loadSongs() async {
    final db = await database;
    return db.query('songs', orderBy: 'title ASC');
  }

  // ─── Song Metadata Cache ────────────────────────────────────────────────

  Future<void> saveSongMetadata(Map<String, Map<String, dynamic>> meta) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete('song_metadata');
      for (final entry in meta.entries) {
        batch.insert('song_metadata', {
          'file_path': entry.key,
          'title': entry.value['title'],
          'artist': entry.value['artist'],
          'album': entry.value['album'],
          'duration': entry.value['duration'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, Map<String, dynamic>>> loadSongMetadata() async {
    final db = await database;
    final rows = await db.query('song_metadata');
    final map = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final path = r['file_path'] as String;
      map[path] = {
        'title': r['title'],
        'artist': r['artist'],
        'album': r['album'],
        'duration': r['duration'],
      };
    }
    return map;
  }

  // ─── Playlists CRUD ─────────────────────────────────────────────────────

  Future<int> createPlaylist(String name) async {
    final db = await database;
    return db.insert('playlists', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<PlaylistData>> loadPlaylists() async {
    final db = await database;
    final plRows = await db.query('playlists', orderBy: 'created_at ASC');
    final playlists = <PlaylistData>[];
    for (final pl in plRows) {
      final playlistId = pl['id'] as int;
      final trackRows = await db.query(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'position ASC',
      );
      final songPaths = trackRows.map((t) => t['file_path'] as String).toList();
      playlists.add(PlaylistData(name: pl['name'] as String, filePaths: songPaths));
    }
    return playlists;
  }

  Future<void> deletePlaylist(String name) async {
    final db = await database;
    final pl = await db.query('playlists', where: 'name = ?', whereArgs: [name], limit: 1);
    if (pl.isEmpty) return;
    final playlistId = pl.first['id'] as int;
    await db.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }

  Future<bool> renamePlaylist(String oldName, String newName) async {
    final db = await database;
    final existing = await db.query('playlists', where: 'name = ?', whereArgs: [newName], limit: 1);
    if (existing.isNotEmpty) return false;
    final rows = await db.update(
      'playlists', {'name': newName},
      where: 'name = ?', whereArgs: [oldName],
    );
    return rows > 0;
  }

  Future<void> setPlaylistSongs(String playlistName, List<String> filePaths) async {
    final db = await database;
    final pl = await db.query('playlists', where: 'name = ?', whereArgs: [playlistName], limit: 1);
    if (pl.isEmpty) return;
    final playlistId = pl.first['id'] as int;
    await db.transaction((txn) async {
      await txn.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);
      final batch = txn.batch();
      for (int i = 0; i < filePaths.length; i++) {
        batch.insert('playlist_tracks', {
          'playlist_id': playlistId,
          'file_path': filePaths[i],
          'position': i,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  // ─── Favorites CRUD ─────────────────────────────────────────────────────

  Future<void> addFavorite(String filePath) async {
    final db = await database;
    await db.insert('favorites', {
      'file_path': filePath,
      'added_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFavorite(String filePath) async {
    final db = await database;
    await db.delete('favorites', where: 'file_path = ?', whereArgs: [filePath]);
  }

  Future<Set<String>> loadFavoritePaths() async {
    final db = await database;
    final rows = await db.query('favorites');
    return rows.map((r) => r['file_path'] as String).toSet();
  }

  Future<void> saveFavorites(Set<String> paths) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('favorites');
      final batch = txn.batch();
      final now = DateTime.now().toIso8601String();
      for (final path in paths) {
        batch.insert('favorites', {'file_path': path, 'added_at': now});
      }
      await batch.commit(noResult: true);
    });
  }
}
