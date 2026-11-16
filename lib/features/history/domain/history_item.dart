import 'dart:convert';

class HistoryItem {
  final int? id;
  final String url;
  final String title;
  final int timestamp;
  final String? faviconUrl;
  final int visitCount;

  /// Individual visit timestamps (oldest first). Populated going forward; rows
  /// created before this field existed carry only their single [timestamp].
  final List<int> visitTimes;

  HistoryItem({
    this.id,
    required this.url,
    required this.title,
    required this.timestamp,
    this.faviconUrl,
    this.visitCount = 1,
    List<int>? visitTimes,
  }) : visitTimes = visitTimes ?? const [];

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'url': url,
      'title': title,
      'time': DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String(),
      'favicon_url': faviconUrl,
      'visit_count': visitCount,
      'visit_times': visitTimes.isEmpty ? null : jsonEncode(visitTimes),
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
    final rawTimes = map['visit_times'] as String?;
    var times = <int>[];
    if (rawTimes != null && rawTimes.isNotEmpty) {
      try {
        times = (jsonDecode(rawTimes) as List).map((e) => (e as num).toInt()).toList();
      } catch (_) {
        times = const [];
      }
    }
    return HistoryItem(
      id: map['id'] as int?,
      url: map['url'] as String? ?? '',
      title: map['title'] as String? ?? '',
      timestamp: ts,
      faviconUrl: map['favicon_url'] as String?,
      visitCount: (map['visit_count'] as int?) ?? 1,
      visitTimes: times,
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
