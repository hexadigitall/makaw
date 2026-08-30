import 'package:sqflite/sqflite.dart';

/// A recently-opened file or folder.
class FileRecent {
  final int? id;
  final String path;
  final String? name;
  final bool isDirectory;
  final int openCount;
  final DateTime lastOpened;

  const FileRecent({
    this.id,
    required this.path,
    this.name,
    this.isDirectory = false,
    this.openCount = 1,
    required this.lastOpened,
  });

  factory FileRecent.fromMap(Map<String, dynamic> m) => FileRecent(
    id: m['id'] as int?,
    path: m['path'] as String,
    name: m['name'] as String?,
    isDirectory: (m['is_directory'] as int? ?? 0) == 1,
    openCount: (m['open_count'] as int?) ?? 1,
    lastOpened: DateTime.parse(m['last_opened'] as String),
  );

  Map<String, dynamic> toMap({bool includeId = true}) => {
    if (includeId) 'id': id,
    'path': path,
    'name': name,
    'is_directory': isDirectory ? 1 : 0,
    'open_count': openCount,
    'last_opened': lastOpened.toIso8601String(),
  };
}

/// Recently-opened files/folders manager backed by the `file_recents` table.
class FileRecentsService {
  static Database? _db;
  static const int _cap = 100;

  static void init(Database db) {
    _db = db;
  }

  static Database get _database {
    if (_db == null) throw StateError('FileRecentsService not initialized. Call init() first.');
    return _db!;
  }

  /// Record an open (upsert by path, incrementing the counter and moving it to
  /// the top of the recents list). Prunes entries above the cap.
  static Future<void> record(String path, {bool isDirectory = false}) async {
    final now = DateTime.now();
    final existing = await _byPath(path);
    if (existing != null) {
      await _database.update(
        'file_recents',
        {
          'name': existing.name ?? _deriveName(path),
          'is_directory': isDirectory ? 1 : 0,
          'open_count': existing.openCount + 1,
          'last_opened': now.toIso8601String(),
        },
        where: 'path = ?',
        whereArgs: [path],
      );
    } else {
      await _database.insert(
        'file_recents',
        FileRecent(path: path, name: _deriveName(path), isDirectory: isDirectory, lastOpened: now).toMap(includeId: false),
      );
    }
    await _prune();
  }

  static Future<FileRecent?> _byPath(String path) async {
    final q = await _database.query('file_recents', where: 'path = ?', whereArgs: [path], limit: 1);
    return q.isEmpty ? null : FileRecent.fromMap(q.first);
  }

  static Future<List<FileRecent>> getRecents({int limit = _cap}) async {
    try {
      final q = await _database.query('file_recents', orderBy: 'last_opened DESC', limit: limit);
      return q.map((m) => FileRecent.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> remove(String path) async {
    await _database.delete('file_recents', where: 'path = ?', whereArgs: [path]);
  }

  static Future<void> clearAll() async {
    await _database.delete('file_recents');
  }

  static Future<void> _prune() async {
    final q = await _database.query(
      'file_recents',
      columns: ['id'],
      orderBy: 'last_opened DESC',
      offset: _cap,
    );
    for (final r in q) {
      await _database.delete('file_recents', where: 'id = ?', whereArgs: [r['id']]);
    }
  }

  static String _deriveName(String path) {
    final trimmed = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    final idx = trimmed.lastIndexOf('/');
    return idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
  }
}
