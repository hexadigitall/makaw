import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import '../../../../core/services/text_action_service.dart';
import '../../../ai/presentation/widgets/ai_markdown_view.dart';
import '../../../documents/data/services/document_state_service.dart';
import '../../../documents/domain/document_reader_contract.dart';

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
  bool _wrap = true;
  double _fontSize = 14;
  bool _richMarkdown = true;
  ReaderTheme _theme = ReaderTheme.dark;
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _saveScrollDebounce;

  bool get _isMarkdown {
    final lower = widget.filePath.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  bool get _isScreenplay {
    final lower = widget.filePath.toLowerCase();
    return lower.endsWith('.fountain') || lower.endsWith('.fdx');
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
      final pos = _scrollCtrl.offset;
      final max = _scrollCtrl.position.maxScrollExtent;
      final pct = max > 0 ? (pos / max).clamp(0.0, 1.0) : 0.0;
      await DocumentStateService.saveProgress(
        widget.filePath,
        title: widget.title,
        scrollOffset: pos,
        scrollProgress: pct,
        theme: _theme,
        fontSize: _fontSize,
      );
      final prefs = await SharedPreferences.getInstance();
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
      if (widget.filePath.toLowerCase().endsWith('.fdx')) {
        text = _extractFdxScript(text);
      }
      final savedState = await DocumentStateService.getState(widget.filePath);
      if (mounted) {
        setState(() {
          _content = text;
          if (savedState != null) {
            _theme = savedState.theme;
            _fontSize = savedState.fontSize.clamp(10.0, 30.0);
          }
        });
        _restoreScrollPosition();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error reading file: $e');
    }
  }

  static String _extractFdxScript(String xmlStr) {
    try {
      final doc = XmlDocument.parse(xmlStr);
      final buf = StringBuffer();
      for (final p in doc.findAllElements('Paragraph')) {
        final type = (p.getAttribute('Type') ?? '').toLowerCase();
        final t = p.findAllElements('Text').map((e) => e.innerText).join().trim();
        if (t.isEmpty) continue;
        if (type.contains('heading')) {
          buf.writeln('\n${t.toUpperCase()}');
        } else if (type.contains('character')) {
          buf.writeln('\n        ${t.toUpperCase()}');
        } else if (type.contains('dialogue')) {
          buf.writeln('    $t');
        } else if (type.contains('parenthetical')) {
          buf.writeln('      $t');
        } else {
          buf.writeln(t);
        }
      }
      if (buf.isNotEmpty) return buf.toString();
    } catch (_) {}
    return xmlStr;
  }

  Color get _readerBg => switch (_theme) {
    ReaderTheme.light => const Color(0xFFF8FAFC),
    ReaderTheme.sepia => const Color(0xFFF4ECD8),
    ReaderTheme.highContrast => Colors.black,
    ReaderTheme.dark => const Color(0xFF0A0F1A),
  };

  Color get _readerFg => switch (_theme) {
    ReaderTheme.light => const Color(0xFF0F172A),
    ReaderTheme.sepia => const Color(0xFF3E2F20),
    ReaderTheme.highContrast => Colors.white,
    ReaderTheme.dark => const Color(0xFFE2E8F0),
  };

  @override
  Widget build(BuildContext context) {
    final name = widget.title.isNotEmpty ? widget.title : widget.filePath.split('\\').last.split('/').last;
    return Scaffold(
      backgroundColor: _readerBg,
      appBar: AppBar(
        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: const Color(0xFF141826),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onClose ?? () => Navigator.pop(context),
        ),
        actions: [
          if (_isMarkdown || _isScreenplay)
            IconButton(
              icon: Icon(
                _richMarkdown ? Icons.code_rounded : Icons.article_outlined,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => setState(() => _richMarkdown = !_richMarkdown),
              tooltip: _richMarkdown ? 'Raw source' : 'Formatted view',
            ),
          PopupMenuButton<ReaderTheme>(
            icon: const Icon(Icons.palette_outlined, color: Colors.white, size: 20),
            color: const Color(0xFF1A1A2E),
            tooltip: 'Reader Theme',
            onSelected: (t) {
              setState(() => _theme = t);
              _saveScrollPosition();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: ReaderTheme.dark, child: Text('Dark', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: ReaderTheme.sepia, child: Text('Sepia', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: ReaderTheme.light, child: Text('Light Paper', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: ReaderTheme.highContrast, child: Text('OLED Contrast', style: TextStyle(color: Colors.white))),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 19),
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
            icon: const Icon(Icons.record_voice_over, color: Colors.white, size: 20),
            onPressed: _content == null
                ? null
                : () => showReadAloudDialog(context, _content!),
            tooltip: 'Read Aloud',
          ),
          IconButton(
            icon: Icon(_wrap ? Icons.wrap_text : Icons.compare_arrows, color: Colors.white, size: 20),
            onPressed: () => setState(() => _wrap = !_wrap),
            tooltip: _wrap ? 'No wrap' : 'Word wrap',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.text_fields, color: Colors.white, size: 20),
            color: const Color(0xFF1A1A2E),
            onSelected: (v) {
              if (v == 'up') setState(() => _fontSize = (_fontSize + 1).clamp(8.0, 32.0));
              if (v == 'down') setState(() => _fontSize = (_fontSize - 1).clamp(8.0, 32.0));
              if (v == 'reset') setState(() => _fontSize = 14);
              _saveScrollPosition();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'up', child: Text('Increase font', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: 'down', child: Text('Decrease font', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: 'reset', child: Text('Reset font size', style: TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white54)))
          : _content == null
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)))
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
                      : (_isScreenplay && _richMarkdown)
                          ? _buildFountainView(_content!)
                          : SelectableText(
                              _content!,
                              contextMenuBuilder: buildLearningSelectionToolbar,
                              style: TextStyle(
                                color: _readerFg,
                                fontSize: _fontSize,
                                height: 1.55,
                                fontFamily: 'monospace',
                              ),
                            ),
                ),
    );
  }

  Widget _buildFountainView(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines.take(4000))
          Builder(builder: (_) {
            final t = line.trim();
            if (t.isEmpty) return const SizedBox(height: 10);
            final isScene = RegExp(r'^(INT\.|EXT\.|INT/EXT\.|EST\.)', caseSensitive: false).hasMatch(t);
            final isCue = !isScene && t.length < 36 && t == t.toUpperCase() && RegExp(r'[A-Z]').hasMatch(t);
            final isParen = t.startsWith('(') && t.endsWith(')');
            return Padding(
              padding: EdgeInsets.only(
                left: isCue ? 72 : (isParen ? 54 : 8),
                right: isCue ? 24 : 8,
                top: isScene ? 12 : 2,
                bottom: 2,
              ),
              child: Text(
                t,
                style: TextStyle(
                  color: isScene ? const Color(0xFF38BDF8) : _readerFg,
                  fontSize: _fontSize,
                  fontWeight: (isScene || isCue) ? FontWeight.w700 : FontWeight.w400,
                  fontStyle: isParen ? FontStyle.italic : FontStyle.normal,
                  fontFamily: 'monospace',
                ),
              ),
            );
          }),
      ],
    );
  }
}
