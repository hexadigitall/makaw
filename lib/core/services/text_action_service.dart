import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
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
  static bool _initialized = false;

  static Future<void> ensureInit() async {
    if (_initialized) return;
    try {
      await _tts.awaitSpeakCompletion(true);
      _initialized = true;
    } catch (_) {}
  }

  /// Pronounce a word or short text aloud once.
  static Future<void> pronounce(String text) async {
    await ensureInit();
    try {
      await _tts.stop();
      _isSpeaking = false;
      _isPaused = false;
      await _tts.speak(text.trim());
    } catch (_) {}
  }

  /// Stop any in-progress speech.
  static Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    _isPaused = false;
  }

  /// Pause in-progress speech.
  static Future<void> pauseSpeaking() async {
    try {
      await _tts.pause();
      _isPaused = true;
    } catch (_) {}
  }

  /// Resume paused speech (flutter_tts resumes from where it left off).
  static Future<void> resumeSpeaking() async {
    try {
      await _tts.speak(_currentText);
      _isPaused = false;
    } catch (_) {}
  }

  /// Read a passage aloud, keeping robust start/stop state so UI controls can
  /// reflect and toggle playback. Toggles stop if already speaking.
  static Future<void> readAloud(String text) async {
    await ensureInit();
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (_isSpeaking) {
      await stopSpeaking();
      return;
    }
    _currentText = clean;
    _isSpeaking = true;
    _isPaused = false;
    _tts.setStartHandler(() {
      _isSpeaking = true;
      _isPaused = false;
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _isPaused = false;
    });
    _tts.setCancelHandler(() {
      _isSpeaking = false;
      _isPaused = false;
    });
    _tts.setPauseHandler(() {
      _isSpeaking = true;
      _isPaused = true;
    });
    _tts.setContinueHandler(() {
      _isSpeaking = true;
      _isPaused = false;
    });
    _tts.setErrorHandler((_) {
      _isSpeaking = false;
      _isPaused = false;
    });
    try {
      await _tts.speak(clean);
    } catch (_) {
      _isSpeaking = false;
      _isPaused = false;
    }
  }

  static bool get isSpeaking => _isSpeaking;
  static bool get isPaused => _isPaused;
  static String get currentText => _currentText;

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
  final scaffoldMessenger = ScaffoldMessenger.of(context);

  void toast(String msg) {
    scaffoldMessenger.hideCurrentSnackBar();
    scaffoldMessenger.showSnackBar(SnackBar(
      content: Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
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

/// Shows live playback controls (Stop, Pause/Resume) while reading [text]
/// aloud. It starts speaking, keeps the controls visible until playback ends
/// (or the user stops), and updates the buttons live via a lightweight poll.
Future<void> showReadAloudDialog(BuildContext context, String text) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  await TextActionService.readAloud(trimmed);

  if (!TextActionService.isSpeaking) return;

  var dismissed = false;
  var poller = Timer(const Duration(seconds: 0), () {});
  void close() {
    if (dismissed) return;
    dismissed = true;
    poller.cancel();
    if (navigator.canPop()) navigator.pop();
    TextActionService.stopSpeaking();
  }

  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) {
      poller = Timer.periodic(const Duration(milliseconds: 200), (t) {
        if (!TextActionService.isSpeaking) {
          t.cancel();
          if (!dismissed && navigator.canPop()) {
            dismissed = true;
            navigator.pop();
          }
        }
      });
      return StatefulBuilder(
        builder: (ctx, setSheet) => PopScope(
          canPop: false,
          child: SafeArea(
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
                  child: Row(
                    children: [
                      Icon(Icons.record_voice_over_rounded, color: Color(0xFFF472B6), size: 18),
                      SizedBox(width: 8),
                      Text('Reading Aloud',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF2D3748), height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Text(
                    trimmed,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        if (TextActionService.isPaused) {
                          TextActionService.resumeSpeaking();
                        } else {
                          TextActionService.pauseSpeaking();
                        }
                        setSheet(() {});
                        Future.delayed(const Duration(milliseconds: 150), () {
                          if (ctx.mounted) setSheet(() {});
                        });
                      },
                      icon: Icon(
                        TextActionService.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: const Color(0xFF22D3EE),
                        size: 18,
                      ),
                      label: Text(
                        TextActionService.isPaused ? 'Resume' : 'Pause',
                        style: const TextStyle(color: Color(0xFF22D3EE)),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: close,
                      icon: const Icon(Icons.stop_rounded, color: Color(0xFFF87171), size: 18),
                      label: const Text('Stop', style: TextStyle(color: Color(0xFFF87171))),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
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
  final docDir = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docDir.path, 'Makaw'));
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
