import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../../core/services/text_action_service.dart';

class HtmlViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const HtmlViewerPage({super.key, required this.filePath, this.title = '', this.onClose});

  @override
  State<HtmlViewerPage> createState() => _HtmlViewerPageState();
}

class _HtmlViewerPageState extends State<HtmlViewerPage> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final name = widget.title.isNotEmpty ? widget.title : widget.filePath.split('\\').last.split('/').last;
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      return Scaffold(
        appBar: AppBar(
          title: Text(name, style: const TextStyle(fontSize: 14)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
            onPressed: widget.onClose ?? () => Navigator.pop(context),
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: Text('File not found', style: TextStyle(color: Colors.white54))),
      );
    }

    final uri = Uri.file(widget.filePath);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(name, style: const TextStyle(fontSize: 14)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress > 0 && _progress < 1 ? _progress : null,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                ),
              )
            : null,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: widget.onClose ?? () => Navigator.pop(context),
        ),
        actions: [
          if (_controller != null)
            IconButton(
              icon: Icon(Icons.record_voice_over, color: Theme.of(context).colorScheme.onSurface, size: 20),
              onPressed: () async {
                final text = await _controller!.evaluateJavascript(source: 'document.body.innerText');
                final clean = text?.toString().trim() ?? '';
                if (clean.isNotEmpty) {
                  showReadAloudDialog(context, clean);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No selectable text'), duration: Duration(seconds: 1)),
                  );
                }
              },
              tooltip: 'Read Aloud',
            ),
          if (_controller != null)
            IconButton(
              icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onSurface, size: 20),
              onPressed: () => _controller!.reload(),
            ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(uri.toString())),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useWideViewPort: true,
          supportZoom: true,
          builtInZoomControls: true,
          displayZoomControls: false,
        ),
        onWebViewCreated: (ctrl) {
          _controller = ctrl;
          enableWebviewLearningActions(controller: ctrl, context: context);
        },
        onLongPressHitTestResult: (controller, hitTestResult) {
          handleWebLongPress(context, hitTestResult);
        },
        onLoadStart: (ctrl, url) => setState(() => _isLoading = true),
        onLoadStop: (ctrl, url) => setState(() => _isLoading = false),
        onProgressChanged: (ctrl, progress) => setState(() => _progress = progress / 100.0),
      ),
    );
  }
}
