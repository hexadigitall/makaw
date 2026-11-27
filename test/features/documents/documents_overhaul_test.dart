import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makaw/app/providers/service_providers.dart';
import 'package:makaw/features/documents/data/services/document_service.dart';
import 'package:makaw/features/documents/data/services/document_state_service.dart';
import 'package:makaw/features/documents/domain/document_format_registry.dart';
import 'package:makaw/features/documents/domain/document_reader_contract.dart';
import 'package:makaw/features/documents/presentation/pages/document_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('DocumentFormatRegistry (~145 formats)', () {
    test('covers all 7 semantic families and representative extensions', () {
      expect(DocumentFormatRegistry.familyFor('book.pdf'), DocumentFamily.booksComics);
      expect(DocumentFormatRegistry.familyFor('spec.pdfa'), DocumentFamily.booksComics);
      expect(DocumentFormatRegistry.familyFor('manga.cbz'), DocumentFamily.booksComics);
      expect(DocumentFormatRegistry.familyFor('novel.fb2'), DocumentFamily.booksComics);

      expect(DocumentFormatRegistry.familyFor('memo.docx'), DocumentFamily.docsNotes);
      expect(DocumentFormatRegistry.familyFor('script.fountain'), DocumentFamily.docsNotes);
      expect(DocumentFormatRegistry.familyFor('notes.enex'), DocumentFamily.docsNotes);
      expect(DocumentFormatRegistry.familyFor('draft.scriv'), DocumentFamily.docsNotes);

      expect(DocumentFormatRegistry.familyFor('budget.xlsx'), DocumentFamily.sheetsData);
      expect(DocumentFormatRegistry.familyFor('report.ods'), DocumentFamily.sheetsData);
      expect(DocumentFormatRegistry.familyFor('data.sylk'), DocumentFamily.sheetsData);

      expect(DocumentFormatRegistry.familyFor('deck.pptx'), DocumentFamily.slides);
      expect(DocumentFormatRegistry.familyFor('talk.odp'), DocumentFamily.slides);
      expect(DocumentFormatRegistry.familyFor('pitch.key'), DocumentFamily.slides);

      expect(DocumentFormatRegistry.familyFor('paper.tex'), DocumentFamily.markupTech);
      expect(DocumentFormatRegistry.familyFor('page.mhtml'), DocumentFamily.markupTech);
      expect(DocumentFormatRegistry.familyFor('manual.man'), DocumentFamily.markupTech);

      expect(DocumentFormatRegistry.familyFor('thread.eml'), DocumentFamily.mailPim);
      expect(DocumentFormatRegistry.familyFor('invite.ics'), DocumentFamily.mailPim);
      expect(DocumentFormatRegistry.familyFor('card.vcf'), DocumentFamily.mailPim);

      expect(DocumentFormatRegistry.familyFor('diagram.svg'), DocumentFamily.vectorCad);
      expect(DocumentFormatRegistry.familyFor('floorplan.dxf'), DocumentFamily.vectorCad);
      expect(DocumentFormatRegistry.familyFor('logo.ai'), DocumentFamily.vectorCad);

      expect(DocumentFormatRegistry.allExtensions.length, greaterThanOrEqualTo(140));
    });

    test('sniffs %PDF- magic bytes cleanly for hybrid formats like .ai', () {
      expect(DocumentFormatRegistry.looksLikePdfBytes('%PDF-1.7\n'.codeUnits), isTrue);
      expect(DocumentFormatRegistry.looksLikePdfBytes([0x50, 0x4B, 0x03, 0x04]), isFalse);
      expect(DocumentFormatRegistry.looksLikeZipBytes([0x50, 0x4B, 0x03, 0x04]), isTrue);
    });
  });

  group('DocumentReadingState & SQLite DocumentStateService', () {
    test('persists progress, pin state, and collections in SQLite', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, v) async {
            await db.execute('''
              CREATE TABLE document_state (
                file_path TEXT PRIMARY KEY,
                title TEXT NOT NULL DEFAULT '',
                format TEXT NOT NULL DEFAULT 'other',
                current_page INTEGER NOT NULL DEFAULT 1,
                total_pages INTEGER NOT NULL DEFAULT 1,
                scroll_progress REAL NOT NULL DEFAULT 0.0,
                scroll_offset REAL NOT NULL DEFAULT 0.0,
                zoom_scale REAL NOT NULL DEFAULT 1.0,
                theme TEXT NOT NULL DEFAULT 'dark',
                font_size REAL NOT NULL DEFAULT 16.0,
                bookmarks TEXT NOT NULL DEFAULT '',
                reading_status TEXT NOT NULL DEFAULT 'unread',
                pinned INTEGER NOT NULL DEFAULT 0,
                last_read TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE document_collections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                color_hex INTEGER NOT NULL DEFAULT 4286680312,
                created_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE document_collection_items (
                collection_id INTEGER NOT NULL,
                file_path TEXT NOT NULL,
                added_at TEXT NOT NULL,
                PRIMARY KEY (collection_id, file_path)
              )
            ''');
          },
        ),
      );
      try {
        DocumentStateService.init(db);
        const testPath = '/tmp/clean_architecture.pdf';
        await DocumentStateService.saveProgress(
          testPath,
          title: 'Clean Architecture',
          currentPage: 42,
          totalPages: 180,
          isPinned: true,
        );

        final loaded = await DocumentStateService.getState(testPath);
        expect(loaded, isNotNull);
        expect(loaded!.currentPage, 42);
        expect(loaded.totalPages, 180);
        expect(loaded.isPinned, isTrue);
        expect(loaded.readingStatus, ReadingStatus.reading);

        final col = await DocumentStateService.createCollection('Engineering');
        expect(col, isNotNull);
        await DocumentStateService.addToCollection(col!.id, testPath);
        expect(DocumentStateService.pathsInCollection(col.id), contains(testPath));
      } finally {
        await db.close();
      }
    });
  });

  group('Redesigned DocumentWidget library UI & Long-Press Multi-Select', () {
    testWidgets('renders 7 family pills cleanly and supports hold-to-select + tap-to-add batch bar', (tester) async {
      final svc = DocumentService();
      svc.seedDocumentsForTest([
        DocumentFileInfo(id: 1, filePath: '/docs/Spec_One.pdf', fileName: 'Spec_One.pdf', folder: '/docs', fileSize: 2048, category: 'pdf'),
        DocumentFileInfo(id: 2, filePath: '/docs/Spec_Two.pdf', fileName: 'Spec_Two.pdf', folder: '/docs', fileSize: 4096, category: 'pdf'),
      ]);
      String? openedPath;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentServiceProvider.overrideWith((ref) => svc),
          ],
          child: MaterialApp(
            home: DocumentWidget(
              autoScan: false,
              openFile: (path) => openedPath = path,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      expect(find.text('Sheets'), findsOneWidget);
      expect(find.text('Slides'), findsOneWidget);
      expect(find.text('Spec_One.pdf'), findsOneWidget);
      expect(find.text('Spec_Two.pdf'), findsOneWidget);

      // Hold down first document to enter multi-select mode
      await tester.longPress(find.text('Spec_One.pdf'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Tap second document while in multi-select mode to add it (does not open viewer)
      await tester.tap(find.text('Spec_Two.pdf'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(openedPath, isNull);
    });
  });
}
