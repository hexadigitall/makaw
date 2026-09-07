import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/documents/domain/entities/document_file_info.dart';

void main() {
  group('DocumentFileInfo', () {
    final info = DocumentFileInfo(
      id: 1,
      filePath: '/storage/emulated/0/Documents/report.pdf',
      fileName: 'report.pdf',
      folder: 'Documents',
      dateTime: DateTime(2026, 1, 15),
      fileSize: 102400,
      category: 'pdf',
    );

    test('creates correctly', () {
      expect(info.fileName, 'report.pdf');
      expect(info.category, 'pdf');
    });

    test('copyWith', () {
      final copy = info.copyWith(fileName: 'report_v2.pdf', fileSize: 204800);
      expect(copy.fileName, 'report_v2.pdf');
      expect(copy.fileSize, 204800);
      expect(copy.id, 1);
    });

    test('equality', () {
      final a = DocumentFileInfo(id: 1, filePath: '/a.pdf', fileName: 'a.pdf', folder: '/', fileSize: 100, category: 'pdf');
      final b = DocumentFileInfo(id: 1, filePath: '/a.pdf', fileName: 'a.pdf', folder: '/', fileSize: 100, category: 'pdf');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality', () {
      final a = DocumentFileInfo(id: 1, filePath: '/a.pdf', fileName: 'a.pdf', folder: '/', fileSize: 100, category: 'pdf');
      final b = DocumentFileInfo(id: 2, filePath: '/b.pdf', fileName: 'b.pdf', folder: '/', fileSize: 200, category: 'pdf');
      expect(a, isNot(b));
    });

    test('toJson / fromJson roundtrip', () {
      final json = info.toJson();
      final restored = DocumentFileInfo.fromJson(json);
      expect(restored, info);
    });

    test('fromJson handles null dateTime', () {
      final json = info.toJson()..remove('dateTime');
      final restored = DocumentFileInfo.fromJson(json);
      expect(restored.dateTime, isNull);
    });

    test('toString', () {
      expect(info.toString(), contains('DocumentFileInfo'));
      expect(info.toString(), contains('report.pdf'));
    });
  });
}
