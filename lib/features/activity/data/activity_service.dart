import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/activity_entry.dart';

/// Unified, on-device activity feed store.
///
/// Every ecosystem records an [ActivityEntry] here when a user does something
/// resume-worthy. The Makaw Home portal and ecosystem hubs read from it to
/// surface a single, consistent "recents" feed with one-tap resume and
/// per-item remove / clear-all control.
///
/// Backed by the `activity` table in the main `makaw.db` database.
class ActivityService {
  static Database? _db;

  /// Bumped on every write so widgets can rebuild without a ChangeNotifier.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const int _cap = 200;

  static void init(Database db) {
    _db = db;
  }

  static Database get _database {
    if (_db == null) throw StateError('ActivityService not initialized. Call init() first.');
    return _db!;
  }

  static bool get initialized => _db != null;

  static void requireInit() => _database;

  static Future<void> record(ActivityEntry entry, {bool dedupe = true}) async {
    if (_db == null) return;
    try {
      if (dedupe) {
        // Upsert semantics: a newer entry for the same kind+payload key bubbles
        // to the top instead of duplicating.
        final key = _dedupeKey(entry);
        if (key.isNotEmpty) {
          await _database.delete('activity', where: key, whereArgs: _dedupeArgs(entry));
        }
      }
      await _database.insert('activity', entry.toMap(includeId: false));
      await _prune();
      revision.value++;
    } catch (_) {}
  }

  static String _dedupeKey(ActivityEntry e) {
    switch (e.kind) {
      case ActivityKind.browser:
      case ActivityKind.document:
      case ActivityKind.file:
        return e.payload.containsKey('ref') ? 'kind = ? AND payload LIKE ?' : '';
      case ActivityKind.terminal:
        return 'kind = ? AND payload LIKE ?';
      case ActivityKind.project:
        return 'kind = ? AND payload LIKE ?';
      case ActivityKind.media:
        return 'kind = ? AND payload LIKE ?';
    }
    return '';
  }

  static List<Object> _dedupeArgs(ActivityEntry e) {
    switch (e.kind) {
      case ActivityKind.browser:
      case ActivityKind.document:
      case ActivityKind.file:
        return [e.kind, '%"ref":"${_esc(e.payload['ref'])}"%'];
      default:
        return [e.kind, '%"ref":"${_esc(e.payload['ref'])}"%'];
    }
  }

  static String _esc(Object? v) => (v?.toString() ?? '').replaceAll('"', '\\"');

  static Future<List<ActivityEntry>> getAll({int limit = _cap}) async {
    if (_db == null) return const [];
    try {
      final rows = await _database.query('activity', orderBy: 'timestamp DESC', limit: limit);
      return rows.map((m) => ActivityEntry.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ActivityEntry>> getByKind(String kind, {int limit = 50}) async {
    if (_db == null) return const [];
    try {
      final rows = await _database.query(
        'activity',
        where: 'kind = ?',
        whereArgs: [kind],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
      return rows.map((m) => ActivityEntry.fromMap(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> remove(int id) async {
    if (_db == null) return;
    try {
      await _database.delete('activity', where: 'id = ?', whereArgs: [id]);
      revision.value++;
    } catch (_) {}
  }

  static Future<void> removeWhere(String kind, String ref) async {
    if (_db == null) return;
    try {
      await _database.delete('activity', where: 'kind = ? AND payload LIKE ?', whereArgs: [kind, '%"ref":"$_esc(ref)"%']);
      revision.value++;
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    if (_db == null) return;
    try {
      await _database.delete('activity');
      revision.value++;
    } catch (_) {}
  }

  static Future<void> clearByKind(String kind) async {
    if (_db == null) return;
    try {
      await _database.delete('activity', where: 'kind = ?', whereArgs: [kind]);
      revision.value++;
    } catch (_) {}
  }

  static Future<void> _prune() async {
    try {
      final rows = await _database.query(
        'activity',
        columns: ['id'],
        orderBy: 'timestamp DESC',
        offset: _cap,
      );
      for (final r in rows) {
        await _database.delete('activity', where: 'id = ?', whereArgs: [r['id']]);
      }
    } catch (_) {}
  }
}
