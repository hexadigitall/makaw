import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/services/news_feed_service.dart';
import '../../domain/entities/entities.dart';

class NewsFeedWidget extends StatefulWidget {
  final NewsFeedService service;
  final void Function(String url) onNavigate;
  final void Function(String action, NewsItem item, String categoryName)? onMenuAction;
  final ScrollController? scrollController;

  const NewsFeedWidget({super.key, required this.service, required this.onNavigate, this.onMenuAction, this.scrollController});

  @override
  NewsFeedWidgetState createState() => NewsFeedWidgetState();
}

class NewsFeedWidgetState extends State<NewsFeedWidget> {
  final Map<String, List<FeedCard>> _feeds = {};
  final Map<String, int> _visibleCount = {};
  final Map<String, int> _newCardCount = {};
  bool _loading = true;
  bool _userScrolling = false;
  static const int _pageSize = 6;
  final List<StreamSubscription> _subscriptions = [];
  Timer? _impressionTimer;
  final Set<String> _impressedCards = {};

  @override
  void initState() {
    super.initState();
    _loadCachedThenSubscribe();
    widget.scrollController?.addListener(_onScroll);
    _impressionTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkImpressions());
  }

  void _loadCachedThenSubscribe() {
    final ordered = widget.service.getOrderedCategories();
    bool hasAny = false;
    for (final cat in ordered) {
      final cached = widget.service.cachedCards(cat.name);
      if (cached.isNotEmpty) {
        _feeds[cat.name] = cached;
        _visibleCount[cat.name] = _pageSize;
        hasAny = true;
      }
    }
    if (hasAny) _loading = false;
    for (final cat in ordered) {
      final sub = widget.service.watchFeed(cat.name).listen((cards) {
        if (!mounted) return;
        setState(() {
          final existing = _feeds[cat.name] ?? [];
          final existingIds = existing.map((c) => c.id).toSet();
          final freshNew = cards.where((c) => !existingIds.contains(c.id)).toList();
          if (freshNew.isNotEmpty) {
            if (_userScrolling && existing.isNotEmpty) {
              _newCardCount[cat.name] = (_newCardCount[cat.name] ?? 0) + freshNew.length;
            } else {
              _feeds[cat.name] = cards;
              _newCardCount[cat.name] = 0;
            }
          }
          _visibleCount[cat.name] ??= _pageSize;
          _loading = false;
        });
      });
      _subscriptions.add(sub);
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _impressionTimer?.cancel();
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  void didUpdateWidget(NewsFeedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      for (final sub in _subscriptions) { sub.cancel(); }
      _subscriptions.clear();
      _loadCachedThenSubscribe();
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
    }
  }

  void _onScroll() {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) return;
    _userScrolling = controller.position.isScrollingNotifier.value;
    final maxScroll = controller.position.maxScrollExtent;
    final currentScroll = controller.position.pixels;
    if (maxScroll - currentScroll < 500) {
      _expandLastCategory();
    }
  }

  void _expandLastCategory() {
    final ordered = widget.service.getOrderedCategories();
    for (int i = ordered.length - 1; i >= 0; i--) {
      final cat = ordered[i];
      final items = _feeds[cat.name] ?? [];
      if (items.isEmpty) continue;
      final current = _visibleCount[cat.name] ?? _pageSize;
      if (current < items.length) {
        setState(() {
          _visibleCount[cat.name] = (current + _pageSize).clamp(0, items.length);
        });
        return;
      }
    }
  }

  void _showMore(String categoryName) {
    final items = _feeds[categoryName] ?? [];
    final current = _visibleCount[categoryName] ?? _pageSize;
    if (current < items.length) {
      setState(() {
        _visibleCount[categoryName] = (current + _pageSize).clamp(0, items.length);
      });
    }
  }

  void _acceptNewCards(String catName) {
    final count = _newCardCount[catName] ?? 0;
    if (count == 0) return;
    setState(() {
      final newCards = widget.service.cachedCards(catName).take(count).toList();
      _feeds[catName] = [...newCards, ...(_feeds[catName] ?? [])];
      _newCardCount[catName] = 0;
    });
  }

  Future<void> refresh() async {
    await widget.service.refreshAll();
  }

  void _checkImpressions() {
    for (final entry in _feeds.entries) {
      for (final card in entry.value) {
        if (!_impressedCards.contains(card.id)) {
          widget.service.recordImpression(card.id);
          _impressedCards.add(card.id);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _feeds.isEmpty) {
      return Center(child: CircularProgressIndicator(color: const Color(0xFF818CF8)));
    }
    final ordered = widget.service.getOrderedCategories();
    return Column(
      children: [
        for (final cat in ordered)
          if ((_feeds[cat.name] ?? []).isNotEmpty)
            _buildCategory(cat, _feeds[cat.name]!),
      ],
    );
  }

  Widget _buildCategory(NewsCategory cat, List<FeedCard> cards) {
    final count = _visibleCount[cat.name] ?? _pageSize;
    final newCount = _newCardCount[cat.name] ?? 0;
    final displayItems = cards.take(count).toList();
    final hasMore = count < cards.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (newCount > 0)
            _buildNewBanner(cat.name, newCount),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(_iconFor(cat.icon), size: 22, color: const Color(0xFF818CF8)),
                const SizedBox(width: 10),
                Text(cat.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  )),
                const Spacer(),
                Text('${cards.length}',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              for (int i = 0; i < displayItems.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RepaintBoundary(child: _buildFeedCard(displayItems[i], cat.name)),
                ),
              if (hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: GestureDetector(
                    onTap: () => _showMore(cat.name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.expand_more, color: Color(0xFF818CF8), size: 22),
                          const SizedBox(width: 6),
                          Text('Show ${(cards.length - count).clamp(0, _pageSize)} more',
                            style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewBanner(String catName, int count) {
    return GestureDetector(
      onTap: () => _acceptNewCards(catName),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fiber_new, color: Color(0xFF818CF8), size: 18),
            const SizedBox(width: 8),
            Text('$count new article${count == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedCard(FeedCard card, String categoryName) {
    return GestureDetector(
      onTap: () {
        widget.service.recordTap(categoryName);
        widget.service.recordClick(card.id);
        if (card.url != null && card.url!.isNotEmpty) widget.onNavigate(card.url!);
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF151E2A),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (card.imageUrl != null && card.imageUrl!.isNotEmpty)
                  SizedBox(
                    height: 180,
                    child: Image.network(card.imageUrl!,
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                      cacheWidth: (MediaQuery.of(context).size.width * 1.5).toInt(),
                      frameBuilder: (ctx, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) return child;
                        return Container(
                          height: 180,
                          color: const Color(0xFF1B242D),
                          child: const Center(child: Icon(Icons.article, color: Color(0xFF94A3B8), size: 36)),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        height: 140,
                        color: const Color(0xFF1B242D),
                        child: const Center(child: Icon(Icons.article, color: Color(0xFF94A3B8), size: 36)),
                      ),
                    ),
                  )
                  else
                  Container(
                    height: 100,
                    color: const Color(0xFF1B242D),
                    child: const Center(child: Icon(Icons.article, color: Color(0xFF94A3B8), size: 36)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.displayTitle,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(card.displaySource,
                            style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13)),
                          const Spacer(),
                          Text(_timeAgo(card.pubDate),
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (card.url != null && card.url!.isNotEmpty) {
                        Share.share(card.url!, subject: card.displayTitle);
                      }
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.share, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                    color: const Color(0xFF1E293B),
                    onSelected: (v) {
                      if (v == 'share') {
                        if (card.url != null && card.url!.isNotEmpty) {
                          Share.share(card.url!, subject: card.displayTitle);
                        }
                      } else {
                        final newsItem = NewsItem(
                          title: card.displayTitle,
                          url: card.url ?? '',
                          summary: card.summary,
                          imageUrl: card.imageUrl,
                          pubDate: card.pubDate,
                          source: card.displaySource,
                        );
                        widget.onMenuAction?.call(v, newsItem, categoryName);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'new_tab', child: ListTile(leading: Icon(Icons.open_in_new, color: Colors.white70, size: 20), title: Text('Open in new tab', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      const PopupMenuItem(value: 'new_tab_group', child: ListTile(leading: Icon(Icons.tab, color: Colors.white70, size: 20), title: Text('Open in new tab in group', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      const PopupMenuItem(value: 'incognito', child: ListTile(leading: Icon(Icons.visibility_off, color: Colors.white70, size: 20), title: Text('Open in incognito tab', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      const PopupMenuItem(value: 'reading_list', child: ListTile(leading: Icon(Icons.bookmark_border, color: Colors.white70, size: 20), title: Text('Add to reading list', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'hide', child: ListTile(leading: Icon(Icons.visibility_off, color: Colors.white70, size: 20), title: Text('Hide this', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      PopupMenuItem(value: 'not_interested_author', child: ListTile(leading: Icon(Icons.person_off, color: Colors.white70, size: 20), title: Text('Not interested in... $categoryName', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      PopupMenuItem(value: 'not_interested_category', child: ListTile(leading: Icon(Icons.category, color: Colors.white70, size: 20), title: Text('Not interested in... $categoryName', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      PopupMenuItem(value: 'dont_show_source', child: ListTile(leading: Icon(Icons.block, color: Colors.white70, size: 20), title: Text("Don't show content from... ${card.displaySource}", style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined, color: Colors.white70, size: 20), title: Text('Report this', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      const PopupMenuItem(value: 'feedback', child: ListTile(leading: Icon(Icons.feedback_outlined, color: Colors.white70, size: 20), title: Text('Send feedback', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                      const PopupMenuItem(value: 'close', child: ListTile(leading: Icon(Icons.close, color: Colors.white70, size: 20), title: Text('Close', style: TextStyle(color: Colors.white, fontSize: 13)), dense: true)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String iconName) {
    switch (iconName) {
      case 'newspaper': return Icons.article;
      case 'desktop': return Icons.desktop_windows;
      case 'sports_soccer': return Icons.sports_soccer;
      case 'sports_esports': return Icons.sports_esports;
      case 'business': return Icons.business_center;
      case 'science': return Icons.science;
      case 'movie': return Icons.movie;
      case 'code': return Icons.code;
      case 'language': return Icons.language;
      case 'local_hospital': return Icons.local_hospital;
      case 'account_balance': return Icons.account_balance;
      case 'smart_toy': return Icons.smart_toy;
      case 'security': return Icons.security;
      case 'rocket_launch': return Icons.rocket_launch;
      case 'eco': return Icons.eco;
      case 'spa': return Icons.spa;
      case 'camera_alt': return Icons.camera_alt;
      case 'rocket': return Icons.rocket;
      case 'school': return Icons.school;
      case 'flight': return Icons.flight;
      case 'restaurant': return Icons.restaurant;
      case 'music_note': return Icons.music_note;
      case 'menu_book': return Icons.menu_book;
      case 'directions_car': return Icons.directions_car;
      default: return Icons.rss_feed;
    }
  }

  String _timeAgo(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
