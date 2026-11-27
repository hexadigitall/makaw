import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../documents/data/services/document_state_service.dart';
import '../../../../core/services/text_action_service.dart';
import '../../../../core/ui/in_app_browser_sheet.dart';
import '../../../../core/ui/makaw_toast.dart';

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
  bool _restoredScroll = false;

  Future<void> _restoreScroll() async {
    if (_restoredScroll || _controller == null) return;
    _restoredScroll = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('doc_scroll_${widget.filePath.hashCode}');
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final y = (map['y'] as num?)?.toInt() ?? 0;
      if (y > 20) {
        await Future.delayed(const Duration(milliseconds: 120));
        await _controller?.scrollTo(x: 0, y: y, animated: false);
      }
    } catch (_) {}
  }

  Future<void> _saveScroll(int y) async {
    try {
      await DocumentStateService.saveProgress(
        widget.filePath,
        title: widget.title,
        scrollOffset: y.toDouble(),
        scrollProgress: y > 20 ? ((y / 4000).clamp(0.05, 0.99)) : 0.05,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('doc_scroll_${widget.filePath.hashCode}', jsonEncode({'y': y}));
    } catch (_) {}
  }

  String? _extractMhtHtml(File file) {
    final lower = file.path.toLowerCase();
    if (!lower.endsWith('.mht') && !lower.endsWith('.mhtml')) return null;
    try {
      final raw = file.readAsStringSync();
      final htmlPart = RegExp(
        r'Content-Type:\s*text/html[^\n]*\r?\n(?:[^\r\n]+\r?\n)*\r?\n([\s\S]*?)(?:\r?\n--|\z)',
        caseSensitive: false,
      ).firstMatch(raw)?.group(1);
      if (htmlPart != null && htmlPart.trim().isNotEmpty) {
        // Basic quoted-printable cleanup (`=\r\n` soft line breaks & `=3D` -> `=`)
        return htmlPart
            .replaceAll(RegExp(r'=\r?\n'), '')
            .replaceAll('=3D', '=')
            .replaceAll('=20', ' ');
      }
      final idx = raw.toLowerCase().indexOf('<html');
      if (idx >= 0) return raw.substring(idx);
    } catch (_) {}
    return null;
  }

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

    final mhtHtml = _extractMhtHtml(file);
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
              icon: Icon(Icons.headphones_rounded, color: Theme.of(context).colorScheme.onSurface, size: 20),
              onPressed: () async {
                final text = await _controller!.evaluateJavascript(source: 'document.body.innerText');
                final clean = (text?.toString() ?? '').replaceAll(RegExp(r'^null$'), '').trim();
                if (clean.isNotEmpty && mounted) {
                  showReadAloudDialog(context, clean);
                } else if (mounted) {
                  MakawToast.warning(context, 'No readable text on page');
                }
              },
              tooltip: 'Listen (Read Aloud)',
            ),
          if (_controller != null)
            IconButton(
              icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onSurface, size: 20),
              onPressed: () => _controller!.reload(),
            ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: mhtHtml == null ? URLRequest(url: WebUri(uri.toString())) : null,
        initialData: mhtHtml != null ? InAppWebViewInitialData(data: mhtHtml, baseUrl: WebUri('about:blank')) : null,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          useWideViewPort: true,
          supportZoom: true,
          builtInZoomControls: true,
          displayZoomControls: false,
        ),
        shouldOverrideUrlLoading: (_, navAction) async {
          final u = navAction.request.url?.toString() ?? '';
          if ((mhtHtml != null || !uri.toString().startsWith('http')) &&
              (u.startsWith('http://') ||
                  u.startsWith('https://') ||
                  u.startsWith('mailto:') ||
                  u.startsWith('tel:'))) {
            if (mounted) {
              MakawExternalLinks.open(context, u, sourceTitle: widget.title);
            }
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onWebViewCreated: (ctrl) {
          _controller = ctrl;
          enableWebviewLearningActions(controller: ctrl, context: context);
        },
        onLongPressHitTestResult: (controller, hitTestResult) {
          handleWebLongPress(context, hitTestResult);
        },
        onLoadStart: (ctrl, url) => setState(() => _isLoading = true),
        onLoadStop: (ctrl, url) {
          setState(() => _isLoading = false);
          _restoreScroll();
        },
        onScrollChanged: (ctrl, x, y) {
          if (_restoredScroll && y >= 0) _saveScroll(y);
        },
        onProgressChanged: (ctrl, progress) => setState(() => _progress = progress / 100.0),
      ),
    );
  }
}
