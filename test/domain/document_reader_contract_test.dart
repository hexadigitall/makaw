import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/documents/domain/document_reader_contract.dart';

void main() {
  group('DocumentReaderContract', () {
    test('resolves DocumentFormat from file extensions', () {
      expect(DocumentFormat.fromExtension('.pdf'), DocumentFormat.pdf);
      expect(DocumentFormat.fromExtension('pdf'), DocumentFormat.pdf);
      expect(DocumentFormat.fromExtension('.epub'), DocumentFormat.epub);
      expect(DocumentFormat.fromExtension('.docx'), DocumentFormat.docx);
      expect(DocumentFormat.fromExtension('.doc'), DocumentFormat.docx);
      expect(DocumentFormat.fromExtension('.txt'), DocumentFormat.txt);
      expect(DocumentFormat.fromExtension('.md'), DocumentFormat.txt);
      expect(DocumentFormat.fromExtension('.xlsx'), DocumentFormat.sheet);
      expect(DocumentFormat.fromExtension('.csv'), DocumentFormat.sheet);
      expect(DocumentFormat.fromExtension('.unknown'), DocumentFormat.other);
    });

    test('serializes and deserializes DocumentReadingState', () {
      final now = DateTime.now();
      final state = DocumentReadingState(
        filePath: '/storage/docs/handbook.pdf',
        title: 'Employee Handbook',
        format: DocumentFormat.pdf,
        currentPage: 42,
        totalPages: 120,
        scrollProgress: 0.35,
        lastRead: now,
        theme: ReaderTheme.sepia,
        fontSize: 18.0,
        bookmarks: [1, 15, 42],
      );

      final map = state.toMap();
      expect(map['file_path'], '/storage/docs/handbook.pdf');
      expect(map['current_page'], 42);
      expect(map['format'], 'pdf');
      expect(map['theme'], 'sepia');

      final reconstructed = DocumentReadingState.fromMap(map);
      expect(reconstructed.filePath, state.filePath);
      expect(reconstructed.title, state.title);
      expect(reconstructed.format, DocumentFormat.pdf);
      expect(reconstructed.currentPage, 42);
      expect(reconstructed.totalPages, 120);
      expect(reconstructed.scrollProgress, 0.35);
      expect(reconstructed.theme, ReaderTheme.sepia);
      expect(reconstructed.fontSize, 18.0);
      expect(reconstructed.bookmarks, [1, 15, 42]);
    });

    test('copyWith properly updates state attributes', () {
      final state = DocumentReadingState(
        filePath: '/docs/book.epub',
        title: 'Novel',
        format: DocumentFormat.epub,
        lastRead: DateTime.now(),
      );

      final updated = state.copyWith(
        currentPage: 5,
        scrollProgress: 0.5,
        theme: ReaderTheme.dark,
      );

      expect(updated.currentPage, 5);
      expect(updated.scrollProgress, 0.5);
      expect(updated.theme, ReaderTheme.dark);
      expect(updated.filePath, '/docs/book.epub');
    });
  });
}
