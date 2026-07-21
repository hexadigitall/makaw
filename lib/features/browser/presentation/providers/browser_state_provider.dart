import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/browser_tab.dart';
import '../../domain/entities/media_item.dart';

class BrowserStateModel {
  final List<BrowserTab> browserTabs;
  final int activeBrowserTabId;
  final bool desktopSite;
  final List<MediaItem> pendingMedia;
  final int nextTabId;

  const BrowserStateModel({
    this.browserTabs = const [],
    this.activeBrowserTabId = 0,
    this.desktopSite = false,
    this.pendingMedia = const [],
    this.nextTabId = 1,
  });

  BrowserStateModel copyWith({
    List<BrowserTab>? browserTabs,
    int? activeBrowserTabId,
    bool? desktopSite,
    List<MediaItem>? pendingMedia,
    int? nextTabId,
  }) {
    return BrowserStateModel(
      browserTabs: browserTabs ?? this.browserTabs,
      activeBrowserTabId: activeBrowserTabId ?? this.activeBrowserTabId,
      desktopSite: desktopSite ?? this.desktopSite,
      pendingMedia: pendingMedia ?? this.pendingMedia,
      nextTabId: nextTabId ?? this.nextTabId,
    );
  }
}

class BrowserStateNotifier extends Notifier<BrowserStateModel> {
  @override
  BrowserStateModel build() {
    _init();
    return const BrowserStateModel();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final desktopSite = prefs.getBool('desktop_site') ?? false;
    state = state.copyWith(desktopSite: desktopSite);
  }

  void addTab() {
    final id = state.nextTabId;
    state = state.copyWith(
      browserTabs: [...state.browserTabs, BrowserTab(id: id, title: 'New Tab', url: 'about:blank')],
      nextTabId: id + 1,
    );
  }

  void closeTab(int id) {
    final tabs = state.browserTabs.where((t) => t.id != id).toList();
    final activeId = state.activeBrowserTabId == id
        ? (tabs.isNotEmpty ? tabs.last.id : 0)
        : state.activeBrowserTabId;
    state = state.copyWith(browserTabs: tabs, activeBrowserTabId: activeId);
  }

  void setActiveTab(int id) {
    state = state.copyWith(activeBrowserTabId: id);
  }

  void updateTab(int id, {String? url, String? title}) {
    state = state.copyWith(
      browserTabs: state.browserTabs.map((t) {
        if (t.id != id) return t;
        return BrowserTab(
          id: t.id,
          url: url ?? t.url,
          title: title ?? t.title,
        );
      }).toList(),
    );
  }

  void setDesktopSite(bool value) {
    state = state.copyWith(desktopSite: value);
    SharedPreferences.getInstance().then((prefs) => prefs.setBool('desktop_site', value));
  }

  void addMediaItem(MediaItem item) {
    state = state.copyWith(pendingMedia: [...state.pendingMedia, item]);
  }

  void clearMedia() {
    state = state.copyWith(pendingMedia: []);
  }
}

final browserStateProvider = NotifierProvider<BrowserStateNotifier, BrowserStateModel>(
  BrowserStateNotifier.new,
);
