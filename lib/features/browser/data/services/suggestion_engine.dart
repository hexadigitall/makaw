import 'dart:math';
import '../models/suggestion_item.dart';

class SuggestionEngine {
  static const int _maxResults = 10;
  static const double _prefixBonus = 150.0;
  static const double _titleMatchBonus = 100.0;
  static const double _urlMatchBonus = 80.0;
  static const double _bookmarkBonus = 50.0;
  static const double _visitCountBonus = 30.0;

  static List<SuggestionItem> rank({
    required String query,
    required List<Map<String, dynamic>> history,
    required List<(String, String)> shortcuts,
    required List<String> searchSuggestions,
    List<Map<String, dynamic>> openTabs = const [],
    bool isIncognito = false,
  }) {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    final results = <SuggestionItem>[];
    final seenUrls = <String>{};
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!isIncognito) {
      for (final h in history) {
        final url = (h['url'] as String? ?? '');
        final title = (h['title'] as String? ?? '');
        final timeStr = h['time'] as String? ?? '';
        int timestamp = 0;
        try { timestamp = DateTime.parse(timeStr).millisecondsSinceEpoch; } catch (_) {}

        final score = _scoreItem(lower, url, title, isBookmark: false);
        if (score <= 0) continue;
        final normalizedUrl = _normalizeUrl(url);
        if (!seenUrls.add(normalizedUrl)) continue;

        results.add(SuggestionItem(
          url: url,
          title: title,
          source: SuggestionSource.history,
          score: score,
          lastVisitTimestamp: timestamp,
        ));
      }

      for (final s in shortcuts) {
        final label = s.$1;
        final url = s.$2;
        final score = _scoreItem(lower, url, label, isBookmark: true);
        if (score <= 0) continue;
        final normalizedUrl = _normalizeUrl(url);
        if (!seenUrls.add(normalizedUrl)) continue;

        results.add(SuggestionItem(
          url: url,
          title: label,
          source: SuggestionSource.bookmark,
          score: score,
        ));
      }
    } else {
      for (final s in shortcuts) {
        final label = s.$1;
        final url = s.$2;
        final score = _scoreItem(lower, url, label, isBookmark: true);
        if (score <= 0) continue;
        final normalizedUrl = _normalizeUrl(url);
        if (!seenUrls.add(normalizedUrl)) continue;

        results.add(SuggestionItem(
          url: url,
          title: label,
          source: SuggestionSource.bookmark,
          score: score,
        ));
      }

      for (final t in openTabs) {
        final url = (t['url'] as String? ?? '');
        final title = (t['title'] as String? ?? '');
        final score = _scoreItem(lower, url, title, isBookmark: false) * 0.9;
        if (score <= 0) continue;
        final normalizedUrl = _normalizeUrl(url);
        if (!seenUrls.add(normalizedUrl)) continue;

        results.add(SuggestionItem(
          url: url,
          title: title,
          source: SuggestionSource.openTab,
          score: score,
        ));
      }
    }

    for (final suggestion in searchSuggestions) {
      final searchUrl = 'https://www.google.com/search?q=${Uri.encodeComponent(suggestion)}';
      final normalizedUrl = _normalizeUrl(searchUrl);
      if (!seenUrls.add(normalizedUrl)) continue;

      final prefixMatch = suggestion.toLowerCase().startsWith(lower);
      final score = prefixMatch ? 200.0 : 120.0;

      results.add(SuggestionItem(
        url: searchUrl,
        title: suggestion,
        source: SuggestionSource.search,
        score: score,
      ));
    }

    results.sort((a, b) {
      final scoreA = a.score + _recencyBonus(a.lastVisitTimestamp, now);
      final scoreB = b.score + _recencyBonus(b.lastVisitTimestamp, now);
      return scoreB.compareTo(scoreA);
    });

    return results.take(_maxResults).toList();
  }

  static double _scoreItem(String query, String url, String title, {required bool isBookmark}) {
    final lowerUrl = url.toLowerCase();
    final lowerTitle = title.toLowerCase();
    double score = 0;

    final urlPrefix = lowerUrl.startsWith('http://') ? lowerUrl.substring(7) : lowerUrl.startsWith('https://') ? lowerUrl.substring(8) : lowerUrl;
    if (urlPrefix.startsWith(query)) {
      score += _prefixBonus + 50;
    } else if (lowerUrl.contains(query)) {
      score += _urlMatchBonus;
    }

    if (lowerTitle.startsWith(query)) {
      score += _prefixBonus;
    } else if (lowerTitle.contains(query)) {
      score += _titleMatchBonus;
    }

    if (isBookmark) score += _bookmarkBonus;

    return score;
  }

  static double _recencyBonus(int timestamp, int now) {
    if (timestamp <= 0) return 0;
    final ageMs = now - timestamp;
    final ageHours = ageMs / (1000 * 60 * 60);
    if (ageHours < 1) return 40;
    if (ageHours < 24) return 30;
    if (ageHours < 168) return 20;
    if (ageHours < 720) return 10;
    return 0;
  }

  static String _normalizeUrl(String url) {
    var normalized = url.toLowerCase();
    if (normalized.endsWith('/')) normalized = normalized.substring(0, normalized.length - 1);
    return normalized;
  }
}
