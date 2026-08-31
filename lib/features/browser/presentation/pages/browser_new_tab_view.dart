import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/services/browser_search_service.dart';
import '../../domain/entities/recent_page_item.dart';
import '../../../news/data/services/news_feed_service.dart';
import '../../../news/presentation/widgets/discover_news_feed_widget.dart';

/// The three visual states of the Browser New Tab view.
///
/// - [idle]: resting hub with the Makaw wordmark, a tappable omnibox capsule,
///   a shortcuts grid, recent pages and trending news.
/// - [focused]: pub (omnibox) pinned to the top with quick actions (new tab,
///   clipboard) and recent searches.
/// - [typing]: live Google autocomplete suggestions with clear (X) support.
enum NewTabState { idle, focused, typing }

/// A modern, Chrome-style New Tab view for the Browser ecosystem.
///
/// Self-contained: it manages its own idle/focused/typing transitions and loads
/// recent searches + autocomplete through [BrowserSearchService]. Navigation is
/// delegated to the host via callbacks so the widget never needs to know how
/// tabs are opened or how the hub is switched.
class BrowserNewTabView extends StatefulWidget {
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenMenu;
  final VoidCallback onShowTabs;
  final VoidCallback onNewTab;
  final Function(String queryOrUrl) onNavigate;
  final VoidCallback onOpenBookmarks;
  final VoidCallback? onEditShortcuts;
  final List<RecentPageItem> recentPages;
  final List<(String, String)> shortcuts;
  final int tabCount;
  final NewsFeedService? newsFeedService;
  final bool autofocus;

  const BrowserNewTabView({
    super.key,
    required this.onOpenDashboard,
    required this.onOpenMenu,
    required this.onShowTabs,
    required this.onNewTab,
    required this.onNavigate,
    required this.onOpenBookmarks,
    this.onEditShortcuts,
    required this.recentPages,
    required this.shortcuts,
    required this.tabCount,
    this.newsFeedService,
    this.autofocus = false,
  });

  @override
  State<BrowserNewTabView> createState() => _BrowserNewTabViewState();
}

class _BrowserNewTabViewState extends State<BrowserNewTabView> {
  NewTabState _state = NewTabState.idle;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<SearchSuggestion> _recentSearches = const [];
  List<SearchSuggestion> _suggestions = const [];
  Timer? _debounce;
  bool _typingLoading = false;
  String? _clipboardText;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    _loadRecentSearches();
    if (widget.autofocus) {
      _state = NewTabState.focused;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() async {
    if (_focusNode.hasFocus) {
      if (_state != NewTabState.focused) {
        setState(() => _state = NewTabState.focused);
      }
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (mounted) setState(() => _clipboardText = text?.trim().isNotEmpty == true ? text!.trim() : null);
      } catch (_) {
        if (mounted) setState(() => _clipboardText = null);
      }
    }
  }

  Future<void> _loadRecentSearches() async {
    final recents = await BrowserSearchService.getRecentSearches();
    if (!mounted) return;
    setState(() => _recentSearches = recents);
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    final text = value.trim();
    if (text.isEmpty) {
      setState(() {
        _state = NewTabState.focused;
        _suggestions = const [];
        _typingLoading = false;
      });
      return;
    }
    setState(() {
      _state = NewTabState.typing;
      _typingLoading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 180), () => _fetchSuggestions(text));
  }

  Future<void> _fetchSuggestions(String text) async {
    final results = await BrowserSearchService.fetchSuggestions(text);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _typingLoading = false;
    });
  }

  void _submit([String? override]) {
    final query = (override ?? _controller.text).trim();
    if (query.isEmpty) return;
    BrowserSearchService.saveSearch(query);
    _controller.clear();
    _state = NewTabState.idle;
    widget.onNavigate(query);
  }

  void _openArticle(String url) => widget.onNavigate(url);

  void _clearTyping() {
    _controller.clear();
    setState(() {
      _state = NewTabState.focused;
      _suggestions = const [];
      _typingLoading = false;
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case NewTabState.typing:
        return _buildTypingView(context);
      case NewTabState.focused:
        return _buildFocusedView(context);
      case NewTabState.idle:
        return _buildIdleView(context);
    }
  }

  Color get _surface => const Color(0xFF0F172A);
  Color get _card => const Color(0xFF1E293B);

  // ── Shared top chrome (Home / tabs / overflow) ────────────────────────────
  Widget _buildTopBar(BuildContext context, {Color? bg}) {
    return Container(
      color: bg ?? const Color(0xFF0B1120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Makaw Browser Home',
            icon: const Icon(Icons.home_outlined, color: Colors.white),
            onPressed: widget.onOpenDashboard,
          ),
          const Spacer(),
          InkWell(
            onTap: widget.onShowTabs,
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.smartphone_rounded, color: Colors.white70, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.tabCount}',
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onPressed: widget.onOpenMenu,
          ),
        ],
      ),
    );
  }

  // ── IDLE ──────────────────────────────────────────────────────────────────
  Widget _buildIdleView(BuildContext context) {
    return ColoredBox(
      color: _surface,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 28),
                    const Text(
                      'Makaw',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 36,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildIdleOmnibox(context),
                    const SizedBox(height: 24),
                    _buildShortcutsGrid(context),
                    const SizedBox(height: 24),
                    _buildRecentPages(context),
                    const SizedBox(height: 24),
                    if (widget.newsFeedService != null)
                      DiscoverNewsFeedWidget(
                        service: widget.newsFeedService!,
                        onArticleSelected: _openArticle,
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleOmnibox(BuildContext context) {
    return InkWell(
      onTap: _focusNode.requestFocus,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: const Row(
          children: [
            Icon(Icons.search, color: Colors.white38, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Search or enter address...',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutsGrid(BuildContext context) {
    final items = List<(String, String)>.of(widget.shortcuts);
    final count = items.length + (widget.onEditShortcuts != null ? 1 : 0);
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          if (widget.onEditShortcuts != null && i == items.length) {
            return _ShortcutTile.edit(onTap: widget.onEditShortcuts!);
          }
          final s = items[i];
          return _ShortcutTile(label: s.$1, url: s.$2, onTap: () => _submit(s.$2));
        },
      ),
    );
  }

  Widget _buildRecentPages(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Pages',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          if (widget.recentPages.isEmpty)
            Text(
              'No pages visited yet. Start browsing to see recent pages here.',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
            )
          else
                    ...widget.recentPages.take(4).map(
                  (p) => InkWell(
                    onTap: () => _submit(p.url),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF243247),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.language_rounded, color: Colors.white38, size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.title.isEmpty ? p.url : p.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                                if (p.title.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    Uri.tryParse(p.url)?.host ?? p.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ── FOCUSED ───────────────────────────────────────────────────────────────
  Widget _buildFocusedView(BuildContext context) {
    return ColoredBox(
      color: _surface,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, bg: const Color(0xFF0B1120)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(child: _buildPinnedOmnibox(context)),
                  const SizedBox(width: 8),
                  _buildClipboardTile(context),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Recent Searches',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_recentSearches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Your recent searches will show up here.',
                          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                        ),
                      )
                    else
                      ..._recentSearches.map(
                        (r) => ListTile(
                          leading: const Icon(Icons.history, color: Colors.white54, size: 20),
                          title: Text(
                            r.query,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          trailing: const Icon(Icons.north_west, color: Colors.white38, size: 18),
                          onTap: () => _submit(r.query),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedOmnibox(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.white.withOpacity(0.4), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onTextChanged,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                hintText: 'Search Google or type a URL',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'New tab',
            icon: const Icon(Icons.add, color: Colors.white70, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: widget.onNewTab,
          ),
        ],
      ),
    );
  }

  Widget _buildClipboardTile(BuildContext context) {
    if (_clipboardText == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _showClipboardSheet(context),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: const Icon(Icons.content_paste_rounded, color: Color(0xFF38BDF8), size: 20),
      ),
    );
  }

  void _showClipboardSheet(BuildContext context) {
    final text = _clipboardText;
    if (text == null) return;
    final preview = text.length > 120 ? '${text.substring(0, 117)}...' : text;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _clipboardAction(Icons.copy, 'Copy', () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                }),
                _clipboardAction(Icons.share, 'Share', () {
                  Navigator.pop(ctx);
                  Share.share(text);
                }),
                _clipboardAction(Icons.edit, 'Edit', () {
                  Navigator.pop(ctx);
                  _controller.text = text;
                  _controller.selection = TextSelection.collapsed(offset: text.length);
                  _state = NewTabState.typing;
                  _onTextChanged(text);
                  setState(() {});
                  _focusNode.requestFocus();
                }),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _clipboardAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF38BDF8), size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
        ],
      ),
    );
  }

  // ── TYPING ────────────────────────────────────────────────────────────────
  Widget _buildTypingView(BuildContext context) {
    final results = _suggestions;
    return ColoredBox(
      color: _surface,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, bg: const Color(0xFF0B1120)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    onPressed: _clearTyping,
                  ),
                  Expanded(child: _buildTypingOmnibox(context)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (_typingLoading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white38),
                        ),
                      ),
                    )
                  else if (results.isEmpty && _controller.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Search Google for "${_controller.text.trim()}"',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    ...results.map(
                      (s) => ListTile(
                        dense: true,
                        leading: Icon(
                          s.kind == SearchSuggestionKind.recent
                              ? Icons.history
                              : Icons.search,
                          color: Colors.white54,
                          size: 20,
                        ),
                        title: Text(
                          s.query,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        subtitle: s.kind == SearchSuggestionKind.recent
                            ? null
                            : Text(
                                'google.com',
                                style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
                              ),
                        onTap: () => _submit(s.query),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingOmnibox(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onTextChanged,
              onSubmitted: (_) => _submit(),
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                hintText: 'Search Google or type a URL',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _clearTyping,
          ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final String? label;
  final String? url;
  final VoidCallback onTap;
  final bool isEdit;

  const _ShortcutTile({
    required this.label,
    required this.url,
    required this.onTap,
  }) : isEdit = false;

  const _ShortcutTile.edit({required this.onTap})
      : label = null,
        url = null,
        isEdit = true;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF243247),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Icon(
                isEdit ? Icons.edit_outlined : Icons.language_rounded,
                color: const Color(0xFF60A5FA),
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isEdit ? 'Edit' : (label ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
