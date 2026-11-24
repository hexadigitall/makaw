import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/browser/domain/entities/browser_tab.dart';
import 'package:makaw/features/browser/presentation/pages/tab_tray_page.dart';
import 'package:makaw/features/browser/presentation/providers/download_service.dart';

void main() {
  group('DownloadService duplicate checking and unique naming', () {
    late Directory tempDir;
    late DownloadService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('makaw_dl_test_');
      service = DownloadService(
        dio: Dio(),
        getDownloadDir: () => tempDir.path,
        showNotification: (_) {},
      );
    });

    tearDown(() {
      service.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('resolveFilename extracts and sanitizes filename with extension', () {
      final name1 = service.resolveFilename('https://example.com/files/report.pdf');
      expect(name1, 'report.pdf');

      final name2 = service.resolveFilename('https://example.com/stream/video?token=123', filename: 'clip');
      expect(name2, 'clip.bin');
    });

    test('isDuplicate detects files existing on disk in download directory', () {
      final filePath = '${tempDir.path}${Platform.pathSeparator}sample.pdf';
      File(filePath).writeAsStringSync('dummy content');

      expect(service.isDuplicate('https://example.com/sample.pdf'), isTrue);
      expect(service.isDuplicate('https://example.com/other.pdf'), isFalse);
    });

    test('isDuplicate detects queued/active download items', () async {
      await service.enqueue('https://example.com/audio.mp3', filename: 'song.mp3');

      expect(service.isDuplicate('https://example.com/audio.mp3'), isTrue);
      expect(service.isDuplicate('https://example.com/new.mp3', filename: 'song.mp3'), isTrue);
      expect(service.isDuplicate('https://example.com/different.mp3'), isFalse);
    });

    test('getUniqueFilename generates non-colliding names', () {
      final filePath = '${tempDir.path}${Platform.pathSeparator}doc.txt';
      File(filePath).writeAsStringSync('first');

      final unique1 = service.getUniqueFilename('doc.txt');
      expect(unique1, 'doc (1).txt');

      final filePath2 = '${tempDir.path}${Platform.pathSeparator}doc (1).txt';
      File(filePath2).writeAsStringSync('second');

      final unique2 = service.getUniqueFilename('doc.txt');
      expect(unique2, 'doc (2).txt');
    });
  });

  group('TabTrayPage last incognito tab close', () {
    testWidgets('closing last incognito tab switches _showIncognito to false without error', (tester) async {
      final regularTab = BrowserTab(id: 1, url: 'https://example.com', title: 'Example', incognito: false);
      final incognitoTab = BrowserTab(id: 2, url: 'https://secret.com', title: 'Secret', incognito: true);

      int closedId = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: TabTrayPage(
            tabs: [regularTab, incognitoTab],
            activeTabId: 2,
            snapshots: const {},
            initialIsIncognito: true,
            onSwitchTab: (_) {},
            onCloseTab: (id) => closedId = id,
            onCreateTab: () {},
          ),
        ),
      );

      // Verify we start in incognito mode displaying the incognito tab
      expect(find.text('Secret'), findsOneWidget);

      // Find the close button for the tab and tap it
      final closeButton = find.byTooltip('Close tab');
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(closedId, 2);

      // After closing the last incognito tab, the tray should have automatically switched back
      // to normal tabs without freezing or error!
      expect(find.text('Example'), findsOneWidget);
    });
  });
}
