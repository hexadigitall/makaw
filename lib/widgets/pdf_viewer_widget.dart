import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

class PdfViewerWidget extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const PdfViewerWidget({
    super.key,
    required this.filePath,
    this.title = '',
    this.onClose,
  });

  @override
  State<PdfViewerWidget> createState() => _PdfViewerWidgetState();
}

class _PdfViewerWidgetState extends State<PdfViewerWidget> {
  int _totalPages = 0;
  int _currentPage = 0;
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: TextStyle(fontSize: 14)),
          backgroundColor: const Color(0xFF1E293B),
          actions: [
            if (widget.onClose != null)
              IconButton(icon: Icon(Icons.close), onPressed: widget.onClose),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Text('File not found', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(widget.title, style: TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF1E293B),
        bottom: _ready
            ? PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: _totalPages > 0 ? (_currentPage + 1) / _totalPages : 0,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF818CF8)),
                ),
              )
            : null,
        actions: [
          if (_ready)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          if (widget.onClose != null)
            IconButton(icon: Icon(Icons.close), onPressed: widget.onClose),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            PDFView(
              filePath: widget.filePath,
              enableSwipe: true,
              swipeHorizontal: false,
              autoSpacing: true,
              pageFling: true,
              onRender: (pages) {
                setState(() {
                  _totalPages = pages ?? 0;
                  _ready = true;
                });
              },
              onViewCreated: (controller) {},
              onPageChanged: (page, total) {
                setState(() {
                  _currentPage = page ?? 0;
                  _totalPages = total ?? 0;
                });
              },
              onError: (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error loading PDF: $error')),
                  );
                }
              },
            ),
            if (!_ready)
              Center(child: CircularProgressIndicator(color: const Color(0xFF818CF8))),
          ],
        ),
      ),
    );
  }
}
