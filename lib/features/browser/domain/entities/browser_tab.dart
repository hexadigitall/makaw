import 'package:flutter/widgets.dart';

class BrowserTab {
  final int id;
  String url;
  String title;
  final bool incognito;
  String? snapshotPath;
  List<String> historyStack;
  int historyIndex;
  final GlobalKey webViewKey = GlobalKey();

  BrowserTab({
    required this.id,
    this.url = '',
    this.title = 'New Tab',
    this.incognito = false,
    this.snapshotPath,
    List<String>? historyStack,
    this.historyIndex = 0,
  }) : historyStack = historyStack ?? [];

  BrowserTab copyWith({int? id, String? url, String? title, bool? incognito, String? snapshotPath, List<String>? historyStack, int? historyIndex}) => BrowserTab(
    id: id ?? this.id,
    url: url ?? this.url,
    title: title ?? this.title,
    incognito: incognito ?? this.incognito,
    snapshotPath: snapshotPath ?? this.snapshotPath,
    historyStack: historyStack ?? List<String>.from(this.historyStack),
    historyIndex: historyIndex ?? this.historyIndex,
  );

  bool get canGoBack => historyIndex > 0;
  bool get canGoForward => historyIndex < historyStack.length - 1;
  bool get isEmpty => url.isEmpty || url == 'about:blank';

  void pushHistory(String url) {
    if (historyStack.isNotEmpty && historyIndex < historyStack.length - 1) {
      historyStack = historyStack.sublist(0, historyIndex + 1);
    }
    if (historyStack.isEmpty || historyStack.last != url) {
      historyStack.add(url);
      historyIndex = historyStack.length - 1;
    }
  }

  String? goBack() {
    if (!canGoBack) return null;
    historyIndex--;
    return historyStack[historyIndex];
  }

  String? goForward() {
    if (!canGoForward) return null;
    historyIndex++;
    return historyStack[historyIndex];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'incognito': incognito,
    'snapshotPath': snapshotPath,
    'historyStack': historyStack,
    'historyIndex': historyIndex,
  };

  factory BrowserTab.fromJson(Map<String, dynamic> json) => BrowserTab(
    id: json['id'] as int,
    url: json['url'] as String? ?? '',
    title: json['title'] as String? ?? 'New Tab',
    incognito: json['incognito'] as bool? ?? false,
    snapshotPath: json['snapshotPath'] as String?,
    historyStack: (json['historyStack'] as List<dynamic>?)?.cast<String>() ?? [],
    historyIndex: json['historyIndex'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrowserTab && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BrowserTab(id: $id, title: $title, url: $url)';
}
