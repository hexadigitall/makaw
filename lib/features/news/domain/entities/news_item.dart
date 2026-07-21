class NewsItem {
  final String title;
  final String url;
  final String? summary;
  final String? imageUrl;
  final DateTime? pubDate;
  final String source;

  NewsItem({
    required this.title,
    required this.url,
    this.summary,
    this.imageUrl,
    this.pubDate,
    required this.source,
  });

  NewsItem copyWith({
    String? title,
    String? url,
    String? summary,
    String? imageUrl,
    DateTime? pubDate,
    String? source,
  }) {
    return NewsItem(
      title: title ?? this.title,
      url: url ?? this.url,
      summary: summary ?? this.summary,
      imageUrl: imageUrl ?? this.imageUrl,
      pubDate: pubDate ?? this.pubDate,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'summary': summary,
    'imageUrl': imageUrl,
    'pubDate': pubDate?.toIso8601String(),
    'source': source,
  };

  factory NewsItem.fromJson(Map<String, dynamic> json) => NewsItem(
    title: json['title'] as String,
    url: json['url'] as String,
    summary: json['summary'] as String?,
    imageUrl: json['imageUrl'] as String?,
    pubDate: json['pubDate'] != null ? DateTime.parse(json['pubDate'] as String) : null,
    source: json['source'] as String,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewsItem && title == other.title && url == other.url && source == other.source;

  @override
  int get hashCode => Object.hash(title, url, source);

  @override
  String toString() => 'NewsItem(title: $title, source: $source)';
}
