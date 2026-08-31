import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webfeed/webfeed.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/entities/entities.dart';
export '../../domain/entities/entities.dart';

class _AnalyticsEvent {
  final String type;
  final String cardId;
  final DateTime timestamp;
  _AnalyticsEvent({required this.type, required this.cardId, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class NewsFeedService {
  static const _tapsKey = 'news_category_taps';
  static const _cacheDuration = Duration(minutes: 30);
  static const _cardTtl = Duration(hours: 24);
  static const _analyticsFlushInterval = Duration(seconds: 30);
  static const _batchSize = 5;

  Database? _db;
  List<NewsCategory> _categories = [];
  String? _countryCode;
  final Map<String, List<FeedCard>> _cardCache = {};
  final Map<String, DateTime> _lastFetch = {};
  final Map<String, String> _etags = {};
  final Map<String, StreamController<List<FeedCard>>> _feedControllers = {};
  final List<_AnalyticsEvent> _pendingAnalytics = [];
  Timer? _analyticsTimer;
  List<NewsCategory> get categories => _categories;

  NewsFeedService() {
    _categories = List.from(_globalFeeds);
  }

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'makaw_feed.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS feed_cards (
            id TEXT PRIMARY KEY,
            card_type TEXT NOT NULL,
            category TEXT NOT NULL,
            title TEXT,
            url TEXT,
            summary TEXT,
            image_url TEXT,
            source TEXT,
            publisher TEXT,
            pub_date TEXT,
            data_json TEXT,
            fetched_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL,
            is_hidden INTEGER DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_fc_cat ON feed_cards(category)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_fc_exp ON feed_cards(expires_at)');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS feed_analytics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            card_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS feed_metadata (
            feed_url TEXT PRIMARY KEY,
            etag TEXT,
            last_fetched INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS feed_metadata (
              feed_url TEXT PRIMARY KEY,
              etag TEXT,
              last_fetched INTEGER NOT NULL
            )
          ''');
        }
      },
    );
    await _loadCardsFromDb();
    await _loadEtagsFromDb();
    await _deleteExpiredCards();
    _startAnalyticsTimer();
  }

  Future<void> _loadCardsFromDb() async {
    final db = _db;
    if (db == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query('feed_cards',
        where: 'expires_at > ? AND is_hidden = 0',
        whereArgs: [now],
        orderBy: 'fetched_at DESC');
    for (final row in rows) {
      final category = row['category'] as String;
      _cardCache.putIfAbsent(category, () => []);
      final card = _rowToCard(row);
      if (card != null) _cardCache[category]!.add(card);
    }
  }

  FeedCard? _rowToCard(Map<String, dynamic> row) {
    try {
      final dataJson = row['data_json'] as String?;
      final Map<String, dynamic> extraData =
          dataJson != null ? jsonDecode(dataJson) as Map<String, dynamic> : {};
      final data = <String, dynamic>{
        'title': row['title'],
        'url': row['url'],
        'summary': row['summary'],
        'imageUrl': row['image_url'],
        'source': row['source'],
        'publisher': row['publisher'],
        'pub_date': row['pub_date'],
        ...extraData,
      };
      return FeedCard(
        id: row['id'] as String,
        type: FeedCardType.values.firstWhere(
          (t) => t.name == row['card_type'],
          orElse: () => FeedCardType.articleCompact,
        ),
        category: row['category'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
        data: data,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _upsertCard(FeedCard card) async {
    final db = _db;
    if (db == null) return;
    final expiresAt = DateTime.now().add(_cardTtl).millisecondsSinceEpoch;
    final fetchedAt = DateTime.now().millisecondsSinceEpoch;
    await db.insert('feed_cards', {
      'id': card.id,
      'card_type': card.type.name,
      'category': card.category,
      'title': card.title,
      'url': card.url,
      'summary': card.summary,
      'image_url': card.imageUrl,
      'source': card.source,
      'publisher': card.publisher,
      'pub_date': card.pubDate?.toIso8601String(),
      'data_json': jsonEncode(card.data),
      'fetched_at': fetchedAt,
      'expires_at': expiresAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _loadEtagsFromDb() async {
    final db = _db;
    if (db == null) return;
    try {
      final rows = await db.query('feed_metadata');
      for (final row in rows) {
        final url = row['feed_url'] as String?;
        final etag = row['etag'] as String?;
        if (url != null && etag != null && etag.isNotEmpty) _etags[url] = etag;
      }
    } catch (_) {}
  }

  Future<String?> _storedEtag(String feedUrl) async {
    if (_etags.containsKey(feedUrl)) return _etags[feedUrl];
    final db = _db;
    if (db == null) return null;
    try {
      final rows = await db.query('feed_metadata',
          where: 'feed_url = ?', whereArgs: [feedUrl], limit: 1);
      final etag = rows.firstOrNull?['etag'] as String?;
      if (etag != null && etag.isNotEmpty) _etags[feedUrl] = etag;
      return etag;
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeEtag(String feedUrl, String etag) async {
    _etags[feedUrl] = etag;
    final db = _db;
    if (db == null) return;
    try {
      await db.insert('feed_metadata', {
        'feed_url': feedUrl,
        'etag': etag,
        'last_fetched': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  Future<void> _deleteExpiredCards() async {
    final db = _db;
    if (db == null) return;
    await db.delete('feed_cards',
        where: 'expires_at < ?', whereArgs: [DateTime.now().millisecondsSinceEpoch]);
  }

  void dispose() {
    _analyticsTimer?.cancel();
    for (final ctrl in _feedControllers.values) {
      ctrl.close();
    }
    _feedControllers.clear();
    _db?.close();
  }

  // ---- Location ----

  Future<void> detectLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      );
      final res = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}'),
        headers: {'User-Agent': 'Makaw/1.0'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final code = data['address']?['country_code']?.toString().toUpperCase();
        if (code != null && code.length == 2) _countryCode = code;
      }
    } catch (_) {}
  }

  void _addLocalCategories() {
    if (_countryCode == null) return;
    _categories.removeWhere((c) => c.name.startsWith('Local'));
    final local = _localFeeds[_countryCode];
    if (local != null) _categories.addAll(local);
  }

  Future<void> ensureLocationReady() async {
    await detectLocation();
    _categories = List.from(_globalFeeds);
    _addLocalCategories();
  }

  // ---- Taps ----

  Future<void> loadTaps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tapsKey);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        for (final cat in _categories) {
          cat.tapCount = data[cat.name] as int? ?? 0;
        }
      } catch (_) {}
    }
  }

  Future<void> _saveTaps() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {for (final cat in _categories) cat.name: cat.tapCount};
    await prefs.setString(_tapsKey, jsonEncode(data));
  }

  void recordTap(String categoryName) {
    for (final cat in _categories) {
      if (cat.name == categoryName) {
        cat.tapCount++;
        _saveTaps();
        return;
      }
    }
  }

  List<NewsCategory> getOrderedCategories() {
    final sorted = List<NewsCategory>.from(_categories);
    sorted.sort((a, b) => b.tapCount.compareTo(a.tapCount));
    return sorted;
  }

  // ---- Feed Card Streaming (SDUI) ----

  Stream<List<FeedCard>> watchFeed(String categoryName) {
    if (!_feedControllers.containsKey(categoryName)) {
      _feedControllers[categoryName] = StreamController<List<FeedCard>>.broadcast();
      final cached = _cardCache[categoryName];
      if (cached != null && cached.isNotEmpty) {
        _feedControllers[categoryName]!.add(List.from(cached));
      }
      _revalidateCategory(categoryName);
    }
    return _feedControllers[categoryName]!.stream;
  }

  List<FeedCard> cachedCards(String categoryName) => List.from(_cardCache[categoryName] ?? []);

  Stream<List<FeedCard>> watchAllFeeds() {
    final ctrl = StreamController<List<FeedCard>>.broadcast();
    final all = <FeedCard>[];
    for (final entry in _cardCache.entries) {
      all.addAll(entry.value);
    }
    all.sort((a, b) => (b.pubDate ?? b.timestamp).compareTo(a.pubDate ?? a.timestamp));
    ctrl.add(all);
    return ctrl.stream;
  }

  List<FeedCard> allCachedCards() {
    final all = <FeedCard>[];
    for (final entry in _cardCache.entries) {
      all.addAll(entry.value);
    }
    all.sort((a, b) => (b.pubDate ?? b.timestamp).compareTo(a.pubDate ?? a.timestamp));
    return all;
  }

  Future<void> _revalidateCategory(String categoryName) async {
    final last = _lastFetch[categoryName];
    if (last != null && DateTime.now().difference(last) < _cacheDuration) return;
    await refreshCategory(categoryName);
  }

  Future<void> refreshCategory(String categoryName) async {
    final cat = _categories.cast<NewsCategory?>().firstWhere(
      (c) => c?.name == categoryName,
      orElse: () => null,
    );
    if (cat == null) return;
    try {
      final headers = <String, String>{'User-Agent': 'MakawBrowser/1.0'};
      final etag = await _storedEtag(cat.feedUrl);
      if (etag != null) headers['If-None-Match'] = etag;
      final response = await http.get(Uri.parse(cat.feedUrl), headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode == 304) {
        _lastFetch[categoryName] = DateTime.now();
        return;
      }
      if (response.statusCode != 200) return;
      final newEtag = response.headers['etag'];
      if (newEtag != null && newEtag.isNotEmpty) {
        await _storeEtag(cat.feedUrl, newEtag);
      }
      final newCards = <FeedCard>[];
      final existingIds = _cardCache[categoryName]?.map((c) => c.id).toSet() ?? {};
      final now = DateTime.now();
      final rawItems = await Isolate.run(() => _parseFeedItems(response.body));
      for (final raw in rawItems) {
        final title = raw['title'] as String? ?? '';
        final link = raw['link'] as String? ?? '';
        if (title.isEmpty || link.isEmpty) continue;
        final cardId = FeedCard.generateId(link, categoryName, title);
        if (existingIds.contains(cardId)) continue;
        final data = <String, dynamic>{
          'title': title,
          'url': link,
          'summary': raw['description'],
          'imageUrl': raw['imageUrl'],
          'source': categoryName,
          'publisher': categoryName,
          'pub_date': raw['pubDate'],
        };
        final card = FeedCard(
          id: cardId,
          type: FeedCardType.articleCompact,
          category: categoryName,
          timestamp: now,
          data: data,
        );
        newCards.add(card);
        await _upsertCard(card);
      }
      if (newCards.isNotEmpty) {
        _cardCache.putIfAbsent(categoryName, () => []);
        _cardCache[categoryName]!.insertAll(0, newCards);
        _lastFetch[categoryName] = DateTime.now();
        _feedControllers[categoryName]?.add(List.from(_cardCache[categoryName]!));
      }
    } catch (_) {}
  }

  Future<void> refreshAll() async {
    _lastFetch.clear();
    final ordered = getOrderedCategories();
    for (int i = 0; i < ordered.length; i += _batchSize) {
      final batch = ordered.skip(i).take(_batchSize).toList();
      await Future.wait(batch.map((cat) => refreshCategory(cat.name)));
    }
  }

  Future<void> forceRefreshAll() async {
    _cardCache.clear();
    final db = _db;
    if (db != null) await db.delete('feed_cards');
    _lastFetch.clear();
    await refreshAll();
  }

  /// Parses an RSS/Atom XML body into primitive maps. Runs inside an isolate
  /// so large buffers never jank the UI; the result only contains sendable
  /// primitives (strings / nullable strings).
  static List<Map<String, Object?>> _parseFeedItems(String body) {
    final out = <Map<String, Object?>>[];
    try {
      final feed = RssFeed.parse(body);
      for (final item in feed.items ?? []) {
        String? imageUrl;
        if (item.media?.contents != null && item.media!.contents!.isNotEmpty) {
          imageUrl = item.media!.contents!.first.url;
        }
        if (imageUrl == null && item.media?.thumbnails != null && item.media!.thumbnails!.isNotEmpty) {
          imageUrl = item.media!.thumbnails!.first.url;
        }
        if (imageUrl == null && item.enclosure != null) {
          final enc = item.enclosure!;
          if (enc.url != null && (enc.type == null || enc.type!.startsWith('image/'))) {
            imageUrl = enc.url;
          }
        }
        if (imageUrl == null && item.description != null) {
          for (final pattern in [
            RegExp(r'<img[^>]+src="([^"]+)"'),
            RegExp(r"<img[^>]+src='([^']+)'"),
          ]) {
            final m = pattern.firstMatch(item.description!);
            if (m != null) {
              imageUrl = m.group(1);
              if (imageUrl!.startsWith('//')) imageUrl = 'https:$imageUrl';
              break;
            }
          }
        }
        out.add({
          'title': item.title?.trim() ?? '',
          'link': item.link ?? '',
          'description': item.description?.trim(),
          'pubDate': item.pubDate?.toIso8601String(),
          'imageUrl': imageUrl,
        });
      }
    } catch (_) {}
    return out;
  }

  // ---- Legacy API (backwards compat) ----

  Future<List<NewsItem>> fetch(String categoryName) async {
    final cat = _categories.cast<NewsCategory?>().firstWhere(
      (c) => c?.name == categoryName,
      orElse: () => null,
    );
    if (cat == null) return [];
    final last = _lastFetch[categoryName];
    if (last != null && DateTime.now().difference(last) < _cacheDuration) {
      return _cardCache[categoryName]
              ?.map((c) => NewsItem(
                    title: c.displayTitle,
                    url: c.url ?? '',
                    summary: c.summary,
                    imageUrl: c.imageUrl,
                    pubDate: c.pubDate,
                    source: c.displaySource,
                  ))
              .toList() ??
          [];
    }
    try {
      final response = await http.get(Uri.parse(cat.feedUrl));
      if (response.statusCode != 200) return [];
      final feed = RssFeed.parse(response.body);
      final items = feed.items?.map((item) {
            String? imageUrl;
            if (item.media?.contents != null && item.media!.contents!.isNotEmpty) {
              imageUrl = item.media!.contents!.first.url;
            }
            if (imageUrl == null && item.media?.thumbnails != null && item.media!.thumbnails!.isNotEmpty) {
              imageUrl = item.media!.thumbnails!.first.url;
            }
            if (imageUrl == null && item.enclosure != null) {
              final enc = item.enclosure!;
              if (enc.url != null && (enc.type == null || enc.type!.startsWith('image/'))) {
                imageUrl = enc.url;
              }
            }
            if (imageUrl == null && item.description != null) {
              final imgMatch = RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(item.description!);
              if (imgMatch != null) {
                imageUrl = imgMatch.group(1);
                if (imageUrl!.startsWith('//')) imageUrl = 'https:$imageUrl';
              }
              if (imageUrl == null) {
                final imgMatch2 = RegExp(r"<img[^>]+src='([^']+)'").firstMatch(item.description!);
                if (imgMatch2 != null) {
                  imageUrl = imgMatch2.group(1);
                  if (imageUrl!.startsWith('//')) imageUrl = 'https:$imageUrl';
                }
              }
            }
            return NewsItem(
              title: item.title?.trim() ?? 'Untitled',
              url: item.link ?? '',
              summary: item.description?.trim(),
              imageUrl: imageUrl,
              pubDate: item.pubDate,
              source: categoryName,
            );
          }).toList() ?? [];
      _lastFetch[categoryName] = DateTime.now();
      return items;
    } catch (_) {
      return [];
    }
  }

  List<NewsItem>? cachedItems(String categoryName) {
    if (!_cardCache.containsKey(categoryName)) return null;
    return _cardCache[categoryName]
            ?.map((c) => NewsItem(
                  title: c.displayTitle,
                  url: c.url ?? '',
                  summary: c.summary,
                  imageUrl: c.imageUrl,
                  pubDate: c.pubDate,
                  source: c.displaySource,
                ))
            .toList() ??
        [];
  }

  // ---- Hide / Block ----

  Future<void> hideCard(String cardId) async {
    final db = _db;
    if (db != null) {
      await db.update('feed_cards', {'is_hidden': 1}, where: 'id = ?', whereArgs: [cardId]);
    }
    for (final entry in _cardCache.entries) {
      entry.value.removeWhere((c) => c.id == cardId);
      _feedControllers[entry.key]?.add(List.from(entry.value));
    }
  }

  // ---- Analytics ----

  void recordImpression(String cardId) {
    _pendingAnalytics.add(_AnalyticsEvent(type: 'impression', cardId: cardId));
  }

  void recordClick(String cardId) {
    _pendingAnalytics.add(_AnalyticsEvent(type: 'click', cardId: cardId));
  }

  void _startAnalyticsTimer() {
    _analyticsTimer = Timer.periodic(_analyticsFlushInterval, (_) => _flushAnalytics());
  }

  Future<void> _flushAnalytics() async {
    if (_pendingAnalytics.isEmpty) return;
    final batch = List<_AnalyticsEvent>.from(_pendingAnalytics);
    _pendingAnalytics.clear();
    final db = _db;
    if (db == null) return;
    for (final event in batch) {
      await db.insert('feed_analytics', {
        'type': event.type,
        'card_id': event.cardId,
        'timestamp': event.timestamp.millisecondsSinceEpoch,
      });
    }
  }

  // ---- Feed Definitions ----

  static final List<NewsCategory> _globalFeeds = [
    NewsCategory(name: 'Top Stories', feedUrl: 'https://feeds.bbci.co.uk/news/rss.xml', icon: 'newspaper'),
    NewsCategory(name: 'World', feedUrl: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml', icon: 'language'),
    NewsCategory(name: 'US News', feedUrl: 'https://feeds.npr.org/1001/rss.xml', icon: 'newspaper'),
    NewsCategory(name: 'Technology', feedUrl: 'https://feeds.bbci.co.uk/news/technology/rss.xml', icon: 'desktop'),
    NewsCategory(name: 'TechCrunch', feedUrl: 'https://techcrunch.com/feed/', icon: 'code'),
    NewsCategory(name: 'The Verge', feedUrl: 'https://www.theverge.com/rss/index.xml', icon: 'code'),
    NewsCategory(name: 'Wired', feedUrl: 'https://www.wired.com/feed/rss', icon: 'code'),
    NewsCategory(name: 'Ars Technica', feedUrl: 'https://feeds.arstechnica.com/arstechnica/index', icon: 'code'),
    NewsCategory(name: 'CNET', feedUrl: 'https://www.cnet.com/rss/all/', icon: 'desktop'),
    NewsCategory(name: 'Science', feedUrl: 'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml', icon: 'science'),
    NewsCategory(name: 'Nature', feedUrl: 'https://www.nature.com/nature.rss', icon: 'science'),
    NewsCategory(name: 'New Scientist', feedUrl: 'https://www.newscientist.com/feed/home', icon: 'science'),
    NewsCategory(name: 'Business', feedUrl: 'https://feeds.bbci.co.uk/news/business/rss.xml', icon: 'business'),
    NewsCategory(name: 'Bloomberg', feedUrl: 'https://www.bloomberg.com/feed/podcast/etf-report.xml', icon: 'business'),
    NewsCategory(name: 'Forbes', feedUrl: 'https://www.forbes.com/innovation/feed/', icon: 'business'),
    NewsCategory(name: 'Sports', feedUrl: 'https://feeds.bbci.co.uk/sport/rss.xml', icon: 'sports_soccer'),
    NewsCategory(name: 'ESPN', feedUrl: 'https://www.espn.com/espn/rss/news', icon: 'sports_soccer'),
    NewsCategory(name: 'Sky Sports', feedUrl: 'https://www.skysports.com/rss/12040', icon: 'sports_soccer'),
    NewsCategory(name: 'Entertainment', feedUrl: 'https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml', icon: 'movie'),
    NewsCategory(name: 'Variety', feedUrl: 'https://variety.com/feed/', icon: 'movie'),
    NewsCategory(name: 'Hollywood Reporter', feedUrl: 'https://www.hollywoodreporter.com/feed/', icon: 'movie'),
    NewsCategory(name: 'Gaming', feedUrl: 'https://www.ign.com/rss/articles/feed', icon: 'sports_esports'),
    NewsCategory(name: 'Polygon', feedUrl: 'https://www.polygon.com/rss/index.xml', icon: 'sports_esports'),
    NewsCategory(name: 'Health', feedUrl: 'https://www.who.int/rss-feeds/news-english.xml', icon: 'local_hospital'),
    NewsCategory(name: 'Politics', feedUrl: 'https://www.politico.com/rss/politicopicks.xml', icon: 'account_balance'),
    NewsCategory(name: 'AI & ML', feedUrl: 'https://blog.google/technology/ai/rss', icon: 'smart_toy'),
    NewsCategory(name: 'Security', feedUrl: 'https://nakedsecurity.sophos.com/feed/', icon: 'security'),
    NewsCategory(name: 'Space', feedUrl: 'https://www.nasa.gov/rss/dyn/breaking_news.rss', icon: 'rocket_launch'),
    NewsCategory(name: 'Environment', feedUrl: 'https://www.theguardian.com/environment/rss', icon: 'eco'),
    NewsCategory(name: 'Lifestyle', feedUrl: 'https://www.apartmenttherapy.com/main.rss', icon: 'spa'),
    NewsCategory(name: 'Photography', feedUrl: 'https://www.dpreview.com/feeds/news', icon: 'camera_alt'),
    NewsCategory(name: 'Startups', feedUrl: 'https://www.inc.com/rss/startups.xml', icon: 'rocket'),
    NewsCategory(name: 'Education', feedUrl: 'https://www.edweek.org/feed/rss', icon: 'school'),
    NewsCategory(name: 'Finance', feedUrl: 'https://www.investopedia.com/feedbuilder/feed/getfeed?feedName=rss_headlines', icon: 'account_balance'),
    NewsCategory(name: 'Travel', feedUrl: 'https://www.lonelyplanet.com/news/feed/atom', icon: 'flight'),
    NewsCategory(name: 'Food', feedUrl: 'https://www.seriouseats.com/feed.xml', icon: 'restaurant'),
    NewsCategory(name: 'Music', feedUrl: 'https://www.billboard.com/feed/', icon: 'music_note'),
    NewsCategory(name: 'Books', feedUrl: 'https://www.goodreads.com/blog/feed', icon: 'menu_book'),
    NewsCategory(name: 'Automotive', feedUrl: 'https://www.motor1.com/rss/news/', icon: 'directions_car'),
  ];

  static final Map<String, List<NewsCategory>> _localFeeds = {
    'US': [
      NewsCategory(name: 'US News', feedUrl: 'https://feeds.npr.org/1001/rss.xml', icon: 'newspaper'),
      NewsCategory(name: 'Local US', feedUrl: 'https://rss.nytimes.com/services/xml/rss/nyt/US.xml', icon: 'language'),
    ],
    'GB': [
      NewsCategory(name: 'UK News', feedUrl: 'https://feeds.bbci.co.uk/news/uk/rss.xml', icon: 'newspaper'),
      NewsCategory(name: 'Local UK', feedUrl: 'https://www.theguardian.com/uk/rss', icon: 'language'),
    ],
    'CA': [
      NewsCategory(name: 'Canada News', feedUrl: 'https://www.cbc.ca/cmlink/rss-canada', icon: 'newspaper'),
      NewsCategory(name: 'Local Canada', feedUrl: 'https://www.theglobeandmail.com/arc/outboundfeeds/rss/', icon: 'language'),
    ],
    'AU': [
      NewsCategory(name: 'Australia News', feedUrl: 'https://www.abc.net.au/news/feed/51120/rss.xml', icon: 'newspaper'),
      NewsCategory(name: 'Local AU', feedUrl: 'https://www.smh.com.au/rss/feed.xml', icon: 'language'),
    ],
    'IN': [
      NewsCategory(name: 'India News', feedUrl: 'https://timesofindia.indiatimes.com/rssfeeds/-2128936835.cms', icon: 'newspaper'),
      NewsCategory(name: 'Local India', feedUrl: 'https://www.thehindu.com/feeder/default.rss', icon: 'language'),
    ],
    'NG': [
      NewsCategory(name: 'Nigeria News', feedUrl: 'https://punchng.com/feed/', icon: 'newspaper'),
      NewsCategory(name: 'Local NG', feedUrl: 'https://www.vanguardngr.com/feed/', icon: 'language'),
    ],
    'ZA': [
      NewsCategory(name: 'South Africa News', feedUrl: 'https://www.news24.com/feeds/all-news.xml', icon: 'newspaper'),
      NewsCategory(name: 'Local ZA', feedUrl: 'https://www.timeslive.co.za/feed/', icon: 'language'),
    ],
    'DE': [
      NewsCategory(name: 'Germany News', feedUrl: 'https://www.spiegel.de/schlagzeilen/tops/index.rss', icon: 'newspaper'),
      NewsCategory(name: 'Local DE', feedUrl: 'https://rss.dw.com/rdf/rss-en-all', icon: 'language'),
    ],
    'FR': [
      NewsCategory(name: 'France News', feedUrl: 'https://www.lemonde.fr/rss/une.xml', icon: 'newspaper'),
      NewsCategory(name: 'Local FR', feedUrl: 'https://www.france24.com/en/rss', icon: 'language'),
    ],
    'JP': [
      NewsCategory(name: 'Japan News', feedUrl: 'https://www3.nhk.or.jp/rss/news/cat0.xml', icon: 'newspaper'),
      NewsCategory(name: 'Local JP', feedUrl: 'https://feeds.japantimes.co.jp/en/news', icon: 'language'),
    ],
    'BR': [
      NewsCategory(name: 'Brazil News', feedUrl: 'https://www.bbc.com/portuguese/topics/cdl8ykj8rally/index.xml', icon: 'newspaper'),
      NewsCategory(name: 'Local BR', feedUrl: 'https://www1.folha.uol.com.br/feed/rss.xml', icon: 'language'),
    ],
    'KE': [
      NewsCategory(name: 'Kenya News', feedUrl: 'https://www.nation.co.ke/feed/', icon: 'newspaper'),
      NewsCategory(name: 'Local KE', feedUrl: 'https://www.standardmedia.co.ke/rss/', icon: 'language'),
    ],
  };
}
