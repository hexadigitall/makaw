import 'package:sqflite/sqflite.dart';

/// A single subtitle cue (timed text line).
class SubtitleCue {
  final int? id;
  final String mediaId;     // e.g. file path/name or "movie — title" composite
  final String mediaTitle;
  final String text;
  final int startMs;
  final int endMs;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SubtitleCue({
    this.id,
    required this.mediaId,
    required this.mediaTitle,
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SubtitleCue.fromMap(Map<String, dynamic> m) => SubtitleCue(
    id: m['id'] as int?,
    mediaId: m['media_id'] as String,
    mediaTitle: m['media_title'] as String,
    text: m['text'] as String,
    startMs: m['start_ms'] as int,
    endMs: m['end_ms'] as int,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
  );

  Map<String, dynamic> toMap({bool includeId = true}) => {
    if (includeId) 'id': id,
    'media_id': mediaId,
    'media_title': mediaTitle,
    'text': text,
    'start_ms': startMs,
    'end_ms': endMs,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

/// Subtitle manager backed by the `subtitles` table in `makaw_mgr.db`.
///
/// Supports saving an entire `.srt`-style cue set (replacing existing cues for
/// a media item) and querying cues active at a given playback position.
class SubtitleService {
  static Database? _db;

  static void init(Database db) {
    _db = db;
  }

  static Database get _database {
    if (_db == null) throw StateError('SubtitleService not initialized. Call init() first.');
    return _db!;
  }

  /// Replace all cues for a media item with [cues]. Returns number inserted.
  static Future<int> saveCues(String mediaId, String mediaTitle, List<SubtitleCue> cues) async {
    int inserted = 0;
    await _database.transaction((txn) async {
      await txn.delete('subtitles', where: 'media_id = ?', whereArgs: [mediaId]);
      for (final c in cues) {
        inserted += await txn.insert('subtitles', c.toMap(includeId: false));
      }
    });
    return inserted;
  }

  static Future<List<SubtitleCue>> cuesForMedia(String mediaId) async {
    try {
      final q = await _database.query(
        'subtitles',
        where: 'media_id = ?',
        whereArgs: [mediaId],
        orderBy: 'start_ms ASC',
      );
      return q.map((m) => SubtitleCue.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The cue active at [positionMs] (start <= position < end).
  static Future<SubtitleCue?> cueAt(String mediaId, int positionMs) async {
    final q = await _database.query(
      'subtitles',
      where: 'media_id = ? AND start_ms <= ? AND end_ms > ?',
      whereArgs: [mediaId, positionMs, positionMs],
      orderBy: 'start_ms DESC',
      limit: 1,
    );
    return q.isEmpty ? null : SubtitleCue.fromMap(q.first);
  }

  static Future<List<SubtitleCue>> search(String query, {int limit = 300}) async {
    final q = '%$query%';
    try {
      final rows = await _database.query(
        'subtitles',
        where: 'media_title LIKE ? OR text LIKE ?',
        whereArgs: [q, q],
        orderBy: 'updated_at DESC',
        limit: limit,
      );
      return rows.map((m) => SubtitleCue.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> deleteMedia(String mediaId) async {
    await _database.delete('subtitles', where: 'media_id = ?', whereArgs: [mediaId]);
  }

  static Future<void> clearAll() async {
    await _database.delete('subtitles');
  }
}
