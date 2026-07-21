class BrowserTab {
  final int id;
  final String url;
  final String title;
  final bool incognito;

  BrowserTab({
    required this.id,
    required this.url,
    this.title = 'New Tab',
    this.incognito = false,
  });

  BrowserTab copyWith({
    int? id,
    String? url,
    String? title,
    bool? incognito,
  }) {
    return BrowserTab(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      incognito: incognito ?? this.incognito,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'incognito': incognito,
  };

  factory BrowserTab.fromJson(Map<String, dynamic> json) => BrowserTab(
    id: json['id'] as int,
    url: json['url'] as String,
    title: json['title'] as String? ?? 'New Tab',
    incognito: json['incognito'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrowserTab && id == other.id && url == other.url && title == other.title && incognito == other.incognito;

  @override
  int get hashCode => Object.hash(id, url, title, incognito);

  @override
  String toString() => 'BrowserTab(id: $id, title: $title, url: $url)';
}
