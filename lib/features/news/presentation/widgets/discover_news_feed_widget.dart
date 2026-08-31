import 'package:flutter/material.dart';

import '../../data/services/news_feed_service.dart';

/// A cache-first Discover feed for the Browser New Tab idle view.
///
/// Reads straight from SQLite via [NewsFeedService.allCachedCards] with zero
/// network latency, then revalidates in the background (RFC 7232 conditional
/// GETs) when the cache is stale or empty. Each card shows its headline,
/// publisher and relative time; a diversity filter caps how many cards a
/// single publisher can occupy so no outlet dominates the feed.
class DiscoverNewsFeedWidget extends StatefulWidget {
  final NewsFeedService service;
  final void Function(String url) onArticleSelected;

  const DiscoverNewsFeedWidget({
    super.key,
    required this.service,
    required this.onArticleSelected,
  });

  @override
  State<DiscoverNewsFeedWidget> createState() => _DiscoverNewsFeedWidgetState();
}

class _DiscoverNewsFeedWidgetState extends State<DiscoverNewsFeedWidget> {
  static const _maxConsecutiveFromSameHost = 2;
  static const _maxTotalFromSameHost = 4;
  static const _staleAfter = Duration(hours: 1);

  String _bucket = 'all';
  List<FeedCard> _articles = const [];
  bool _initializing = true;
  bool _refreshing = false;
  DateTime? _lastRefresh;
  bool _backgroundRefreshQueued = false;

  static const _categories = <({String id, String label})>[
    (id: 'all', label: 'All'),
    (id: 'tech', label: 'Tech & AI'),
    (id: 'business', label: 'Business'),
    (id: 'science', label: 'Science'),
    (id: 'world', label: 'World'),
  ];

  @override
  void initState() {
    super.initState();
    _loadCacheFirst();
  }

  /// 1. Instant cache-first read (no spinner unless there is nothing cached).
  void _loadCacheFirst() {
    final cached = _articlesForBucket('all');
    if (mounted) {
      setState(() {
        _articles = _articlesForBucket(_bucket);
        _initializing = false;
      });
    }
    if (cached.isEmpty) {
      _refresh();
    } else {
      _scheduleBackgroundRefresh();
    }
  }

  void _scheduleBackgroundRefresh() {
    if (_backgroundRefreshQueued) return;
    _backgroundRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _backgroundRefreshQueued = false;
      final newest = _newestTimestamp;
      if (_lastRefresh == null ||
          (newest != null && DateTime.now().difference(newest) > _staleAfter)) {
        _refresh();
      }
    });
  }

  DateTime? get _newestTimestamp {
    DateTime? newest;
    for (final card in widget.service.allCachedCards()) {
      final t = card.pubDate ?? card.timestamp;
      if (newest == null || t.isAfter(newest)) newest = t;
    }
    return newest;
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await widget.service.refreshAll();
    if (!mounted) return;
    setState(() {
      _lastRefresh = DateTime.now();
      _articles = _articlesForBucket(_bucket);
      _refreshing = false;
    });
  }

  void _onBucketChanged(String bucket) {
    setState(() {
      _bucket = bucket;
      _articles = _articlesForBucket(bucket);
    });
    _scheduleBackgroundRefresh();
  }

  List<FeedCard> _articlesForBucket(String bucket) {
    final all = widget.service.allCachedCards().where((c) {
      final title = c.displayTitle;
      if (title == 'Untitled' || (c.url ?? '').isEmpty) return false;
      if (bucket == 'all') return true;
      return _matchesBucket(c.category, bucket);
    }).toList();
    all.sort((a, b) => (b.pubDate ?? b.timestamp).compareTo(a.pubDate ?? a.timestamp));
    return _diversify(all, limit: 24);
  }

  /// Publisher diversity: never let one publisher dominate the feed.
  List<FeedCard> _diversify(List<FeedCard> cards, {int limit = 24}) {
    final out = <FeedCard>[];
    final hostCounts = <String, int>{};
    final window = <String?>[];
    for (final card in cards) {
      final host = Uri.tryParse(card.url ?? '')?.host ?? card.displaySource;
      final total = hostCounts[host] ?? 0;
      if (total >= _maxTotalFromSameHost) continue;
      final consecutive = window.where((h) => h == host).length;
      if (consecutive >= _maxConsecutiveFromSameHost) continue;
      out.add(card);
      hostCounts[host] = total + 1;
      window.add(host);
      if (window.length > 2) window.removeAt(0);
      if (out.length >= limit) break;
    }
    return out;
  }

  bool _matchesBucket(String category, String bucket) {
    final lower = category.toLowerCase();
    switch (bucket) {
      case 'tech':
        for (final k in [
          'technology', 'techcrunch', 'verge', 'wired', 'ars', 'cnet',
          'ai', 'security', 'space', 'startup', 'gaming',
        ]) {
          if (lower.contains(k)) return true;
        }
        return lower.contains('code');
      case 'business':
        return ['business', 'bloomberg', 'forbes', 'finance', 'investopedia', 'startup']
            .any(lower.contains);
      case 'science':
        return ['science', 'nature', 'scientist', 'space', 'nasa', 'environment']
            .any(lower.contains);
      case 'world':
        return ['top stories', 'world', 'us news', 'politics', 'health', 'entertainment',
                'travel', 'environment', 'lifestyle']
            .any(lower.contains);
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: Color(0xFF38BDF8), size: 18),
              const SizedBox(width: 8),
              const Text(
                'Trending',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_refreshing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
                )
              else
                IconButton(
                  tooltip: 'Refresh feeds',
                  icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _refresh,
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final selected = cat.id == _bucket;
                return GestureDetector(
                  onTap: () => _onBucketChanged(cat.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF38BDF8) : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: selected ? Colors.transparent : Colors.white.withOpacity(0.12),
                      ),
                    ),
                    child: Text(
                      cat.label,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white70,
                        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          if (_initializing && _articles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF38BDF8)),
                ),
              ),
            )
          else if (_articles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No articles yet. Pull to refresh or wait for background sync.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                ),
              ),
            )
          else
            ..._buildCards(_articles),
        ],
      ),
    );
  }

  List<Widget> _buildCards(List<FeedCard> cards) {
    return [
      for (var i = 0; i < cards.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == cards.length - 1 ? 0 : 10),
          child: i == 0 && cards[i].imageUrl != null && cards[i].imageUrl!.isNotEmpty
              ? _HeroCard(card: cards[i], onTap: () => widget.onArticleSelected(cards[i].url ?? ''))
              : _CompactRow(card: cards[i], onTap: () => widget.onArticleSelected(cards[i].url ?? '')),
        ),
    ];
  }
}

class _HeroCard extends StatelessWidget {
  final FeedCard card;
  final VoidCallback onTap;

  const _HeroCard({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF243247),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                card.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF1B242D),
                  child: const Center(child: Icon(Icons.article, color: Color(0xFF94A3B8), size: 36)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(card.displaySource,
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text('•  ${_timeAgo(card.pubDate)}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
}

class _CompactRow extends StatelessWidget {
  final FeedCard card;
  final VoidCallback onTap;

  const _CompactRow({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = card.imageUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF243247),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(card.displaySource,
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 6),
                      Text('•  ${_timeAgo(card.pubDate)}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            if (image != null && image.isNotEmpty) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _timeAgo(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}