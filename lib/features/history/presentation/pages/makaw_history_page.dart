import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../data/history_service.dart';
import '../../domain/history_item.dart';

class MakawHistoryPage extends StatefulWidget {
  final void Function(String url) onNavigate;

  const MakawHistoryPage({super.key, required this.onNavigate});

  @override
  State<MakawHistoryPage> createState() => _MakawHistoryPageState();
}

class _MakawHistoryPageState extends State<MakawHistoryPage> {
  List<HistoryItem> _allItems = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final items = _searchQuery.isEmpty
          ? await HistoryService.getAll()
          : await HistoryService.search(_searchQuery);
      if (mounted) setState(() { _allItems = items; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _allItems = []; _isLoading = false; });
    }
  }

  Map<String, List<HistoryItem>> get _groupedItems {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final weekAgo = today.subtract(Duration(days: 7));

    final Map<String, List<HistoryItem>> groups = {};
    for (final item in _allItems) {
      final itemDate = item.dateTime;
      String label;
      if (!itemDate.isBefore(today)) {
        label = 'Today';
      } else if (!itemDate.isBefore(yesterday)) {
        label = 'Yesterday';
      } else if (!itemDate.isBefore(weekAgo)) {
        label = 'This Week';
      } else {
        label = 'Older';
      }
      groups.putIfAbsent(label, () => []);
      groups[label]!.add(item);
    }
    return groups;
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(dt.year, dt.month, dt.day);

    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:${dt.minute.toString().padLeft(2, '0')} $ampm';

    if (!itemDate.isBefore(today)) {
      return 'Today, $timeStr';
    } else if (!itemDate.isBefore(today.subtract(Duration(days: 1)))) {
      return 'Yesterday, $timeStr';
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, $timeStr';
    }
  }

  void _showItemActions(HistoryItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: EdgeInsets.only(top: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(item.displayTitle,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              _actionTile(Icons.open_in_new, 'Open in New Tab', () {
                Navigator.of(ctx).pop();
                widget.onNavigate(item.url);
              }),
              _actionTile(Icons.content_copy, 'Copy Link', () {
                Clipboard.setData(ClipboardData(text: item.url));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Link copied'), duration: Duration(seconds: 1), backgroundColor: Color(0xFF334155)),
                );
              }),
              _actionTile(Icons.delete_outline, 'Delete', () async {
                Navigator.of(ctx).pop();
                await HistoryService.deleteEntry(item.id!);
                await _loadHistory();
              }, color: Color(0xFFF87171)),
            ],
          ),
        );
      },
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.white70, size: 22),
      title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 14)),
      onTap: onTap,
      dense: true,
    );
  }

  void _showClearBrowsingDataDialog() {
    bool clearHistory = true;
    bool clearCookies = false;
    bool clearCache = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              backgroundColor: Color(0xFF1E293B),
              title: Text('Clear Browsing Data', style: TextStyle(color: Colors.white, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _checkboxTile('Browsing history', clearHistory, (v) => setDlgState(() => clearHistory = v ?? false)),
                  _checkboxTile('Cookies and site data', clearCookies, (v) => setDlgState(() => clearCookies = v ?? false)),
                  _checkboxTile('Cached images and files', clearCache, (v) => setDlgState(() => clearCache = v ?? false)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    if (clearHistory) {
                      await HistoryService.clearAll();
                      await _loadHistory();
                    }
                    if (clearCookies) {
                      try {
                        final cookieMgr = await _getCookieManager();
                        await cookieMgr?.deleteAllCookies();
                      } catch (_) {}
                    }
                    if (clearCache) {
                      // WebView cache is cleared from the main app
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Browsing data cleared'), duration: Duration(seconds: 1), backgroundColor: Color(0xFF334155)),
                      );
                    }
                  },
                  child: Text('Clear', style: TextStyle(color: Color(0xFFF87171))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<dynamic> _getCookieManager() async {
    try {
      final mgr = CookieManager.instance();
      return mgr;
    } catch (_) {
      return null;
    }
  }

  Widget _checkboxTile(String title, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: TextStyle(color: Colors.white, fontSize: 14)),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: Color(0xFF00897B),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Color(0xFF1E293B),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          style: TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search history',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: Colors.white38, size: 22),
            prefixIconConstraints: BoxConstraints(minWidth: 40),
          ),
          onChanged: (v) {
            _searchQuery = v.trim();
            _loadHistory();
          },
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                _searchQuery = '';
                _loadHistory();
                _searchFocus.unfocus();
              },
            ),
          IconButton(
            icon: Icon(Icons.delete_sweep, color: Color(0xFFF87171)),
            onPressed: _allItems.isEmpty ? null : _showClearBrowsingDataDialog,
            tooltip: 'Clear browsing data',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xFF00897B)))
          : _allItems.isEmpty
              ? _buildEmptyState()
              : _buildGroupedList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: Colors.white24),
          SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No results found' : 'No browsing history',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty ? 'Try a different search' : 'Visit some websites to see history here',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList() {
    final groups = _groupedItems;
    final sectionOrder = ['Today', 'Yesterday', 'This Week', 'Older'];
    final sections = sectionOrder.where((s) => groups.containsKey(s)).toList();

    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: Color(0xFF00897B),
      backgroundColor: Color(0xFF1E293B),
      child: ListView.builder(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
        itemCount: sections.length,
        itemBuilder: (_, sectionIndex) {
          final section = sections[sectionIndex];
          final items = groups[section]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, sectionIndex == 0 ? 12 : 20, 16, 8),
                child: Text(
                  section.toUpperCase(),
                  style: TextStyle(
                    color: Color(0xFF00897B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ...items.asMap().entries.map((entry) {
                final item = entry.value;
                return _buildHistoryTile(item);
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHistoryTile(HistoryItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onNavigate(item.url);
          Navigator.of(context).pop();
        },
        onLongPress: () => _showItemActions(item),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.googleFaviconUrl.isNotEmpty
                      ? Image.network(
                          item.googleFaviconUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(Icons.language, color: Color(0xFF00897B), size: 22),
                        )
                      : Icon(Icons.language, color: Color(0xFF00897B), size: 22),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayTitle,
                      style: TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 3),
                    Text(
                      '${item.domain} \u00b7 ${_formatTime(item.timestamp)}',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.more_vert, color: Colors.white38, size: 18),
                onPressed: () => _showItemActions(item),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
