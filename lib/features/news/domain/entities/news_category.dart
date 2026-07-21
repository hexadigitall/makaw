class NewsCategory {
  final String name;
  final String feedUrl;
  final String icon;
  int tapCount;

  NewsCategory({
    required this.name,
    required this.feedUrl,
    required this.icon,
    this.tapCount = 0,
  });

  NewsCategory copyWith({String? name, String? feedUrl, String? icon, int? tapCount}) =>
      NewsCategory(
        name: name ?? this.name,
        feedUrl: feedUrl ?? this.feedUrl,
        icon: icon ?? this.icon,
        tapCount: tapCount ?? this.tapCount,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'feedUrl': feedUrl,
    'icon': icon,
    'tapCount': tapCount,
  };

  factory NewsCategory.fromJson(Map<String, dynamic> json) => NewsCategory(
    name: json['name'] as String,
    feedUrl: json['feedUrl'] as String,
    icon: json['icon'] as String,
    tapCount: json['tapCount'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NewsCategory && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'NewsCategory(name: $name, url: $feedUrl)';
}
