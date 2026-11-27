import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/core/services/text_action_service.dart';
import 'package:makaw/core/ui/makaw_toast.dart';
import 'package:makaw/features/media/presentation/pages/video_player_page.dart';
import 'package:makaw/features/viewer/presentation/pages/epub_viewer_page.dart';

void main() {
  group('Multi-format video subtitle engine (SRT, VTT, ASS, SUB, GZip)', () {
    test('parses CRLF + BOM SRT and strips inline HTML tags cleanly', () {
      const srt = '\uFEFF1\r\n00:00:01,500 --> 00:00:04,200\r\n<i>Hello</i> <b>Makaw</b>!\r\nSecond line\r\n\r\n'
          '2\r\n00:01:10,000 --> 00:01:12,500\r\nFinal cue\r\n';
      final cues = parseSubtitleContent(srt, filePath: 'movie.srt');
      expect(cues.length, 2);
      expect(cues[0].start, const Duration(seconds: 1, milliseconds: 500));
      expect(cues[0].end, const Duration(seconds: 4, milliseconds: 200));
      expect(cues[0].text, 'Hello Makaw!\nSecond line');
      expect(cues[1].start, const Duration(minutes: 1, seconds: 10));
    });

    test('parses WebVTT including MM:SS.mmm short timestamps and NOTE/STYLE blocks', () {
      const vtt = 'WEBVTT\n\nNOTE ignore comment\n\n00:12.250 --> 00:15.750 align:middle\nOpening scene line\n';
      final cues = parseSubtitleContent(vtt, filePath: 'show.vtt');
      expect(cues.length, 1);
      expect(cues.first.start, const Duration(seconds: 12, milliseconds: 250));
      expect(cues.first.end, const Duration(seconds: 15, milliseconds: 750));
      expect(cues.first.text, 'Opening scene line');
    });

    test('parses ASS/SSA Dialogue events and strips override tags', () {
      const ass = '''[Script Info]
Title: Test
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:05.00,0:00:09.25,Default,,0,0,0,,{\\an8}First\\NSecond
''';
      final cues = parseSubtitleContent(ass, filePath: 'anime.ass');
      expect(cues.length, 1);
      expect(cues.first.start, const Duration(seconds: 5));
      expect(cues.first.end, const Duration(seconds: 9, milliseconds: 250));
      expect(cues.first.text, 'First\nSecond');
    });

    test('decompresses gzipped subtitle download payloads cleanly', () {
      const raw = '1\n00:00:02,000 --> 00:00:05,000\nZippy Subtitles!\n';
      final gz = GZipEncoder().encode(utf8.encode(raw));
      final decoded = decodeSubtitleBytes(gz);
      final cues = parseSubtitleContent(decoded, filePath: 'sub.srt.gz');
      expect(cues.length, 1);
      expect(cues.first.text, 'Zippy Subtitles!');
    });
  });

  group('EPUB internal chapter & fragment link resolver', () {
    test('resolves relative paths, parent directory links, and #fragments accurately', () {
      const paths = [
        'OEBPS/Text/cover.xhtml',
        'OEBPS/Text/toc.xhtml',
        'OEBPS/Text/chapter01.xhtml',
        'OEBPS/Text/chapter02.xhtml',
      ];

      final r1 = resolveEpubChapterLink(
        chapterPaths: paths,
        currentChapterPath: 'OEBPS/Text/toc.xhtml',
        href: 'chapter02.xhtml#section3',
      );
      expect(r1.isExternalUrl, isFalse);
      expect(r1.chapterIndex, 3);
      expect(r1.fragment, 'section3');

      final r2 = resolveEpubChapterLink(
        chapterPaths: paths,
        currentChapterPath: 'OEBPS/Text/chapter01.xhtml',
        href: '../Text/toc.xhtml',
      );
      expect(r2.chapterIndex, 1);
      expect(r2.fragment, isNull);

      final r3 = resolveEpubChapterLink(
        chapterPaths: paths,
        currentChapterPath: 'OEBPS/Text/chapter01.xhtml',
        href: '#footnote4',
      );
      expect(r3.chapterIndex, 2);
      expect(r3.fragment, 'footnote4');

      final ext = resolveEpubChapterLink(
        chapterPaths: paths,
        currentChapterPath: 'OEBPS/Text/chapter01.xhtml',
        href: 'https://example.org',
      );
      expect(ext.isExternalUrl, isTrue);
    });
  });

  group('MakawToast floating overlay notification', () {
    testWidgets('shows styled overlay toast with title, action button, and auto-dismisses', (tester) async {
      var actionTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => MakawToast.success(
                  context,
                  'Subtitle loaded cleanly',
                  title: 'Subtitles Active',
                  actionLabel: 'Undo',
                  onAction: () => actionTapped = true,
                  duration: const Duration(milliseconds: 500),
                ),
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger'));
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('Subtitles Active'), findsOneWidget);
      expect(find.text('Subtitle loaded cleanly'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(actionTapped, isTrue);
    });
  });

  group('TextActionService chunked Read Aloud / Listen engine', () {
    test('chunks long 10,000-char chapters cleanly under 440 chars without dropping sentences', () {
      final longPassage = List.generate(
        80,
        (i) => 'Sentence number ${i + 1} explores physical book acoustics and smooth narration.',
      ).join(' ');
      expect(longPassage.length, greaterThan(4500));

      final chunks = TextActionService.chunkSpeechText(longPassage);
      expect(chunks.length, greaterThan(10));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(440));
      }
      expect(chunks.first, contains('Sentence number 1'));
      expect(chunks.last, contains('Sentence number 80'));
      expect(TextActionService.ttsRateForMultiplier(1.0), closeTo(0.5, 0.001));
      expect(TextActionService.ttsRateForMultiplier(1.8), closeTo(0.9, 0.001));
    });
  });
}
