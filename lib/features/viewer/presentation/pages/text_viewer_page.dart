import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

class TextViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const TextViewerPage({super.key, required this.filePath, this.title = '', this.onClose});

  @override
  State<TextViewerPage> createState() => _TextViewerPageState();
}

class _TextViewerPageState extends State<TextViewerPage> {
  String? _content;
  String? _error;
  bool _wrap = false;
  double _fontSize = 13;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() => _error = 'File not found');
        return;
      }
      String text;
      final size = await file.length();
      if (size > 5 * 1024 * 1024) {
        final bytes = await file.readAsBytes();
        text = utf8.decode(bytes.sublist(0, 5 * 1024 * 1024), allowMalformed: true);
        text = '$text\n\n--- File truncated (showing first 5MB) ---';
      } else {
        text = await file.readAsString();
      }
      if (mounted) setState(() => _content = text);
    } catch (e) {
      if (mounted) setState(() => _error = 'Error reading file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.title.isNotEmpty ? widget.title : widget.filePath.split('\\').last.split('/').last;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(name, style: const TextStyle(fontSize: 14)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: widget.onClose ?? () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_wrap ? Icons.wrap_text : Icons.compare_arrows, color: Theme.of(context).colorScheme.onSurface, size: 20),
            onPressed: () => setState(() => _wrap = !_wrap),
            tooltip: _wrap ? 'No wrap' : 'Word wrap',
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.text_fields, color: Theme.of(context).colorScheme.onSurface, size: 20),
            onSelected: (v) {
              if (v == 'up') setState(() => _fontSize = (_fontSize + 1).clamp(8.0, 32.0));
              if (v == 'down') setState(() => _fontSize = (_fontSize - 1).clamp(8.0, 32.0));
              if (v == 'reset') setState(() => _fontSize = 13);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'up', child: Text('Increase font', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'down', child: Text('Decrease font', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'reset', child: Text('Reset font size', style: TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white54)))
          : _content == null
              ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _content!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: _fontSize,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
    );
  }
}
