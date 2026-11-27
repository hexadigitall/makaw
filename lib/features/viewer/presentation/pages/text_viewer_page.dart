import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/text_action_service.dart';
import '../../../ai/presentation/widgets/ai_markdown_view.dart';

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
  bool _richMarkdown = true;
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _saveScrollDebounce;

  bool get _isMarkdown {
    final lower = widget.filePath.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadFile();
  }

  @override
  void dispose() {
    _saveScrollDebounce?.cancel();
    _saveScrollPosition();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    _saveScrollDebounce?.cancel();
    _saveScrollDebounce = Timer(const Duration(milliseconds: 500), _saveScrollPosition);
  }

  Future<void> _saveScrollPosition() async {
    if (!_scrollCtrl.hasClients) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pos = _scrollCtrl.offset;
      final max = _scrollCtrl.position.maxScrollExtent;
      final pct = max > 0 ? (pos / max).clamp(0.0, 1.0) : 0.0;
      await prefs.setString('doc_scroll_${widget.filePath.hashCode}', jsonEncode({
        'offset': pos,
        'progress': pct,
      }));
    } catch (_) {}
  }

  Future<void> _restoreScrollPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('doc_scroll_${widget.filePath.hashCode}');
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final savedOffset = (map['offset'] as num?)?.toDouble() ?? 0.0;
      if (savedOffset > 16) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollCtrl.hasClients) return;
          final clamped = savedOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent);
          _scrollCtrl.jumpTo(clamped);
        });
      }
    } catch (_) {}
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
      if (mounted) {
        setState(() => _content = text);
        _restoreScrollPosition();
      }
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
          if (_isMarkdown)
            IconButton(
              icon: Icon(
                _richMarkdown ? Icons.code_rounded : Icons.article_outlined,
                color: Theme.of(context).colorScheme.onSurface,
                size: 20,
              ),
              onPressed: () => setState(() => _richMarkdown = !_richMarkdown),
              tooltip: _richMarkdown ? 'Raw source' : 'Rendered Markdown',
            ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 19),
            onPressed: _content == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _content!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
                    );
                  },
            tooltip: 'Copy all',
          ),
          IconButton(
            icon: Icon(Icons.record_voice_over, color: Theme.of(context).colorScheme.onSurface, size: 20),
            onPressed: _content == null
                ? null
                : () => showReadAloudDialog(context, _content!),
            tooltip: 'Read Aloud',
          ),
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
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  child: (_isMarkdown && _richMarkdown)
                      ? AiMarkdownView(
                          text: _content!,
                          onCopyCode: (code, _) {
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Code copied'), duration: Duration(seconds: 2)),
                            );
                          },
                        )
                      : SelectableText(
                          _content!,
                          contextMenuBuilder: buildLearningSelectionToolbar,
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
