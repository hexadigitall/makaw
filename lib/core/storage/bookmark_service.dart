import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// A user bookmark.
class Bookmark {
  final int? id;
  final String title;
  final String url;
  final int? folderId;
  final String? faviconUrl;
  final List<String> tags;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Bookmark({
    this.id,
    required this.title,
    required this.url,
    this.folderId,
    this.faviconUrl,
    this.tags = const [],
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Bookmark.fromMap(Map<String, dynamic> m) => Bookmark(
    id: m['id'] as int?,
    title: m['title'] as String,
    url: m['url'] as String,
    folderId: m['folder_id'] as int?,
    faviconUrl: m['favicon_url'] as String?,
    tags: _decodeList(m['tags'] as String?),
    notes: m['notes'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
  );

  Map<String, dynamic> toMap({bool includeId = true}) => {
    if (includeId) 'id': id,
    'title': title,
    'url': url,
    'folder_id': folderId,
    'favicon_url': faviconUrl,
    'tags': encodeList(tags),
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  static String encodeList(List<String> items) => jsonEncode(items);
  static List<String> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is List) return data.whereType<String>().toList();
    } catch (_) {}
    return const [];
  }
}

/// A bookmark folder.
class BookmarkFolder {
  final int? id;
  final String name;
  final int? parentId;
  final int sortOrder;
  final DateTime createdAt;

  const BookmarkFolder({
    this.id,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
    required this.createdAt,
  });

  factory BookmarkFolder.fromMap(Map<String, dynamic> m) => BookmarkFolder(
    id: m['id'] as int?,
    name: m['name'] as String,
    parentId: m['parent_id'] as int?,
    sortOrder: (m['sort_order'] as int?) ?? 0,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  Map<String, dynamic> toMap({bool includeId = true}) => {
    if (includeId) 'id': id,
    'name': name,
    'parent_id': parentId,
    'sort_order': sortOrder,
    'created_at': createdAt.toIso8601String(),
  };
}

/// Full-featured bookmark manager backed by `makaw_mgr.db`.
class BookmarkService {
  static Database? _db;

  static void init(Database db) {
    _db = db;
  }

  static Database get _database {
    if (_db == null) throw StateError('BookmarkService not initialized. Call init() first.');
    return _db!;
  }

  // ── Folders ─────────────────────────────────────────────────────────────────

  static Future<List<BookmarkFolder>> getFolders() async {
    try {
      final rows = await _database.query('bookmark_folders', orderBy: 'sort_order ASC, name ASC');
      return rows.map((m) => BookmarkFolder.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<BookmarkFolder?> getRootFolder(int? folderId) async {
    if (folderId == null) return null;
    final rows = await _database.query('bookmark_folders', where: 'id = ?', whereArgs: [folderId]);
    return rows.isEmpty ? null : BookmarkFolder.fromMap(rows.first);
  }

  static Future<int> createFolder(String name, {int? parentId}) async {
    final id = await _database.insert(
      'bookmark_folders',
      BookmarkFolder(name: name, parentId: parentId, createdAt: DateTime.now()).toMap(),
    );
    return id;
  }

  static Future<void> renameFolder(int id, String name) async {
    await _database.update('bookmark_folders', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteFolder(int id, {bool cascade = true}) async {
    final txn = await _database.transaction((txn) async {
      final children = await txn.query('bookmark_folders', where: 'parent_id = ?', whereArgs: [id]);
      for (final c in children) {
        await deleteFolder(c['id'] as int, cascade: cascade);
      }
      if (cascade) {
        await txn.update(
          'bookmarks',
          {'folder_id': null},
          where: 'folder_id = ?',
          whereArgs: [id],
        );
      }
      await txn.delete('bookmark_folders', where: 'id = ?', whereArgs: [id]);
    });
    return txn;
  }

  // ── Bookmarks ───────────────────────────────────────────────────────────────

  static Future<List<Bookmark>> getAll({int? folderId, int limit = 1000}) async {
    try {
      final results = await _database.query(
        'bookmarks',
        where: folderId != null ? 'folder_id = ?' : null,
        whereArgs: folderId != null ? [folderId] : null,
        orderBy: 'updated_at DESC',
        limit: limit,
      );
      return results.map((m) => Bookmark.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<Bookmark?> getByUrl(String url) async {
    final rows = await _database.query('bookmarks', where: 'url = ?', whereArgs: [url]);
    return rows.isEmpty ? null : Bookmark.fromMap(rows.first);
  }

  static Future<Bookmark?> getById(int id) async {
    final rows = await _database.query('bookmarks', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Bookmark.fromMap(rows.first);
  }

  static Future<List<Bookmark>> search(String query, {int limit = 300}) async {
    final q = '%$query%';
    final results = await _database.query(
      'bookmarks',
      where: 'title LIKE ? OR url LIKE ? OR tags LIKE ? OR notes LIKE ?',
      whereArgs: [q, q, q, q],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return results.map((m) => Bookmark.fromMap(m)).toList();
  }

  /// Insert or update a bookmark (upsert by url). Returns the row id.
  static Future<int> upsert(Bookmark b) async {
    final now = DateTime.now();
    final existing = await getByUrl(b.url);
    if (existing != null) {
      await _database.update(
        'bookmarks',
        {
          'title': b.title,
          'url': b.url,
          'folder_id': b.folderId,
          'favicon_url': b.faviconUrl,
          'tags': Bookmark.encodeList(b.tags),
          'notes': b.notes,
          'updated_at': now.toIso8601String(),
        },
        where: 'url = ?',
        whereArgs: [b.url],
      );
      return existing.id!;
    }
    return await _database.insert(
      'bookmarks',
      b.toMap(includeId: false)
        ..['created_at'] = now.toIso8601String()
        ..['updated_at'] = now.toIso8601String(),
    );
  }

  static Future<void> addBookmark(Bookmark b) async {
    await upsert(b);
  }

  static Future<void> updateBookmark(Bookmark b) async {
    if (b.id == null) return;
    await _database.update(
      'bookmarks',
      b.toMap(includeId: false)..['updated_at'] = DateTime.now().toIso8601String(),
      where: 'id = ?',
      whereArgs: [b.id],
    );
  }

  static Future<void> moveToFolder(int id, int? folderId) async {
    await _database.update(
      'bookmarks',
      {'folder_id': folderId, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> addTag(int id, String tag) async {
    final b = await getById(id);
    if (b == null) return;
    final tags = {...b.tags, tag}.toList();
    await _database.update(
      'bookmarks',
      {'tags': Bookmark.encodeList(tags), 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> removeTag(int id, String tag) async {
    final b = await getById(id);
    if (b == null) return;
    final tags = b.tags.where((t) => t != tag).toList();
    await _database.update(
      'bookmarks',
      {'tags': Bookmark.encodeList(tags), 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> deleteBookmark(int id) async {
    await _database.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteByUrl(String url) async {
    final b = await getByUrl(url);
    if (b?.id != null) await deleteBookmark(b!.id!);
  }

  static Future<void> clearAll() async {
    await _database.delete('bookmarks');
  }

  static Future<List<String>> allTags() async {
    final rows = await _database.query('bookmarks', columns: ['tags']);
    final tags = <String>{};
    for (final r in rows) {
      tags.addAll(Bookmark._decodeList(r['tags'] as String?));
    }
    return tags.toList()..sort();
  }

  // ── Migration of legacy SharedPreferences shortcuts ─────────────────────────

  /// Migrate the legacy `browser_shortcuts` prefs (list of `[title, url]`) into
  /// the bookmarks table. Accepts the decoded list so main can pass it directly.
  static Future<int> migrateShortcuts(List<dynamic> shortcuts) async {
    int migrated = 0;
    for (final s in shortcuts) {
      if (s is List && s.length >= 2 && s[0] is String && s[1] is String) {
        final title = s[0] as String;
        final url = s[1] as String;
        if (url.trim().isEmpty) continue;
        await upsert(Bookmark(
          title: title.trim().isEmpty ? _titleFromUrl(url) : title.trim(),
          url: url.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        migrated++;
      }
    }
    return migrated;
  }

  static String _titleFromUrl(String url) {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}
