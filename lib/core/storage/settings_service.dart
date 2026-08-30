import 'dart:async';
import 'package:sqflite/sqflite.dart';

/// Typed application settings backed by the `settings` table in `makaw_mgr.db`.
///
/// Values are stored as strings with an explicit type tag so helpers can
/// round-trip bool/int/double/string/list. A [Stream] notifies listeners when
/// a key changes (for live-updating UI).
class SettingsService {
  static Database? _db;
  static final StreamController<String> _changes = StreamController<String>.broadcast();

  static void init(Database db) {
    _db = db;
  }

  static Database get _database {
    if (_db == null) throw StateError('SettingsService not initialized. Call init() first.');
    return _db!;
  }

  /// Emits the key whenever a setting is written.
  static Stream<String> get changes => _changes.stream;

  // ── typed getters (all async; sqflite is async-only) ────────────────────────

  static Future<String?> getString(String key, {String? def}) async {
    final v = await _readValue(key);
    return v ?? def;
  }

  static Future<String?> getStringOrNull(String key) async => _readValue(key);

  static Future<bool> getBool(String key, {bool def = false}) async {
    final v = await _readValue(key);
    if (v == null) return def;
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
    return def;
  }

  static Future<int> getInt(String key, {int def = 0}) async {
    final v = await _readValue(key);
    return v == null ? def : (int.tryParse(v) ?? def);
  }

  static Future<double> getDouble(String key, {double def = 0}) async {
    final v = await _readValue(key);
    return v == null ? def : (double.tryParse(v) ?? def);
  }

  static Future<List<String>> getList(String key, {List<String> def = const []}) async {
    final v = await _readValue(key);
    if (v == null || v.isEmpty) return def;
    try {
      final re = RegExp(r"^(\[)?(.*?)(\])?$", dotAll: true);
      final m = re.firstMatch(v);
      final inner = m?.group(2) ?? v;
      final items = <String>[];
      for (final c in inner.split(',')) {
        final t = c.trim().replaceAll("'", '');
        if (t.isNotEmpty) items.add(t);
      }
      return items;
    } catch (_) {
      return def;
    }
  }

  // ── setters ─────────────────────────────────────────────────────────────────

  static Future<void> setString(String key, String value) => _write(key, value, 'string');
  static Future<void> setBool(String key, bool value) => _write(key, value.toString(), 'bool');
  static Future<void> setInt(String key, int value) => _write(key, value.toString(), 'int');
  static Future<void> setDouble(String key, double value) => _write(key, value.toString(), 'double');
  static Future<void> setList(String key, List<String> value) => _write(key, value.map((e) => "'$e'").join(','), 'list');

  // ── misc ────────────────────────────────────────────────────────────────────

  static Future<void> remove(String key) async {
    await _database.delete('settings', where: 'key = ?', whereArgs: [key]);
    _changes.add(key);
  }

  static Future<Map<String, String>> all() async {
    final rows = await _database.query('settings');
    return {for (final r in rows) r['key'] as String: (r['value'] as String? ?? '')};
  }

  static Future<void> clearAll() async {
    await _database.delete('settings');
    _changes.add('');
  }

  static Future<String?> _readValue(String key) async {
    final q = await _database.query('settings', where: 'key = ?', whereArgs: [key]);
    if (q.isEmpty) return null;
    return q.first['value'] as String?;
  }

  static Future<void> _write(String key, String value, String type) async {
    await _database.insert(
      'settings',
      {
        'key': key,
        'value': value,
        'type': type,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.add(key);
  }
}
