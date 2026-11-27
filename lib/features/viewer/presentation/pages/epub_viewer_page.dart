import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import '../../../../core/services/text_action_service.dart';
import '../../../documents/data/services/document_state_service.dart';
import '../../../documents/domain/document_reader_contract.dart';

class _EpubChapter {
  final String title;
  final String path;
  final String html;
  const _EpubChapter({required this.title, required this.path, required this.html});
}

class _ParsedEpubBook {
  final String bookTitle;
  final String author;
  final bool isEncrypted;
  final List<_EpubChapter> chapters;
  final Map<String, String> imageDataUris;

  const _ParsedEpubBook({
    required this.bookTitle,
    required this.author,
    required this.isEncrypted,
    required this.chapters,
    required this.imageDataUris,
  });
}

class _EpubSearchHit {
  final int chapterIndex;
  final String chapterTitle;
  final String snippet;
  const _EpubSearchHit({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.snippet,
  });
}

/// Top-level pure-Dart EPUB parser exposed for background isolate execution
/// and unit testing. Supports OPF spine + EPUB 2 NCX + EPUB 3 Nav TOC.
Map<String, dynamic> parseEpubBytes(List<int> bytes, {String fallbackTitle = 'Book'}) {
  final archive = ZipDecoder().decodeBytes(bytes);

  final byLowerPath = <String, ArchiveFile>{};
  for (final f in archive.files) {
    if (f.isFile) {
      byLowerPath[f.name.replaceAll('\\', '/').toLowerCase()] = f;
    }
  }

  final encFile = byLowerPath['meta-inf/encryption.xml'];
  if (encFile != null) {
    final encXml = utf8.decode(encFile.content as List<int>, allowMalformed: true);
    if (encXml.contains('EncryptedData') && !encXml.contains('http://www.idpf.org/2008/embedding')) {
      return {
        'bookTitle': fallbackTitle,
        'author': '',
        'isEncrypted': true,
        'chapters': <Map<String, String>>[],
        'images': <String, String>{},
      };
    }
  }

  var opfPath = '';
  final container = byLowerPath['meta-inf/container.xml'];
  if (container != null) {
    try {
      final doc = XmlDocument.parse(utf8.decode(container.content as List<int>, allowMalformed: true));
      opfPath = doc
              .findAllElements('rootfile', namespace: '*')
              .map((e) => e.getAttribute('full-path'))
              .whereType<String>()
              .firstOrNull ??
          '';
    } catch (_) {}
  }
  if (opfPath.isEmpty) {
    opfPath = archive.files
            .where((f) => f.isFile && f.name.toLowerCase().endsWith('.opf'))
            .map((f) => f.name)
            .firstOrNull ??
        '';
  }

  var bookTitle = fallbackTitle;
  var author = '';
  final spinePaths = <String>[];
  final tocTitlesByHref = <String, String>{};

  if (opfPath.isNotEmpty) {
    final opfFile = byLowerPath[opfPath.toLowerCase()];
    if (opfFile != null) {
      try {
        final opfDir = p.posix.dirname(opfPath);
        final opfDoc = XmlDocument.parse(utf8.decode(opfFile.content as List<int>, allowMalformed: true));
        final titleText = opfDoc.findAllElements('title', namespace: '*').firstOrNull?.innerText.trim();
        if (titleText != null && titleText.isNotEmpty) bookTitle = titleText;
        author = opfDoc.findAllElements('creator', namespace: '*').firstOrNull?.innerText.trim() ?? '';

        final idToHref = <String, String>{};
        String? ncxHref;
        String? navHref;
        for (final item in opfDoc.findAllElements('item', namespace: '*')) {
          final id = item.getAttribute('id') ?? '';
          final href = item.getAttribute('href') ?? '';
          final mediaType = item.getAttribute('media-type') ?? '';
          final props = item.getAttribute('properties') ?? '';
          if (id.isNotEmpty && href.isNotEmpty) {
            final resolved = opfDir == '.' ? href : p.posix.normalize('$opfDir/$href');
            final cleanHref = Uri.decodeFull(resolved).replaceAll('\\', '/');
            idToHref[id] = cleanHref;
            if (mediaType.contains('ncx') || cleanHref.toLowerCase().endsWith('.ncx')) {
              ncxHref = cleanHref;
            }
            if (props.split(RegExp(r'\s+')).contains('nav')) {
              navHref = cleanHref;
            }
          }
        }

        for (final itemref in opfDoc.findAllElements('itemref', namespace: '*')) {
          final idref = itemref.getAttribute('idref') ?? '';
          final target = idToHref[idref];
          if (target != null && !spinePaths.contains(target)) {
            spinePaths.add(target);
          }
        }

        // EPUB 3 Nav TOC support
        if (navHref != null) {
          final navFile = byLowerPath[navHref.toLowerCase()];
          if (navFile != null) {
            try {
              final navDir = p.posix.dirname(navHref);
              final navDoc = XmlDocument.parse(utf8.decode(navFile.content as List<int>, allowMalformed: true));
              for (final a in navDoc.findAllElements('a', namespace: '*')) {
                final href = a.getAttribute('href') ?? '';
                final label = a.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
                if (label.isNotEmpty && href.isNotEmpty) {
                  final srcNoFrag = href.split('#').first;
                  final resolved = navDir == '.' ? srcNoFrag : p.posix.normalize('$navDir/$srcNoFrag');
                  tocTitlesByHref.putIfAbsent(Uri.decodeFull(resolved).toLowerCase(), () => label);
                }
              }
            } catch (_) {}
          }
        }

        // EPUB 2 NCX TOC support
        if (ncxHref != null) {
          final ncxFile = byLowerPath[ncxHref.toLowerCase()];
          if (ncxFile != null) {
            try {
              final ncxDir = p.posix.dirname(ncxHref);
              final ncxDoc = XmlDocument.parse(utf8.decode(ncxFile.content as List<int>, allowMalformed: true));
              for (final nav in ncxDoc.findAllElements('navPoint', namespace: '*')) {
                final label = nav.findAllElements('text', namespace: '*').firstOrNull?.innerText.trim() ?? '';
                final rawSrc = nav.findAllElements('content', namespace: '*').firstOrNull?.getAttribute('src') ?? '';
                if (label.isNotEmpty && rawSrc.isNotEmpty) {
                  final srcNoFrag = rawSrc.split('#').first;
                  final resolved = ncxDir == '.' ? srcNoFrag : p.posix.normalize('$ncxDir/$srcNoFrag');
                  tocTitlesByHref.putIfAbsent(Uri.decodeFull(resolved).toLowerCase(), () => label);
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
  }

  // Fallback: if OPF/spine missing or empty, collect XHTML/HTML files alphabetically
  if (spinePaths.isEmpty) {
    final htmlFiles = archive.files
        .where((f) =>
            f.isFile &&
            !f.name.contains('__MACOSX') &&
            RegExp(r'\.(xhtml|html|htm)$', caseSensitive: false).hasMatch(f.name))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final f in htmlFiles) {
      spinePaths.add(f.name);
    }
  }

  // Build capped inline image cache (up to 48 images <= 1.2 MB each to protect memory)
  final imageDataUris = <String, String>{};
  for (final f in archive.files) {
    if (!f.isFile || f.size > 1200 * 1024 || imageDataUris.length >= 48) continue;
    final lower = f.name.toLowerCase();
    String? mime;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) mime = 'image/jpeg';
    else if (lower.endsWith('.png')) mime = 'image/png';
    else if (lower.endsWith('.webp')) mime = 'image/webp';
    else if (lower.endsWith('.gif')) mime = 'image/gif';
    else if (lower.endsWith('.svg')) mime = 'image/svg+xml';
    if (mime != null) {
      imageDataUris[f.name.replaceAll('\\', '/').toLowerCase()] =
          'data:$mime;base64,${base64Encode(f.content as List<int>)}';
    }
  }

  final chapters = <Map<String, String>>[];
  for (var i = 0; i < spinePaths.length; i++) {
    final rawPath = spinePaths[i];
    final key = rawPath.toLowerCase();
    final af = byLowerPath[key] ??
        archive.files.where((f) => f.isFile && f.name.toLowerCase().endsWith('/$key')).firstOrNull;
    if (af == null) continue;
    final content = utf8.decode(af.content as List<int>, allowMalformed: true);
    var title = tocTitlesByHref[key] ?? '';
    if (title.isEmpty) {
      final hMatch = RegExp(r'<h[1-3][^>]*>([\s\S]*?)</h[1-3]>', caseSensitive: false).firstMatch(content);
      if (hMatch != null) {
        title = hMatch.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      }
    }
    if (title.isEmpty) {
      final tMatch = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(content);
      if (tMatch != null) title = tMatch.group(1)!.trim();
    }
    if (title.isEmpty || title.length > 80) title = 'Section ${i + 1}';
    chapters.add({'title': title, 'path': rawPath, 'html': content});
  }

  return {
    'bookTitle': bookTitle,
    'author': author,
    'isEncrypted': false,
    'chapters': chapters,
    'images': imageDataUris,
  };
}

/// Flagship distraction-free EPUB Book Reader (`EpubReaderWidget`).
///
/// Features pure-Dart background unzip/OPF/NCX/Nav parsing (zero Chromium
/// local-server crashes on large/complex books like `lff_E.epub`), live
/// in-chapter + whole-book reading progress, 4 paper surfaces, Serif/Sans/Mono
/// typefaces, adjustable line spacing & margins, per-chapter bookmarks,
/// instant cross-book full-text search, and Read Aloud integration.
class EpubReaderWidget extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const EpubReaderWidget({
    super.key,
    required this.filePath,
    this.title = '',
    this.onClose,
  });

  @override
  State<EpubReaderWidget> createState() => _EpubReaderWidgetState();
}

enum _EpubFontFamily { serif, sans, mono }

class _EpubReaderWidgetState extends State<EpubReaderWidget> {
  _ParsedEpubBook? _book;
  bool _loading = true;
  String? _error;
  int _chapterIdx = 0;
  double _chapterScroll = 0.0;
  double _fontSize = 18.0;
  double _lineHeight = 1.72;
  double _marginH = 22.0;
  _EpubFontFamily _fontFamily = _EpubFontFamily.serif;
  ReaderTheme _theme = ReaderTheme.dark;

  bool _showChrome = true;
  bool _isScrubbing = false;
  int _scrubChapter = 0;
  List<int> _bookmarks = [];

  InAppWebViewController? _webCtrl;
  String? _plainFallbackText;
  bool _usePlainFallback = false;

  @override
  void initState() {
    super.initState();
    _loadEpub();
  }

  @override
  void dispose() {
    _savePosition();
    super.dispose();
  }

  Future<void> _savePosition() async {
    final total = _book?.chapters.length ?? 1;
    final current = _chapterIdx + 1;
    final progress = total > 0 ? ((_chapterIdx + _chapterScroll) / total).clamp(0.0, 1.0) : 0.0;
    try {
      await DocumentStateService.saveProgress(
        widget.filePath,
        title: _book?.bookTitle.isNotEmpty == true ? _book!.bookTitle : widget.title,
        currentPage: current,
        totalPages: total,
        scrollProgress: progress,
        theme: _theme,
        fontSize: _fontSize,
        bookmarks: _bookmarks,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('doc_pos_${widget.filePath.hashCode}', jsonEncode({
        'chapter': _chapterIdx,
        'scroll': _chapterScroll,
        'lineHeight': _lineHeight,
        'marginH': _marginH,
        'fontFamily': _fontFamily.index,
        'bookmarks': _bookmarks,
        'ts': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  Future<void> _loadEpub() async {
    try {
      final file = File(widget.filePath);
      if (!file.existsSync()) {
        setState(() {
          _error = 'File not found';
          _loading = false;
        });
        return;
      }

      final rawResult = await compute(_parseEpubIsolate, widget.filePath);
      final chaptersRaw = (rawResult['chapters'] as List).cast<Map<String, String>>();
      final imgs = (rawResult['images'] as Map).cast<String, String>();
      final parsed = _ParsedEpubBook(
        bookTitle: rawResult['bookTitle'] as String? ?? '',
        author: rawResult['author'] as String? ?? '',
        isEncrypted: rawResult['isEncrypted'] as bool? ?? false,
        chapters: [
          for (final c in chaptersRaw)
            _EpubChapter(title: c['title'] ?? 'Chapter', path: c['path'] ?? '', html: c['html'] ?? ''),
        ],
        imageDataUris: imgs,
      );

      if (parsed.isEncrypted) {
        if (mounted) {
          setState(() {
            _book = parsed;
            _error = 'This EPUB uses DRM encryption (META-INF/encryption.xml) and cannot be decrypted inline.';
            _loading = false;
          });
        }
        return;
      }

      final savedState = await DocumentStateService.getState(widget.filePath);
      var restoredIdx = 0;
      if (savedState != null && parsed.chapters.isNotEmpty) {
        restoredIdx = (savedState.currentPage - 1).clamp(0, parsed.chapters.length - 1);
        _theme = savedState.theme;
        _fontSize = savedState.fontSize.clamp(13.0, 28.0);
        if (savedState.bookmarks.isNotEmpty) _bookmarks = List<int>.from(savedState.bookmarks);
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawPref = prefs.getString('doc_pos_${widget.filePath.hashCode}');
        if (rawPref != null && parsed.chapters.isNotEmpty) {
          final map = jsonDecode(rawPref) as Map<String, dynamic>;
          if (savedState == null) {
            restoredIdx = ((map['chapter'] as int?) ?? 0).clamp(0, parsed.chapters.length - 1);
          }
          _chapterScroll = ((map['scroll'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0);
          _lineHeight = ((map['lineHeight'] as num?)?.toDouble() ?? 1.72).clamp(1.3, 2.2);
          _marginH = ((map['marginH'] as num?)?.toDouble() ?? 22.0).clamp(12.0, 42.0);
          final ffIdx = (map['fontFamily'] as int?) ?? 0;
          _fontFamily = _EpubFontFamily.values[ffIdx.clamp(0, _EpubFontFamily.values.length - 1)];
          if (_bookmarks.isEmpty && map['bookmarks'] is List) {
            _bookmarks = (map['bookmarks'] as List).whereType<int>().toList();
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _book = parsed;
        _chapterIdx = restoredIdx;
        _scrubChapter = restoredIdx;
        _loading = false;
      });
      _loadChapterIntoWebView();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not open EPUB: $e';
          _loading = false;
        });
      }
    }
  }

  static Map<String, dynamic> _parseEpubIsolate(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    return parseEpubBytes(bytes, fallbackTitle: p.basenameWithoutExtension(filePath));
  }

  Color get _surfaceBg => switch (_theme) {
        ReaderTheme.light => const Color(0xFFFFFFFF),
        ReaderTheme.sepia => const Color(0xFFF4ECD8),
        ReaderTheme.highContrast => const Color(0xFF000000),
        ReaderTheme.dark => const Color(0xFF0E1420),
      };

  Color get _surfaceFg => switch (_theme) {
        ReaderTheme.light => const Color(0xFF111827),
        ReaderTheme.sepia => const Color(0xFF3B2E1E),
        ReaderTheme.highContrast => const Color(0xFFFFFFFF),
        ReaderTheme.dark => const Color(0xFFE2E8F0),
      };

  Color get _chromeBg => switch (_theme) {
        ReaderTheme.light => const Color(0xFFF8FAFC),
        ReaderTheme.sepia => const Color(0xFFEBE1C8),
        ReaderTheme.highContrast => const Color(0xFF0A0A0A),
        ReaderTheme.dark => const Color(0xFF141826),
      };

  bool get _isLightPaper => _theme == ReaderTheme.light || _theme == ReaderTheme.sepia;

  String get _cssFontFamily => switch (_fontFamily) {
        _EpubFontFamily.serif => "Georgia, 'Times New Roman', Cambria, serif",
        _EpubFontFamily.sans => "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
        _EpubFontFamily.mono => "'JetBrains Mono', 'Fira Code', monospace",
      };

  String _styledChapterHtml(_EpubChapter chapter) {
    final bgHex = '#${(_surfaceBg.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final fgHex = '#${(_surfaceFg.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final accentHex = _isLightPaper ? '#4F46E5' : '#A78BFA';

    final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*?)</body>', caseSensitive: false).firstMatch(chapter.html);
    var body = bodyMatch?.group(1) ?? chapter.html;

    // Strip untrusted scripts/frames so our isolated tap+scroll bridge runs safely.
    body = body
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<iframe[\s\S]*?</iframe>', caseSensitive: false), '')
        .replaceAll(RegExp(r'''\son[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)''', caseSensitive: false), '');

    final chapterDir = p.posix.dirname(chapter.path);
    final imgMap = _book?.imageDataUris ?? const {};
    body = body.replaceAllMapped(
      RegExp(r'''(src\s*=\s*["'])([^"']+)(["'])''', caseSensitive: false),
      (m) {
        final rawSrc = m.group(2)!;
        if (rawSrc.startsWith('data:') || rawSrc.startsWith('http')) return m.group(0)!;
        final decoded = Uri.decodeFull(rawSrc.split('#').first).replaceAll('\\', '/');
        final resolved = (chapterDir == '.' ? decoded : p.posix.normalize('$chapterDir/$decoded')).toLowerCase();
        final dataUri = imgMap[resolved] ??
            imgMap.entries.where((e) => e.key.endsWith(p.posix.basename(decoded).toLowerCase())).firstOrNull?.value;
        if (dataUri != null) return '${m.group(1)}$dataUri${m.group(3)}';
        return m.group(0)!;
      },
    );

    final topInset = _showChrome ? 68 : 28;
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=4,user-scalable=yes">
<style id="makaw-reader-css">
  *{box-sizing:border-box}
  html,body{margin:0;padding:0;background:$bgHex;color:$fgHex;font-family:$_cssFontFamily;font-size:${_fontSize.toStringAsFixed(0)}px;line-height:${_lineHeight.toStringAsFixed(2)};word-wrap:break-word;-webkit-font-smoothing:antialiased}
  body{padding:${topInset}px ${_marginH.toStringAsFixed(0)}px 96px ${_marginH.toStringAsFixed(0)}px;max-width:740px;margin:0 auto}
  h1,h2,h3,h4{line-height:1.28;margin:1.2em 0 0.55em;color:$fgHex;font-weight:700;letter-spacing:-0.01em}
  p{margin:0.72em 0;text-align:justify;hyphens:auto}
  a{color:$accentHex;text-decoration:none}
  img,svg{max-width:100% !important;height:auto !important;display:block;margin:16px auto;border-radius:8px}
  blockquote{border-left:3px solid $accentHex;margin:1em 0;padding:0.45em 1em;opacity:0.9;font-style:italic}
  table{width:100%;border-collapse:collapse;margin:12px 0;font-size:0.9em}
  th,td{border:1px solid rgba(148,163,184,0.3);padding:6px 8px}
  pre,code{font-family:monospace;font-size:0.86em;overflow-x:auto}
</style>
</head>
<body>$body
<script>
(function(){
  var timer = null;
  window.addEventListener('scroll', function() {
    clearTimeout(timer);
    timer = setTimeout(function(){
      var doc = document.documentElement;
      var max = Math.max(1, (doc.scrollHeight || document.body.scrollHeight) - window.innerHeight);
      var pct = Math.min(1, Math.max(0, window.scrollY / max));
      if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('epubScroll', pct);
    }, 60);
  }, {passive:true});
  document.addEventListener('click', function(e) {
    if (e.target && e.target.closest && e.target.closest('a,button,summary')) return;
    var sel = window.getSelection ? window.getSelection().toString() : '';
    if (sel && sel.length > 0) return;
    if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('epubTap');
  });
})();
</script>
</body>
</html>''';
  }

  static String _htmlToPlainText(String html) {
    final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*?)</body>', caseSensitive: false).firstMatch(html);
    var s = bodyMatch?.group(1) ?? html;
    s = s
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<(?:br|p|div|h[1-6]|li|tr)[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  void _applyLiveTypography() {
    if (_usePlainFallback || _webCtrl == null) {
      _loadChapterIntoWebView();
      return;
    }
    final bgHex = '#${(_surfaceBg.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final fgHex = '#${(_surfaceFg.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final js = '''
      document.documentElement.style.background = '$bgHex';
      document.body.style.background = '$bgHex';
      document.body.style.color = '$fgHex';
      document.body.style.fontFamily = ${jsonEncode(_cssFontFamily)};
      document.body.style.fontSize = '${_fontSize.toStringAsFixed(0)}px';
      document.body.style.lineHeight = '${_lineHeight.toStringAsFixed(2)}';
      document.body.style.paddingLeft = '${_marginH.toStringAsFixed(0)}px';
      document.body.style.paddingRight = '${_marginH.toStringAsFixed(0)}px';
    ''';
    _webCtrl!.evaluateJavascript(source: js);
    _savePosition();
  }

  void _loadChapterIntoWebView() {
    final chapters = _book?.chapters ?? const [];
    if (chapters.isEmpty) return;
    final ch = chapters[_chapterIdx.clamp(0, chapters.length - 1)];
    if (_usePlainFallback) {
      setState(() => _plainFallbackText = _htmlToPlainText(ch.html));
    } else if (_webCtrl != null) {
      _webCtrl!.loadData(data: _styledChapterHtml(ch), mimeType: 'text/html', encoding: 'utf8');
    }
    _savePosition();
  }

  void _selectChapter(int idx) {
    final chapters = _book?.chapters ?? const [];
    if (chapters.isEmpty) return;
    final clamped = idx.clamp(0, chapters.length - 1);
    setState(() {
      _chapterIdx = clamped;
      _scrubChapter = clamped;
      _chapterScroll = 0.0;
    });
    _loadChapterIntoWebView();
  }

  void _toggleBookmark() {
    setState(() {
      if (_bookmarks.contains(_chapterIdx)) {
        _bookmarks.remove(_chapterIdx);
      } else {
        _bookmarks.add(_chapterIdx);
        _bookmarks.sort();
      }
    });
    HapticFeedback.selectionClick();
    _savePosition();
  }

  void _showTocSheet() {
    final chapters = _book?.chapters ?? const [];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141826),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          builder: (_, sc) => Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 34,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_rounded, color: Color(0xFFA78BFA), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _book?.bookTitle ?? 'Chapters',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_book?.author.isNotEmpty == true)
                            Text(
                              _book!.author,
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                indicatorColor: const Color(0xFFA78BFA),
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF94A3B8),
                tabs: [
                  Tab(text: 'Contents (${chapters.length})'),
                  Tab(text: 'Bookmarks (${_bookmarks.length})'),
                ],
              ),
              const Divider(color: Color(0xFF283148), height: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView.builder(
                      controller: sc,
                      itemCount: chapters.length,
                      itemBuilder: (_, i) {
                        final active = i == _chapterIdx;
                        final bookmarked = _bookmarks.contains(i);
                        return ListTile(
                          dense: true,
                          selected: active,
                          selectedTileColor: const Color(0xFFA78BFA).withValues(alpha: 0.14),
                          leading: SizedBox(
                            width: 28,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: active ? const Color(0xFFA78BFA) : const Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            chapters[i].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active ? Colors.white : Colors.white70,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                          trailing: bookmarked
                              ? const Icon(Icons.bookmark_rounded, color: Color(0xFFA78BFA), size: 17)
                              : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            _selectChapter(i);
                          },
                        );
                      },
                    ),
                    _bookmarks.isEmpty
                        ? const Center(
                            child: Text(
                              'Tap the bookmark icon in the header\nto save your favorite chapters.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _bookmarks.length,
                            itemBuilder: (_, i) {
                              final chIdx = _bookmarks[i].clamp(0, chapters.length - 1);
                              return ListTile(
                                leading: const Icon(Icons.bookmark_rounded, color: Color(0xFFA78BFA)),
                                title: Text(chapters[chIdx].title, style: const TextStyle(color: Colors.white)),
                                subtitle: Text('Chapter ${chIdx + 1} of ${chapters.length}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF94A3B8), size: 19),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    setState(() => _bookmarks.remove(chIdx));
                                    _savePosition();
                                  },
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _selectChapter(chIdx);
                                },
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchSheet() {
    final chapters = _book?.chapters ?? const [];
    final ctrl = TextEditingController();
    var hits = <_EpubSearchHit>[];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141826),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void runQuery(String q) {
            final cleanQ = q.trim().toLowerCase();
            if (cleanQ.length < 2) {
              setSheetState(() => hits = []);
              return;
            }
            final found = <_EpubSearchHit>[];
            for (var i = 0; i < chapters.length && found.length < 60; i++) {
              final plain = _htmlToPlainText(chapters[i].html);
              final idx = plain.toLowerCase().indexOf(cleanQ);
              if (idx != -1) {
                final start = (idx - 35).clamp(0, plain.length);
                final end = (idx + cleanQ.length + 75).clamp(0, plain.length);
                found.add(_EpubSearchHit(
                  chapterIndex: i,
                  chapterTitle: chapters[i].title,
                  snippet: plain.substring(start, end).replaceAll('\n', ' ').trim(),
                ));
              }
            }
            setSheetState(() => hits = found);
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.92,
            builder: (_, sc) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 10),
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search inside book...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFA78BFA)),
                        filled: true,
                        fillColor: const Color(0xFF1E2438),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onChanged: runQuery,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: hits.isEmpty
                        ? Center(
                            child: Text(
                              ctrl.text.trim().length < 2
                                  ? 'Type at least 2 characters to search chapters'
                                  : 'No matches found',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            controller: sc,
                            itemCount: hits.length,
                            separatorBuilder: (_, __) => const Divider(color: Color(0xFF283148), height: 1),
                            itemBuilder: (_, i) {
                              final h = hits[i];
                              return ListTile(
                                title: Text(h.chapterTitle, style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12.5, fontWeight: FontWeight.w700)),
                                subtitle: Text('...${h.snippet}...', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _selectChapter(h.chapterIndex);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAppearanceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141826),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void updateState(VoidCallback fn, {bool reloadHtml = false}) {
            setState(fn);
            setSheetState(() {});
            if (reloadHtml) {
              _loadChapterIntoWebView();
            } else {
              _applyLiveTypography();
            }
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Paper & Color', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _paperSwatch('Paper', ReaderTheme.light, Colors.white, const Color(0xFF111827), () => updateState(() => _theme = ReaderTheme.light)),
                      _paperSwatch('Sepia', ReaderTheme.sepia, const Color(0xFFF4ECD8), const Color(0xFF3B2E1E), () => updateState(() => _theme = ReaderTheme.sepia)),
                      _paperSwatch('Slate', ReaderTheme.dark, const Color(0xFF0E1420), const Color(0xFFE2E8F0), () => updateState(() => _theme = ReaderTheme.dark)),
                      _paperSwatch('OLED', ReaderTheme.highContrast, Colors.black, Colors.white, () => updateState(() => _theme = ReaderTheme.highContrast)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Typeface', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _fontChoice('Serif', _EpubFontFamily.serif, () => updateState(() => _fontFamily = _EpubFontFamily.serif)),
                      const SizedBox(width: 8),
                      _fontChoice('Sans', _EpubFontFamily.sans, () => updateState(() => _fontFamily = _EpubFontFamily.sans)),
                      const SizedBox(width: 8),
                      _fontChoice('Mono', _EpubFontFamily.mono, () => updateState(() => _fontFamily = _EpubFontFamily.mono)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text('Font Size', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 20),
                        onPressed: () => updateState(() => _fontSize = (_fontSize - 1).clamp(13.0, 28.0)),
                      ),
                      Text('${_fontSize.round()} pt', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 20),
                        onPressed: () => updateState(() => _fontSize = (_fontSize + 1).clamp(13.0, 28.0)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('Spacing', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      ChoiceChip(
                        label: const Text('Compact'),
                        selected: (_lineHeight - 1.45).abs() < 0.1,
                        onSelected: (_) => updateState(() => _lineHeight = 1.45),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Balanced'),
                        selected: (_lineHeight - 1.72).abs() < 0.1,
                        onSelected: (_) => updateState(() => _lineHeight = 1.72),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Airy'),
                        selected: (_lineHeight - 2.0).abs() < 0.1,
                        onSelected: (_) => updateState(() => _lineHeight = 2.0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: const Color(0xFFA78BFA),
                    title: const Text('Safe Plain Text Mode', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                    subtitle: const Text('Strips all HTML formatting for maximum stability', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                    value: _usePlainFallback,
                    onChanged: (v) => updateState(() => _usePlainFallback = v, reloadHtml: true),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _paperSwatch(String label, ReaderTheme t, Color fill, Color ink, VoidCallback onTap) {
    final selected = _theme == t;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFFA78BFA) : Colors.white24,
              width: selected ? 2.2 : 1,
            ),
          ),
          child: Center(
            child: Text(label, style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  Widget _fontChoice(String label, _EpubFontFamily ff, VoidCallback onTap) {
    final selected = _fontFamily == ff;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFA78BFA).withValues(alpha: 0.22) : const Color(0xFF1E2438),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? const Color(0xFFA78BFA) : Colors.white12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapters = _book?.chapters ?? const [];
    final title = _book?.bookTitle.isNotEmpty == true
        ? _book!.bookTitle
        : (widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath));
    final overallProgress = chapters.isNotEmpty
        ? ((_chapterIdx + _chapterScroll) / chapters.length).clamp(0.0, 1.0)
        : 0.0;
    final headerFg = _isLightPaper ? const Color(0xFF0F172A) : Colors.white;
    final headerSubFg = _isLightPaper ? const Color(0xFF4F46E5) : const Color(0xFFA78BFA);

    return Scaffold(
      backgroundColor: _surfaceBg,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(chapters)),

          // Top frosted reader header
          if (_showChrome)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
                decoration: BoxDecoration(
                  color: _chromeBg.withValues(alpha: 0.94),
                  border: Border(bottom: BorderSide(color: headerFg.withValues(alpha: 0.08))),
                ),
                child: SizedBox(
                  height: 54,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded, color: headerFg),
                        onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: chapters.isNotEmpty ? _showTocSheet : null,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: headerFg, fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              if (chapters.isNotEmpty)
                                Text(
                                  'Ch ${_chapterIdx + 1}/${chapters.length} · ${chapters[_chapterIdx].title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: headerSubFg, fontSize: 11.5, fontWeight: FontWeight.w500),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (chapters.isNotEmpty) ...[
                        IconButton(
                          icon: Icon(Icons.search_rounded, color: headerFg.withValues(alpha: 0.8), size: 20),
                          tooltip: 'Search in book',
                          onPressed: _showSearchSheet,
                        ),
                        IconButton(
                          icon: Icon(
                            _bookmarks.contains(_chapterIdx) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: _bookmarks.contains(_chapterIdx) ? headerSubFg : headerFg.withValues(alpha: 0.8),
                            size: 20,
                          ),
                          tooltip: 'Bookmark chapter',
                          onPressed: _toggleBookmark,
                        ),
                        IconButton(
                          icon: Icon(Icons.text_fields_rounded, color: headerFg.withValues(alpha: 0.8), size: 20),
                          tooltip: 'Paper & Typography',
                          onPressed: _showAppearanceSheet,
                        ),
                        IconButton(
                          icon: Icon(Icons.menu_book_rounded, color: headerFg.withValues(alpha: 0.8), size: 20),
                          tooltip: 'Chapters & Bookmarks',
                          onPressed: _showTocSheet,
                        ),
                        IconButton(
                          icon: Icon(Icons.record_voice_over_rounded, color: headerFg.withValues(alpha: 0.8), size: 19),
                          tooltip: 'Read Aloud',
                          onPressed: () {
                            final text = _htmlToPlainText(chapters[_chapterIdx].html);
                            if (text.isNotEmpty) showReadAloudDialog(context, text);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // Bottom reader navigation dock
          if (_showChrome && !_loading && chapters.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: _chromeBg.withValues(alpha: 0.95),
                padding: EdgeInsets.fromLTRB(10, 4, 10, MediaQuery.of(context).padding.bottom + 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isScrubbing && chapters.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Ch ${_scrubChapter + 1}: ${chapters[_scrubChapter].title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: headerSubFg, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (chapters.length > 1)
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2.5,
                          activeTrackColor: headerSubFg,
                          inactiveTrackColor: headerSubFg.withValues(alpha: 0.2),
                          thumbColor: headerSubFg,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: (_isScrubbing ? _scrubChapter : _chapterIdx).toDouble().clamp(0, (chapters.length - 1).toDouble()),
                          min: 0,
                          max: (chapters.length - 1).toDouble(),
                          onChanged: (v) => setState(() {
                            _isScrubbing = true;
                            _scrubChapter = v.round().clamp(0, chapters.length - 1);
                          }),
                          onChangeEnd: (v) {
                            setState(() => _isScrubbing = false);
                            _selectChapter(v.round());
                          },
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _chapterIdx > 0 ? () => _selectChapter(_chapterIdx - 1) : null,
                          icon: Icon(Icons.chevron_left_rounded, size: 20, color: headerFg),
                          label: Text('Prev', style: TextStyle(color: headerFg, fontSize: 13)),
                        ),
                        Text(
                          '${(overallProgress * 100).round()}% read  ·  ${_chapterIdx + 1}/${chapters.length}',
                          style: TextStyle(color: headerFg.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        TextButton.icon(
                          onPressed: _chapterIdx < chapters.length - 1 ? () => _selectChapter(_chapterIdx + 1) : null,
                          icon: Text('Next', style: TextStyle(color: headerFg, fontSize: 13)),
                          label: Icon(Icons.chevron_right_rounded, size: 20, color: headerFg),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Edge-to-edge hairline progress when chrome is tucked
          if (!_showChrome && !_loading && chapters.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: LinearProgressIndicator(
                  value: overallProgress,
                  minHeight: 2.5,
                  backgroundColor: headerFg.withValues(alpha: 0.08),
                  color: headerSubFg,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(List<_EpubChapter> chapters) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFA78BFA)));
    }
    if (_error != null || chapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_outlined, color: Color(0xFFA78BFA), size: 50),
              const SizedBox(height: 12),
              Text(
                _error ?? 'No readable chapters found inside this EPUB.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => OpenFilex.open(widget.filePath),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open Externally'),
              ),
            ],
          ),
        ),
      );
    }

    if (_usePlainFallback) {
      final text = _plainFallbackText ?? _htmlToPlainText(chapters[_chapterIdx].html);
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() => _showChrome = !_showChrome),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(_marginH, MediaQuery.of(context).padding.top + 68, _marginH, 100),
          child: SelectableText(
            text,
            contextMenuBuilder: buildLearningSelectionToolbar,
            style: TextStyle(color: _surfaceFg, fontSize: _fontSize, height: _lineHeight),
          ),
        ),
      );
    }

    final initialHtml = _styledChapterHtml(chapters[_chapterIdx]);
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: initialHtml,
        mimeType: 'text/html',
        encoding: 'utf8',
        baseUrl: WebUri('about:blank'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
      ),
      onWebViewCreated: (ctrl) {
        _webCtrl = ctrl;
        ctrl.addJavaScriptHandler(
          handlerName: 'epubTap',
          callback: (_) {
            if (mounted) setState(() => _showChrome = !_showChrome);
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'epubScroll',
          callback: (args) {
            if (!mounted || args.isEmpty) return;
            final pct = (args.first as num?)?.toDouble();
            if (pct != null && pct.isFinite && (pct - _chapterScroll).abs() >= 0.01) {
              setState(() => _chapterScroll = pct.clamp(0.0, 1.0));
            }
          },
        );
        enableWebviewLearningActions(controller: ctrl, context: context);
      },
      onLongPressHitTestResult: (ctrl, hit) => handleWebLongPress(context, hit),
    );
  }
}
