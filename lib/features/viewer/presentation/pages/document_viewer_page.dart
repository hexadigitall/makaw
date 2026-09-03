import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../data/services/document_to_html.dart';
import '../../../../core/services/text_action_service.dart';

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
            icon: const Icon(Icons.record_voice_over, color: Colors.white70),
            onPressed: _webViewController != null ? () async {
              final text = await _webViewController!.evaluateJavascript(source: 'document.body.innerText');
              final clean = text?.toString().trim() ?? '';
              if (clean.isNotEmpty && mounted) {
                showReadAloudDialog(context, clean);
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No selectable text'), duration: Duration(seconds: 1), backgroundColor: Color(0xFF334155)),
                );
              }
            } : null,
            tooltip: 'Read Aloud',
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white70),
            onPressed: _webViewController != null ? () async {
              final text = await _webViewController!.evaluateJavascript(source: 'document.body.innerText');
              if (text != null && mounted) {
                Clipboard.setData(ClipboardData(text: text.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1), backgroundColor: Color(0xFF334155)),
                );
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
                  onLongPressHitTestResult: (controller, hitTestResult) {
                    handleWebLongPress(context, hitTestResult);
                  },
                ),
    );
  }
}
