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
}
