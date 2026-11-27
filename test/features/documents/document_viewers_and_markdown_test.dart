import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/app/providers/service_providers.dart';
import 'package:makaw/features/ai/presentation/widgets/ai_markdown_view.dart';
import 'package:makaw/features/documents/data/services/document_service.dart';
import 'package:makaw/features/documents/presentation/pages/document_page.dart';
import 'package:makaw/features/pdf/presentation/pages/pdf_viewer_page.dart';
import 'package:makaw/features/viewer/data/services/document_to_html.dart';
import 'package:makaw/features/viewer/presentation/pages/epub_viewer_page.dart';
import 'package:makaw/features/viewer/presentation/pages/spreadsheet_viewer_page.dart';
import 'package:makaw/features/viewer/presentation/pages/vector_cad_viewer_page.dart';

Archive _makeArchive(Map<String, List<int>> files) {
  final arch = Archive();
  for (final e in files.entries) {
    arch.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return arch;
}

void main() {
  group('PDF progress fraction calculation', () {
    test('tracks continuous scroll and handles 1-page PDFs without sticking at 0', () {
      expect(computePdfProgressFraction(currentPageZeroBased: 0, totalPages: 0), 0.0);
      expect(computePdfProgressFraction(currentPageZeroBased: 0, totalPages: 1), 1.0);
      expect(
        computePdfProgressFraction(
          currentPageZeroBased: 0,
          totalPages: 10,
          scrollOffset: 450,
          maxScrollExtent: 900,
        ),
        0.5,
      );
      expect(resolvePdfPageForFraction(0.0, 10), 0);
      expect(resolvePdfPageForFraction(0.5, 11), 5);
      expect(resolvePdfPageForFraction(1.0, 10), 9);
    });
  });

  group('Pure-Dart EPUB isolate parser', () {
    test('parses OPF spine, EPUB 3 Nav TOC, and NCX titles safely', () {
      final zip = _makeArchive({
        'META-INF/container.xml': utf8.encode(
          '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        ),
        'OEBPS/content.opf': utf8.encode(
          '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Deep Work</dc:title><dc:creator>Cal Newport</dc:creator></metadata>'
          '<manifest>'
          '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
          '<item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest>'
          '<spine><itemref idref="ch1"/></spine></package>',
        ),
        'OEBPS/nav.xhtml': utf8.encode(
          '<html xmlns="http://www.w3.org/1999/xhtml"><body><nav><ol><li><a href="ch1.xhtml">Chapter One: Focus</a></li></ol></nav></body></html>',
        ),
        'OEBPS/ch1.xhtml': utf8.encode('<html><body><p>Hello EPUB reader</p></body></html>'),
      });
      final encoded = ZipEncoder().encode(zip);
      final parsed = parseEpubBytes(encoded, fallbackTitle: 'Fallback');
      expect(parsed['bookTitle'], 'Deep Work');
      expect(parsed['author'], 'Cal Newport');
      expect(parsed['isEncrypted'], isFalse);
      final chapters = parsed['chapters'] as List<Map<String, String>>;
      expect(chapters.length, 1);
      expect(chapters.first['title'], 'Chapter One: Focus');
      expect(chapters.first['html'], contains('Hello EPUB reader'));
    });

    test('detects DRM encryption.xml cleanly without throwing', () {
      final zip = _makeArchive({
        'META-INF/encryption.xml': utf8.encode('<encryption><EncryptedData/></encryption>'),
      });
      final parsed = parseEpubBytes(ZipEncoder().encode(zip), fallbackTitle: 'DRM Book');
      expect(parsed['isEncrypted'], isTrue);
    });
  });

  group('EPS/PS & XPS vector parsing', () {
    test('slices DOS EPSF binary header and extracts bounding box, paths, and text', () {
      const ps = '%!PS-Adobe-3.0 EPSF-3.0\n'
          '%%Title: Test Vector\n'
          '%%BoundingBox: 0 0 100 100\n'
          '0 0 1 setrgbcolor 2 setlinewidth\n'
          'newpath 10 10 moveto 90 90 lineto stroke\n'
          '20 20 30 30 rectfill\n'
          '15 80 moveto (Periodic) show\n'
          '%%EOF\n';
      final psBytes = utf8.encode(ps);
      final dosHeader = ByteData(30);
      dosHeader.setUint8(0, 0xC5);
      dosHeader.setUint8(1, 0xD0);
      dosHeader.setUint8(2, 0xD3);
      dosHeader.setUint8(3, 0xC6);
      dosHeader.setUint32(4, 30, Endian.little);
      dosHeader.setUint32(8, psBytes.length, Endian.little);
      final fullBytes = [...dosHeader.buffer.asUint8List(), ...psBytes];

      final doc = EpsPsDocument.parse(fullBytes);
      expect(doc.title, 'Test Vector');
      expect(doc.boundingBox, const Rect.fromLTRB(0, 0, 100, 100));
      expect(doc.ops.length, 2);
      expect(doc.labels.map((l) => l.text), contains('Periodic'));
      expect(doc.hasRenderableContent, isTrue);
    });

    test('converts XPS FixedPage Path and Glyphs to SVG HTML', () {
      final zip = _makeArchive({
        'Documents/1/Pages/1.fpage': utf8.encode(
          '<FixedPage Width="400" Height="300" xmlns="http://schemas.microsoft.com/xps/2005/06">'
          '<Path Data="M 10,10 L 100,100" Stroke="#FF000000" StrokeThickness="2"/>'
          '<Glyphs UnicodeString="XPS Ready" OriginX="20" OriginY="50" FontRenderingEmSize="16" Fill="#FF1E293B"/>'
          '</FixedPage>',
        ),
      });
      final svgBody = convertXpsArchiveToHtmlBody(zip);
      expect(svgBody, isNotNull);
      expect(svgBody, contains('<path d="M 10,10 L 100,100"'));
      expect(svgBody, contains('XPS Ready'));
    });
  });

  group('SpreadsheetViewerPage multi-format rendering', () {
    testWidgets('opens namespaced XLSX via workbook.xml.rels and UTF-8 BOM semicolon CSV', (tester) async {
      late Directory tmpDir;
      late File xlsxFile;
      late File csvFile;

      await tester.runAsync(() async {
        tmpDir = await Directory.systemTemp.createTemp('makaw_sheet_test_');
        final xlsxZip = _makeArchive({
          'xl/sharedStrings.xml': utf8.encode(
            '<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<si><t>Symbol</t></si><si><t>Element</t></si><si><t>H</t></si><si><t>Hydrogen</t></si></sst>',
          ),
          'xl/_rels/workbook.xml.rels': utf8.encode(
            '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId9" Target="worksheets/custom1.xml"/>'
            '<Relationship Id="rId10" Target="worksheets/custom2.xml"/></Relationships>',
          ),
          'xl/workbook.xml': utf8.encode(
            '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="Elements" sheetId="1" r:id="rId9"/><sheet name="Isotopes" sheetId="2" r:id="rId10"/></sheets></workbook>',
          ),
          'xl/worksheets/custom1.xml': utf8.encode(
            '<?xml version="1.0"?><x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<x:sheetData>'
            '<x:row r="1"><x:c r="A1" t="s"><x:v>0</x:v></x:c><x:c r="B1" t="s"><x:v>1</x:v></x:c></x:row>'
            '<x:row r="2"><x:c r="A2" t="s"><x:v>2</x:v></x:c><x:c r="B2" t="s"><x:v>3</x:v></x:c></x:row>'
            '</x:sheetData></x:worksheet>',
          ),
          'xl/worksheets/custom2.xml': utf8.encode(
            '<?xml version="1.0"?><x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<x:sheetData><x:row r="1"><x:c r="A1" t="inlineStr"><x:is><x:t>Deuterium</x:t></x:is></x:c></x:row></x:sheetData></x:worksheet>',
          ),
        });
        xlsxFile = File('${tmpDir.path}/sample.xlsx');
        await xlsxFile.writeAsBytes(ZipEncoder().encode(xlsxZip));

        csvFile = File('${tmpDir.path}/semicolon.csv');
        await csvFile.writeAsBytes([
          0xEF, 0xBB, 0xBF,
          ...utf8.encode('Item;Qty\n"Alpha; Beta";42\n'),
        ]);
      });

      try {
        await tester.pumpWidget(MaterialApp(home: SpreadsheetViewerPage(key: ValueKey(xlsxFile.path), filePath: xlsxFile.path)));
        for (var i = 0; i < 12 && find.text('Hydrogen').evaluate().isEmpty; i++) {
          await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 30));
        }

        expect(find.text('Elements'), findsOneWidget);
        expect(find.text('Isotopes'), findsOneWidget);
        expect(find.text('Hydrogen'), findsOneWidget);

        await tester.tap(find.text('Isotopes'));
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Deuterium'), findsOneWidget);

        await tester.pumpWidget(MaterialApp(home: SpreadsheetViewerPage(key: ValueKey(csvFile.path), filePath: csvFile.path)));
        for (var i = 0; i < 12 && find.text('Alpha; Beta').evaluate().isEmpty; i++) {
          await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 30));
        }

        expect(find.text('Alpha; Beta'), findsOneWidget);
        expect(find.text('42'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.runAsync(() async {
          try {
            if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
          } catch (_) {}
        });
      }
    });
  });

  group('OLE2 binary DOC extraction', () {
    test('recovers UTF-16LE paragraphs inside OLE2 WordDocument bytes', () async {
      final header = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
      const msg = 'Quarterly Architecture Review Completed.';
      final utf16 = <int>[];
      for (final c in msg.codeUnits) {
        utf16.add(c & 0xFF);
        utf16.add((c >> 8) & 0xFF);
      }
      final tmp = await Directory.systemTemp.createTemp('makaw_doc_test_');
      try {
        final f = File('${tmp.path}/sample.doc');
        await f.writeAsBytes([...header, ...utf16, 0, 0]);
        final html = await DocumentToHtml.convert(f);
        expect(html, contains('Quarterly Architecture Review Completed.'));
      } finally {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      }
    });
  });

  group('AiMarkdownView consistency & export transformers', () {
    testWidgets('renders markdown tables with bold/italic cells without leaking ** or ###', (tester) async {
      const sample = '''
##### Quick Periodic Overview
#CompactHeading
1. ### Step One

| # | Sym | Element Name | Group |
| :--- | :--- | :--- | :--- |
| **1** | **H** | Hydrogen | |
| **2** | **He** | Helium | Noble Gas |
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiMarkdownView(text: sample),
            ),
          ),
        ),
      );

      final textDump = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
          .followedBy(
            tester.widgetList<SelectableText>(find.byType(SelectableText)).map(
                  (w) => w.data ?? w.textSpan?.toPlainText() ?? '',
                ),
          )
          .join('\n');

      expect(textDump, contains('Quick Periodic Overview'));
      expect(textDump, contains('CompactHeading'));
      expect(textDump, contains('Step One'));
      expect(textDump, contains('Hydrogen'));
      expect(textDump, isNot(contains('**')));
      expect(textDump, isNot(contains('###')));
      expect(textDump, isNot(contains('#####')));

      final plain = AiMarkdownView.stripMarkdown(sample);
      expect(plain, isNot(contains('**')));
      expect(plain, isNot(contains('###')));

      final exportedHtml = AiMarkdownView.markdownToHtml(sample);
      expect(exportedHtml, contains('<table>'));
      expect(exportedHtml, contains('<strong>H</strong>'));
      expect(exportedHtml, isNot(contains('**')));
    });
  });

  group('Portrait Documents Header layout safety', () {
    testWidgets('displays 517 count badge in 360px portrait without RenderFlex overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final svc = DocumentService();
      svc.seedDocumentsForTest([
        for (var i = 0; i < 517; i++)
          DocumentFileInfo(
            id: i + 1,
            filePath: '/docs/file_$i.pdf',
            fileName: 'Document_$i.pdf',
            folder: '/docs',
            fileSize: 1024,
            category: 'pdf',
          ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [documentServiceProvider.overrideWith((ref) => svc)],
          child: MaterialApp(home: DocumentWidget(autoScan: false, openFile: (_) {})),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(tester.takeException(), isNull);
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('517'), findsAtLeastNWidgets(1));
    });
  });
}
