import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;

class PdfMergerPage extends StatefulWidget {
  const PdfMergerPage({super.key});

  @override
  State<PdfMergerPage> createState() => _PdfMergerPageState();
}

class _PdfMergerPageState extends State<PdfMergerPage> {
  final List<_PdfFile> _files = [];
  bool _isMerging = false;
  String? _outputPath;

  static const _kDark = Color(0xFF0F0F1A);
  static const _kCard = Color(0xFF1A1A2E);
  static const _kAccent = Color(0xFF818CF8);
  static const _kMuted = Color(0xFF666680);

  Future<void> _addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        for (final f in result.files) {
          if (f.path != null && !_files.any((x) => x.path == f.path)) {
            _files.add(_PdfFile(path: f.path!, name: f.name, size: f.size));
          }
        }
      });
    }
  }

  void _removeFile(int index) => setState(() => _files.removeAt(index));

  void _reorderFile(int oldIdx, int newIdx) {
    setState(() {
      if (oldIdx < newIdx) newIdx--;
      final item = _files.removeAt(oldIdx);
      _files.insert(newIdx, item);
    });
  }

  Future<void> _mergeFiles() async {
    if (_files.length < 2) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least 2 PDF files to merge')),
      );
      return;
    }
    setState(() => _isMerging = true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final paths = _files.map((f) => f.path).toList();

      await Isolate.run(() => _mergePdfsInIsolate(paths, outputPath));

      setState(() { _outputPath = outputPath; _isMerging = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('PDF merge complete!'),
          action: SnackBarAction(label: 'Open', textColor: _kAccent, onPressed: _openMerged),
        ),
      );
    } catch (e) {
      setState(() => _isMerging = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Merge failed: $e')));
    }
  }

  static Future<void> _mergePdfsInIsolate(List<String> inputPaths, String outputPath) async {
    final outputDoc = pw.Document();

    for (final path in inputPaths) {
      final file = File(path);
      if (!await file.exists()) continue;

      final bytes = await file.readAsBytes();
      final doc = await pdfrx.PdfDocument.openData(bytes);

      for (var i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        final renderPage = await page.render(
          width: (page.width * 2).toInt(),
          height: (page.height * 2).toInt(),
        );
        if (renderPage == null) continue;

        final rawPixels = renderPage.pixels;
        final rgbaImage = img.Image.fromBytes(
          width: renderPage.width,
          height: renderPage.height,
          bytes: rawPixels.buffer,
          format: img.Format.uint8,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        );
        final pngBytes = Uint8List.fromList(img.encodePng(rgbaImage));
        final pdfImage = pw.MemoryImage(pngBytes);
        renderPage.dispose();

        final pageWidth = page.width * pdf.PdfPageFormat.point;
        final pageHeight = page.height * pdf.PdfPageFormat.point;

        outputDoc.addPage(
          pw.Page(
            pageFormat: pdf.PdfPageFormat(pageWidth, pageHeight),
            build: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pdfImage, fit: pw.BoxFit.contain,
                width: pageWidth, height: pageHeight),
            ),
          ),
        );
      }
      await doc.dispose();
    }

    final file = File(outputPath);
    await file.writeAsBytes(await outputDoc.save(), flush: true);
  }

  void _openMerged() {
    if (_outputPath == null) return;
    Navigator.pop(context, _outputPath);
  }

  void _shareMerged() {
    if (_outputPath == null) return;
    Share.shareXFiles([XFile(_outputPath!)]);
  }

  String _formatSize(int bytes) {
    if (bytes > 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: const Text('Merge PDFs', style: TextStyle(color: Colors.white, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Text('${_files.length} file${_files.length == 1 ? '' : 's'} selected',
                style: const TextStyle(color: Colors.white, fontSize: 14))),
              ElevatedButton.icon(
                onPressed: _addFiles,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Files'),
                style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
              ),
            ]),
          ),
          Expanded(
            child: _files.isEmpty
                ? Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.picture_as_pdf, color: _kMuted, size: 48),
                      const SizedBox(height: 12),
                      Text('No PDF files added', style: TextStyle(color: _kMuted)),
                      const SizedBox(height: 8),
                      Text('Tap "Add Files" to select PDFs to merge', style: TextStyle(color: _kMuted, fontSize: 12)),
                    ],
                  ))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _files.length,
                    onReorder: _reorderFile,
                    itemBuilder: (_, i) {
                      final file = _files[i];
                      return Card(
                        key: ValueKey(file.path),
                        color: _kCard,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: _kAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                            child: Text('${i + 1}', style: const TextStyle(color: _kAccent, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(file.name, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                          subtitle: Text(_formatSize(file.size), style: const TextStyle(color: _kMuted, fontSize: 11)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: _kMuted, size: 18),
                              onPressed: () => _removeFile(i),
                            ),
                            const Icon(Icons.drag_handle, color: _kMuted, size: 18),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          if (_files.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                if (_isMerging) ...[
                  const LinearProgressIndicator(backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation(_kAccent)),
                  const SizedBox(height: 8),
                  const Text('Merging PDF pages...', style: TextStyle(color: _kMuted, fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isMerging ? null : _mergeFiles,
                    icon: Icon(_outputPath != null ? Icons.check : Icons.merge_type, size: 20),
                    label: Text(_outputPath != null ? 'Merge Complete' : 'Merge ${_files.length} Files'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _outputPath != null ? Colors.green : _kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                if (_outputPath != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: _openMerged,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open'),
                      style: OutlinedButton.styleFrom(foregroundColor: _kAccent),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: _shareMerged,
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(foregroundColor: _kAccent),
                    )),
                  ]),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

class _PdfFile {
  final String path;
  final String name;
  final int size;
  const _PdfFile({required this.path, required this.name, required this.size});
}
