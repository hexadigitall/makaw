import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

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

class _EpubReaderWidgetState extends State<EpubReaderWidget> {
  final _epubController = EpubController();
  double _progress = 0;
  bool _isLoading = true;
  double _currentFontSize = 16;

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
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF818CF8))),
              )
            : PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF818CF8)),
                ),
              ),
        actions: [
          PopupMenuButton<String>(
            color: const Color(0xFF1E293B),
            icon: Icon(Icons.text_fields, color: Colors.white70, size: 20),
            onSelected: (v) {
              if (v == 'increase') {
                _currentFontSize = (_currentFontSize + 2).clamp(10.0, 32.0);
                _epubController.setFontSize(fontSize: _currentFontSize);
              } else if (v == 'decrease') {
                _currentFontSize = (_currentFontSize - 2).clamp(10.0, 32.0);
                _epubController.setFontSize(fontSize: _currentFontSize);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'increase', child: Row(children: [Icon(Icons.text_fields, color: Colors.white70, size: 18), SizedBox(width: 8), Text('Increase Font', style: TextStyle(color: Colors.white))])),
              PopupMenuItem(value: 'decrease', child: Row(children: [Icon(Icons.text_fields, color: Colors.white70, size: 14), SizedBox(width: 8), Text('Decrease Font', style: TextStyle(color: Colors.white))])),
            ],
          ),
          IconButton(
            icon: Icon(Icons.skip_previous, color: Colors.white70, size: 20),
            onPressed: () => _epubController.prev(),
            tooltip: 'Previous page',
          ),
          IconButton(
            icon: Icon(Icons.skip_next, color: Colors.white70, size: 20),
            onPressed: () => _epubController.next(),
            tooltip: 'Next page',
          ),
          if (widget.onClose != null)
            IconButton(icon: Icon(Icons.close), onPressed: widget.onClose),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            EpubViewer(
              epubSource: EpubSource.fromFile(file),
              epubController: _epubController,
              displaySettings: EpubDisplaySettings(
                flow: EpubFlow.paginated,
                snap: true,
                theme: EpubTheme.dark(),
              ),
              onChaptersLoaded: (_) {
                setState(() => _isLoading = false);
              },
              onEpubLoaded: () {
                setState(() => _isLoading = false);
              },
              onRelocated: (value) {
                setState(() => _progress = value?.progress ?? 0);
              },
              selectAnnotationRange: false,
            ),
            if (_isLoading)
              Center(child: CircularProgressIndicator(color: const Color(0xFF818CF8))),
          ],
        ),
      ),
    );
  }
}
