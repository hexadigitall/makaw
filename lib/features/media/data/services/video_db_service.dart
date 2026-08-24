import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class VideoPlaybackRecord {
  final String path;
  final String title;
  final int positionMs;
  final int durationMs;
  final int lastPlayed;
  final bool isCompleted;

  VideoPlaybackRecord({
    required this.path,
    required this.title,
    required this.positionMs,
    required this.durationMs,
    required this.lastPlayed,
    this.isCompleted = false,
  });

  double get progress => durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
}

class MakawVideoDbService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'makaw_video.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE video_history (
            path TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            position_ms INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            last_played INTEGER NOT NULL,
            is_completed INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE video_bookmarks (
            path TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<void> savePlaybackPosition({
    required String path,
    required String title,
    required int positionMs,
    required int durationMs,
  }) async {
    final db = await database;
    final isCompleted = durationMs > 0 && (positionMs / durationMs) >= 0.95;
    await db.insert('video_history', {
      'path': path,
      'title': title,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'last_played': DateTime.now().millisecondsSinceEpoch,
      'is_completed': isCompleted ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<VideoPlaybackRecord?> getRecord(String path) async {
    final db = await database;
    final rows = await db.query('video_history', where: 'path = ?', whereArgs: [path]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return VideoPlaybackRecord(
      path: r['path'] as String,
      title: r['title'] as String,
      positionMs: r['position_ms'] as int,
      durationMs: r['duration_ms'] as int,
      lastPlayed: r['last_played'] as int,
      isCompleted: (r['is_completed'] as int) == 1,
    );
  }

  static Future<List<VideoPlaybackRecord>> getRecentHistory({int limit = 50}) async {
    final db = await database;
    final rows = await db.query('video_history', orderBy: 'last_played DESC', limit: limit);
    return rows.map((r) => VideoPlaybackRecord(
      path: r['path'] as String,
      title: r['title'] as String,
      positionMs: r['position_ms'] as int,
      durationMs: r['duration_ms'] as int,
      lastPlayed: r['last_played'] as int,
      isCompleted: (r['is_completed'] as int) == 1,
    )).toList();
  }

  static Future<void> clearHistory() async {
    final db = await database;
    await db.delete('video_history');
  }
}
