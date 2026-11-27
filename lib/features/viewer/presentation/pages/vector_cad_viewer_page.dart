import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../../../documents/data/services/document_state_service.dart';
import '../../../documents/domain/document_format_registry.dart';
import '../../../pdf/presentation/pages/pdf_viewer_page.dart';

/// Vector, Print & CAD Viewer (`SVG`, `DXF`, `XPS`, `OXPS`, `VSDX`, `ODG`, `AI`,
/// plus honest metadata/fallback inspection for `DWG`, `PS`, `EPS`, `VSD`, `CDR`).
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
        _svgHtml = _wrapSvgHtml(rawSvg);
      } else if (ext == 'dxf') {
        final rawDxf = utf8.decode(bytes, allowMalformed: true);
        _dxf = _DxfDrawing.parse(rawDxf);
      } else if (DocumentFormatRegistry.looksLikeZipBytes(bytes)) {
        final archive = ZipDecoder().decodeBytes(bytes);
        final svgEntry = archive.files
            .where((f) => f.isFile && f.name.toLowerCase().endsWith('.svg'))
            .firstOrNull;
        if (svgEntry != null) {
          _svgHtml = _wrapSvgHtml(utf8.decode(svgEntry.content as List<int>, allowMalformed: true));
        } else {
          final fileCount = archive.files.where((f) => f.isFile).length;
          _summary = '${ext.toUpperCase()} package inspected ($fileCount internal parts). Native full-fidelity vector conversion is scheduled in Phase D.';
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

  String _wrapSvgHtml(String svgBody) => '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=8,user-scalable=yes">
<style>html,body{margin:0;padding:12px;width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:${_lightCanvas ? '#F8FAFC' : '#0A0F1A'};}
svg{max-width:100%;max-height:100%;width:auto;height:auto;}</style>
</head><body>$svgBody</body></html>''';

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
          if (_svgHtml != null || _dxf != null)
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
    );
  }
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

    Offset map(Offset p) => Offset(p.dx * scale + dx, dy - p.dy * scale);

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
