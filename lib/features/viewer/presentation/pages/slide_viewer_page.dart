import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../../../../core/utils/natural_sort.dart';
import '../../../documents/data/services/document_state_service.dart';

class _SlideData {
  final int index;
  final String title;
  final List<String> lines;
  final String notes;
  final Uint8List? previewImage;

  const _SlideData({
    required this.index,
    required this.title,
    required this.lines,
    this.notes = '',
    this.previewImage,
  });
}

/// Interactive Presentation & Slide Deck Viewer (`PPTX`, `PPTM`, `PPSX`, `POTX`,
/// `ODP`, `OTP`, `FODP`, `KEY`, plus text/metadata recovery for binary `PPT`).
class SlideViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const SlideViewerPage({
    super.key,
    required this.filePath,
    this.title = '',
    this.onClose,
  });

  @override
  State<SlideViewerPage> createState() => _SlideViewerPageState();
}

class _SlideViewerPageState extends State<SlideViewerPage> {
  final List<_SlideData> _slides = [];
  bool _loading = true;
  String? _error;
  bool _isLegacyBinary = false;
  bool _showNotes = false;
  int _currentSlide = 0;
  late PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _loadDeck();
  }

  @override
  void dispose() {
    _saveProgress();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProgress() async {
    if (_slides.isEmpty) return;
    await DocumentStateService.saveProgress(
      widget.filePath,
      title: widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath),
      currentPage: _currentSlide + 1,
      totalPages: _slides.length,
      scrollProgress: ((_currentSlide + 1) / _slides.length).clamp(0.0, 1.0),
    );
  }

  Future<void> _loadDeck() async {
    try {
      final file = File(widget.filePath);
      if (!file.existsSync()) {
        setState(() {
          _error = 'File not found';
          _loading = false;
        });
        return;
      }
      final ext = p.extension(widget.filePath).replaceAll('.', '').toLowerCase();
      final bytes = await file.readAsBytes();
      final slides = <_SlideData>[];

      if (ext == 'fodp') {
        slides.addAll(_parseOdpXml(utf8.decode(bytes, allowMalformed: true)));
      } else if (_looksLikeZip(bytes)) {
        final archive = ZipDecoder().decodeBytes(bytes);
        if (const {'pptx', 'pptm', 'ppsx', 'ppsm', 'potx', 'potm'}.contains(ext)) {
          slides.addAll(_parsePptx(archive));
        } else if (const {'odp', 'otp'}.contains(ext)) {
          final contentFile = archive.findFile('content.xml');
          if (contentFile != null) {
            slides.addAll(_parseOdpXml(utf8.decode(contentFile.content as List<int>, allowMalformed: true)));
          }
        } else if (ext == 'key') {
          slides.addAll(_parseKeynote(archive));
        }
      } else {
        // Legacy binary (.ppt / .pps / .sdd): try extracting clean printable runs
        final recovered = _recoverLegacyText(bytes);
        if (recovered.isNotEmpty) {
          for (var i = 0; i < recovered.length; i += 8) {
            final chunk = recovered.sublist(i, (i + 8).clamp(0, recovered.length));
            slides.add(_SlideData(
              index: slides.length + 1,
              title: chunk.first,
              lines: chunk.skip(1).toList(),
            ));
          }
        } else {
          _isLegacyBinary = true;
        }
      }

      final saved = await DocumentStateService.getState(widget.filePath);
      final restored = (saved != null && slides.isNotEmpty)
          ? (saved.currentPage - 1).clamp(0, slides.length - 1)
          : 0;

      if (!mounted) return;
      _pageCtrl.dispose();
      _pageCtrl = PageController(initialPage: restored);
      setState(() {
        _slides.addAll(slides);
        _currentSlide = restored;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not read presentation: $e';
          _loading = false;
        });
      }
    }
  }

  static bool _looksLikeZip(List<int> b) =>
      b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04;

  static List<_SlideData> _parsePptx(Archive archive) {
    final slideFiles = archive.files
        .where((f) => f.isFile && RegExp(r'^ppt/slides/slide\d+\.xml$', caseSensitive: false).hasMatch(f.name))
        .toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));

    final notesByNum = <String, String>{};
    for (final nf in archive.files) {
      final m = RegExp(r'^ppt/notesSlides/notesSlide(\d+)\.xml$', caseSensitive: false).firstMatch(nf.name);
      if (m != null && nf.isFile) {
        final raw = utf8.decode(nf.content as List<int>, allowMalformed: true);
        final lines = _extractXmlTextLines(raw, 't');
        if (lines.isNotEmpty) notesByNum[m.group(1)!] = lines.join('\n');
      }
    }

    final result = <_SlideData>[];
    for (var i = 0; i < slideFiles.length; i++) {
      final sf = slideFiles[i];
      final numMatch = RegExp(r'slide(\d+)\.xml', caseSensitive: false).firstMatch(sf.name);
      final slideNum = numMatch?.group(1) ?? '${i + 1}';
      final raw = utf8.decode(sf.content as List<int>, allowMalformed: true);
      final paragraphs = _extractPptxParagraphs(raw);
      final title = paragraphs.isNotEmpty ? paragraphs.first : 'Slide ${i + 1}';
      final body = paragraphs.length > 1 ? paragraphs.sublist(1) : const <String>[];
      result.add(_SlideData(
        index: i + 1,
        title: title,
        lines: body,
        notes: notesByNum[slideNum] ?? '',
      ));
    }
    return result;
  }

  static List<String> _extractPptxParagraphs(String xmlStr) {
    try {
      final doc = XmlDocument.parse(xmlStr);
      final out = <String>[];
      for (final pElem in doc.findAllElements('p', namespace: '*')) {
        final text = pElem
            .findAllElements('t', namespace: '*')
            .map((t) => t.innerText)
            .join('')
            .trim();
        if (text.isNotEmpty) out.add(text);
      }
      return out;
    } catch (_) {
      return _extractXmlTextLines(xmlStr, 't');
    }
  }

  static List<String> _extractXmlTextLines(String xmlStr, String tag) {
    try {
      final doc = XmlDocument.parse(xmlStr);
      return doc
          .findAllElements(tag, namespace: '*')
          .map((e) => e.innerText.trim())
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<_SlideData> _parseOdpXml(String xmlStr) {
    final result = <_SlideData>[];
    try {
      final doc = XmlDocument.parse(xmlStr);
      final pages = doc.findAllElements('page', namespace: '*');
      var idx = 0;
      for (final page in pages) {
        idx++;
        final lines = page
            .findAllElements('p', namespace: '*')
            .map((p) => p.innerText.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        final notes = page
            .findAllElements('notes', namespace: '*')
            .expand((n) => n.findAllElements('p', namespace: '*'))
            .map((p) => p.innerText.trim())
            .where((t) => t.isNotEmpty)
            .join('\n');
        result.add(_SlideData(
          index: idx,
          title: lines.isNotEmpty ? lines.first : 'Slide $idx',
          lines: lines.length > 1 ? lines.sublist(1) : const [],
          notes: notes,
        ));
      }
    } catch (_) {}
    return result;
  }

  static List<_SlideData> _parseKeynote(Archive archive) {
    final quickLookImgs = archive.files
        .where((f) =>
            f.isFile &&
            RegExp(r'QuickLook/.*\.(jpe?g|png)$', caseSensitive: false).hasMatch(f.name))
        .toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));
    if (quickLookImgs.isNotEmpty) {
      return [
        for (var i = 0; i < quickLookImgs.length; i++)
          _SlideData(
            index: i + 1,
            title: 'Keynote Preview ${i + 1}',
            lines: const [],
            previewImage: Uint8List.fromList(quickLookImgs[i].content as List<int>),
          ),
      ];
    }
    return const [];
  }

  static List<String> _recoverLegacyText(List<int> bytes) {
    final decoded = utf8.decode(bytes, allowMalformed: true);
    final matches = RegExp(r'[A-Za-z0-9][A-Za-z0-9 ,.:;\-\(\)/?!%]{8,140}').allMatches(decoded);
    final seen = <String>{};
    final out = <String>[];
    for (final m in matches) {
      final line = m.group(0)!.trim();
      if (line.contains('Microsoft') || line.contains('PowerPoint') || line.contains('Arial')) continue;
      if (seen.add(line)) out.add(line);
      if (out.length >= 120) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141826),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            if (_slides.isNotEmpty)
              Text('Slide ${_currentSlide + 1} of ${_slides.length}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
          ],
        ),
        actions: [
          if (_slides.isNotEmpty && _slides[_currentSlide].notes.isNotEmpty)
            IconButton(
              icon: Icon(_showNotes ? Icons.speaker_notes : Icons.speaker_notes_outlined, color: const Color(0xFFF59E0B)),
              tooltip: 'Speaker Notes',
              onPressed: () => setState(() => _showNotes = !_showNotes),
            ),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
            tooltip: 'Open Externally',
            onPressed: () => OpenFilex.open(widget.filePath),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.white60))));
    }
    if (_isLegacyBinary || _slides.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.slideshow_rounded, color: Color(0xFFF59E0B), size: 52),
              const SizedBox(height: 12),
              const Text('Presentation Preview Unavailable', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'This legacy or Apple Keynote deck contains binary streams not directly decoded inline. Open in your installed viewer app for full animations.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
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

    final activeSlide = _slides[_currentSlide];
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _slides.length,
            onPageChanged: (idx) {
              setState(() => _currentSlide = idx);
              _saveProgress();
            },
            itemBuilder: (_, idx) => _buildSlideCard(_slides[idx]),
          ),
        ),
        if (_showNotes && activeSlide.notes.isNotEmpty)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 150),
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(top: BorderSide(color: Color(0xFF334155))),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SPEAKER NOTES', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Text(activeSlide.notes, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45)),
                ],
              ),
            ),
          ),
        SizedBox(
          height: 74,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: _slides.length,
            itemBuilder: (_, idx) {
              final selected = idx == _currentSlide;
              final s = _slides[idx];
              return GestureDetector(
                onTap: () => _pageCtrl.animateToPage(idx, duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                child: Container(
                  width: 96,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFF59E0B).withValues(alpha: 0.18) : const Color(0xFF141826),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? const Color(0xFFF59E0B) : const Color(0xFF283148),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${s.index}', style: TextStyle(color: selected ? const Color(0xFFF59E0B) : Colors.white54, fontSize: 10, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Expanded(
                        child: Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSlideCard(_SlideData slide) {
    if (slide.previewImage != null) {
      return Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.memory(slide.previewImage!, fit: BoxFit.contain),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF334155)),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('SLIDE ${slide.index}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  slide.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1.25),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: slide.lines.isEmpty
                      ? const SizedBox.shrink()
                      : ListView.separated(
                          itemCount: slide.lines.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (_, i) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 6, right: 8),
                                child: Icon(Icons.circle, size: 6, color: Color(0xFFF59E0B)),
                              ),
                              Expanded(
                                child: Text(slide.lines[i], style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, height: 1.4)),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
