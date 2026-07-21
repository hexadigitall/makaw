enum FeedCardType {
  articleHero,
  articleCompact,
  topicCarousel,
  adCard,
  updateBanner,
}

class FeedCard {
  final String id;
  final FeedCardType type;
  final String category;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  FeedCard({
    required this.id,
    required this.type,
    required this.category,
    required this.timestamp,
    required this.data,
  });

  String? get title => data['title'] as String?;
  String? get url => data['url'] as String?;
  String? get summary => data['summary'] as String?;
  String? get imageUrl => data['imageUrl'] as String?;
  double? get aspectRatio => (data['aspect_ratio'] as num?)?.toDouble();
  String? get source => data['source'] as String?;
  String? get publisher => data['publisher'] as String?;
  int? get readTimeMinutes => data['read_time_mins'] as int?;
  DateTime? get pubDate =>
      data['pub_date'] != null
          ? DateTime.tryParse(data['pub_date'] as String)
          : null;

  String get displayTitle => title ?? 'Untitled';
  String get displaySource => source ?? publisher ?? category;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'category': category,
        'timestamp': timestamp.toIso8601String(),
        'title': title,
        'url': url,
        'summary': summary,
        'imageUrl': imageUrl,
        'source': source,
        'publisher': publisher,
        'pub_date': pubDate?.toIso8601String(),
        'data': data,
      };

  factory FeedCard.fromJson(Map<String, dynamic> json) => FeedCard(
        id: json['id'] as String,
        type: FeedCardType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => FeedCardType.articleCompact,
        ),
        category: json['category'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        data: (json['data'] as Map<String, dynamic>?) ?? {},
      );

  static String generateId(String url, String source, String title) {
    return '${url}_${source}_$title'.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }

  FeedCard copyWith({bool? hidden}) => FeedCard(
        id: id,
        type: type,
        category: category,
        timestamp: timestamp,
        data: Map.from(data),
      );
}
