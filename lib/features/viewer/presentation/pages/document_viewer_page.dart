import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/document_to_html.dart';
import '../../../documents/data/services/document_state_service.dart';
import '../../../../core/services/text_action_service.dart';
import '../../../../core/ui/makaw_toast.dart';

class DocumentViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const DocumentViewerPage({super.key, required this.filePath, required this.title, this.onClose});

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  String? _htmlContent;
  String? _error;
  bool _isLoading = true;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) setState(() { _error = 'File not found'; _isLoading = false; });
        return;
      }
      final html = await DocumentToHtml.convert(file);
      if (mounted) {
        setState(() { _htmlContent = html; _isLoading = false; });
        _loadHtml();
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Error reading document: $e'; _isLoading = false; });
    }
  }

  bool _restoredScroll = false;

  Future<void> _restoreScroll() async {
    if (_restoredScroll || _webViewController == null) return;
    _restoredScroll = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('doc_scroll_${widget.filePath.hashCode}');
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final y = (map['y'] as num?)?.toInt() ?? 0;
      if (y > 20) {
        await Future.delayed(const Duration(milliseconds: 120));
        await _webViewController?.scrollTo(x: 0, y: y, animated: false);
      }
    } catch (_) {}
  }

  Future<void> _saveScroll(int y) async {
    try {
      final progress = y > 20 ? ((y / 4000).clamp(0.05, 0.99)) : 0.05;
      await DocumentStateService.saveProgress(
        widget.filePath,
        title: widget.title,
        scrollOffset: y.toDouble(),
        scrollProgress: progress,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('doc_scroll_${widget.filePath.hashCode}', jsonEncode({'y': y}));
    } catch (_) {}
  }

  void _loadHtml() {
    if (_webViewController != null && _htmlContent != null) {
      _webViewController!.loadData(data: _htmlContent!, mimeType: 'text/html', encoding: 'utf8');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.headphones_rounded, color: Colors.white70, size: 21),
            onPressed: _webViewController != null ? () async {
              final text = await _webViewController!.evaluateJavascript(source: 'document.body.innerText');
              final clean = (text?.toString() ?? '').replaceAll(RegExp(r'^null$'), '').trim();
              if (clean.isNotEmpty && mounted) {
                showReadAloudDialog(context, clean);
              } else if (mounted) {
                MakawToast.warning(context, 'No readable text found in document');
              }
            } : null,
            tooltip: 'Listen (Read Aloud)',
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white70),
            onPressed: _webViewController != null ? () async {
              final text = await _webViewController!.evaluateJavascript(source: 'document.body.innerText');
              if (text != null && mounted) {
                Clipboard.setData(ClipboardData(text: text.toString()));
                MakawToast.success(context, 'Copied to clipboard');
              }
            } : null,
            tooltip: 'Copy all text',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF00897B)),
                  SizedBox(height: 16),
                  Text('Opening document...', style: TextStyle(color: Colors.white54, fontSize: 14)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Color(0xFFF87171)),
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri('about:blank')),
                  initialSettings: InAppWebViewSettings(
                    transparentBackground: true,
                    supportZoom: true,
                    builtInZoomControls: true,
                    displayZoomControls: false,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    verticalScrollBarEnabled: false,
                  ),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                    enableWebviewLearningActions(controller: controller, context: context);
                    _loadHtml();
                  },
                  onLoadStop: (controller, _) {
                    _restoreScroll();
                  },
                  onScrollChanged: (controller, x, y) {
                    if (_restoredScroll && y >= 0) {
                      _saveScroll(y);
                    }
                  },
                  onLongPressHitTestResult: (controller, hitTestResult) {
                    handleWebLongPress(context, hitTestResult);
                  },
                ),
    );
  }
}
