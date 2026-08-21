class NewsCategory {
  final String name;
  final String feedUrl;
  final String icon;
  final String topic;
  int tapCount;

  NewsCategory({
    required this.name,
    required this.feedUrl,
    required this.icon,
    this.topic = 'All',
    this.tapCount = 0,
  });

  NewsCategory copyWith({String? name, String? feedUrl, String? icon, String? topic, int? tapCount}) =>
      NewsCategory(
        name: name ?? this.name,
        feedUrl: feedUrl ?? this.feedUrl,
        icon: icon ?? this.icon,
        topic: topic ?? this.topic,
        tapCount: tapCount ?? this.tapCount,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'feedUrl': feedUrl,
    'icon': icon,
    'topic': topic,
    'tapCount': tapCount,
  };

  factory NewsCategory.fromJson(Map<String, dynamic> json) => NewsCategory(
    name: json['name'] as String,
    feedUrl: json['feedUrl'] as String,
    icon: json['icon'] as String,
    topic: json['topic'] as String? ?? 'All',
    tapCount: json['tapCount'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NewsCategory && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'NewsCategory(name: $name, url: $feedUrl, topic: $topic)';
}
