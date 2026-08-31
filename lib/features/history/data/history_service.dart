import 'package:sqflite/sqflite.dart';
import '../domain/history_item.dart';

class HistoryService {
  static Database? _db;

  static const int _pruneDays = 90;

  static void init(Database db) {
    _db = db;
  }

  static Database get _database {
    if (_db == null) throw StateError('HistoryService not initialized. Call init() first.');
    return _db!;
  }

  static Future<void> addEntry(HistoryItem item) async {
    if (_db == null) return;
    try {
      await _database.insert(
        'history',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  static Future<List<HistoryItem>> getAll({int limit = 500}) async {
    if (_db == null) return [];
    try {
      final results = await _database.query(
        'history',
        orderBy: 'time DESC',
        limit: limit,
      );
      return results.map((m) => HistoryItem.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<HistoryItem>> search(String query, {int limit = 200}) async {
    if (_db == null) return [];
    try {
      final results = await _database.query(
        'history',
        where: 'title LIKE ? OR url LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
        orderBy: 'time DESC',
        limit: limit,
      );
      return results.map((m) => HistoryItem.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> deleteEntry(int id) async {
    if (_db == null) return;
    try {
      await _database.delete('history', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    if (_db == null) return;
    try {
      await _database.delete('history');
    } catch (_) {}
  }

  static Future<void> updateTitle(String url, String title) async {
    if (_db == null) return;
    try {
      await _database.rawUpdate('UPDATE history SET title = ? WHERE url = ?', [title, url]);
    } catch (_) {}
  }

  static Future<void> pruneOldEntries() async {
    if (_db == null) return;
    try {
      final cutoff = DateTime.now().subtract(Duration(days: _pruneDays));
      await _database.delete(
        'history',
        where: 'time < ?',
        whereArgs: [cutoff.toIso8601String()],
      );
    } catch (_) {}
  }
}
