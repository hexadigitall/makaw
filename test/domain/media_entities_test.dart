import 'package:flutter_test/flutter_test.dart';
import 'package:makaw_mobile/features/media/domain/entities/image_file_info.dart';
import 'package:makaw_mobile/features/media/domain/entities/video_file_info.dart';

void main() {
  group('ImageFileInfo', () {
    final img = ImageFileInfo(
      id: 1,
      filePath: '/storage/emulated/0/DCIM/photo.jpg',
      fileName: 'photo.jpg',
      folder: 'DCIM',
      dateTime: DateTime(2026, 6, 1),
      fileSize: 500000,
    );

    test('creates correctly', () {
      expect(img.fileName, 'photo.jpg');
      expect(img.fileSize, 500000);
    });

    test('copyWith', () {
      final copy = img.copyWith(folder: 'Screenshots');
      expect(copy.folder, 'Screenshots');
      expect(copy.id, 1);
    });

    test('equality', () {
      final a = ImageFileInfo(id: 1, filePath: '/a.jpg', fileName: 'a.jpg', folder: '/', fileSize: 100);
      final b = ImageFileInfo(id: 1, filePath: '/a.jpg', fileName: 'a.jpg', folder: '/', fileSize: 100);
      expect(a, b);
    });

    test('toJson / fromJson roundtrip', () {
      final json = img.toJson();
      final restored = ImageFileInfo.fromJson(json);
      expect(restored, img);
    });

    test('fromJson handles null dateTime', () {
      final json = img.toJson()..remove('dateTime');
      final restored = ImageFileInfo.fromJson(json);
      expect(restored.dateTime, isNull);
    });
  });

  group('VideoFileInfo', () {
    final vid = VideoFileInfo(
      id: 1,
      filePath: '/storage/emulated/0/Movies/clip.mp4',
      fileName: 'clip.mp4',
      folder: 'Movies',
      dateTime: DateTime(2026, 5, 15),
      fileSize: 10000000,
    );

    test('creates correctly', () {
      expect(vid.fileName, 'clip.mp4');
      expect(vid.folder, 'Movies');
    });

    test('copyWith', () {
      final copy = vid.copyWith(fileSize: 20000000);
      expect(copy.fileSize, 20000000);
    });

    test('equality', () {
      final a = VideoFileInfo(id: 1, filePath: '/a.mp4', fileName: 'a.mp4', folder: '/', fileSize: 100);
      final b = VideoFileInfo(id: 1, filePath: '/a.mp4', fileName: 'a.mp4', folder: '/', fileSize: 100);
      expect(a, b);
    });

    test('toJson / fromJson roundtrip', () {
      final json = vid.toJson();
      final restored = VideoFileInfo.fromJson(json);
      expect(restored, vid);
    });

    test('fromJson handles null dateTime', () {
      final json = vid.toJson()..remove('dateTime');
      final restored = VideoFileInfo.fromJson(json);
      expect(restored.dateTime, isNull);
    });
  });
}
