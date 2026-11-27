import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/platform/session_paths.dart';
import '../ui/makaw_toast.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// A definition (from a dictionary API) for a selected word.
class WordDefinition {
  final String word;
  final String phonetic;
  final List<String> partsOfSpeech;
  final List<String> definitions;
  final List<String> examples;

  const WordDefinition({
    required this.word,
    this.phonetic = '',
    this.partsOfSpeech = const [],
    this.definitions = const [],
    this.examples = const [],
  });
}

/// Translation result for a selected text.
class TranslationResult {
  final String text;
  final String translatedText;
  final String sourceLang;
  final String targetLang;

  const TranslationResult({
    required this.text,
    required this.translatedText,
    required this.sourceLang,
    required this.targetLang,
  });
}

/// Central service for text-learning actions usable across all readers:
/// define, pronounce, read aloud, translate, copy, select all.
class TextActionService {
  static final TextActionService instance = TextActionService._();
  TextActionService._() {
    _tts.setSharedInstance(true);
  }

  static FlutterTts _tts = FlutterTts();
  static bool _isSpeaking = false;
  static bool _isPaused = false;
  static String _currentText = '';
  static List<String> _chunks = const [];
  static int _chunkIndex = 0;
  static double _speechMultiplier = 1.0;
  static int _sessionToken = 0;
  static bool _initialized = false;
  static bool _handlersBound = false;
  static OverlayEntry? _listenOverlay;
  static final ValueNotifier<int> speechVersion = ValueNotifier<int>(0);

  /// Splits long text into natural sentence/clause chunks <= [maxChunkLen] chars
  /// so Android TextToSpeech never hits its 4000-char limit and Pause/Resume/Skip
  /// track exact sentence position.
  static List<String> chunkSpeechText(String raw, {int maxChunkLen = 440}) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];

    final sentences = normalized
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    final out = <String>[];
    final buf = StringBuffer();

    void flushBuf() {
      final s = buf.toString().trim();
      if (s.isNotEmpty) out.add(s);
      buf.clear();
    }

    for (final sentence in sentences) {
      if (sentence.length > maxChunkLen) {
        flushBuf();
        var start = 0;
        while (start < sentence.length) {
          var end = (start + maxChunkLen).clamp(0, sentence.length);
          if (end < sentence.length) {
            final space = sentence.lastIndexOf(' ', end);
            if (space > start + 40) end = space;
          }
          final piece = sentence.substring(start, end).trim();
          if (piece.isNotEmpty) out.add(piece);
          start = end;
        }
        continue;
      }

      if (buf.isEmpty) {
        buf.write(sentence);
      } else if (buf.length + 1 + sentence.length <= maxChunkLen) {
        buf.write(' $sentence');
      } else {
        flushBuf();
        buf.write(sentence);
      }
    }
    flushBuf();
    return out;
  }

  static void _notifySpeechChanged() {
    speechVersion.value++;
  }

  static double ttsRateForMultiplier(double multiplier) =>
      (multiplier * 0.5).clamp(0.25, 0.95);

  static Future<void> ensureInit() async {
    if (!_initialized) {
      try {
        await _tts.awaitSpeakCompletion(false);
        await _tts.setSpeechRate(ttsRateForMultiplier(_speechMultiplier));
        _initialized = true;
      } catch (_) {}
    }
    if (!_handlersBound) {
      _handlersBound = true;
      _tts.setCompletionHandler(() {
        final token = _sessionToken;
        if (!_isSpeaking || _isPaused || token != _sessionToken) return;
        if (_chunkIndex + 1 < _chunks.length) {
          _chunkIndex++;
          _notifySpeechChanged();
          _speakCurrentChunk(token);
        } else {
          _isSpeaking = false;
          _isPaused = false;
          _chunkIndex = 0;
          _dismissListenOverlay();
          _notifySpeechChanged();
        }
      });
      _tts.setErrorHandler((_) {
        _isSpeaking = false;
        _isPaused = false;
        _notifySpeechChanged();
      });
    }
  }

  static Future<void> _speakCurrentChunk(int token) async {
    if (token != _sessionToken || _chunkIndex < 0 || _chunkIndex >= _chunks.length) return;
    try {
      await _tts.setSpeechRate(ttsRateForMultiplier(_speechMultiplier));
      await _tts.speak(_chunks[_chunkIndex]);
    } catch (_) {
      if (token == _sessionToken) {
        _isSpeaking = false;
        _isPaused = false;
        _notifySpeechChanged();
      }
    }
  }

  /// Pronounce a word or short text aloud once.
  static Future<void> pronounce(String text) async {
    await ensureInit();
    final clean = text.trim();
    if (clean.isEmpty) return;
    try {
      _sessionToken++;
      await _tts.stop();
      _isSpeaking = false;
      _isPaused = false;
      _notifySpeechChanged();
      await _tts.setSpeechRate(ttsRateForMultiplier(0.95));
      await _tts.speak(clean);
    } catch (_) {}
  }

  /// Stop any in-progress speech and close the floating listen overlay.
  static Future<void> stopSpeaking() async {
    _sessionToken++;
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    _isPaused = false;
    _chunks = const [];
    _chunkIndex = 0;
    _dismissListenOverlay();
    _notifySpeechChanged();
  }

  /// Pause at the exact current sentence chunk (preserved for resumeSpeaking).
  static Future<void> pauseSpeaking() async {
    _sessionToken++;
    try {
      await _tts.stop();
    } catch (_) {}
    if (_chunks.isNotEmpty) {
      _isSpeaking = true;
      _isPaused = true;
    }
    _notifySpeechChanged();
  }

  /// Resume speaking cleanly from the exact paused sentence chunk.
  static Future<void> resumeSpeaking() async {
    if (_chunks.isEmpty) return;
    await ensureInit();
    final token = ++_sessionToken;
    _isSpeaking = true;
    _isPaused = false;
    _notifySpeechChanged();
    await _speakCurrentChunk(token);
  }

  static Future<void> skipPrevious() async {
    if (_chunks.isEmpty) return;
    await ensureInit();
    final token = ++_sessionToken;
    try {
      await _tts.stop();
    } catch (_) {}
    _chunkIndex = (_chunkIndex - 1).clamp(0, _chunks.length - 1);
    _isSpeaking = true;
    _isPaused = false;
    _notifySpeechChanged();
    await _speakCurrentChunk(token);
  }

  static Future<void> skipNext() async {
    if (_chunks.isEmpty) return;
    await ensureInit();
    final token = ++_sessionToken;
    try {
      await _tts.stop();
    } catch (_) {}
    if (_chunkIndex + 1 < _chunks.length) {
      _chunkIndex++;
      _isSpeaking = true;
      _isPaused = false;
      _notifySpeechChanged();
      await _speakCurrentChunk(token);
    } else {
      await stopSpeaking();
    }
  }

  static Future<void> setSpeechMultiplier(double multiplier) async {
    _speechMultiplier = multiplier.clamp(0.7, 2.0);
    _notifySpeechChanged();
    if (_isSpeaking && !_isPaused && _chunks.isNotEmpty) {
      final token = ++_sessionToken;
      try {
        await _tts.stop();
      } catch (_) {}
      await _speakCurrentChunk(token);
    }
  }

  /// Read a passage aloud using sentence-chunked queue (handles huge documents!).
  static Future<void> readAloud(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (_isSpeaking) {
      await stopSpeaking();
      return;
    }
    await playFromBeginning(clean);
  }

  /// Restart reading [text] from the very beginning using sentence chunks.
  static Future<void> playFromBeginning(String text) async {
    await ensureInit();
    final clean = text.trim();
    if (clean.isEmpty) return;
    final token = ++_sessionToken;
    try {
      await _tts.stop();
    } catch (_) {}
    _currentText = clean;
    _chunks = chunkSpeechText(clean);
    if (_chunks.isEmpty) return;
    _chunkIndex = 0;
    _isSpeaking = true;
    _isPaused = false;
    _notifySpeechChanged();
    await _speakCurrentChunk(token);
  }

  static bool get isSpeaking => _isSpeaking;
  static bool get isPaused => _isPaused;
  static String get currentText => _currentText;
  static int get currentChunkIndex => _chunkIndex;
  static int get totalChunks => _chunks.length;
  static double get speechMultiplier => _speechMultiplier;
  static String get currentChunkText =>
      (_chunkIndex >= 0 && _chunkIndex < _chunks.length) ? _chunks[_chunkIndex] : _currentText;

  static void _dismissListenOverlay() {
    try {
      _listenOverlay?.remove();
    } catch (_) {}
    _listenOverlay = null;
  }

  /// Look up a word definition using the free DictionaryAPI.
  static Future<WordDefinition?> define(String text) async {
    final word = text.trim().split(RegExp(r'\s+')).first.replaceAll(RegExp("[^a-zA-Z'\\-]"), '');
    if (word.isEmpty) return null;
    try {
      final uri = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as List;
      if (data.isEmpty) return null;
      final entry = data.first as Map<String, dynamic>;
      final phonetic = (entry['phonetic'] as String?) ?? '';
      final meanings = (entry['meanings'] as List?) ?? [];
      final parts = <String>[];
      final defs = <String>[];
      final examples = <String>[];
      for (final m in meanings) {
        final p = (m as Map<String, dynamic>)['partOfSpeech'] as String? ?? '';
        final defArr = (m['definitions'] as List?) ?? [];
        for (final d in defArr.take(3)) {
          final dm = d as Map<String, dynamic>;
          if (parts.length < 4) parts.add(p);
          defs.add((dm['definition'] as String?) ?? '');
          final ex = (dm['example'] as String?) ?? '';
          if (ex.isNotEmpty && examples.length < 3) examples.add(ex);
        }
      }
      return WordDefinition(
        word: word,
        phonetic: phonetic,
        partsOfSpeech: parts,
        definitions: defs,
        examples: examples,
      );
    } catch (_) {
      return null;
    }
  }

  /// Translate text via the free Google translate web endpoint (POST form).
  static Future<TranslationResult?> translate(String text, {String target = 'en'}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      final uri = Uri.parse('https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$target&dt=t&q=${Uri.encodeComponent(trimmed)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as List;
      final sentences = (data[0] as List?) ?? [];
      final buffer = StringBuffer();
      for (final s in sentences) {
        if (s is List && s.isNotEmpty && s[0] != null) buffer.write('${s[0]} ');
      }
      final translated = buffer.toString().trim();
      String sourceLang = 'auto';
      try {
        sourceLang = (data[2] as String?) ?? 'auto';
      } catch (_) {}
      return TranslationResult(
        text: trimmed,
        translatedText: translated,
        sourceLang: sourceLang,
        targetLang: target,
      );
    } catch (_) {
      return null;
    }
  }

  static void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }
}

/// Shows a transient non-dismissible loading dialog; returns a function to
/// dismiss it.
///
/// NOTE: the underlying `showDialog` must NOT be awaited here — awaiting it
/// would block until the dialog is dismissed, but this dialog is
/// non-dismissible, so the future would never complete and the loading state
/// would hang forever. The dialog is launched fire-and-forget and the caller
/// closes it via the returned dismiss function.
Future<void Function()> _showLoadingIndicator(BuildContext context, String message) async {
  final completer = Completer<void Function()>();
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dCtx) {
        if (!completer.isCompleted) {
          completer.complete(() {
            if (dCtx.mounted) Navigator.of(dCtx, rootNavigator: true).pop();
          });
        }
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8))),
                  const SizedBox(width: 16),
                  Flexible(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14))),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  return completer.future;
}
/// A reusable bottom-sheet row used by text-action menus.
class TextActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  const TextActionTile({super.key, required this.icon, required this.label, this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.white70, size: 20),
      title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 14)),
      dense: true,
      onTap: onTap,
    );
  }
}

/// Shows the shared learning/action menu for a selected [text].
///
/// Directly opens the dictionary meaning modal for [text] (reused by EPUB reader
/// selection bar and learning context menus).
Future<void> showDefineDialog(BuildContext context, String text) async {
  final selected = text.trim();
  if (selected.isEmpty) return;
  final wordToken = selected.split(RegExp(r'\s+')).first.replaceAll(RegExp("[^a-zA-Z'\\-]"), '');
  final targetWord = wordToken.isNotEmpty ? wordToken : selected;
  final dismiss = await _showLoadingIndicator(context, 'Looking up "$targetWord"...');
  final def = await TextActionService.define(targetWord);
  dismiss();
  if (!context.mounted) return;
  if (def == null || def.definitions.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('No dictionary entry found for "$targetWord"')),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dCtx) => AlertDialog(
      backgroundColor: const Color(0xFF141928),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Expanded(
            child: Text(def.word, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          if (def.phonetic.isNotEmpty)
            Text(def.phonetic, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < def.definitions.length && i < def.partsOfSpeech.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}. ${def.partsOfSpeech[i]}',
                      style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(def.definitions[i], style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
                    if (i < def.examples.length && def.examples[i].isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('“${def.examples[i]}”', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => TextActionService.pronounce(def.word),
          icon: const Icon(Icons.volume_up_rounded, color: Color(0xFF818CF8), size: 18),
          label: const Text('Pronounce', style: TextStyle(color: Color(0xFF818CF8))),
        ),
        TextButton(
          onPressed: () {
            TextActionService.copyToClipboard(def.word);
            Navigator.of(dCtx).pop();
          },
          child: const Text('Copy', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(),
          child: const Text('Close', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
      ],
    ),
  );
}

/// Centralized selection action menu supporting Define, Pronounce, Read Aloud,
/// Translate, Copy, and Select All. Pass [readAloudContext] to read a broader
/// surrounding block instead of just the selection itself (e.g. a whole paragraph).
/// [readAloudContext] is the passage read by "Read Aloud" (defaults to the
/// selection itself). Pass a larger block (e.g. the containing paragraph) so
/// that reading aloud starts from the paragraph that holds the selection.
///
/// Returns a future that completes when the sheet closes.
Future<void> showTextActionMenu(BuildContext context, String text, {String? title, String? readAloudContext}) async {
  final selected = text.trim();
  if (selected.isEmpty) return;
  final readTarget = (readAloudContext ?? '').trim().isNotEmpty ? readAloudContext!.trim() : selected;
  final isSingleWord = selected.split(RegExp(r'\s+')).length == 1;

  void toast(String msg) {
    MakawToast.info(context, msg);
  }

  // Show definition / translation inline on request.
  Future<void> showDefinitionDialog() async {
    toast('Looking up "${isSingleWord ? selected : selected.split(' ').first}"...');
    final dismiss = await _showLoadingIndicator(context, 'Looking up definition...');
    final def = isSingleWord ? await TextActionService.define(selected) : null;
    dismiss();
    if (!context.mounted) return;
    if (def == null || def.definitions.isEmpty) {
      toast('No definition found');
      return;
    }
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Expanded(
              child: Text(def.word, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (def.phonetic.isNotEmpty)
              Text(def.phonetic, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < def.definitions.length && i < def.partsOfSpeech.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${i + 1}.',
                              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          Text(def.partsOfSpeech[i],
                              style: const TextStyle(
                                  color: Color(0xFF818CF8), fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(def.definitions[i], style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
                      if (i < def.examples.length && def.examples[i].isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('“${def.examples[i]}”',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (isSingleWord)
            TextButton.icon(
              onPressed: () async {
                Navigator.of(dCtx).pop();
                await TextActionService.pronounce(def.word);
              },
              icon: const Icon(Icons.volume_up, color: Color(0xFF818CF8), size: 18),
              label: const Text('Pronounce', style: TextStyle(color: Color(0xFF818CF8))),
            ),
          TextButton(
            onPressed: () {
              TextActionService.copyToClipboard(def.word);
              Navigator.of(dCtx).pop();
              toast('Copied');
            },
            child: const Text('Copy', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: const Text('Close', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
        ],
      ),
    );
  }

  Future<void> showTranslationDialog() async {
    final dismiss = await _showLoadingIndicator(context, 'Translating...');
    final result = await TextActionService.translate(selected);
    dismiss();
    if (!context.mounted) return;
    if (result == null || result.translatedText.isEmpty) {
      toast('Translation failed');
      return;
    }
    showDialog(
      context: context,
      builder: (trCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Translation', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.text, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
              child: Text(result.translatedText, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              Navigator.of(trCtx).pop();
              await TextActionService.readAloud(result.translatedText);
            },
            icon: const Icon(Icons.volume_up, color: Color(0xFF818CF8), size: 18),
            label: const Text('Read Aloud', style: TextStyle(color: Color(0xFF818CF8))),
          ),
          TextButton(
            onPressed: () {
              TextActionService.copyToClipboard(result.translatedText);
              Navigator.of(trCtx).pop();
              toast('Translated text copied');
            },
            child: const Text('Copy', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          TextButton(
            onPressed: () => Navigator.of(trCtx).pop(),
            child: const Text('Close', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
        ],
      ),
    );
  }

  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              title ?? selected,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(color: Color(0xFF2D3748), height: 1),
          if (isSingleWord)
            TextActionTile(
              icon: Icons.menu_book_rounded,
              label: 'Meaning / Definition',
              color: const Color(0xFF818CF8),
              onTap: () {
                Navigator.pop(ctx);
                showDefinitionDialog();
              },
            ),
          TextActionTile(
            icon: Icons.volume_up_rounded,
            label: 'Pronounce',
            color: const Color(0xFF22D3EE),
            onTap: () async {
              Navigator.pop(ctx);
              await TextActionService.pronounce(selected);
            },
          ),
          TextActionTile(
            icon: Icons.record_voice_over_rounded,
            label: TextActionService.isSpeaking ? 'Stop Reading Aloud' : 'Read Aloud',
            color: const Color(0xFFF472B6),
            onTap: () {
              Navigator.pop(ctx);
              showReadAloudDialog(context, readTarget);
            },
          ),
          TextActionTile(
            icon: Icons.translate_rounded,
            label: 'Translate',
            color: const Color(0xFF38BDF8),
            onTap: () {
              Navigator.pop(ctx);
              showTranslationDialog();
            },
          ),
          TextActionTile(
            icon: Icons.content_copy_rounded,
            label: 'Copy',
            onTap: () {
              TextActionService.copyToClipboard(selected);
              Navigator.pop(ctx);
              toast('Copied to clipboard');
            },
          ),
          TextActionTile(
            icon: Icons.select_all_rounded,
            label: 'Select All',
            onTap: () {
              Navigator.pop(ctx);
              toast('Selection scoped to the word/sentence you tapped. Long-press and drag handles to extend.');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Shows a non-blocking floating obsidian Listen Player dock (or clean sheet
/// fallback in headless tests) with live sentence progress, Prev/Next skip,
/// Pause/Resume at exact sentence, speed cycling (`0.8x`..`1.8x`), and Stop.
Future<void> showReadAloudDialog(BuildContext context, String text) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;

  await TextActionService.playFromBeginning(trimmed);
  if (!context.mounted) return;

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) {
    TextActionService._dismissListenOverlay();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _MakawListenOverlayHost(
        onStop: () {
          if (TextActionService._listenOverlay == entry) {
            TextActionService._dismissListenOverlay();
          }
          TextActionService.stopSpeaking();
        },
      ),
    );
    TextActionService._listenOverlay = entry;
    overlay.insert(entry);
    return;
  }

  // Fallback for widget test environments without a root Overlay
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF141826),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _MakawListenCardBody(
      onClose: () {
        Navigator.of(ctx).pop();
        TextActionService.stopSpeaking();
      },
    ),
  );
}

class _MakawListenOverlayHost extends StatelessWidget {
  final VoidCallback onStop;
  const _MakawListenOverlayHost({required this.onStop});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      left: 14,
      right: 14,
      bottom: mq.padding.bottom + 14,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Material(
            color: Colors.transparent,
            child: _MakawListenCardBody(onClose: onStop),
          ),
        ),
      ),
    );
  }
}

class _MakawListenCardBody extends StatelessWidget {
  final VoidCallback onClose;
  const _MakawListenCardBody({required this.onClose});

  static const _speeds = [0.8, 1.0, 1.25, 1.5, 1.8];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: TextActionService.speechVersion,
      builder: (_, __, ___) {
        final idx = TextActionService.currentChunkIndex;
        final total = TextActionService.totalChunks;
        final paused = TextActionService.isPaused;
        final speed = TextActionService.speechMultiplier;
        final progress = total > 0 ? ((idx + 1) / total).clamp(0.0, 1.0) : 0.0;
        final preview = TextActionService.currentChunkText;

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xF5141928),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.45)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFA78BFA).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.headphones_rounded, color: Color(0xFFA78BFA), size: 16),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Listening · ${total > 0 ? "${idx + 1}/$total" : "Ready"}',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          if (preview.isNotEmpty)
                            Text(
                              preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, height: 1.3),
                            ),
                        ],
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        final curIdx = _speeds.indexWhere((s) => (s - speed).abs() < 0.05);
                        final next = _speeds[(curIdx + 1) % _speeds.length];
                        TextActionService.setSpeechMultiplier(next);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 1 : 2).replaceFirst(RegExp(r'0$'), '')}x',
                          style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                      tooltip: 'Stop Listening',
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    iconSize: 22,
                    color: Colors.white70,
                    onPressed: idx > 0 ? TextActionService.skipPrevious : null,
                    icon: const Icon(Icons.skip_previous_rounded),
                    tooltip: 'Previous Sentence',
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFA78BFA).withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      if (paused) {
                        TextActionService.resumeSpeaking();
                      } else {
                        TextActionService.pauseSpeaking();
                      }
                    },
                    icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 19),
                    label: Text(paused ? 'Resume' : 'Pause', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    iconSize: 22,
                    color: Colors.white70,
                    onPressed: idx + 1 < total ? TextActionService.skipNext : null,
                    icon: const Icon(Icons.skip_next_rounded),
                    tooltip: 'Next Sentence',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: progress,
                minHeight: 2.5,
                backgroundColor: Colors.white12,
                color: const Color(0xFFA78BFA),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Builds a text-selection toolbar (with the platform's default Copy /
/// Select-all buttons) plus a Makaw "Learn & Tools" button that opens the
/// shared learning menu for the current selection. Use as the
/// [SelectableText]/[SelectionArea]/[SelectableRegion] `contextMenuBuilder`.
Widget buildLearningSelectionToolbar(BuildContext context, EditableTextState editableTextState) {
  final value = editableTextState.textEditingValue;
  final sel = value.selection;
  final selected = sel.isValid && !sel.isCollapsed ? sel.textInside(value.text).trim() : '';
  final readTarget = sel.isValid && !sel.isCollapsed
      ? _paragraphOfFullText(value.text, sel.start, sel.end)
      : selected;
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      ContextMenuButtonItem(
        type: ContextMenuButtonType.custom,
        label: 'Learn & Tools',
        onPressed: () async {
          editableTextState.hideToolbar();
          if (selected.isNotEmpty) {
            await showTextActionMenu(context, selected, readAloudContext: readTarget);
          }
        },
      ),
      ...editableTextState.contextMenuButtonItems,
    ],
  );
}

// Expand a selection within [full] to the surrounding paragraph (line) so Read
// Aloud starts from the paragraph holding the selection.
String _paragraphOfFullText(String full, int start, int end) {
  if (full.isEmpty) return '';
  var s = start;
  var e = end;
  while (s > 0) {
    if (full.codeUnitAt(s - 1) == 10) break; // \n
    s--;
  }
  while (e < full.length) {
    if (full.codeUnitAt(e) == 10) break;
    e++;
  }
  final p = full.substring(s, e).trim();
  return p.isEmpty ? full.substring(start, end).trim() : p;
}

/// Injects a script into a webview so that when the user selects text, a
/// message is posted back to Flutter and the shared learning menu opens.
/// Register the JS handler in the controller's `onWebViewCreated` (or after
/// the webview is ready).
Future<void> enableWebviewLearningActions({
  required InAppWebViewController controller,
  required BuildContext context,
  String handlerName = 'makawLearn',
}) async {
  controller.addJavaScriptHandler(handlerName: handlerName, callback: (args) async {
    if (args.isEmpty || args.first == null) return null;
    final raw = args.first;
    String text = '';
    String paragraph = '';
    if (raw is List && raw.isNotEmpty) {
      text = (raw[0]?.toString() ?? '').trim();
      if (raw.length > 1) paragraph = (raw[1]?.toString() ?? '').trim();
    } else {
      text = raw.toString().trim();
    }
    if (text.isEmpty || !context.mounted) return null;
    if (paragraph.isNotEmpty && paragraph != text) {
      // Read Aloud starts from the containing paragraph of the selection.
      await showTextActionMenu(context, text, readAloudContext: paragraph);
    } else {
      await showTextActionMenu(context, text);
    }
    return null;
  });
  // Selection is driven by the native webview (long-press a word opens the
  // drag handles). We only react AFTER the user appears done adjusting the
  // selection: selection changes reset a debounce timer, and only once the
  // selection has been stable for a short while do we surface the learning
  // menu. This avoids popping the menu over the handles while the user is
  // still dragging to shorten/extend the selection.
  await controller.evaluateJavascript(source: '''
    (function(){
      if (window.__makawLearnInstalled) return;
      window.__makawLearnInstalled = true;
      var last = '';
      var timer = null;
      function paragraphOf(sel){
        try {
          var node = sel.anchorNode || sel.focusNode || null;
          if (!node) return '';
          var el = node.nodeType === 3 ? node.parentElement : node;
          while (el && el !== document.body && el !== document.documentElement){
            var disp = window.getComputedStyle(el).display;
            if (disp === 'block' || disp === 'list-item') break;
            el = el.parentElement;
          }
          return el && el.innerText ? el.innerText.trim() : '';
        } catch(err){ return ''; }
      }
      function reset(){
        if (timer){ clearTimeout(timer); timer = null; }
      }
      function pending(){
        if (timer) clearTimeout(timer);
        timer = setTimeout(function(){
          timer = null;
          try {
            var sel = window.getSelection ? window.getSelection() : null;
            var t = sel && !sel.isCollapsed ? sel.toString().trim() : '';
            if (t.length === 0) {
              last = '';
              return;
            }
            if (t === last) return;
            last = t;
            var para = paragraphOf(sel);
            window.flutter_inappwebview.callHandler("$handlerName", [t, para]);
          } catch(err){}
        }, 800);
      }
      document.addEventListener('selectionchange', pending, false);
      document.addEventListener('mouseup', pending, false);
      document.addEventListener('touchend', pending, false);
      window.addEventListener('scroll', reset, true);
    })();
  ''');
}

/// Downloads an image from a web [url] into the app's public Makaw download
/// folder and returns the saved [File] (or null on failure).
Future<File?> saveWebImage(String url, {String? suggestedName}) async {
  try {
    final uri = Uri.parse(url);
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) return null;
    final dir = await _webImageSaveDir();
    final ext = p.extension(uri.path);
    var name = (suggestedName ?? (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'image'))
        .replaceAll(RegExp(r'[^\w.\-]'), '_');
    if (name.isEmpty) name = 'image';
    if (!name.contains('.')) name = ext.isNotEmpty ? '$name$ext' : '$name.jpg';
    if (name.split('.').last.length > 5) name = '$name.jpg';
    final file = File(p.join(dir, name));
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file;
  } catch (_) {
    return null;
  }
}

Future<String> _webImageSaveDir() async {
  final prefs = await SharedPreferences.getInstance();
  final override = prefs.getString('download_location') ?? '';
  if (override.isNotEmpty) {
    try {
      final d = Directory(override);
      await d.create(recursive: true);
      if (await d.exists()) return d.path;
    } catch (_) {}
  }
  if (Platform.isAndroid) {
    for (final base in ['/storage/emulated/0/Download', '/sdcard/Download', '/storage/emulated/0/Downloads']) {
      try {
        final dir = Directory('$base/Makaw');
        await dir.create(recursive: true);
        if (await dir.exists()) return dir.path;
      } catch (_) {}
    }
  }
  final base = await SessionPaths.downloadsDir();
  final dir = Directory(p.join(base, 'Makaw'));
  await dir.create(recursive: true);
  return dir.path;
}

/// Shows a bottom-sheet so the user can save a web image (from long-press).
/// Returns true if a file was saved.
Future<bool> promptSaveWebImage(BuildContext context, String url) async {
  if (url.isEmpty) return false;
  var saved = false;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text('Save Image',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const Divider(color: Color(0xFF2D3748), height: 1),
          TextActionTile(
            icon: Icons.download_rounded,
            label: 'Download to device',
            color: const Color(0xFF38BDF8),
            onTap: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(const SnackBar(
                content: Text('Saving image...'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ));
              final file = await saveWebImage(url);
              if (file != null) {
                saved = true;
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(SnackBar(
                  content: Text('Image saved: ${p.basename(file.path)}'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF0F766E),
                ));
              } else {
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(const SnackBar(
                  content: Text('Could not save image'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  return saved;
}

/// Handles a webview long-press [InAppWebViewHitTestResult]; when the user
/// presses on an image it opens the save-image menu. Returns true if handled.
bool handleWebLongPress(BuildContext context, InAppWebViewHitTestResult hitTestResult) {
  if (hitTestResult.type == InAppWebViewHitTestResultType.IMAGE_TYPE) {
    final url = hitTestResult.extra ?? '';
    if (url.isNotEmpty && context.mounted) {
      promptSaveWebImage(context, url);
      return true;
    }
  }
  return false;
}
