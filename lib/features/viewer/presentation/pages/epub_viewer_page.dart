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
import '../../../../core/ui/in_app_browser_sheet.dart';
import '../../../../core/ui/makaw_toast.dart';
import '../../../documents/data/services/document_state_service.dart';
import '../../../documents/domain/document_reader_contract.dart';

class _EpubChapter {
  final String title;
  final String path;
  final String html;
  final int wordCount;
  const _EpubChapter({
    required this.title,
    required this.path,
    required this.html,
    this.wordCount = 0,
  });
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

class _EpubHighlight {
  final String id;
  final int chapterIndex;
  final String quote;
  final String colorKey;
  final String note;
  final String createdAt;

  const _EpubHighlight({
    required this.id,
    required this.chapterIndex,
    required this.quote,
    required this.colorKey,
    this.note = '',
    this.createdAt = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'chapterIndex': chapterIndex,
        'quote': quote,
        'colorKey': colorKey,
        'note': note,
        'createdAt': createdAt,
      };

  factory _EpubHighlight.fromJson(Map<String, dynamic> m) => _EpubHighlight(
        id: m['id']?.toString() ?? '',
        chapterIndex: (m['chapterIndex'] as int?) ?? 0,
        quote: m['quote']?.toString() ?? '',
        colorKey: m['colorKey']?.toString() ?? 'yellow',
        note: m['note']?.toString() ?? '',
        createdAt: m['createdAt']?.toString() ?? '',
      );
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

/// Resolution result for an `<a href="...">` click inside an EPUB chapter.
class EpubLinkTarget {
  final int? chapterIndex;
  final String? fragment;
  final bool isExternalUrl;
  const EpubLinkTarget({
    this.chapterIndex,
    this.fragment,
    this.isExternalUrl = false,
  });
}

/// Resolves relative EPUB links (`ch05.xhtml#sec2`, `../Text/p3.xhtml`, `#note1`,
/// or `https://...`) cleanly against [chapterPaths] so internal navigation never
/// falls through to a blank `about:blank` page.
EpubLinkTarget resolveEpubChapterLink({
  required List<String> chapterPaths,
  required String currentChapterPath,
  required String href,
}) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return const EpubLinkTarget();

  final lower = trimmed.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('mailto:')) {
    return const EpubLinkTarget(isExternalUrl: true);
  }

  final hashIdx = trimmed.indexOf('#');
  final rawPathPart = (hashIdx == -1 ? trimmed : trimmed.substring(0, hashIdx)).split('?').first.trim();
  final fragment = (hashIdx != -1 && hashIdx + 1 < trimmed.length)
      ? Uri.decodeFull(trimmed.substring(hashIdx + 1))
      : null;

  if (rawPathPart.isEmpty || rawPathPart == 'about:blank') {
    final curIdx = chapterPaths.indexOf(currentChapterPath);
    return EpubLinkTarget(chapterIndex: curIdx >= 0 ? curIdx : null, fragment: fragment);
  }

  var cleanPath = rawPathPart;
  if (cleanPath.toLowerCase().startsWith('about:blank')) {
    cleanPath = cleanPath.substring('about:blank'.length).replaceFirst(RegExp(r'^/+'), '');
  }
  try {
    cleanPath = Uri.decodeFull(cleanPath);
  } catch (_) {}
  cleanPath = cleanPath.replaceAll('\\', '/');

  final currentDir = p.posix.dirname(currentChapterPath.replaceAll('\\', '/'));
  final resolved = (currentDir == '.' ? cleanPath : p.posix.normalize('$currentDir/$cleanPath'))
      .replaceFirst(RegExp(r'^/+'), '')
      .toLowerCase();
  final baseName = p.posix.basename(cleanPath).toLowerCase();

  for (var i = 0; i < chapterPaths.length; i++) {
    if (chapterPaths[i].replaceAll('\\', '/').toLowerCase() == resolved) {
      return EpubLinkTarget(chapterIndex: i, fragment: fragment);
    }
  }
  for (var i = 0; i < chapterPaths.length; i++) {
    final candidate = chapterPaths[i].replaceAll('\\', '/').toLowerCase();
    if (candidate.endsWith('/$resolved') || (baseName.isNotEmpty && p.posix.basename(candidate) == baseName)) {
      return EpubLinkTarget(chapterIndex: i, fragment: fragment);
    }
  }
  return EpubLinkTarget(fragment: fragment);
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

/// Physical-book EPUB Reader (`EpubReaderWidget`).
///
/// Features paginated swipe/tap page turning (plus Scroll toggle), live internal
/// EPUB anchor/chapter link resolution (`resolveEpubChapterLink`), 4-color pen
/// highlighter + marginalia notes, inline Dictionary Lookup (`TextActionService`),
/// word pronunciation, per-chapter Bookmark ribbon, reading time estimation,
/// Eye-Comfort Warmth filter, cross-book search, and two-page tablet spreads.
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
  static const Map<String, Color> _penColors = {
    'yellow': Color(0xFFFDE047),
    'green': Color(0xFF6EE7B7),
    'blue': Color(0xFF7DD3FC),
    'pink': Color(0xFFF9A8D4),
  };

  static const Map<String, String> _penCssRgba = {
    'yellow': 'rgba(253, 224, 71, 0.44)',
    'green': 'rgba(110, 231, 183, 0.42)',
    'blue': 'rgba(125, 211, 252, 0.42)',
    'pink': 'rgba(249, 168, 212, 0.42)',
  };

  _ParsedEpubBook? _book;
  bool _loading = true;
  String? _error;
  int _chapterIdx = 0;
  int _pageInChapter = 0;
  int _totalPagesInChapter = 1;
  double _chapterScroll = 0.0;
  double _fontSize = 18.0;
  double _lineHeight = 1.72;
  double _marginH = 24.0;
  double _warmthFilter = 0.0;
  bool _paginatedMode = true;
  _EpubFontFamily _fontFamily = _EpubFontFamily.serif;
  ReaderTheme _theme = ReaderTheme.dark;

  bool _showChrome = true;
  bool _isScrubbing = false;
  int _scrubChapter = 0;
  List<int> _bookmarks = [];
  List<_EpubHighlight> _highlights = [];

  String _selectedQuote = '';
  String _selectedParagraph = '';
  String? _pendingAnchorFragment;
  bool _jumpToLastPageOnLoad = false;

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
    final chFrac = _paginatedMode && _totalPagesInChapter > 1
        ? _pageInChapter / _totalPagesInChapter
        : _chapterScroll;
    final progress = total > 0 ? ((_chapterIdx + chFrac) / total).clamp(0.0, 1.0) : 0.0;
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
        'pageInChapter': _pageInChapter,
        'scroll': _chapterScroll,
        'lineHeight': _lineHeight,
        'marginH': _marginH,
        'warmth': _warmthFilter,
        'paginated': _paginatedMode,
        'fontFamily': _fontFamily.index,
        'bookmarks': _bookmarks,
        'ts': DateTime.now().toIso8601String(),
      }));
      await prefs.setString(
        'epub_hl_${widget.filePath.hashCode}',
        jsonEncode(_highlights.map((h) => h.toJson()).toList()),
      );
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
            _EpubChapter(
              title: c['title'] ?? 'Chapter',
              path: c['path'] ?? '',
              html: c['html'] ?? '',
              wordCount: _countWords(c['html'] ?? ''),
            ),
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
          _pageInChapter = (map['pageInChapter'] as int?) ?? 0;
          _chapterScroll = ((map['scroll'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0);
          _lineHeight = ((map['lineHeight'] as num?)?.toDouble() ?? 1.72).clamp(1.3, 2.2);
          _marginH = ((map['marginH'] as num?)?.toDouble() ?? 24.0).clamp(12.0, 42.0);
          _warmthFilter = ((map['warmth'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 0.45);
          _paginatedMode = (map['paginated'] as bool?) ?? true;
          final ffIdx = (map['fontFamily'] as int?) ?? 0;
          _fontFamily = _EpubFontFamily.values[ffIdx.clamp(0, _EpubFontFamily.values.length - 1)];
          if (_bookmarks.isEmpty && map['bookmarks'] is List) {
            _bookmarks = (map['bookmarks'] as List).whereType<int>().toList();
          }
        }
        final rawHl = prefs.getString('epub_hl_${widget.filePath.hashCode}');
        if (rawHl != null) {
          final list = jsonDecode(rawHl) as List;
          _highlights = list.whereType<Map<String, dynamic>>().map(_EpubHighlight.fromJson).toList();
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

  static int _countWords(String html) {
    final plain = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return RegExp(r'\b\w+\b').allMatches(plain).length;
  }

  static Map<String, dynamic> _parseEpubIsolate(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    return parseEpubBytes(bytes, fallbackTitle: p.basenameWithoutExtension(filePath));
  }

  Color get _surfaceBg => switch (_theme) {
        ReaderTheme.light => const Color(0xFFFFFFFF),
        ReaderTheme.sepia => const Color(0xFFF5ECD7),
        ReaderTheme.highContrast => const Color(0xFF000000),
        ReaderTheme.dark => const Color(0xFF0E1420),
      };

  Color get _surfaceFg => switch (_theme) {
        ReaderTheme.light => const Color(0xFF14181F),
        ReaderTheme.sepia => const Color(0xFF3A2D1D),
        ReaderTheme.highContrast => const Color(0xFFFFFFFF),
        ReaderTheme.dark => const Color(0xFFE2E8F0),
      };

  Color get _chromeBg => switch (_theme) {
        ReaderTheme.light => const Color(0xFFF8FAFC),
        ReaderTheme.sepia => const Color(0xFFECE0C4),
        ReaderTheme.highContrast => const Color(0xFF0A0A0A),
        ReaderTheme.dark => const Color(0xFF141826),
      };

  bool get _isLightPaper => _theme == ReaderTheme.light || _theme == ReaderTheme.sepia;

  String get _cssFontFamily => switch (_fontFamily) {
        _EpubFontFamily.serif => "Georgia, 'Times New Roman', Cambria, serif",
        _EpubFontFamily.sans => "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
        _EpubFontFamily.mono => "'JetBrains Mono', 'Fira Code', monospace",
      };

  String _styledChapterHtml(_EpubChapter chapter, {bool isSpread = false}) {
    final bgHex = '#${(_surfaceBg.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final fgHex = '#${(_surfaceFg.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final accentHex = _isLightPaper ? '#4F46E5' : '#A78BFA';
    final gutterShadow = _isLightPaper
        ? 'rgba(30, 41, 59, 0.08)'
        : 'rgba(0, 0, 0, 0.35)';

    final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*?)</body>', caseSensitive: false).firstMatch(chapter.html);
    var body = bodyMatch?.group(1) ?? chapter.html;

    // Strip untrusted scripts/frames so our isolated page-flip + link + highlighter bridge runs safely.
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

    final chapterHighlights = _highlights
        .where((h) => h.chapterIndex == _chapterIdx)
        .map((h) => {
              'id': h.id,
              'quote': h.quote,
              'rgba': _penCssRgba[h.colorKey] ?? _penCssRgba['yellow']!,
            })
        .toList();

    final marginPx = _marginH.toStringAsFixed(0);
    final gapPx = (_marginH * 2).toStringAsFixed(0);
    final topPad = 36;
    final botPad = 42;
    final colCountCss = _paginatedMode
        ? (isSpread
            ? 'column-width: calc((100vw - ${(marginPx)}px * 3) / 2); column-gap: ${marginPx}px;'
            : 'column-width: calc(100vw - ${gapPx}px); column-gap: ${gapPx}px;')
        : '';

    final pagedStyles = _paginatedMode
        ? '''
  html,body{margin:0;padding:0;width:100vw;height:100vh;overflow:hidden;background:$bgHex;color:$fgHex;user-select:text;-webkit-user-select:text}
  #makaw-viewport{position:relative;width:100vw;height:100vh;overflow:hidden;box-shadow:inset 10px 0 18px -12px $gutterShadow}
  #makaw-columns{
    box-sizing:border-box;
    height:100vh;
    padding:${topPad}px ${marginPx}px ${botPad}px ${marginPx}px;
    $colCountCss
    column-fill:auto;
    transition:transform 250ms cubic-bezier(0.22, 1, 0.36, 1);
    will-change:transform;
  }
  .makaw-page-edge{position:fixed;right:0;top:0;bottom:0;width:8px;pointer-events:none;background:linear-gradient(to left, $gutterShadow, transparent)}
'''
        : '''
  html,body{margin:0;padding:0;background:$bgHex;color:$fgHex;user-select:text;-webkit-user-select:text}
  #makaw-columns{padding:64px ${marginPx}px 110px ${marginPx}px;max-width:740px;margin:0 auto}
''';

    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=4,user-scalable=yes">
<style id="makaw-reader-css">
  *{box-sizing:border-box}
  $pagedStyles
  body{font-family:$_cssFontFamily;font-size:${_fontSize.toStringAsFixed(0)}px;line-height:${_lineHeight.toStringAsFixed(2)};word-wrap:break-word;-webkit-font-smoothing:antialiased}
  h1,h2,h3,h4{line-height:1.28;margin:0.8em 0 0.5em;color:$fgHex;font-weight:700;letter-spacing:-0.01em;break-after:avoid}
  p{margin:0.68em 0;text-align:justify;hyphens:auto;orphans:2;widows:2}
  a{color:$accentHex;text-decoration:underline;text-underline-offset:2px}
  img,svg{max-width:100% !important;max-height:74vh !important;width:auto !important;height:auto !important;display:block;margin:14px auto;border-radius:8px;break-inside:avoid}
  blockquote{border-left:3px solid $accentHex;margin:0.9em 0;padding:0.4em 0.9em;opacity:0.9;font-style:italic;break-inside:avoid}
  table{width:100%;border-collapse:collapse;margin:12px 0;font-size:0.9em}
  th,td{border:1px solid rgba(148,163,184,0.3);padding:6px 8px}
  mark.makaw-hl{border-radius:3px;padding:1px 0;color:inherit}
</style>
</head>
<body>
<div id="makaw-viewport">
  <div id="makaw-columns">$body</div>
  ${_paginatedMode ? '<div class="makaw-page-edge"></div>' : ''}
</div>
<script>
(function(){
  var paginated = $_paginatedMode;
  var initialPage = $_pageInChapter;
  var jumpLast = $_jumpToLastPageOnLoad;
  var anchorFrag = ${jsonEncode(_pendingAnchorFragment)};
  var savedHighlights = ${jsonEncode(chapterHighlights)};
  var cols = document.getElementById('makaw-columns');
  var totalPages = 1;
  var curPage = 0;

  function applyHighlightText(item) {
    if (!item || !item.quote || item.quote.length < 2) return;
    var walker = document.createTreeWalker(cols, NodeFilter.SHOW_TEXT, null, false);
    var target = item.quote;
    var node;
    while ((node = walker.nextNode())) {
      if (!node.nodeValue) continue;
      if (node.parentElement && node.parentElement.classList && node.parentElement.classList.contains('makaw-hl')) continue;
      var idx = node.nodeValue.indexOf(target);
      if (idx !== -1) {
        var range = document.createRange();
        range.setStart(node, idx);
        range.setEnd(node, idx + target.length);
        var mark = document.createElement('mark');
        mark.className = 'makaw-hl';
        mark.setAttribute('data-hl-id', item.id);
        mark.style.background = item.rgba;
        try {
          range.surroundContents(mark);
          return;
        } catch(e) {}
      }
    }
  }

  for (var h = 0; h < savedHighlights.length; h++) {
    applyHighlightText(savedHighlights[h]);
  }

  function recalcPages(keepPage) {
    if (!paginated) return;
    var vw = window.innerWidth || document.documentElement.clientWidth || 360;
    var sw = cols.scrollWidth;
    totalPages = Math.max(1, Math.round(sw / vw));
    if (jumpLast) {
      curPage = Math.max(0, totalPages - 1);
      jumpLast = false;
    } else if (keepPage !== undefined) {
      curPage = Math.max(0, Math.min(totalPages - 1, keepPage));
    } else {
      curPage = Math.max(0, Math.min(totalPages - 1, curPage));
    }
    cols.style.transform = 'translateX(-' + (curPage * vw) + 'px)';
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('epubPageMetrics', [curPage, totalPages]);
    }
  }

  function goToAnchor(frag) {
    if (!frag) return;
    var el = document.getElementById(frag) || document.querySelector('[name="' + CSS.escape(frag) + '"]');
    if (!el) return;
    if (paginated) {
      cols.style.transform = 'translateX(0px)';
      var vw = window.innerWidth || 360;
      var left = el.getBoundingClientRect().left;
      var targetPg = Math.max(0, Math.min(totalPages - 1, Math.floor(left / vw)));
      recalcPages(targetPg);
    } else {
      el.scrollIntoView({behavior:'smooth', block:'start'});
    }
  }

  window.__makawBookApi = {
    nextPage: function() {
      if (!paginated) return;
      if (curPage + 1 < totalPages) {
        recalcPages(curPage + 1);
      } else if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('epubTurnChapter', 1);
      }
    },
    prevPage: function() {
      if (!paginated) return;
      if (curPage > 0) {
        recalcPages(curPage - 1);
      } else if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('epubTurnChapter', -1);
      }
    },
    goToPage: function(idx) {
      recalcPages(idx);
    },
    addMark: function(id, rgba) {
      var sel = window.getSelection ? window.getSelection() : null;
      if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return;
      var mark = document.createElement('mark');
      mark.className = 'makaw-hl';
      mark.setAttribute('data-hl-id', id);
      mark.style.background = rgba;
      try {
        sel.getRangeAt(0).surroundContents(mark);
      } catch(e) {}
      sel.removeAllRanges();
    },
    removeMark: function(id) {
      var els = document.querySelectorAll('mark[data-hl-id="' + id + '"]');
      for (var i = 0; i < els.length; i++) {
        var m = els[i];
        var p = m.parentNode;
        while (m.firstChild) p.insertBefore(m.firstChild, m);
        p.removeChild(m);
      }
    }
  };

  window.addEventListener('load', function() {
    recalcPages(initialPage);
    if (anchorFrag) setTimeout(function(){ goToAnchor(anchorFrag); }, 80);
  });
  window.addEventListener('resize', function() { setTimeout(function(){ recalcPages(curPage); }, 80); });
  setTimeout(function() {
    recalcPages(initialPage);
    if (anchorFrag) goToAnchor(anchorFrag);
  }, 120);

  // Touch swipe page turning + edge zone taps (literal book feel!)
  var startX = 0, startY = 0, startTime = 0;
  document.addEventListener('touchstart', function(e) {
    if (e.touches.length !== 1) return;
    startX = e.touches[0].clientX;
    startY = e.touches[0].clientY;
    startTime = Date.now();
  }, {passive:true});

  document.addEventListener('touchend', function(e) {
    if (!paginated || e.changedTouches.length !== 1) return;
    var sel = window.getSelection ? window.getSelection().toString() : '';
    if (sel && sel.trim().length > 0) return;
    var dx = e.changedTouches[0].clientX - startX;
    var dy = e.changedTouches[0].clientY - startY;
    var dt = Date.now() - startTime;
    if (dt < 600 && Math.abs(dx) > 36 && Math.abs(dx) > Math.abs(dy) * 1.15) {
      if (dx < 0) window.__makawBookApi.nextPage();
      else window.__makawBookApi.prevPage();
    }
  }, {passive:true});

  // Intercept internal links cleanly (never open dead about:blank!), handle highlight tap, or edge-tap flip.
  document.addEventListener('click', function(e) {
    var link = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (link) {
      e.preventDefault();
      e.stopPropagation();
      var href = link.getAttribute('href') || '';
      if (href.startsWith('#')) {
        goToAnchor(href.substring(1));
      } else if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('epubLink', href);
      }
      return;
    }

    var hl = e.target && e.target.closest ? e.target.closest('mark.makaw-hl') : null;
    if (hl) {
      var id = hl.getAttribute('data-hl-id');
      if (id && window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('epubTapHighlight', id);
      }
      return;
    }

    var sel = window.getSelection ? window.getSelection().toString() : '';
    if (sel && sel.trim().length > 0) return;

    var vw = window.innerWidth || 360;
    if (paginated) {
      if (e.clientX < vw * 0.22) {
        window.__makawBookApi.prevPage();
        return;
      }
      if (e.clientX > vw * 0.78) {
        window.__makawBookApi.nextPage();
        return;
      }
    }
    if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('epubTap');
  }, true);

  // Scroll tracking for continuous scroll mode
  var scrollTimer = null;
  window.addEventListener('scroll', function() {
    if (paginated) return;
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(function(){
      var doc = document.documentElement;
      var max = Math.max(1, (doc.scrollHeight || document.body.scrollHeight) - window.innerHeight);
      var pct = Math.min(1, Math.max(0, window.scrollY / max));
      if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('epubScroll', pct);
    }, 60);
  }, {passive:true});

  // Non-intrusive selection watcher (powers Color Pen Highlighter + Dictionary + Pronunciation dock)
  var selTimer = null;
  function sendSelection() {
    clearTimeout(selTimer);
    selTimer = setTimeout(function(){
      var sel = window.getSelection ? window.getSelection() : null;
      var t = sel && !sel.isCollapsed ? sel.toString().trim() : '';
      var node = sel && sel.anchorNode ? (sel.anchorNode.nodeType === 3 ? sel.anchorNode.parentElement : sel.anchorNode) : null;
      var para = node && node.innerText ? node.innerText.trim() : t;
      if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('epubSelection', [t, para]);
      }
    }, 260);
  }
  document.addEventListener('selectionchange', sendSelection, false);
  document.addEventListener('touchend', sendSelection, false);
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

  void _loadChapterIntoWebView() {
    final chapters = _book?.chapters ?? const [];
    if (chapters.isEmpty) return;
    final ch = chapters[_chapterIdx.clamp(0, chapters.length - 1)];
    final isSpread = MediaQuery.maybeOf(context)?.size.width != null &&
        MediaQuery.of(context).size.width >= 760;
    if (_usePlainFallback) {
      setState(() => _plainFallbackText = _htmlToPlainText(ch.html));
    } else if (_webCtrl != null) {
      _webCtrl!.loadData(
        data: _styledChapterHtml(ch, isSpread: isSpread),
        mimeType: 'text/html',
        encoding: 'utf8',
      );
    }
    _pendingAnchorFragment = null;
    _jumpToLastPageOnLoad = false;
    _savePosition();
  }

  void _selectChapter(
    int idx, {
    String? anchorFragment,
    bool jumpToLastPage = false,
  }) {
    final chapters = _book?.chapters ?? const [];
    if (chapters.isEmpty) return;
    final clamped = idx.clamp(0, chapters.length - 1);
    setState(() {
      _chapterIdx = clamped;
      _scrubChapter = clamped;
      _pageInChapter = 0;
      _totalPagesInChapter = 1;
      _chapterScroll = 0.0;
      _selectedQuote = '';
      _pendingAnchorFragment = anchorFragment;
      _jumpToLastPageOnLoad = jumpToLastPage;
    });
    _loadChapterIntoWebView();
  }

  void _handleInternalLink(String rawHref) {
    final chapters = _book?.chapters ?? const [];
    if (chapters.isEmpty) return;
    final target = resolveEpubChapterLink(
      chapterPaths: chapters.map((c) => c.path).toList(),
      currentChapterPath: chapters[_chapterIdx].path,
      href: rawHref,
    );
    if (target.isExternalUrl) {
      MakawExternalLinks.open(context, rawHref, sourceTitle: _book?.bookTitle);
      return;
    }
    if (target.chapterIndex != null) {
      if (target.chapterIndex == _chapterIdx && target.fragment != null) {
        _webCtrl?.evaluateJavascript(
          source: "document.getElementById(${jsonEncode(target.fragment)})?.scrollIntoView({behavior:'smooth'});",
        );
      } else {
        _selectChapter(target.chapterIndex!, anchorFragment: target.fragment);
        MakawToast.info(
          context,
          chapters[target.chapterIndex!].title,
          title: 'Jumped to Section',
          duration: const Duration(milliseconds: 1600),
        );
      }
      return;
    }
    MakawToast.warning(context, 'Link target not found inside book package');
  }

  void _toggleBookmark() {
    setState(() {
      if (_bookmarks.contains(_chapterIdx)) {
        _bookmarks.remove(_chapterIdx);
        MakawToast.info(context, 'Bookmark removed');
      } else {
        _bookmarks.add(_chapterIdx);
        _bookmarks.sort();
        MakawToast.success(context, 'Page ${_pageInChapter + 1} · Ch ${_chapterIdx + 1}', title: 'Bookmarked');
      }
    });
    HapticFeedback.selectionClick();
    _savePosition();
  }

  Future<void> _addHighlight(String colorKey, {String note = ''}) async {
    final quote = _selectedQuote.trim();
    if (quote.isEmpty) return;
    final id = 'hl_${DateTime.now().microsecondsSinceEpoch}';
    final rgba = _penCssRgba[colorKey] ?? _penCssRgba['yellow']!;
    setState(() {
      _highlights.insert(
        0,
        _EpubHighlight(
          id: id,
          chapterIndex: _chapterIdx,
          quote: quote,
          colorKey: colorKey,
          note: note,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      _selectedQuote = '';
    });
    await _webCtrl?.evaluateJavascript(
      source: 'window.__makawBookApi && window.__makawBookApi.addMark(${jsonEncode(id)}, ${jsonEncode(rgba)});',
    );
    _savePosition();
    if (mounted) {
      MakawToast.success(context, note.isNotEmpty ? 'Highlight & note saved' : 'Passage highlighted');
    }
  }

  void _showHighlightActionSheet(String hlId) {
    final hl = _highlights.where((h) => h.id == hlId).firstOrNull;
    if (hl == null) return;
    final noteCtrl = TextEditingController(text: hl.note);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141826),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(ctx).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '"${hl.quote}"',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _penColors[hl.colorKey] ?? Colors.amberAccent, fontStyle: FontStyle.italic, fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Add a margin note...',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFF1E2438),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => _highlights.removeWhere((h) => h.id == hl.id));
                    _webCtrl?.evaluateJavascript(
                      source: 'window.__makawBookApi && window.__makawBookApi.removeMark(${jsonEncode(hl.id)});',
                    );
                    _savePosition();
                    MakawToast.info(context, 'Highlight erased');
                  },
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                  label: const Text('Erase', style: TextStyle(color: Colors.redAccent)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    TextActionService.pronounce(hl.quote);
                  },
                  child: const Text('Pronounce'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA78BFA), foregroundColor: Colors.black),
                  onPressed: () {
                    Navigator.pop(ctx);
                    final idx = _highlights.indexWhere((h) => h.id == hl.id);
                    if (idx >= 0) {
                      setState(() {
                        _highlights[idx] = _EpubHighlight(
                          id: hl.id,
                          chapterIndex: hl.chapterIndex,
                          quote: hl.quote,
                          colorKey: hl.colorKey,
                          note: noteCtrl.text.trim(),
                          createdAt: hl.createdAt,
                        );
                      });
                      _savePosition();
                      MakawToast.success(context, 'Note updated');
                    }
                  },
                  child: const Text('Save Note'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showNotePromptForSelection() {
    final ctrl = TextEditingController();
    var chosenColor = 'yellow';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141826),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(ctx).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Highlight & Note', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('"$_selectedQuote"', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 12.5)),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final e in _penColors.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => setSheetState(() => chosenColor = e.key),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: chosenColor == e.key ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Write your reflection or study note...',
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFF1E2438),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA78BFA), foregroundColor: Colors.black),
                onPressed: () {
                  Navigator.pop(ctx);
                  _addHighlight(chosenColor, note: ctrl.text.trim());
                },
                child: const Text('Save Highlight & Note'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTocSheet() {
    final chapters = _book?.chapters ?? const [];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141826),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DefaultTabController(
        length: 3,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
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
                labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(text: 'Contents (${chapters.length})'),
                  Tab(text: 'Bookmarks (${_bookmarks.length})'),
                  Tab(text: 'Highlights (${_highlights.length})'),
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
                        final estMin = (chapters[i].wordCount / 225).ceil().clamp(1, 180);
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
                          subtitle: Text('~$estMin min read', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5)),
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
                              'Tap the bookmark icon to mark your spot.',
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
                    _highlights.isEmpty
                        ? const Center(
                            child: Text(
                              'Long-press text while reading and pick\na color pen to highlight quotes & notes.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _highlights.length,
                            itemBuilder: (_, i) {
                              final h = _highlights[i];
                              final chIdx = h.chapterIndex.clamp(0, chapters.length - 1);
                              final color = _penColors[h.colorKey] ?? const Color(0xFFFDE047);
                              return ListTile(
                                leading: Container(width: 5, height: 38, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                                title: Text('"${h.quote}"', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                subtitle: Text(
                                  h.note.isNotEmpty ? '${chapters[chIdx].title} · Note: ${h.note}' : chapters[chIdx].title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void updateState(VoidCallback fn, {bool reloadHtml = false}) {
            setState(fn);
            setSheetState(() {});
            if (reloadHtml) {
              _loadChapterIntoWebView();
            } else {
              _savePosition();
            }
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
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
                      _paperSwatch('Paper', ReaderTheme.light, Colors.white, const Color(0xFF111827), () => updateState(() => _theme = ReaderTheme.light, reloadHtml: true)),
                      _paperSwatch('Sepia', ReaderTheme.sepia, const Color(0xFFF5ECD7), const Color(0xFF3A2D1D), () => updateState(() => _theme = ReaderTheme.sepia, reloadHtml: true)),
                      _paperSwatch('Slate', ReaderTheme.dark, const Color(0xFF0E1420), const Color(0xFFE2E8F0), () => updateState(() => _theme = ReaderTheme.dark, reloadHtml: true)),
                      _paperSwatch('OLED', ReaderTheme.highContrast, Colors.black, Colors.white, () => updateState(() => _theme = ReaderTheme.highContrast, reloadHtml: true)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Page Mode', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _fontChoice('Book Flip (Swipe)', _paginatedMode ? _EpubFontFamily.serif : _EpubFontFamily.mono, () => updateState(() => _paginatedMode = true, reloadHtml: true), forceSelected: _paginatedMode),
                      const SizedBox(width: 8),
                      _fontChoice('Continuous Scroll', _EpubFontFamily.sans, () => updateState(() => _paginatedMode = false, reloadHtml: true), forceSelected: !_paginatedMode),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Typeface', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _fontChoice('Serif', _EpubFontFamily.serif, () => updateState(() => _fontFamily = _EpubFontFamily.serif, reloadHtml: true)),
                      const SizedBox(width: 8),
                      _fontChoice('Sans', _EpubFontFamily.sans, () => updateState(() => _fontFamily = _EpubFontFamily.sans, reloadHtml: true)),
                      const SizedBox(width: 8),
                      _fontChoice('Mono', _EpubFontFamily.mono, () => updateState(() => _fontFamily = _EpubFontFamily.mono, reloadHtml: true)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Font Size', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 20),
                        onPressed: () => updateState(() => _fontSize = (_fontSize - 1).clamp(13.0, 28.0), reloadHtml: true),
                      ),
                      Text('${_fontSize.round()} pt', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 20),
                        onPressed: () => updateState(() => _fontSize = (_fontSize + 1).clamp(13.0, 28.0), reloadHtml: true),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Eye Warmth', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: _warmthFilter,
                          min: 0.0,
                          max: 0.45,
                          activeColor: const Color(0xFFF59E0B),
                          onChanged: (v) => updateState(() => _warmthFilter = v),
                        ),
                      ),
                      Text('${(_warmthFilter * 100 / 0.45).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Spacing', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      ChoiceChip(
                        label: const Text('Compact'),
                        selected: (_lineHeight - 1.45).abs() < 0.1,
                        onSelected: (_) => updateState(() => _lineHeight = 1.45, reloadHtml: true),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Balanced'),
                        selected: (_lineHeight - 1.72).abs() < 0.1,
                        onSelected: (_) => updateState(() => _lineHeight = 1.72, reloadHtml: true),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Airy'),
                        selected: (_lineHeight - 2.0).abs() < 0.1,
                        onSelected: (_) => updateState(() => _lineHeight = 2.0, reloadHtml: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: const Color(0xFFA78BFA),
                    title: const Text('Safe Plain Text Mode', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                    subtitle: const Text('Strips HTML layout for maximum stability', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
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

  Widget _fontChoice(String label, _EpubFontFamily ff, VoidCallback onTap, {bool? forceSelected}) {
    final selected = forceSelected ?? (_fontFamily == ff);
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12.5,
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
    final chFrac = chapters.isNotEmpty
        ? (_paginatedMode && _totalPagesInChapter > 1 ? _pageInChapter / _totalPagesInChapter : _chapterScroll)
        : 0.0;
    final overallProgress = chapters.isNotEmpty
        ? ((_chapterIdx + chFrac) / chapters.length).clamp(0.0, 1.0)
        : 0.0;
    final remainingWords = chapters.skip(_chapterIdx).fold<int>(0, (sum, c) => sum + c.wordCount);
    final remMins = (remainingWords / 225).ceil().clamp(1, 9999);
    final estTimeLabel = remMins >= 60 ? '${remMins ~/ 60}h ${remMins % 60}m left' : '~$remMins min left';

    final headerFg = _isLightPaper ? const Color(0xFF0F172A) : Colors.white;
    final headerSubFg = _isLightPaper ? const Color(0xFF4F46E5) : const Color(0xFFA78BFA);
    final isBookmarked = _bookmarks.contains(_chapterIdx);

    return Scaffold(
      backgroundColor: _surfaceBg,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(chapters)),

          // Subtle physical book footer & warmth overlay
          if (_warmthFilter > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Color.fromRGBO(255, 176, 66, _warmthFilter)),
              ),
            ),

          if (!_loading && chapters.isNotEmpty && _paginatedMode && !_usePlainFallback)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + (_showChrome ? 102 : 8),
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        chapters[_chapterIdx].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: headerFg.withValues(alpha: 0.42), fontSize: 10.5),
                      ),
                    ),
                    Text(
                      'p. ${_pageInChapter + 1} / $_totalPagesInChapter  ·  ${(overallProgress * 100).round()}%',
                      style: TextStyle(color: headerFg.withValues(alpha: 0.45), fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

          // Physical corner Bookmark Ribbon when page/chapter is bookmarked
          if (!_loading && chapters.isNotEmpty && isBookmarked)
            Positioned(
              top: MediaQuery.of(context).padding.top + (_showChrome ? 54 : 0),
              right: 22,
              child: GestureDetector(
                onTap: _toggleBookmark,
                child: Container(
                  width: 22,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE11D48),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
                    boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
                  ),
                  child: const Icon(Icons.bookmark_rounded, color: Colors.white, size: 13),
                ),
              ),
            ),

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
                            isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: isBookmarked ? const Color(0xFFE11D48) : headerFg.withValues(alpha: 0.8),
                            size: 20,
                          ),
                          tooltip: 'Bookmark spot',
                          onPressed: _toggleBookmark,
                        ),
                        IconButton(
                          icon: Icon(Icons.text_fields_rounded, color: headerFg.withValues(alpha: 0.8), size: 20),
                          tooltip: 'Paper, Page Flip & Typography',
                          onPressed: _showAppearanceSheet,
                        ),
                        IconButton(
                          icon: Icon(Icons.menu_book_rounded, color: headerFg.withValues(alpha: 0.8), size: 20),
                          tooltip: 'Contents, Bookmarks & Highlights',
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

          // Non-modal Selection Pen + Dictionary Meaning + Pronunciation Bar
          if (_selectedQuote.isNotEmpty)
            Positioned(
              left: 14,
              right: 14,
              bottom: MediaQuery.of(context).padding.bottom + (_showChrome ? 104 : 18),
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xF5141826),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.45)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in _penColors.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => _addHighlight(e.key),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: e.value,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                              ),
                            ),
                          ),
                        const VerticalDivider(color: Colors.white24, width: 12),
                        _selToolBtn(Icons.volume_up_rounded, 'Pronounce', () => TextActionService.pronounce(_selectedQuote)),
                        _selToolBtn(Icons.menu_book_rounded, 'Meaning', () => showDefineDialog(context, _selectedQuote)),
                        _selToolBtn(Icons.edit_note_rounded, 'Note', _showNotePromptForSelection),
                        _selToolBtn(Icons.record_voice_over_rounded, 'Read', () => showReadAloudDialog(context, _selectedParagraph.isNotEmpty ? _selectedParagraph : _selectedQuote)),
                        _selToolBtn(Icons.copy_rounded, 'Copy', () {
                          Clipboard.setData(ClipboardData(text: _selectedQuote));
                          MakawToast.success(context, 'Passage copied to clipboard');
                          setState(() => _selectedQuote = '');
                        }),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 17),
                          onPressed: () => setState(() => _selectedQuote = ''),
                        ),
                      ],
                    ),
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
                          label: Text('Prev Ch', style: TextStyle(color: headerFg, fontSize: 12.5)),
                        ),
                        Text(
                          '${(overallProgress * 100).round()}% · $estTimeLabel',
                          style: TextStyle(color: headerFg.withValues(alpha: 0.72), fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                        TextButton.icon(
                          onPressed: _chapterIdx < chapters.length - 1 ? () => _selectChapter(_chapterIdx + 1) : null,
                          icon: Text('Next Ch', style: TextStyle(color: headerFg, fontSize: 12.5)),
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

  Widget _selToolBtn(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFFA78BFA), size: 16),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

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
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -300 && _chapterIdx < chapters.length - 1) _selectChapter(_chapterIdx + 1);
          if (v > 300 && _chapterIdx > 0) _selectChapter(_chapterIdx - 1);
        },
        onTap: () => setState(() => _showChrome = !_showChrome),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(_marginH, MediaQuery.of(context).padding.top + 68, _marginH, 108),
          child: SelectableText(
            text,
            contextMenuBuilder: buildLearningSelectionToolbar,
            style: TextStyle(color: _surfaceFg, fontSize: _fontSize, height: _lineHeight),
          ),
        ),
      );
    }

    final isSpread = MediaQuery.of(context).size.width >= 760;
    final initialHtml = _styledChapterHtml(chapters[_chapterIdx], isSpread: isSpread);
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: initialHtml,
        mimeType: 'text/html',
        encoding: 'utf8',
        baseUrl: WebUri('about:blank'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
      ),
      shouldOverrideUrlLoading: (_, navAction) async {
        final rawUrl = navAction.request.url?.toString() ?? '';
        if (rawUrl.isEmpty || rawUrl == 'about:blank') return NavigationActionPolicy.ALLOW;
        _handleInternalLink(rawUrl);
        return NavigationActionPolicy.CANCEL;
      },
      onWebViewCreated: (ctrl) {
        _webCtrl = ctrl;
        ctrl.addJavaScriptHandler(
          handlerName: 'epubTap',
          callback: (_) {
            if (mounted) {
              setState(() {
                _selectedQuote = '';
                _showChrome = !_showChrome;
              });
            }
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'epubLink',
          callback: (args) {
            if (!mounted || args.isEmpty) return;
            final href = args.first?.toString() ?? '';
            if (href.isNotEmpty) _handleInternalLink(href);
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'epubPageMetrics',
          callback: (args) {
            if (!mounted || args.isEmpty || args.first is! List) return;
            final list = args.first as List;
            if (list.length >= 2) {
              final pg = (list[0] as num?)?.toInt() ?? 0;
              final tot = (list[1] as num?)?.toInt() ?? 1;
              if (pg != _pageInChapter || tot != _totalPagesInChapter) {
                setState(() {
                  _pageInChapter = pg.clamp(0, (tot - 1).clamp(0, 999999));
                  _totalPagesInChapter = tot.clamp(1, 999999);
                });
              }
            }
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'epubTurnChapter',
          callback: (args) {
            if (!mounted || args.isEmpty) return;
            final delta = (args.first as num?)?.toInt() ?? 0;
            if (delta > 0 && _chapterIdx < chapters.length - 1) {
              _selectChapter(_chapterIdx + 1);
            } else if (delta < 0 && _chapterIdx > 0) {
              _selectChapter(_chapterIdx - 1, jumpToLastPage: true);
            } else {
              MakawToast.info(context, delta > 0 ? 'End of book reached' : 'First page of book');
            }
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
        ctrl.addJavaScriptHandler(
          handlerName: 'epubSelection',
          callback: (args) {
            if (!mounted || args.isEmpty || args.first is! List) return;
            final list = args.first as List;
            final sel = list.isNotEmpty ? (list[0]?.toString() ?? '').trim() : '';
            final para = list.length > 1 ? (list[1]?.toString() ?? '').trim() : '';
            if (sel != _selectedQuote) {
              setState(() {
                _selectedQuote = sel;
                _selectedParagraph = para;
              });
            }
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'epubTapHighlight',
          callback: (args) {
            if (!mounted || args.isEmpty) return;
            final hlId = args.first?.toString() ?? '';
            if (hlId.isNotEmpty) _showHighlightActionSheet(hlId);
          },
        );
      },
      onLongPressHitTestResult: (ctrl, hit) => handleWebLongPress(context, hit),
    );
  }
}
