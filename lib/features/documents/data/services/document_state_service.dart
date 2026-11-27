import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../domain/document_reader_contract.dart';

class DocumentCollection {
  final int id;
  final String name;
  final int colorHex;
  final DateTime createdAt;

  const DocumentCollection({
    required this.id,
    required this.name,
    this.colorHex = 0xFF818CF8,
    required this.createdAt,
  });

  factory DocumentCollection.fromMap(Map<String, dynamic> map) => DocumentCollection(
    id: map['id'] as int,
    name: map['name'] as String,
    colorHex: (map['color_hex'] as int?) ?? 0xFF818CF8,
    createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// SQLite persistence for unified [DocumentReadingState], bookmarks, pins, and
/// user document collections inside `makaw_mgr.db`.
class DocumentStateService {
  DocumentStateService._();

  static Database? _db;

  /// Broadcasts counter increments whenever reading state or collections change
  /// so the Documents Library refreshes progress rings immediately.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static final Map<String, DocumentReadingState> _cache = {};
  static final Map<int, Set<String>> _collectionPathsCache = {};
  static List<DocumentCollection> _collectionsCache = [];

  static void init(Database db) {
    _db = db;
    _cache.clear();
    _collectionsCache = [];
    _collectionPathsCache.clear();
  }

  static bool get isInitialized => _db != null;

  static void _bump() {
    version.value = version.value + 1;
  }

  static Map<String, DocumentReadingState> get cachedStates => Map.unmodifiable(_cache);

  static List<DocumentCollection> get cachedCollections => List.unmodifiable(_collectionsCache);

  static Set<String> pathsInCollection(int collectionId) =>
      _collectionPathsCache[collectionId] ?? const {};

  static Future<void> warmCache() async {
    final db = _db;
    if (db == null) return;
    try {
      final rows = await db.query('document_state', orderBy: 'last_read DESC');
      _cache.clear();
      for (final row in rows) {
        final state = DocumentReadingState.fromMap(row);
        _cache[state.filePath] = state;
      }
      final cols = await db.query('document_collections', orderBy: 'name COLLATE NOCASE ASC');
      _collectionsCache = cols.map(DocumentCollection.fromMap).toList();
      _collectionPathsCache.clear();
      final items = await db.query('document_collection_items');
      for (final row in items) {
        final cid = row['collection_id'] as int;
        final fp = row['file_path'] as String;
        _collectionPathsCache.putIfAbsent(cid, () => <String>{}).add(fp);
      }
      _bump();
    } catch (_) {}
  }

  static Future<DocumentReadingState?> getState(String filePath) async {
    final cached = _cache[filePath];
    if (cached != null) return cached;
    final db = _db;
    if (db == null) return null;
    try {
      final rows = await db.query(
        'document_state',
        where: 'file_path = ?',
        whereArgs: [filePath],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final state = DocumentReadingState.fromMap(rows.first);
      _cache[filePath] = state;
      return state;
    } catch (_) {
      return null;
    }
  }

  static DocumentReadingState? peekState(String filePath) => _cache[filePath];

  static Future<void> saveProgress(
    String filePath, {
    String? title,
    int? currentPage,
    int? totalPages,
    double? scrollProgress,
    double? scrollOffset,
    double? zoomScale,
    ReaderTheme? theme,
    double? fontSize,
    List<int>? bookmarks,
    ReadingStatus? readingStatus,
    bool? isPinned,
  }) async {
    final existing = await getState(filePath);
    final ext = p.extension(filePath);
    final resolvedTitle = (title != null && title.isNotEmpty)
        ? title
        : (existing?.title.isNotEmpty == true ? existing!.title : p.basename(filePath));
    final nextPage = currentPage ?? existing?.currentPage ?? 1;
    final nextTotal = (totalPages != null && totalPages > 0)
        ? totalPages
        : (existing?.totalPages ?? 1);
    final nextProgress = scrollProgress ??
        (nextTotal > 1 ? (nextPage / nextTotal).clamp(0.0, 1.0) : (existing?.scrollProgress ?? 0.0));
    final nextStatus = readingStatus ??
        ((nextProgress >= 0.98 || (nextTotal > 1 && nextPage >= nextTotal))
            ? ReadingStatus.finished
            : (nextProgress > 0.0 || nextPage > 1)
                ? ReadingStatus.reading
                : (existing?.readingStatus ?? ReadingStatus.unread));

    final updated = DocumentReadingState(
      filePath: filePath,
      title: resolvedTitle,
      format: existing?.format ?? DocumentFormat.fromExtension(ext),
      currentPage: nextPage,
      totalPages: nextTotal,
      scrollProgress: nextProgress,
      scrollOffset: scrollOffset ?? existing?.scrollOffset ?? 0.0,
      zoomScale: zoomScale ?? existing?.zoomScale ?? 1.0,
      lastRead: DateTime.now(),
      theme: theme ?? existing?.theme ?? ReaderTheme.dark,
      fontSize: fontSize ?? existing?.fontSize ?? 16.0,
      bookmarks: bookmarks ?? existing?.bookmarks ?? const [],
      readingStatus: nextStatus,
      isPinned: isPinned ?? existing?.isPinned ?? false,
    );

    _cache[filePath] = updated;
    _bump();

    final db = _db;
    if (db == null) return;
    try {
      await db.insert(
        'document_state',
        updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  static Future<void> togglePin(String filePath, {String? title}) async {
    final existing = await getState(filePath);
    await saveProgress(
      filePath,
      title: title,
      isPinned: !(existing?.isPinned ?? false),
    );
  }

  static Future<List<DocumentReadingState>> getContinueReading({int limit = 12}) async {
    if (_cache.isEmpty && _db != null) await warmCache();
    final items = _cache.values
        .where((s) => s.readingStatus == ReadingStatus.reading || s.isPinned || s.normalizedProgress > 0.01)
        .toList()
      ..sort((a, b) => b.lastRead.compareTo(a.lastRead));
    return items.take(limit).toList();
  }

  // ── Collections ─────────────────────────────────────────────────────────────

  static Future<DocumentCollection?> createCollection(String name, {int colorHex = 0xFF818CF8}) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    final db = _db;
    final now = DateTime.now();
    if (db == null) {
      final col = DocumentCollection(
        id: clean.hashCode,
        name: clean,
        colorHex: colorHex,
        createdAt: now,
      );
      if (!_collectionsCache.any((c) => c.name.toLowerCase() == clean.toLowerCase())) {
        _collectionsCache = [..._collectionsCache, col]..sort((a, b) => a.name.compareTo(b.name));
        _bump();
      }
      return col;
    }
    try {
      final id = await db.insert(
        'document_collections',
        {
          'name': clean,
          'color_hex': colorHex,
          'created_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await warmCache();
      return _collectionsCache.where((c) => c.id == id || c.name.toLowerCase() == clean.toLowerCase()).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  static Future<void> addToCollection(int collectionId, String filePath) async {
    _collectionPathsCache.putIfAbsent(collectionId, () => <String>{}).add(filePath);
    _bump();
    final db = _db;
    if (db == null) return;
    try {
      await db.insert(
        'document_collection_items',
        {
          'collection_id': collectionId,
          'file_path': filePath,
          'added_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {}
  }

  static Future<void> removeFromCollection(int collectionId, String filePath) async {
    _collectionPathsCache[collectionId]?.remove(filePath);
    _bump();
    final db = _db;
    if (db == null) return;
    try {
      await db.delete(
        'document_collection_items',
        where: 'collection_id = ? AND file_path = ?',
        whereArgs: [collectionId, filePath],
      );
    } catch (_) {}
  }
}
