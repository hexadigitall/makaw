import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// A single autocomplete / recent-search entry surfaced in the New Tab view.
class SearchSuggestion {
  final String query;
  final String? url;
  final SearchSuggestionKind kind;

  const SearchSuggestion({
    required this.query,
    this.url,
    this.kind = SearchSuggestionKind.search,
  });
}

enum SearchSuggestionKind { search, recent, url }

/// Persists recent searches in a dedicated SQLite database and proxies the
/// Google suggestion endpoint to power the New Tab autocomplete.
class BrowserSearchService {
  static Database? _db;

  static const String _suggestEndpoint =
      'https://suggestqueries.google.com/complete/search?client=chrome&q=';

  static Future<Database> open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'makaw_browser_searches.db');
    _db = await _initDatabase(path);
    return _db!;
  }

  static Future<Database> _initDatabase(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recent_searches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            query TEXT NOT NULL,
            searched_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_recent_searches_at ON recent_searches(searched_at DESC)',
        );
      },
    );
    return db;
  }

  static bool get isOpen => _db != null;

  /// Records a search submitted from the omnibox so it can be shown again on
  /// the focused New Tab view.
  static Future<void> saveSearch(String query) async {
    final db = _db;
    if (db == null) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    try {
      final now = DateTime.now().toIso8601String();
      await db.insert(
        'recent_searches',
        {'query': trimmed, 'searched_at': now},
      );
      await db.delete(
        'recent_searches',
        where: 'id NOT IN (SELECT id FROM recent_searches ORDER BY searched_at DESC LIMIT ?)',
        whereArgs: [20],
      );
    } catch (_) {}
  }

  /// Returns the most recently submitted searches, newest first.
  static Future<List<SearchSuggestion>> getRecentSearches({int limit = 8}) async {
    final db = _db;
    if (db == null) return [];
    try {
      final rows = await db.query(
        'recent_searches',
        orderBy: 'searched_at DESC',
        limit: limit,
      );
      return rows
          .map((r) => SearchSuggestion(
                query: (r['query'] as String? ?? ''),
                kind: SearchSuggestionKind.recent,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches live suggestions from Google for the given typed input.
  static Future<List<SearchSuggestion>> fetchSuggestions(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return [];
    try {
      final uri = Uri.parse('$_suggestEndpoint${Uri.encodeComponent(trimmed)}');
      final res = await http
          .get(uri, headers: {'User-Agent': 'MakawBrowser/1.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final decoded = jsonDecode(res.body);
      if (decoded is! List || decoded.length < 2) return [];
      final list = decoded[1];
      if (list is! List) return [];
      final out = <SearchSuggestion>[];
      for (final item in list.take(8)) {
        if (item is String && item.isNotEmpty) {
          out.add(SearchSuggestion(query: item, kind: SearchSuggestionKind.search));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
