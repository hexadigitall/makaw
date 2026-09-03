import 'package:sqflite/sqflite.dart';

/// A single lyric entry. May be a full-song lyric blob or a timed line with
/// start/end timestamps (ms).
class Lyric {
  final int? id;
  final String songId;      // e.g. "artist — title" composite key
  final String songTitle;
  final String? artist;
  final String text;        // for timed lyrics: the line text
  final int? startMs;       // nullable for plain (non-timed) lyrics
  final int? endMs;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Lyric({
    this.id,
    required this.songId,
    required this.songTitle,
    this.artist,
    required this.text,
    this.startMs,
    this.endMs,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Lyric.fromMap(Map<String, dynamic> m) => Lyric(
    id: m['id'] as int?,
    songId: m['song_id'] as String,
    songTitle: m['song_title'] as String,
    artist: m['artist'] as String?,
    text: m['text'] as String,
    startMs: m['start_ms'] as int?,
    endMs: m['end_ms'] as int?,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
  );

  Map<String, dynamic> toMap({bool includeId = true}) => {
    if (includeId) 'id': id,
    'song_id': songId,
    'song_title': songTitle,
    'artist': artist,
    'text': text,
    'start_ms': startMs,
    'end_ms': endMs,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

/// Lyrics manager backed by the `lyrics` table in `makaw_mgr.db`.
class LyricService {
  static Database? _db;

  static void init(Database db) {
    _db = db;
  }

  static Database get _database {
    if (_db == null) throw StateError('LyricService not initialized. Call init() first.');
    return _db!;
  }

  /// Save a full lyric blob for a song (replaces any previous full text).
  static Future<int> saveFullLyric({
    required String songId,
    required String songTitle,
    String? artist,
    required String text,
  }) async {
    final now = DateTime.now();
    await _database.delete('lyrics', where: "song_id = ? AND start_ms IS NULL", whereArgs: [songId]);
    return await _database.insert(
      'lyrics',
      Lyric(songId: songId, songTitle: songTitle, artist: artist, text: text, createdAt: now, updatedAt: now).toMap(includeId: false),
    );
  }

  /// Replace a song's timed lines wholesale.
  static Future<void> saveTimedLyrics({
    required String songId,
    required String songTitle,
    String? artist,
    required List<Lyric> lines,
  }) async {
    await _database.transaction((txn) async {
      await txn.delete('lyrics', where: "song_id = ? AND start_ms IS NOT NULL", whereArgs: [songId]);
      for (final line in lines) {
        await txn.insert('lyrics', line.toMap(includeId: false));
      }
    });
  }

  /// Add a single timed line.
  static Future<int> addLine(Lyric line) async {
    return await _database.insert('lyrics', line.toMap(includeId: false));
  }

  static Future<List<Lyric>> linesForSong(String songId) async {
    try {
      final q = await _database.query(
        'lyrics',
        where: 'song_id = ? AND start_ms IS NOT NULL',
        whereArgs: [songId],
        orderBy: 'start_ms ASC',
      );
      return q.map((m) => Lyric.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<Lyric?> fullLyricForSong(String songId) async {
    final q = await _database.query(
      'lyrics',
      where: 'song_id = ? AND start_ms IS NULL',
      whereArgs: [songId],
      limit: 1,
    );
    return q.isEmpty ? null : Lyric.fromMap(q.first);
  }

  static Future<List<Lyric>> search(String query, {int limit = 200}) async {
    final q = '%$query%';
    try {
      final rows = await _database.query(
        'lyrics',
        where: 'song_id LIKE ? OR song_title LIKE ? OR artist LIKE ? OR text LIKE ?',
        whereArgs: [q, q, q, q],
        orderBy: 'updated_at DESC',
        limit: limit,
      );
      return rows.map((m) => Lyric.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> deleteLyric(int id) async {
    await _database.delete('lyrics', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteSong(String songId) async {
    await _database.delete('lyrics', where: 'song_id = ?', whereArgs: [songId]);
  }

  /// List distinct songs (one representative [Lyric] per song_id), grouped by
  /// most recently updated.
  static Future<List<Lyric>> listSongs({int limit = 1000}) async {
    try {
      final rows = await _database.rawQuery('''
        SELECT * FROM lyrics
        WHERE id IN (SELECT MAX(id) FROM lyrics GROUP BY song_id)
        ORDER BY updated_at DESC
        LIMIT ?
      ''', [limit]);
      return rows.map((m) => Lyric.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clearAll() async {
    await _database.delete('lyrics');
  }
}
