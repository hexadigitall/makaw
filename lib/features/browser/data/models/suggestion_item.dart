enum SuggestionSource { history, bookmark, search, openTab }

class SuggestionItem {
  final String url;
  final String title;
  final String? faviconUrl;
  final SuggestionSource source;
  final double score;
  final int visitCount;
  final int lastVisitTimestamp;

  SuggestionItem({
    required this.url,
    required this.title,
    this.faviconUrl,
    required this.source,
    required this.score,
    this.visitCount = 1,
    this.lastVisitTimestamp = 0,
  });

  String get domain {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  String get displayTitle {
    if (title.isEmpty || title == 'about:blank' || title == url) {
      return domain;
    }
    return title;
  }

  String get googleFaviconUrl {
    final d = domain;
    return d.isNotEmpty ? 'https://www.google.com/s2/favicons?domain=$d&sz=64' : '';
  }
}
