import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/browser/domain/entities/browser_tab.dart';
import 'package:makaw/features/browser/domain/entities/media_item.dart';
import 'package:makaw/features/browser/domain/entities/view_mode.dart';

void main() {
  group('BrowserTab', () {
    test('creates with defaults', () {
      final tab = BrowserTab(id: 1, url: 'https://example.com');
      expect(tab.title, 'New Tab');
      expect(tab.incognito, false);
    });

    test('copyWith updates fields', () {
      final tab = BrowserTab(id: 1, url: 'https://example.com');
      final copy = tab.copyWith(title: 'Updated', url: 'https://other.com');
      expect(copy.id, 1);
      expect(copy.title, 'Updated');
      expect(copy.url, 'https://other.com');
    });

    test('equality', () {
      final a = BrowserTab(id: 1, url: 'https://a.com');
      final b = BrowserTab(id: 1, url: 'https://a.com');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality', () {
      final a = BrowserTab(id: 1, url: 'https://a.com');
      final b = BrowserTab(id: 2, url: 'https://b.com');
      expect(a, isNot(b));
    });

    test('toJson / fromJson roundtrip', () {
      final tab = BrowserTab(id: 1, url: 'https://example.com', title: 'Test', incognito: true);
      final json = tab.toJson();
      final restored = BrowserTab.fromJson(json);
      expect(restored, tab);
    });

    test('toString', () {
      final tab = BrowserTab(id: 1, url: 'https://example.com');
      expect(tab.toString(), contains('BrowserTab'));
    });
  });

  group('MediaItem', () {
    test('creates with defaults', () {
      final item = MediaItem(url: 'https://example.com/video.mp4', type: 'video');
      expect(item.title, '');
      expect(item.formats, isEmpty);
    });

    test('copyWith', () {
      final item = MediaItem(url: 'https://example.com/video.mp4', type: 'video');
      final copy = item.copyWith(title: 'My Video');
      expect(copy.title, 'My Video');
      expect(copy.url, item.url);
    });

    test('toJson / fromJson roundtrip with formats', () {
      final format = MediaFormat(label: '1080p', url: 'https://example.com/1080.mp4', height: 1080);
      final item = MediaItem(
        url: 'https://example.com/video.mp4',
        type: 'video',
        title: 'Test',
        formats: [format],
      );
      final json = item.toJson();
      final restored = MediaItem.fromJson(json);
      expect(restored.url, item.url);
      expect(restored.formats.length, 1);
      expect(restored.formats.first.label, '1080p');
    });
  });

  group('ViewMode', () {
    test('has expected values', () {
      expect(ViewMode.values.length, 4);
      expect(ViewMode.home, isA<ViewMode>());
    });
  });

  group('MediaFormat', () {
    test('equality', () {
      final a = MediaFormat(label: 'HD', url: 'https://example.com/hd.mp4');
      final b = MediaFormat(label: 'HD', url: 'https://example.com/hd.mp4');
      expect(a, b);
    });

    test('copyWith', () {
      final f = MediaFormat(label: 'SD', url: 'https://example.com/sd.mp4');
      final copy = f.copyWith(height: 480, bitrate: 1000);
      expect(copy.height, 480);
      expect(copy.bitrate, 1000);
    });

    test('toJson / fromJson roundtrip', () {
      final f = MediaFormat(label: '4K', url: 'https://example.com/4k.mp4', mimeType: 'video/mp4', height: 2160, bitrate: 15000);
      final json = f.toJson();
      final restored = MediaFormat.fromJson(json);
      expect(restored.label, f.label);
      expect(restored.height, 2160);
    });
  });
}
