import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/history_item.dart';

class HistoryService {
  static Database? _db;
  static final ValueNotifier<int> historyVersion = ValueNotifier<int>(0);

  static const int _pruneDays = 90;
  static const int _maxStoredVisits = 50;

  static void init(Database db) {
    _db = db;
  }

  static Database get _database {
    if (_db == null) throw StateError('HistoryService not initialized. Call init() first.');
    return _db!;
  }

  static Future<void> addEntry(HistoryItem item) async {
    if (_db == null) return;
    final url = normalizeUrl(item.url);
    if (url == null) return;
    final title = item.title.isEmpty ? url : item.title;
    final ts = item.timestamp == 0
        ? DateTime.now().millisecondsSinceEpoch
        : item.timestamp;
    final time = DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String();
    try {
      final existing = await _database.query(
        'history',
        columns: ['visit_times'],
        where: 'url = ?',
        whereArgs: [url],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        var times = <int>[];
        final raw = existing.first['visit_times'] as String?;
        if (raw != null && raw.isNotEmpty) {
          try {
            times = (jsonDecode(raw) as List)
                .map((e) => (e as num).toInt())
                .toList();
          } catch (_) {
            times = <int>[];
          }
        }
        times.add(ts);
        if (times.length > _maxStoredVisits) {
          times = times.sublist(times.length - _maxStoredVisits);
        }
        await _database.rawUpdate(
          'UPDATE history SET title = ?, time = ?, visit_count = visit_count + 1, '
          'visit_times = ? WHERE url = ?',
          [title, time, jsonEncode(times), url],
        );
        historyVersion.value++;
        return;
      }
      await _database.insert(
        'history',
        {
          'url': url,
          'title': title,
          'time': time,
          'favicon_url': item.faviconUrl,
          'visit_count': 1,
          'visit_times': jsonEncode([ts]),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      historyVersion.value++;
    } catch (_) {}
  }

  /// Canonical key for a visited page: drops tracking params, fragments and a
  /// leading `www.` so redirects and campaign links collapse to one entry.
  /// Returns null for URLs that must never be stored.
  static String? normalizeUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    const junkSchemes = [
      'about:',
      'data:',
      'blob:',
      'javascript:',
      'intent:',
      'file:',
      'chrome:',
    ];
    for (final s in junkSchemes) {
      if (lower.startsWith(s)) return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return trimmed;
    if (uri.scheme != 'http' && uri.scheme != 'https') return trimmed;
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    if (host.isEmpty) return null;
    final params = Map<String, String>.from(uri.queryParameters);
    params.removeWhere((k, _) {
      final key = k.toLowerCase();
      return key.startsWith('utm_') ||
          key == 'gclid' ||
          key == 'fbclid' ||
          key == 'msclkid' ||
          key == 'igshid' ||
          key == 'mc_cid' ||
          key == 'mc_eid';
    });
    return Uri(
      scheme: uri.scheme,
      host: host,
      path: uri.path.isEmpty ? '/' : uri.path,
      queryParameters: params.isEmpty ? null : params,
    ).toString();
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
      historyVersion.value++;
    } catch (_) {}
  }

  static Future<void> deleteByUrl(String url) async {
    if (_db == null) return;
    final key = normalizeUrl(url) ?? url;
    try {
      await _database.delete('history', where: 'url = ?', whereArgs: [key]);
      historyVersion.value++;
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    if (_db == null) return;
    try {
      await _database.delete('history');
      historyVersion.value++;
    } catch (_) {}
  }

  static Future<void> updateTitle(String url, String title) async {
    if (_db == null) return;
    final key = normalizeUrl(url);
    if (key == null) return;
    try {
      await _database.rawUpdate('UPDATE history SET title = ? WHERE url = ?', [title, key]);
      historyVersion.value++;
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
