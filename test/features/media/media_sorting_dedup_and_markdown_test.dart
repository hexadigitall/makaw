import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/core/utils/natural_sort.dart';
import 'package:makaw/features/music/domain/entities/song_info.dart';
import 'package:makaw/features/ai/presentation/widgets/ai_markdown_view.dart';

void main() {
  group('Natural Alphabetical Sorting (Numbers then A-Z)', () {
    test('orders numbers (0-9) before letters (A-Z)', () {
      final input = ['Zebra', '100 Reasons', '01 Intro', 'Avatar', '2 Fast', '10 Cloverfield', '!Special'];
      input.sort(naturalCompare);

      expect(input, [
        '01 Intro',
        '2 Fast',
        '10 Cloverfield',
        '100 Reasons',
        'Avatar',
        'Zebra',
        '!Special',
      ]);
    });

    test('orders numeric chunks naturally (e.g. Episode 2 before Episode 10)', () {
      final input = ['Episode 10', 'Episode 1', 'Episode 2', 'Episode 20'];
      input.sort(naturalCompare);

      expect(input, [
        'Episode 1',
        'Episode 2',
        'Episode 10',
        'Episode 20',
      ]);
    });

    test('is case-insensitive while preserving equality semantics', () {
      expect(naturalCompare('apple', 'Banana') < 0, isTrue);
      expect(naturalCompare('Banana', 'banana') == 0, isFalse); // tie-breaker handles case
      expect(naturalCompare('01 song', '02 SONG') < 0, isTrue);
    });
  });

  group('SongInfo Format Badges & Lossless Differentiation', () {
    test('extracts format badge correctly from file path', () {
      final mp3Song = SongInfo(id: 1, title: 'Track 1', artist: 'Artist', album: '', filePath: '/music/track.mp3');
      final flacSong = SongInfo(id: 2, title: 'Track 1', artist: 'Artist', album: '', filePath: '/music/track.flac');
      final wavSong = SongInfo(id: 3, title: 'Track 1', artist: 'Artist', album: '', filePath: '/music/track.wav');
      final aacSong = SongInfo(id: 4, title: 'Track 1', artist: 'Artist', album: '', filePath: '/music/track.aac');

      expect(mp3Song.formatBadge, 'MP3');
      expect(mp3Song.isLossless, isFalse);

      expect(flacSong.formatBadge, 'FLAC');
      expect(flacSong.isLossless, isTrue);

      expect(wavSong.formatBadge, 'WAV');
      expect(wavSong.isLossless, isTrue);

      expect(aacSong.formatBadge, 'AAC');
      expect(aacSong.isLossless, isFalse);
    });
  });

  group('AI Markdown Rendering & Exports', () {
    test('stripMarkdown removes markdown symbols cleanly for plain text export', () {
      const rawMarkdown = '''### How to bake a cake: According to **Bloomberg**
> The best cake requires *patience*.
- Step 1: Mix **flour** and `sugar`
- Step 2: Bake at 350°F
```python
print("Cake ready")
```''';

      final stripped = AiMarkdownView.stripMarkdown(rawMarkdown);

      expect(stripped.contains('###'), isFalse);
      expect(stripped.contains('**'), isFalse);
      expect(stripped.contains('```'), isFalse);
      expect(stripped.contains('>'), isFalse);
      expect(stripped.contains('How to bake a cake: According to Bloomberg'), isTrue);
      expect(stripped.contains('The best cake requires patience.'), isTrue);
      expect(stripped.contains('Step 1: Mix flour and sugar'), isTrue);
      expect(stripped.contains('print("Cake ready")'), isTrue);
    });

    test('markdownToHtml converts markdown to styled HTML', () {
      const raw = '### Title\nAccording to **Bloomberg**, this is *essential*.\n```dart\nvoid main() {}\n```';
      final html = AiMarkdownView.markdownToHtml(raw, title: 'Test Export', model: 'gemini-3.8-flash');

      expect(html.contains('<h3>Title</h3>'), isTrue);
      expect(html.contains('<strong>Bloomberg</strong>'), isTrue);
      expect(html.contains('<em>essential</em>'), isTrue);
      expect(html.contains('<pre><code class="language-dart">void main() {}</code></pre>'), isTrue);
      expect(html.contains('Model: gemini-3.8-flash'), isTrue);
    });

    test('markdownToDoc converts markdown to Word-compatible document', () {
      const raw = '## Overview\nWord document **formatted** cleanly.\n| Col 1 | Col 2 |\n| A | B |';
      final doc = AiMarkdownView.markdownToDoc(raw, title: 'Word Export', model: 'gemini-3.8-flash');

      expect(doc.contains('xmlns:w="urn:schemas-microsoft-com:office:word"'), isTrue);
      expect(doc.contains('<h2>Overview</h2>'), isTrue);
      expect(doc.contains('<strong>formatted</strong>'), isTrue);
    });
  });
}
