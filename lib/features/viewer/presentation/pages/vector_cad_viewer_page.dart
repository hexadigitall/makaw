import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../../../documents/data/services/document_state_service.dart';
import '../../../documents/domain/document_format_registry.dart';
import '../../../pdf/presentation/pages/pdf_viewer_page.dart';

/// Vector, Print & CAD Viewer (`SVG`, `DXF`, `EPS`, `PS`, `XPS`, `OXPS`,
/// `VSDX`, `ODG`, `AI`, plus binary CAD metadata inspection).
class VectorCadViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const VectorCadViewerPage({
    super.key,
    required this.filePath,
    this.title = '',
    this.onClose,
  });

  @override
  State<VectorCadViewerPage> createState() => _VectorCadViewerPageState();
}

class _VectorCadViewerPageState extends State<VectorCadViewerPage> {
  bool _loading = true;
  bool _redirectToPdf = false;
  String? _svgHtml;
  _DxfDrawing? _dxf;
  EpsPsDocument? _eps;
  String? _rawSource;
  bool _showRawSource = false;
  String? _summary;
  bool _lightCanvas = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.filePath);
      if (!file.existsSync()) {
        setState(() {
          _summary = 'File not found';
          _loading = false;
        });
        return;
      }
      final ext = p.extension(widget.filePath).replaceAll('.', '').toLowerCase();
      final bytes = await file.readAsBytes();

      // Adobe Illustrator CS+ PDF-compatible .ai files open natively in pdfrx!
      if (ext == 'ai' && DocumentFormatRegistry.looksLikePdfBytes(bytes)) {
        if (mounted) {
          setState(() {
            _redirectToPdf = true;
            _loading = false;
          });
        }
        return;
      }

      if (ext == 'svg') {
        final rawSvg = utf8.decode(bytes, allowMalformed: true);
        _rawSource = rawSvg;
        _svgHtml = _wrapSvgHtml(rawSvg);
      } else if (ext == 'dxf') {
        final rawDxf = utf8.decode(bytes, allowMalformed: true);
        _rawSource = rawDxf;
        _dxf = _DxfDrawing.parse(rawDxf);
      } else if (ext == 'eps' || ext == 'ps' || _looksLikePostScript(bytes)) {
        final parsed = EpsPsDocument.parse(bytes);
        _eps = parsed;
        _rawSource = parsed.rawPostScript;
      } else if (DocumentFormatRegistry.looksLikeZipBytes(bytes)) {
        final archive = ZipDecoder().decodeBytes(bytes);
        if (ext == 'xps' || ext == 'oxps') {
          final xpsBody = convertXpsArchiveToHtmlBody(archive);
          if (xpsBody != null) {
            _svgHtml = _wrapMultiSvgHtml(xpsBody);
          }
        }
        if (_svgHtml == null) {
          final svgEntry = archive.files
              .where((f) => f.isFile && f.name.toLowerCase().endsWith('.svg'))
              .firstOrNull;
          if (svgEntry != null) {
            _svgHtml = _wrapSvgHtml(utf8.decode(svgEntry.content as List<int>, allowMalformed: true));
          } else {
            final textNotes = _extractPackageText(archive);
            final fileCount = archive.files.where((f) => f.isFile).length;
            _summary = textNotes.isNotEmpty
                ? '${ext.toUpperCase()} package ($fileCount parts)\n\n$textNotes'
                : '${ext.toUpperCase()} package inspected ($fileCount internal parts).';
          }
        }
      } else {
        final headerAscii = utf8.decode(bytes.take(64).toList(), allowMalformed: true).trim();
        _summary = 'Format: ${ext.toUpperCase()}\nSize: ${(bytes.length / 1024).toStringAsFixed(1)} KB\nHeader signature: ${headerAscii.split('\n').first}';
      }

      await DocumentStateService.saveProgress(
        widget.filePath,
        title: widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath),
        currentPage: 1,
        totalPages: 1,
        scrollProgress: 1.0,
      );

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _summary = 'Could not load vector file: $e';
          _loading = false;
        });
      }
    }
  }

  static bool _looksLikePostScript(List<int> bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0xC5 &&
        bytes[1] == 0xD0 &&
        bytes[2] == 0xD3 &&
        bytes[3] == 0xC6) {
      return true;
    }
    final head = utf8.decode(bytes.take(16).toList(), allowMalformed: true);
    return head.startsWith('%!PS-Adobe');
  }

  static String _extractPackageText(Archive archive) {
    final buf = StringBuffer();
    for (final f in archive.files) {
      if (!f.isFile || !f.name.toLowerCase().endsWith('.xml')) continue;
      try {
        final doc = XmlDocument.parse(utf8.decode(f.content as List<int>, allowMalformed: true));
        for (final node in doc.findAllElements('Text', namespace: '*')) {
          final t = node.innerText.trim();
          if (t.isNotEmpty) buf.writeln('• $t');
        }
        for (final node in doc.findAllElements('p', namespace: '*')) {
          final t = node.innerText.trim();
          if (t.isNotEmpty) buf.writeln('• $t');
        }
      } catch (_) {}
      if (buf.length > 3000) break;
    }
    return buf.toString().trim();
  }

  String _wrapSvgHtml(String svgBody) => '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=8,user-scalable=yes">
<style>html,body{margin:0;padding:12px;width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:${_lightCanvas ? '#F8FAFC' : '#0A0F1A'};}
svg{max-width:100%;max-height:100%;width:auto;height:auto;}</style>
</head><body>$svgBody</body></html>''';

  String _wrapMultiSvgHtml(String pagesHtml) => '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=8,user-scalable=yes">
<style>
  *{box-sizing:border-box}
  html,body{margin:0;padding:14px;background:${_lightCanvas ? '#E2E8F0' : '#0A0F1A'};font-family:sans-serif}
  .xps-page{background:#FFFFFF;border-radius:8px;margin:0 auto 16px auto;box-shadow:0 4px 16px rgba(0,0,0,0.35);overflow:hidden;max-width:860px}
  .xps-page svg{width:100%;height:auto;display:block}
</style>
</head><body>$pagesHtml</body></html>''';

  @override
  Widget build(BuildContext context) {
    if (_redirectToPdf) {
      return MakawPdfViewerPage(
        filePath: widget.filePath,
        title: widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath),
        onClose: widget.onClose,
      );
    }
    final name = widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath);
    final hasCanvas = _svgHtml != null || _dxf != null || (_eps != null && _eps!.hasRenderableContent);
    return Scaffold(
      backgroundColor: _lightCanvas ? const Color(0xFFF8FAFC) : const Color(0xFF0A0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141826),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
        ),
        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
        actions: [
          if (_rawSource != null && _rawSource!.isNotEmpty)
            IconButton(
              icon: Icon(_showRawSource ? Icons.brush_rounded : Icons.code_rounded, color: Colors.white70, size: 20),
              tooltip: _showRawSource ? 'Vector Preview' : 'Inspect Source',
              onPressed: () => setState(() => _showRawSource = !_showRawSource),
            ),
          if (hasCanvas)
            IconButton(
              icon: Icon(_lightCanvas ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: Colors.white70, size: 20),
              tooltip: 'Toggle Canvas Theme',
              onPressed: () {
                setState(() {
                  _lightCanvas = !_lightCanvas;
                  if (_svgHtml != null) {
                    _load();
                  }
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
            onPressed: () => OpenFilex.open(widget.filePath),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE879F9)));

    if (_showRawSource && _rawSource != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          _rawSource!.length > 150000 ? '${_rawSource!.substring(0, 150000)}\n... [truncated]' : _rawSource!,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.45,
            color: _lightCanvas ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
      );
    }

    if (_svgHtml != null) {
      return InAppWebView(
        initialData: InAppWebViewInitialData(data: _svgHtml!, baseUrl: WebUri('about:blank')),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: false,
          supportZoom: true,
          builtInZoomControls: true,
          displayZoomControls: false,
        ),
      );
    }

    if (_eps != null) {
      final eps = _eps!;
      if (!eps.hasRenderableContent) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.polyline_rounded, color: Color(0xFFE879F9), size: 52),
                const SizedBox(height: 12),
                Text(
                  eps.metadataSummary,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  children: [
                    if (eps.rawPostScript.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _showRawSource = true),
                        icon: const Icon(Icons.code_rounded, size: 17),
                        label: const Text('Inspect PostScript'),
                      ),
                    ElevatedButton.icon(
                      onPressed: () => OpenFilex.open(widget.filePath),
                      icon: const Icon(Icons.open_in_new_rounded, size: 17),
                      label: const Text('Open Externally'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      return Stack(
        children: [
          InteractiveViewer(
            minScale: 0.4,
            maxScale: 20.0,
            child: SizedBox.expand(
              child: CustomPaint(
                painter: _EpsPainter(eps, lightMode: _lightCanvas),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: Text(
                '${eps.ops.length} paths · ${eps.labels.length} text runs${eps.previewPixels.isNotEmpty ? ' · preview bitmap' : ''}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      );
    }

    if (_dxf != null) {
      return Stack(
        children: [
          InteractiveViewer(
            minScale: 0.4,
            maxScale: 20.0,
            child: SizedBox.expand(
              child: CustomPaint(
                painter: _DxfPainter(_dxf!, lightMode: _lightCanvas),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'DXF Entities: ${_dxf!.lines.length} lines · ${_dxf!.circles.length} circles',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.architecture_rounded, color: Color(0xFFE879F9), size: 52),
              const SizedBox(height: 12),
              Text(_summary ?? 'Binary Vector / CAD Format', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => OpenFilex.open(widget.filePath),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open in External App'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Converts all `*.fpage` files in an XPS/OXPS ZIP archive into clean inline SVGs.
@visibleForTesting
String? convertXpsArchiveToHtmlBody(Archive archive) {
  final pages = archive.files
      .where((f) => f.isFile && f.name.toLowerCase().endsWith('.fpage'))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (pages.isEmpty) return null;

  final buf = StringBuffer();
  const esc = HtmlEscape();
  for (final pf in pages.take(40)) {
    try {
      final doc = XmlDocument.parse(utf8.decode(pf.content as List<int>, allowMalformed: true));
      final root = doc.rootElement;
      final width = double.tryParse(root.getAttribute('Width') ?? '') ?? 816;
      final height = double.tryParse(root.getAttribute('Height') ?? '') ?? 1056;
      buf.write('<div class="xps-page"><svg viewBox="0 0 $width $height" xmlns="http://www.w3.org/2000/svg">');

      for (final el in doc.descendants.whereType<XmlElement>()) {
        final local = el.name.local;
        if (local == 'Path') {
          final data = el.getAttribute('Data');
          if (data == null || data.isEmpty) continue;
          final fill = _xpsColorToCss(el.getAttribute('Fill')) ?? 'none';
          final stroke = _xpsColorToCss(el.getAttribute('Stroke')) ?? (fill == 'none' ? '#0F172A' : 'none');
          final sw = el.getAttribute('StrokeThickness') ?? '1';
          buf.write('<path d="${esc.convert(data)}" fill="$fill" stroke="$stroke" stroke-width="$sw"/>');
        } else if (local == 'Glyphs') {
          final txt = el.getAttribute('UnicodeString');
          if (txt == null || txt.isEmpty) continue;
          final x = double.tryParse(el.getAttribute('OriginX') ?? '') ?? 0;
          final y = double.tryParse(el.getAttribute('OriginY') ?? '') ?? 20;
          final fs = double.tryParse(el.getAttribute('FontRenderingEmSize') ?? '') ?? 14;
          final fill = _xpsColorToCss(el.getAttribute('Fill')) ?? '#0F172A';
          buf.write('<text x="$x" y="$y" font-size="$fs" fill="$fill">${esc.convert(txt)}</text>');
        }
      }
      buf.write('</svg></div>');
    } catch (_) {}
  }
  return buf.isNotEmpty ? buf.toString() : null;
}

String? _xpsColorToCss(String? raw) {
  if (raw == null || raw.isEmpty || !raw.startsWith('#')) return null;
  final hex = raw.substring(1);
  if (hex.length == 8) {
    // XPS uses #AARRGGBB; CSS hex prefers #RRGGBB
    return '#${hex.substring(2)}';
  }
  return '#$hex';
}

class EpsDrawOp {
  final Path path;
  final Color color;
  final bool fill;
  final double strokeWidth;
  const EpsDrawOp({
    required this.path,
    required this.color,
    required this.fill,
    required this.strokeWidth,
  });
}

class EpsLabel {
  final Offset pos;
  final String text;
  final Color color;
  const EpsLabel({required this.pos, required this.text, required this.color});
}

/// Pure-Dart EPS / PostScript vector path & EPSI preview parser.
class EpsPsDocument {
  final Rect boundingBox;
  final List<EpsDrawOp> ops;
  final List<EpsLabel> labels;
  final List<Rect> previewPixels;
  final int previewWidth;
  final int previewHeight;
  final String title;
  final String creator;
  final String rawPostScript;

  const EpsPsDocument({
    required this.boundingBox,
    required this.ops,
    required this.labels,
    required this.previewPixels,
    required this.previewWidth,
    required this.previewHeight,
    required this.title,
    required this.creator,
    required this.rawPostScript,
  });

  bool get hasRenderableContent => ops.isNotEmpty || labels.isNotEmpty || previewPixels.isNotEmpty;

  String get metadataSummary {
    final parts = <String>[];
    if (title.isNotEmpty) parts.add('Title: $title');
    if (creator.isNotEmpty) parts.add('Creator: $creator');
    parts.add('BoundingBox: ${boundingBox.left.round()} ${boundingBox.top.round()} ${boundingBox.right.round()} ${boundingBox.bottom.round()}');
    parts.add('Extracted: ${ops.length} paths · ${labels.length} labels');
    if (!hasRenderableContent) {
      parts.add('Binary/compressed PostScript procedures detected without plain vector strokes.');
    }
    return parts.join('\n');
  }

  factory EpsPsDocument.parse(List<int> bytes) {
    var psBytes = bytes;
    // DOS EPS Binary Header (C5 D0 D3 C6): slice the PostScript payload range.
    if (bytes.length >= 12 &&
        bytes[0] == 0xC5 &&
        bytes[1] == 0xD0 &&
        bytes[2] == 0xD3 &&
        bytes[3] == 0xC6) {
      final psStart = _readLeUint32(bytes, 4);
      final psLen = _readLeUint32(bytes, 8);
      if (psStart < bytes.length && psLen > 0) {
        final psEnd = math.min(bytes.length, psStart + psLen);
        psBytes = bytes.sublist(psStart, psEnd);
      }
    }

    final rawPs = utf8.decode(psBytes, allowMalformed: true);
    var title = '';
    var creator = '';
    Rect? bbox;

    for (final line in rawPs.split(RegExp(r'\r?\n')).take(120)) {
      if (line.startsWith('%%Title:')) {
        title = line.substring(8).trim();
      } else if (line.startsWith('%%Creator:')) {
        creator = line.substring(10).trim();
      } else if (bbox == null &&
          (line.startsWith('%%BoundingBox:') || line.startsWith('%%HiResBoundingBox:'))) {
        final nums = RegExp(r'-?\d+(?:\.\d+)?')
            .allMatches(line)
            .map((m) => double.tryParse(m.group(0)!))
            .whereType<double>()
            .toList();
        if (nums.length >= 4 && nums[2] > nums[0] && nums[3] > nums[1]) {
          bbox = Rect.fromLTRB(nums[0], nums[1], nums[2], nums[3]);
        }
      }
    }

    // Parse optional monochrome EPSI %%BeginPreview hex bitmap
    final previewPixels = <Rect>[];
    var previewW = 0, previewH = 0;
    final prevMatch = RegExp(
      r'%%BeginPreview:\s*(\d+)\s+(\d+)\s+(\d+)\s+\d+([\s\S]*?)%%EndPreview',
      caseSensitive: false,
    ).firstMatch(rawPs);
    if (prevMatch != null) {
      previewW = int.tryParse(prevMatch.group(1)!) ?? 0;
      previewH = int.tryParse(prevMatch.group(2)!) ?? 0;
      final depth = int.tryParse(prevMatch.group(3)!) ?? 1;
      if (previewW > 0 && previewH > 0 && previewW <= 512 && previewH <= 512 && depth == 1) {
        final hexStr = prevMatch.group(4)!.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
        final bytesPerRow = (previewW + 7) ~/ 8;
        for (var y = 0; y < previewH; y++) {
          for (var bx = 0; bx < bytesPerRow; bx++) {
            final idx = (y * bytesPerRow + bx) * 2;
            if (idx + 2 > hexStr.length) break;
            final val = int.tryParse(hexStr.substring(idx, idx + 2), radix: 16) ?? 0;
            for (var bit = 0; bit < 8; bit++) {
              final x = bx * 8 + bit;
              if (x < previewW && ((val >> (7 - bit)) & 1) == 1) {
                previewPixels.add(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1));
              }
            }
          }
        }
      }
    }

    // Lightweight stack-based ASCII PostScript drawing interpreter
    final ops = <EpsDrawOp>[];
    final labels = <EpsLabel>[];
    final stack = <dynamic>[];
    var curPath = ui.Path();
    var curX = 0.0, curY = 0.0;
    var hasCur = false;
    var color = const Color(0xFF38BDF8);
    var strokeW = 1.0;
    var tx = 0.0, ty = 0.0, sx = 1.0, sy = 1.0;
    final stateStack = <({Color color, double strokeW, double tx, double ty, double sx, double sy})>[];

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    void track(double x, double y) {
      if (!x.isFinite || !y.isFinite) return;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    double mapX(double x) => x * sx + tx;
    double mapY(double y) => y * sy + ty;

    double popNum([double fallback = 0.0]) {
      while (stack.isNotEmpty) {
        final v = stack.removeLast();
        if (v is num) return v.toDouble();
      }
      return fallback;
    }

    String popStr() {
      while (stack.isNotEmpty) {
        final v = stack.removeLast();
        if (v is String) return v;
      }
      return '';
    }

    // Limit token scan on huge files to protect main isolate memory/latency.
    final tokens = _tokenizePostScript(rawPs.length > 250000 ? rawPs.substring(0, 250000) : rawPs);
    for (final tok in tokens) {
      if (tok.startsWith('(') && tok.endsWith(')')) {
        stack.add(tok.substring(1, tok.length - 1));
        continue;
      }
      final numVal = double.tryParse(tok);
      if (numVal != null) {
        stack.add(numVal);
        if (stack.length > 256) stack.removeAt(0);
        continue;
      }

      switch (tok) {
        case 'newpath':
        case 'n':
          curPath = ui.Path();
          hasCur = false;
          break;
        case 'closepath':
        case 'h':
          curPath.close();
          break;
        case 'moveto':
        case 'm':
          final y = mapY(popNum());
          final x = mapX(popNum());
          curPath.moveTo(x, y);
          curX = x;
          curY = y;
          hasCur = true;
          track(x, y);
          break;
        case 'rmoveto':
          final dy = popNum() * sy;
          final dx = popNum() * sx;
          curX += dx;
          curY += dy;
          curPath.moveTo(curX, curY);
          hasCur = true;
          track(curX, curY);
          break;
        case 'lineto':
        case 'l':
          final y = mapY(popNum());
          final x = mapX(popNum());
          if (!hasCur) {
            curPath.moveTo(x, y);
            hasCur = true;
          } else {
            curPath.lineTo(x, y);
          }
          curX = x;
          curY = y;
          track(x, y);
          break;
        case 'rlineto':
          final dy = popNum() * sy;
          final dx = popNum() * sx;
          curX += dx;
          curY += dy;
          if (!hasCur) {
            curPath.moveTo(curX, curY);
            hasCur = true;
          } else {
            curPath.lineTo(curX, curY);
          }
          track(curX, curY);
          break;
        case 'curveto':
        case 'c':
          final y3 = mapY(popNum());
          final x3 = mapX(popNum());
          final y2 = mapY(popNum());
          final x2 = mapX(popNum());
          final y1 = mapY(popNum());
          final x1 = mapX(popNum());
          if (!hasCur) curPath.moveTo(x1, y1);
          curPath.cubicTo(x1, y1, x2, y2, x3, y3);
          curX = x3;
          curY = y3;
          hasCur = true;
          track(x1, y1);
          track(x2, y2);
          track(x3, y3);
          break;
        case 'rectfill':
        case 'rectstroke':
          final h = popNum() * sy;
          final w = popNum() * sx;
          final y = mapY(popNum());
          final x = mapX(popNum());
          final rPath = ui.Path()..addRect(Rect.fromLTWH(x, y, w, h));
          track(x, y);
          track(x + w, y + h);
          ops.add(EpsDrawOp(
            path: rPath,
            color: color,
            fill: tok == 'rectfill',
            strokeWidth: strokeW,
          ));
          break;
        case 'arc':
          final a2 = popNum();
          final a1 = popNum();
          final r = popNum().abs() * ((sx.abs() + sy.abs()) / 2);
          final cy = mapY(popNum());
          final cx = mapX(popNum());
          final startRad = a1 * math.pi / 180;
          final sweepRad = (a2 - a1) * math.pi / 180;
          curPath.arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r), startRad, sweepRad, !hasCur);
          hasCur = true;
          track(cx - r, cy - r);
          track(cx + r, cy + r);
          break;
        case 'stroke':
        case 'S':
        case 's':
          if (tok == 's') curPath.close();
          ops.add(EpsDrawOp(path: curPath, color: color, fill: false, strokeWidth: strokeW));
          curPath = ui.Path();
          hasCur = false;
          break;
        case 'fill':
        case 'eofill':
        case 'f':
        case 'F':
          ops.add(EpsDrawOp(path: curPath, color: color, fill: true, strokeWidth: strokeW));
          curPath = ui.Path();
          hasCur = false;
          break;
        case 'B':
          ops.add(EpsDrawOp(path: curPath, color: color, fill: true, strokeWidth: strokeW));
          ops.add(EpsDrawOp(path: curPath, color: color, fill: false, strokeWidth: strokeW));
          curPath = ui.Path();
          hasCur = false;
          break;
        case 'setlinewidth':
        case 'w':
          strokeW = popNum(1.0).clamp(0.3, 24.0);
          break;
        case 'setgray':
        case 'g':
        case 'G':
          final gray = (popNum(0.0).clamp(0.0, 1.0) * 255).round();
          color = Color.fromARGB(255, gray, gray, gray);
          break;
        case 'setrgbcolor':
        case 'rg':
        case 'RG':
          final b = (popNum(0.0).clamp(0.0, 1.0) * 255).round();
          final g = (popNum(0.0).clamp(0.0, 1.0) * 255).round();
          final r = (popNum(0.0).clamp(0.0, 1.0) * 255).round();
          color = Color.fromARGB(255, r, g, b);
          break;
        case 'setcmykcolor':
          final k = popNum(0.0).clamp(0.0, 1.0);
          final yC = popNum(0.0).clamp(0.0, 1.0);
          final m = popNum(0.0).clamp(0.0, 1.0);
          final c = popNum(0.0).clamp(0.0, 1.0);
          final r = ((1.0 - c) * (1.0 - k) * 255).round().clamp(0, 255);
          final g = ((1.0 - m) * (1.0 - k) * 255).round().clamp(0, 255);
          final b = ((1.0 - yC) * (1.0 - k) * 255).round().clamp(0, 255);
          color = Color.fromARGB(255, r, g, b);
          break;
        case 'translate':
          final dy = popNum();
          final dx = popNum();
          tx += dx * sx;
          ty += dy * sy;
          break;
        case 'scale':
          final nsy = popNum(1.0);
          final nsx = popNum(1.0);
          sx *= nsx;
          sy *= nsy;
          break;
        case 'gsave':
        case 'q':
          stateStack.add((color: color, strokeW: strokeW, tx: tx, ty: ty, sx: sx, sy: sy));
          break;
        case 'grestore':
        case 'Q':
          if (stateStack.isNotEmpty) {
            final st = stateStack.removeLast();
            color = st.color;
            strokeW = st.strokeW;
            tx = st.tx;
            ty = st.ty;
            sx = st.sx;
            sy = st.sy;
          }
          break;
        case 'show':
          final str = popStr().trim();
          if (str.isNotEmpty) {
            labels.add(EpsLabel(pos: Offset(curX, curY), text: str, color: color));
            track(curX, curY);
          }
          break;
        default:
          break;
      }
      if (ops.length >= 6000) break;
    }

    final finalBox = bbox ??
        (minX.isFinite && maxX > minX && maxY > minY
            ? Rect.fromLTRB(minX, minY, maxX, maxY)
            : const Rect.fromLTWH(0, 0, 200, 200));

    return EpsPsDocument(
      boundingBox: finalBox,
      ops: ops,
      labels: labels,
      previewPixels: previewPixels,
      previewWidth: previewW,
      previewHeight: previewH,
      title: title,
      creator: creator,
      rawPostScript: rawPs,
    );
  }

  static int _readLeUint32(List<int> b, int offset) =>
      b[offset] | (b[offset + 1] << 8) | (b[offset + 2] << 16) | (b[offset + 3] << 24);

  static List<String> _tokenizePostScript(String src) {
    final tokens = <String>[];
    var i = 0;
    final len = src.length;
    while (i < len) {
      final ch = src.codeUnitAt(i);
      if (ch == 0x25) {
        // `%` comment until newline
        while (i < len && src.codeUnitAt(i) != 0x0A && src.codeUnitAt(i) != 0x0D) {
          i++;
        }
        continue;
      }
      if (ch <= 0x20 || ch == 0x7B || ch == 0x7D || ch == 0x5B || ch == 0x5D) {
        i++;
        continue;
      }
      if (ch == 0x28) {
        // PostScript balanced string literal `( ... )`
        final start = i++;
        var depth = 1;
        while (i < len && depth > 0) {
          final c = src.codeUnitAt(i);
          if (c == 0x5C && i + 1 < len) {
            i += 2;
            continue;
          }
          if (c == 0x28) depth++;
          if (c == 0x29) depth--;
          i++;
        }
        tokens.add(src.substring(start, i));
        continue;
      }
      final start = i;
      while (i < len) {
        final c = src.codeUnitAt(i);
        if (c <= 0x20 || c == 0x25 || c == 0x28 || c == 0x29 || c == 0x7B || c == 0x7D || c == 0x5B || c == 0x5D) {
          break;
        }
        i++;
      }
      tokens.add(src.substring(start, i));
    }
    return tokens;
  }
}

class _EpsPainter extends CustomPainter {
  final EpsPsDocument doc;
  final bool lightMode;
  const _EpsPainter(this.doc, {required this.lightMode});

  @override
  void paint(Canvas canvas, Size size) {
    if (doc.ops.isEmpty && doc.labels.isEmpty && doc.previewPixels.isNotEmpty) {
      final pw = math.max(1.0, doc.previewWidth.toDouble());
      final ph = math.max(1.0, doc.previewHeight.toDouble());
      final s = math.min((size.width - 40) / pw, (size.height - 40) / ph);
      final ox = (size.width - pw * s) / 2;
      final oy = (size.height - ph * s) / 2;
      final paint = Paint()
        ..color = lightMode ? const Color(0xFF0F172A) : Colors.white
        ..style = PaintingStyle.fill;
      for (final r in doc.previewPixels) {
        canvas.drawRect(Rect.fromLTWH(ox + r.left * s, oy + r.top * s, math.max(1, s), math.max(1, s)), paint);
      }
      return;
    }

    final box = doc.boundingBox;
    final w = math.max(1.0, box.width);
    final h = math.max(1.0, box.height);
    final scale = math.min((size.width - 44) / w, (size.height - 44) / h);
    final dx = (size.width - w * scale) / 2 - box.left * scale;
    final dy = (size.height - h * scale) / 2 + box.bottom * scale;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, -scale);

    for (final op in doc.ops) {
      final adaptiveColor = (!lightMode && op.color.computeLuminance() < 0.08)
          ? Colors.white
          : (lightMode && op.color.computeLuminance() > 0.92 ? const Color(0xFF0F172A) : op.color);
      final paint = Paint()
        ..color = adaptiveColor
        ..style = op.fill ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = math.max(0.8 / scale, op.strokeWidth)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(op.path, paint);
    }
    canvas.restore();

    for (final lbl in doc.labels) {
      final adaptiveColor = !lightMode ? Colors.white : const Color(0xFF0F172A);
      final tp = TextPainter(
        text: TextSpan(text: lbl.text, style: TextStyle(color: adaptiveColor, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lbl.pos.dx * scale + dx, dy - lbl.pos.dy * scale - tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _EpsPainter oldDelegate) =>
      oldDelegate.doc != doc || oldDelegate.lightMode != lightMode;
}

class _DxfLine {
  final Offset a;
  final Offset b;
  const _DxfLine(this.a, this.b);
}

class _DxfCircle {
  final Offset center;
  final double radius;
  const _DxfCircle(this.center, this.radius);
}

class _DxfDrawing {
  final List<_DxfLine> lines;
  final List<_DxfCircle> circles;
  final Rect bounds;

  const _DxfDrawing(this.lines, this.circles, this.bounds);

  factory _DxfDrawing.parse(String raw) {
    final tokens = raw.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
    final lines = <_DxfLine>[];
    final circles = <_DxfCircle>[];

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    void track(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    var i = 0;
    while (i + 1 < tokens.length) {
      if (tokens[i] == '0' && tokens[i + 1] == 'LINE') {
        double x1 = 0, y1 = 0, x2 = 0, y2 = 0;
        i += 2;
        while (i + 1 < tokens.length && tokens[i] != '0') {
          final code = tokens[i];
          final val = double.tryParse(tokens[i + 1]);
          if (val != null) {
            if (code == '10') x1 = val;
            if (code == '20') y1 = val;
            if (code == '11') x2 = val;
            if (code == '21') y2 = val;
          }
          i += 2;
        }
        track(x1, y1);
        track(x2, y2);
        lines.add(_DxfLine(Offset(x1, y1), Offset(x2, y2)));
        continue;
      }
      if (tokens[i] == '0' && tokens[i + 1] == 'CIRCLE') {
        double cx = 0, cy = 0, r = 0;
        i += 2;
        while (i + 1 < tokens.length && tokens[i] != '0') {
          final code = tokens[i];
          final val = double.tryParse(tokens[i + 1]);
          if (val != null) {
            if (code == '10') cx = val;
            if (code == '20') cy = val;
            if (code == '40') r = val;
          }
          i += 2;
        }
        track(cx - r, cy - r);
        track(cx + r, cy + r);
        circles.add(_DxfCircle(Offset(cx, cy), r));
        continue;
      }
      i++;
    }

    final rect = minX.isFinite ? Rect.fromLTRB(minX, minY, maxX, maxY) : const Rect.fromLTWH(0, 0, 100, 100);
    return _DxfDrawing(lines, circles, rect);
  }
}

class _DxfPainter extends CustomPainter {
  final _DxfDrawing dxf;
  final bool lightMode;
  const _DxfPainter(this.dxf, {required this.lightMode});

  @override
  void paint(Canvas canvas, Size size) {
    final w = math.max(1.0, dxf.bounds.width);
    final h = math.max(1.0, dxf.bounds.height);
    final scale = math.min((size.width - 40) / w, (size.height - 40) / h);
    final dx = (size.width - w * scale) / 2 - dxf.bounds.left * scale;
    final dy = (size.height - h * scale) / 2 + dxf.bounds.bottom * scale;

    Offset map(Offset pt) => Offset(pt.dx * scale + dx, dy - pt.dy * scale);

    final paint = Paint()
      ..color = lightMode ? const Color(0xFF0F172A) : const Color(0xFF38BDF8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (final line in dxf.lines) {
      canvas.drawLine(map(line.a), map(line.b), paint);
    }
    for (final circle in dxf.circles) {
      canvas.drawCircle(map(circle.center), circle.radius * scale, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DxfPainter oldDelegate) =>
      oldDelegate.dxf != dxf || oldDelegate.lightMode != lightMode;
}
