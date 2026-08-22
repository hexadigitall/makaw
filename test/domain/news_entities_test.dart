import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/news/domain/entities/news_item.dart';
import 'package:makaw/features/news/domain/entities/news_category.dart';
import 'package:makaw/features/news/domain/entities/feed_card.dart';

void main() {
  group('NewsItem', () {
    final item = NewsItem(
      title: 'Breaking News',
      url: 'https://example.com/news/1',
      summary: 'Something happened',
      imageUrl: 'https://example.com/img.jpg',
      pubDate: DateTime(2026, 7, 20),
      source: 'BBC',
    );

    test('creates correctly', () {
      expect(item.title, 'Breaking News');
      expect(item.source, 'BBC');
    });

    test('copyWith', () {
      final copy = item.copyWith(title: 'Updated News');
      expect(copy.title, 'Updated News');
      expect(copy.url, item.url);
    });

    test('equality', () {
      final a = NewsItem(title: 'X', url: 'https://x.com', source: 'X');
      final b = NewsItem(title: 'X', url: 'https://x.com', source: 'X');
      expect(a, b);
    });

    test('toJson / fromJson roundtrip', () {
      final json = item.toJson();
      final restored = NewsItem.fromJson(json);
      expect(restored.title, item.title);
      expect(restored.source, item.source);
      expect(restored.pubDate, item.pubDate);
    });

    test('fromJson handles null pubDate', () {
      final json = item.toJson()..remove('pubDate');
      final restored = NewsItem.fromJson(json);
      expect(restored.pubDate, isNull);
    });
  });

  group('FeedCard', () {
    test('creates correctly', () {
      final card = FeedCard(
        id: '1',
        type: FeedCardType.articleHero,
        category: 'tech',
        timestamp: DateTime(2026, 7, 21),
        data: {'title': 'Test Article', 'source': 'TechCrunch'},
      );
      expect(card.id, '1');
      expect(card.displayTitle, 'Test Article');
      expect(card.displaySource, 'TechCrunch');
    });

    test('displayTitle falls back to Untitled', () {
      final card = FeedCard(id: '2', type: FeedCardType.articleCompact, category: 'news', timestamp: DateTime(2026, 7, 21), data: {});
      expect(card.displayTitle, 'Untitled');
    });

    test('displaySource falls back to category', () {
      final card = FeedCard(id: '3', type: FeedCardType.topicCarousel, category: 'sports', timestamp: DateTime(2026, 7, 21), data: {});
      expect(card.displaySource, 'sports');
    });

    test('toJson / fromJson roundtrip', () {
      final card = FeedCard(id: '4', type: FeedCardType.adCard, category: 'ads', timestamp: DateTime(2026, 7, 21), data: {'url': 'https://ad.com'});
      final json = card.toJson();
      final restored = FeedCard.fromJson(json);
      expect(restored.id, card.id);
      expect(restored.type, card.type);
      expect(restored.url, card.url);
    });

    test('fromJson defaults to articleCompact for unknown type', () {
      final json = {'id': '5', 'type': 'unknownType', 'category': 'test', 'timestamp': '2026-07-21T00:00:00.000', 'data': {}};
      final restored = FeedCard.fromJson(json);
      expect(restored.type, FeedCardType.articleCompact);
    });

    test('fromJson handles null data map', () {
      final json = {'id': '6', 'type': 'updateBanner', 'category': 'updates', 'timestamp': '2026-07-21T00:00:00.000'};
      final restored = FeedCard.fromJson(json);
      expect(restored.data, {});
    });

    test('generateId produces consistent IDs', () {
      final id1 = FeedCard.generateId('https://a.com', 'src1', 'Title');
      final id2 = FeedCard.generateId('https://a.com', 'src1', 'Title');
      expect(id1, id2);
    });

    test('copyWith returns equivalent card', () {
      final card = FeedCard(id: '7', type: FeedCardType.articleHero, category: 'tech', timestamp: DateTime(2026, 7, 21), data: {});
      final copy = card.copyWith();
      expect(copy.id, card.id);
      expect(copy.type, card.type);
    });

    test('pubDate parsed from data', () {
      final card = FeedCard(id: '8', type: FeedCardType.articleCompact, category: 'news', timestamp: DateTime(2026, 7, 21), data: {'pub_date': '2026-07-20T10:00:00.000'});
      expect(card.pubDate, DateTime(2026, 7, 20, 10));
    });

    test('pubDate returns null when missing', () {
      final card = FeedCard(id: '9', type: FeedCardType.articleCompact, category: 'news', timestamp: DateTime(2026, 7, 21), data: {});
      expect(card.pubDate, isNull);
    });
  });

  group('NewsCategory', () {
    final cat = NewsCategory(name: 'Technology', feedUrl: 'https://techcrunch.com/feed/', icon: 'code');

    test('creates correctly', () {
      expect(cat.name, 'Technology');
      expect(cat.tapCount, 0);
    });

    test('tapCount is mutable', () {
      cat.tapCount++;
      expect(cat.tapCount, 1);
    });

    test('copyWith', () {
      final copy = cat.copyWith(name: 'Tech');
      expect(copy.name, 'Tech');
      expect(copy.feedUrl, cat.feedUrl);
    });

    test('equality by name', () {
      final a = NewsCategory(name: 'Tech', feedUrl: 'https://a.com', icon: 'code');
      final b = NewsCategory(name: 'Tech', feedUrl: 'https://b.com', icon: 'code');
      expect(a, b);
    });

    test('toJson / fromJson roundtrip', () {
      cat.tapCount = 5;
      final json = cat.toJson();
      final restored = NewsCategory.fromJson(json);
      expect(restored.name, 'Technology');
      expect(restored.tapCount, 5);
    });
  });
}
