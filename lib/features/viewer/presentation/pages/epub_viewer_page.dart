import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _restoredPosition = false;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('doc_pos_${widget.filePath.hashCode}');
      if (data != null) {
        final map = jsonDecode(data) as Map<String, dynamic>;
        final cfi = map['cfi'] as String?;
        if (cfi != null && cfi.isNotEmpty) {
          // Restore to saved CFI position after epub loads
          _restoredPosition = false;
        }
      }
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('doc_pos_${widget.filePath.hashCode}', jsonEncode({
        'progress': _progress,
        'ts': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontSize: 14)),
          backgroundColor: const Color(0xFF1E293B),
          actions: [
            if (widget.onClose != null)
              IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        body: const Center(child: Text('File not found', style: TextStyle(color: Colors.white54))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF1E293B),
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF818CF8))),
              )
            : PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF818CF8)),
                ),
              ),
        actions: [
          PopupMenuButton<String>(
            color: const Color(0xFF1E293B),
            icon: const Icon(Icons.text_fields, color: Colors.white70, size: 20),
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
              const PopupMenuItem(value: 'increase', child: Row(children: [Icon(Icons.text_fields, color: Colors.white70, size: 18), SizedBox(width: 8), Text('Increase Font', style: TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'decrease', child: Row(children: [Icon(Icons.text_fields, color: Colors.white70, size: 14), SizedBox(width: 8), Text('Decrease Font', style: TextStyle(color: Colors.white))])),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.white70, size: 20),
            onPressed: () => _epubController.prev(),
            tooltip: 'Previous page',
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white70, size: 20),
            onPressed: () => _epubController.next(),
            tooltip: 'Next page',
          ),
          if (widget.onClose != null)
            IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
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
                final p = value?.progress ?? 0;
                setState(() => _progress = p);
                // Save position periodically (every ~5% change)
                if ((p * 100).round() % 5 == 0) _savePosition();
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
