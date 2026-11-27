import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/core/storage/lrc_storage_service.dart';
import 'package:makaw/features/ai/data/services/ai_pdf_exporter.dart';
import 'package:makaw/features/documents/data/services/archive_service.dart';
import 'package:makaw/features/viewer/data/services/document_to_html.dart';

void main() {
  group('LrcStorageService', () {
    test('parseLrc extracts sorted synced lines and strips metadata tags', () {
      const sample = '''
[ti:Midnight Run]
[ar:Makaw Band]
[00:12.40]Second verse comes after
[00:04.25]First line starts here
[00:19.00][01:02.50]Repeated chorus line
''';
      final lines = LrcStorageService.parseLrc(sample);
      expect(lines.length, 4);
      expect(lines[0].text, 'First line starts here');
      expect(lines[0].time, const Duration(seconds: 4, milliseconds: 250));
      expect(lines[1].text, 'Second verse comes after');
      expect(lines[2].text, 'Repeated chorus line');
      expect(lines[3].time, const Duration(minutes: 1, seconds: 2, milliseconds: 500));
    });

    test('formatLrc emits universal LRC tags cleanly', () {
      final lrc = LrcStorageService.formatLrc(
        title: 'Horizon',
        artist: 'Ada',
        album: 'Skies',
        lines: [
          LrcLine(const Duration(seconds: 5, milliseconds: 320), 'Sun rises'),
          LrcLine(const Duration(seconds: 12, milliseconds: 50), 'Morning glow'),
        ],
      );
      expect(lrc, contains('[ti:Horizon]'));
      expect(lrc, contains('[ar:Ada]'));
      expect(lrc, contains('[00:05.32]Sun rises'));
      expect(lrc, contains('[00:12.05]Morning glow'));
      final reparsed = LrcStorageService.parseLrc(lrc);
      expect(reparsed.length, 2);
      expect(reparsed.first.text, 'Sun rises');
    });
  });

  group('ArchiveService', () {
    test('createZip, inspectArchive, and extractArchive round-trip cleanly', () async {
      final tempDir = await Directory.systemTemp.createTemp('makaw_arch_test_');
      try {
        final srcFile1 = File('${tempDir.path}/alpha.txt')..writeAsStringSync('Hello Alpha');
        final subDir = Directory('${tempDir.path}/nested')..createSync();
        File('${subDir.path}/beta.txt').writeAsStringSync('Hello Beta');
        final zipPath = '${tempDir.path}/bundle.zip';

        final created = await ArchiveService.createZip(
          sourcePaths: [srcFile1.path, subDir.path],
          outputZipPath: zipPath,
        );
        expect(created.success, isTrue);
        expect(created.fileCount, 2);
        expect(File(zipPath).existsSync(), isTrue);

        final entries = await ArchiveService.inspectArchive(zipPath);
        expect(entries.any((e) => e.name.endsWith('alpha.txt')), isTrue);
        expect(entries.any((e) => e.name.endsWith('nested/beta.txt')), isTrue);

        final outDir = '${tempDir.path}/extracted';
        final extracted = await ArchiveService.extractArchive(
          archivePath: zipPath,
          destinationDir: outDir,
        );
        expect(extracted.success, isTrue);
        expect(extracted.fileCount, 2);
        expect(File('$outDir/alpha.txt').readAsStringSync(), 'Hello Alpha');
        expect(File('$outDir/nested/beta.txt').readAsStringSync(), 'Hello Beta');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('createTarGz and extractArchive round-trip cleanly', () async {
      final tempDir = await Directory.systemTemp.createTemp('makaw_tgz_test_');
      try {
        final src = File('${tempDir.path}/notes.md')..writeAsStringSync('# Archive Note');
        final tgzPath = '${tempDir.path}/bundle.tar.gz';

        final created = await ArchiveService.createTarGz(
          sourcePaths: [src.path],
          outputPath: tgzPath,
        );
        expect(created.success, isTrue);

        final entries = await ArchiveService.inspectArchive(tgzPath);
        expect(entries.map((e) => e.name), contains('notes.md'));

        final outDir = '${tempDir.path}/out';
        final extracted = await ArchiveService.extractArchive(
          archivePath: tgzPath,
          destinationDir: outDir,
        );
        expect(extracted.success, isTrue);
        expect(File('$outDir/notes.md').readAsStringSync(), '# Archive Note');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('extractArchive rejects path traversal entries', () async {
      final tempDir = await Directory.systemTemp.createTemp('makaw_slip_test_');
      try {
        final archive = Archive()
          ..addFile(ArchiveFile('../outside.txt', 3, utf8.encode('bad')));
        final zipPath = '${tempDir.path}/evil.zip';
        File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));

        final outDir = '${tempDir.path}/out';
        final result = await ArchiveService.extractArchive(
          archivePath: zipPath,
          destinationDir: outDir,
        );
        expect(result.success, isTrue);
        expect(result.fileCount, 0);
        expect(File('${tempDir.path}/outside.txt').existsSync(), isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('AiPdfExporter & DocumentToHtml Word-HTML .doc', () {
    test('buildPdfBytes builds valid multi-page PDF 1.4 output', () {
      final longMarkdown = List.generate(
        70,
        (i) => '## Section ${i + 1}\nThis is line ${i + 1} with **bold** and `inline code`.',
      ).join('\n\n');

      final bytes = AiPdfExporter.buildPdfBytes(
        title: 'AI Engineering Spec',
        model: 'gemini-2.5-flash',
        markdownText: longMarkdown,
      );
      final text = latin1.decode(bytes);
      expect(text, startsWith('%PDF-1.4'));
      expect(text.trimRight(), endsWith('%%EOF'));
      expect(text, contains('Page 2 of'));
    });

    test('DocumentToHtml converts Word-HTML .doc without raw pre-escaping', () async {
      final tempDir = await Directory.systemTemp.createTemp('makaw_doc_test_');
      try {
        final docFile = File('${tempDir.path}/ai_export.doc')
          ..writeAsStringSync('<html><body><h1>Summary</h1><p>Clean paragraph.</p></body></html>');
        final html = await DocumentToHtml.convert(docFile);
        expect(html, contains('<h1>Summary</h1>'));
        expect(html, isNot(contains('&lt;h1&gt;')));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
