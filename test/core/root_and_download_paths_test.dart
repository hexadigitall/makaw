import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/core/platform/platform_paths.dart';
import 'package:makaw/core/platform/session_paths.dart';
import 'package:makaw/core/services/root_service.dart';

void main() {
  group('Default device download directory without Makaw/MakawDownloads subfolders', () {
    test('defaultDownloadsHint points to default Download folder and not Makaw subfolder', () {
      final hint = PlatformPaths.defaultDownloadsHint();
      expect(hint.contains('MakawDownloads'), isFalse);
      expect(hint.endsWith('/Makaw'), isFalse);
      expect(hint.endsWith(r'\Makaw'), isFalse);
      if (Platform.isAndroid) {
        expect(hint, '/storage/emulated/0/Download');
      }
    });

    test('SessionPaths.downloadsDir resolves without MakawDownloads subfolder', () async {
      final dir = await SessionPaths.downloadsDir();
      expect(dir.contains('MakawDownloads'), isFalse);
      expect(dir.endsWith('/Makaw'), isFalse);
      expect(dir.endsWith(r'\Makaw'), isFalse);
      if (Platform.isAndroid) {
        expect(dir.startsWith('/storage/emulated/0/Download') || dir.startsWith('/sdcard/Download'), isTrue);
      }
    });
  });

  group('RootService', () {
    test('RootService instance is singleton', () {
      expect(RootService.instance, isNotNull);
      expect(identical(RootService.instance, RootService.instance), isTrue);
    });

    test('isRootAvailable executes without error', () async {
      final available = await RootService.instance.isRootAvailable();
      expect(available, isA<bool>());
    });

    test('isRootGranted executes without error', () async {
      final granted = await RootService.instance.isRootGranted();
      expect(granted, isA<bool>());
    });
  });
}
