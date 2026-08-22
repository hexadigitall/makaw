import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/browser/domain/entities/browser_tab.dart';
import 'package:makaw/features/browser/domain/repositories/browser_repository.dart';
import 'package:makaw/features/documents/domain/repositories/document_repository.dart';
import 'package:makaw/features/media/domain/repositories/image_repository.dart';
import 'package:makaw/features/media/domain/repositories/video_repository.dart';
import 'package:makaw/features/music/domain/repositories/music_repository.dart';
import 'package:makaw/features/news/domain/repositories/news_repository.dart';
import 'package:mocktail/mocktail.dart';

// Mock implementations for repository interface contract tests
class MockBrowserRepository extends Mock implements BrowserRepository {}
class MockDocumentRepository extends Mock implements DocumentRepository {}
class MockImageRepository extends Mock implements ImageRepository {}
class MockVideoRepository extends Mock implements VideoRepository {}
class MockMusicRepository extends Mock implements MusicRepository {}
class MockNewsRepository extends Mock implements NewsRepository {}

void main() {
  group('BrowserRepository contract', () {
    test('can be mocked and stubbed', () {
      final repo = MockBrowserRepository();
      when(() => repo.getTabs()).thenReturn([]);
      when(() => repo.getActiveTab()).thenReturn(null);
      expect(repo.getTabs(), isEmpty);
      expect(repo.getActiveTab(), isNull);
    });

    test('createTab returns a tab', () {
      final repo = MockBrowserRepository();
      final tab = BrowserTab(id: 1, url: 'https://example.com');
      when(() => repo.createTab(url: any(named: 'url'), incognito: any(named: 'incognito'))).thenReturn(tab);
      final result = repo.createTab(url: 'https://example.com');
      expect(result.id, 1);
      expect(result.url, 'https://example.com');
    });
  });

  group('DocumentRepository contract', () {
    test('can be mocked', () {
      final repo = MockDocumentRepository();
      when(() => repo.getAllDocuments()).thenReturn([]);
      when(() => repo.isScanning).thenReturn(false);
      expect(repo.getAllDocuments(), isEmpty);
      expect(repo.isScanning, false);
    });
  });

  group('ImageRepository contract', () {
    test('can be mocked', () {
      final repo = MockImageRepository();
      when(() => repo.getAllImages()).thenReturn([]);
      expect(repo.getAllImages(), isEmpty);
    });
  });

  group('VideoRepository contract', () {
    test('can be mocked', () {
      final repo = MockVideoRepository();
      when(() => repo.getAllVideos()).thenReturn([]);
      when(() => repo.resumePosition(any())).thenReturn(0);
      expect(repo.getAllVideos(), isEmpty);
      expect(repo.resumePosition('/test.mp4'), 0);
    });
  });

  group('MusicRepository contract', () {
    test('can be mocked', () {
      final repo = MockMusicRepository();
      when(() => repo.getAllSongs()).thenReturn([]);
      when(() => repo.getAlbums()).thenReturn({});
      expect(repo.getAllSongs(), isEmpty);
      expect(repo.getAlbums(), isEmpty);
    });
  });

  group('NewsRepository contract', () {
    test('can be mocked', () {
      final repo = MockNewsRepository();
      when(() => repo.getCategories()).thenReturn([]);
      expect(repo.getCategories(), isEmpty);
    });
  });
}
