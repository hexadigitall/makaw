import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../domain/entities/browser_tab.dart';

const _kAccentTealLight = Color(0xFF0D9488);
const _kAccentTealDark = Color(0xFF14B8A6);
const _kIconBgLight = Color(0xFFF1F5F9);
const _kIconBgDark = Color(0xFF1E293B);
const _kIncognitoPurple = Color(0xFF7C3AED);

class TabTrayPage extends StatefulWidget {
  final List<BrowserTab> tabs;
  final int activeTabId;
  final Map<int, Uint8List?> snapshots;
  final ValueChanged<int> onSwitchTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onCreateTab;
  final VoidCallback? onCreateIncognitoTab;
  final bool initialIsIncognito;

  const TabTrayPage({
    super.key,
    required this.tabs,
    required this.activeTabId,
    this.snapshots = const {},
    required this.onSwitchTab,
    required this.onCloseTab,
    required this.onCreateTab,
    this.onCreateIncognitoTab,
    this.initialIsIncognito = false,
  });

  @override
  State<TabTrayPage> createState() => _TabTrayPageState();
}

class _TabTrayPageState extends State<TabTrayPage> {
  late List<BrowserTab> _tabs;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showIncognito = false;

  @override
  void initState() {
    super.initState();
    _tabs = List.from(widget.tabs);
    _showIncognito = widget.initialIsIncognito;
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _friendlyTitle(String url) {
    final u = url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '');
    final idx = u.indexOf('/');
    return idx > 0 ? u.substring(0, idx) : u;
  }

  void _closeTab(int id) {
    setState(() {
      _tabs.removeWhere((t) => t.id == id);
    });
    widget.onCloseTab(id);
  }

  List<BrowserTab> get _visibleTabs {
    final filtered = _tabs.where((t) => t.incognito == _showIncognito).toList();
    if (_searchQuery.isEmpty) return filtered;
    return filtered.where((t) {
      final title = (t.title.isNotEmpty ? t.title : t.url).toLowerCase();
      final url = t.url.toLowerCase();
      return title.contains(_searchQuery) || url.contains(_searchQuery);
    }).toList();
  }

  Widget _buildTabSnapshot(BrowserTab tab) {
    if (tab.incognito) {
      return Container(
        color: _kIncognitoPurple.withValues(alpha: 0.15),
        child: Center(
          child: Icon(Icons.visibility_off, color: _kIncognitoPurple.withValues(alpha: 0.5), size: 48),
        ),
      );
    }
    final memoryData = widget.snapshots[tab.id];
    if (memoryData != null) {
      return Image.memory(memoryData, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (tab.snapshotPath != null) {
      final file = File(tab.snapshotPath!);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover, gaplessPlayback: true);
      }
    }
    if (tab.url.isNotEmpty && tab.url != 'about:blank') {
      final domain = _friendlyTitle(tab.url);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final kAccentTeal = isDark ? _kAccentTealDark : _kAccentTealLight;
      final kIconBgColor = isDark ? _kIconBgDark : _kIconBgLight;
      return Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: kIconBgColor, borderRadius: BorderRadius.circular(8)),
              child: Center(
                child: Text(domain.isNotEmpty ? domain[0].toUpperCase() : '?',
                    style: TextStyle(color: kAccentTeal, fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(height: 8),
            Text(domain, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );
    }
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
              child: Center(child: Text('M', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
            ),
            SizedBox(height: 6),
            Text('New Tab', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kAccentTeal = isDark ? _kAccentTealDark : _kAccentTealLight;

    final hasIncognitoTabs = _tabs.any((t) => t.incognito);
    final regularCount = _tabs.where((t) => !t.incognito).length;
    final incognitoCount = _tabs.where((t) => t.incognito).length;
    final visible = _visibleTabs;
    final isEmptyState = visible.isEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.add_circle_outline, color: _showIncognito ? _kIncognitoPurple : kAccentTeal, size: 28),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showIncognito ? widget.onCreateIncognitoTab?.call() : widget.onCreateTab();
                  },
                  splashRadius: 20,
                ),
                Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showIncognito = false),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _showIncognito ? Theme.of(context).cardColor : kAccentTeal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _showIncognito ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3) : kAccentTeal.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tab, size: 18, color: _showIncognito ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6) : kAccentTeal),
                        SizedBox(width: 4),
                        Text('$regularCount', style: TextStyle(color: _showIncognito ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6) : kAccentTeal, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                if (hasIncognitoTabs) ...[
                  SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _showIncognito = true),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showIncognito ? _kIncognitoPurple.withValues(alpha: 0.15) : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _showIncognito ? _kIncognitoPurple.withValues(alpha: 0.3) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_off, size: 16, color: _showIncognito ? _kIncognitoPurple : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                          SizedBox(width: 4),
                          Text('$incognitoCount', style: TextStyle(color: _showIncognito ? _kIncognitoPurple : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
                Spacer(),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, color: Theme.of(context).colorScheme.onSurface),
                  onSelected: (v) {
                    switch (v) {
                      case 'new_tab':
                        Navigator.of(context).pop();
                        widget.onCreateTab();
                      case 'new_incognito':
                        Navigator.of(context).pop();
                        widget.onCreateIncognitoTab?.call();
                      case 'close_all':
                        final toClose = _tabs.where((t) => t.incognito == _showIncognito).toList();
                        for (final tab in toClose) widget.onCloseTab(tab.id);
                        setState(() => _tabs.removeWhere((t) => toClose.any((tc) => tc.id == t.id)));
                      case 'select_tabs':
                        Navigator.of(context).pop();
                      case 'delete_data':
                        Navigator.of(context).pop();
                      case 'settings':
                        Navigator.of(context).pop();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'new_tab', child: Row(children: [Icon(Icons.add, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)), SizedBox(width: 12), Text('New tab', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                    PopupMenuItem(value: 'new_incognito', child: Row(children: [Icon(Icons.visibility_off, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)), SizedBox(width: 12), Text('New Incognito tab', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'close_all', child: Row(children: [Icon(Icons.close, size: 18, color: Colors.redAccent), SizedBox(width: 12), Text('Close all tabs', style: TextStyle(color: Colors.redAccent))])),
                    PopupMenuItem(value: 'select_tabs', child: Row(children: [Icon(Icons.checklist, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)), SizedBox(width: 12), Text('Select tabs', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                    PopupMenuItem(value: 'delete_data', child: Row(children: [Icon(Icons.delete_sweep_outlined, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)), SizedBox(width: 12), Text('Delete browsing data', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                    PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)), SizedBox(width: 12), Text('Settings', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))])),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search your tabs',
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), size: 20),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ),
          Expanded(
            child: isEmptyState
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_showIncognito ? Icons.visibility_off : Icons.tab, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), size: 48),
                      SizedBox(height: 12),
                      Text(_searchQuery.isNotEmpty ? 'No matching tabs' : 'No ${_showIncognito ? 'incognito ' : ''}tabs', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final tab = visible[i];
                    final isActive = tab.id == widget.activeTabId;
                    final displayTitle = tab.url.isEmpty ? 'New Tab' : tab.title;
                    return Dismissible(
                      key: ValueKey('tab_${tab.id}'),
                      direction: DismissDirection.horizontal,
                      background: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.delete_outline, color: Colors.white, size: 28),
                      ),
                      onDismissed: (_) => _closeTab(tab.id),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            widget.onSwitchTab(tab.id);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: isActive ? Border.all(color: kAccentTeal, width: 2) : null,
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(isActive ? 10 : 12)),
                                ),
                                child: Row(
                                  children: [
                                    tab.incognito
                                      ? Icon(Icons.visibility_off, size: 14, color: _kIncognitoPurple)
                                      : Container(
                                          width: 20, height: 20,
                                          decoration: BoxDecoration(
                                            color: _kIconBgDark,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              tab.url.isNotEmpty ? tab.url.replaceFirst(RegExp(r'^https?://(www\.)?'), '')[0].toUpperCase() : 'M',
                                              style: TextStyle(color: kAccentTeal, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        displayTitle.length > 16 ? '${displayTitle.substring(0, 16)}...' : displayTitle,
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _closeTab(tab.id),
                                      child: Container(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(isActive ? 10 : 12)),
                                  child: _buildTabSnapshot(tab),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ));
                  },
                ),
          ),
        ],
        ),
      ),
    );
  }
}
