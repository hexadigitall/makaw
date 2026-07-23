class HistoryItem {
  final int? id;
  final String url;
  final String title;
  final int timestamp;
  final String? faviconUrl;

  HistoryItem({
    this.id,
    required this.url,
    required this.title,
    required this.timestamp,
    this.faviconUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'url': url,
      'title': title,
      'time': DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String(),
      'favicon_url': faviconUrl,
    };
  }

  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    int ts;
    final rawTime = map['time'] as String? ?? '';
    try {
      ts = DateTime.parse(rawTime).millisecondsSinceEpoch;
    } catch (_) {
      ts = 0;
    }
    return HistoryItem(
      id: map['id'] as int?,
      url: map['url'] as String? ?? '',
      title: map['title'] as String? ?? '',
      timestamp: ts,
      faviconUrl: map['favicon_url'] as String?,
    );
  }

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

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}
