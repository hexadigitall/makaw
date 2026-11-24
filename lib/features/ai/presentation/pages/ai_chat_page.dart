import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Gemini chat screen.
///
/// Owns its own message list: the previous implementation built the page once
/// inside a `MaterialPageRoute` and called `setState` on the *host* app state,
/// so prompts were sent and then silently dropped because the pushed route was
/// never rebuilt.
class AiChatPage extends StatefulWidget {
  final String apiKey;
  final String? initialModel;
  final Future<String?> Function()? onOpenSettings;

  /// Optional page context (opened from the Browser AI button). The context is
  /// sent to the model with each question but never renders as a fake user
  /// message, and it never touches the WebView.
  final String? pageTitle;
  final String? pageUrl;

  const AiChatPage({
    super.key,
    required this.apiKey,
    this.initialModel,
    this.onOpenSettings,
    this.pageTitle,
    this.pageUrl,
  });

  /// Cleans an entered API key by stripping leading/trailing whitespace,
  /// surrounding quotes, and accidental prefixes like `export GEMINI_API_KEY=`.
  static String cleanApiKey(String raw) {
    var key = raw.trim();
    if (key.startsWith('export ')) {
      key = key.substring(7).trim();
    }
    if (key.contains('=')) {
      key = key.split('=').last.trim();
    }
    if ((key.startsWith('"') && key.endsWith('"')) ||
        (key.startsWith("'") && key.endsWith("'"))) {
      key = key.substring(1, key.length - 1).trim();
    }
    return key;
  }

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  static const _accent = Color(0xFF14B8A6);

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, String>> _messages = [];

  String _key = '';
  GenerativeModel? _model;
  ChatSession? _chat;
  http.Client? _httpClient;
  bool _loading = false;
  bool _lastFailed = false;
  String _lastQuestion = '';

  String _activeModel = 'gemini-3.8-flash';
  static const List<String> _candidateModels = [
    'gemini-3.8-flash',
    'gemini-3.5-flash',
    'gemini-3.0-flash',
    'gemini-2.5-flash',
    'gemini-1.5-flash',
  ];

  @override
  void initState() {
    super.initState();
    _key = AiChatPage.cleanApiKey(widget.apiKey);
    if (widget.initialModel != null && widget.initialModel!.trim().isNotEmpty) {
      _activeModel = widget.initialModel!.trim();
    }
    _ensureSession();
  }

  @override
  void didUpdateWidget(AiChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cleaned = AiChatPage.cleanApiKey(widget.apiKey);
    final newModel = widget.initialModel?.trim();
    bool shouldReset = false;
    if (cleaned != _key) {
      _key = cleaned;
      shouldReset = true;
    }
    if (newModel != null && newModel.isNotEmpty && newModel != _activeModel) {
      _activeModel = newModel;
      shouldReset = true;
    }
    if (shouldReset) {
      _model = null;
      _chat = null;
      _ensureSession();
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _httpClient?.close();
    super.dispose();
  }

  bool _ensureSession({String? model}) {
    if (_key.isEmpty) return false;
    final m = model ?? _activeModel;
    _activeModel = m;
    try {
      _httpClient?.close();
      _httpClient = http.Client();
      _model = GenerativeModel(
        model: m,
        apiKey: _key,
        httpClient: _httpClient,
      );
      _chat = _model!.startChat();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _resetChat() {
    setState(_messages.clear);
    _chat = null;
    _ensureSession();
  }

  void _scrollToEnd() {
    if (!_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  String _promptWithContext(String text) {
    final url = widget.pageUrl ?? '';
    if (url.isEmpty) return text;
    final title = widget.pageTitle ?? '';
    final buffer = StringBuffer()
      ..writeln('The user is currently viewing this page in their browser:')
      ..writeln('URL: $url');
    if (title.isNotEmpty && title != url) buffer.writeln('Title: $title');
    buffer
      ..writeln('Use this page as context when answering.')
      ..writeln()
      ..write(text);
    return buffer.toString();
  }

  String _formatErrorMessage(Object error) {
    final s = error.toString().toLowerCase();
    if (s.contains('handshake') ||
        s.contains('connection terminated') ||
        s.contains('socketexception')) {
      return 'Network connection error (TLS handshake terminated).\n\n'
          'The mobile network interrupted the secure connection to Gemini. '
          'Please check your data/Wi-Fi and tap Retry.';
    }
    if (s.contains('api_key_invalid') ||
        (s.contains('400') && s.contains('key')) ||
        s.contains('api key not valid')) {
      return 'Invalid Gemini API key.\n\n'
          'Please tap the Settings icon (⚙) at the top right to verify and update your key.';
    }
    if (s.contains('resource_exhausted') || s.contains('429')) {
      return 'Gemini API quota or rate limit exceeded.\n\n'
          'Please wait a moment before trying again, or check your Google AI Studio plan.';
    }
    if (s.contains('not found') || s.contains('404')) {
      return 'Gemini model "$_activeModel" was not found or is deprecated.\n\n'
          'Please tap the Settings icon (⚙) to switch to gemini-3.8-flash.';
    }
    return 'Error: $error\n\nPlease check your network connection and API key.';
  }

  Future<void> _send(String text) async {
    if (text.isEmpty || _loading) return;
    if (!_ensureSession()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set your Gemini API key first')),
      );
      await _openSettings();
      return;
    }
    _msgCtrl.clear();
    _lastQuestion = text;
    final replyIndex = _messages.length + 1;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _messages.add({'role': 'model', 'text': ''});
      _loading = true;
      _lastFailed = false;
    });
    _scrollToEnd();

    final promptText = _promptWithContext(text);
    final buffer = StringBuffer();
    Object? lastError;

    // Attempt streaming with retry for network/handshake hiccups
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt > 0) {
          _ensureSession();
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }

        final stream = _chat!
            .sendMessageStream(Content.text(promptText))
            .timeout(const Duration(seconds: 45));

        buffer.clear();
        await for (final chunk in stream) {
          final piece = chunk.text;
          if (piece == null || piece.isEmpty) continue;
          buffer.write(piece);
          if (!mounted) return;
          setState(() => _messages[replyIndex] = {'role': 'model', 'text': buffer.toString()});
          _scrollToEnd();
        }

        if (buffer.isNotEmpty) {
          lastError = null;
          break;
        }
      } catch (e) {
        lastError = e;
        final errStr = e.toString().toLowerCase();

        // If current model is not found, try fallback models
        if (errStr.contains('not found') || errStr.contains('no longer available') || errStr.contains('404')) {
          for (final candidate in _candidateModels) {
            if (candidate != _activeModel) {
              _ensureSession(model: candidate);
              break;
            }
          }
          continue;
        }

        final isNetworkOrHandshake = e is HandshakeException ||
            e is SocketException ||
            e is http.ClientException ||
            errStr.contains('handshake') ||
            errStr.contains('connection terminated') ||
            errStr.contains('connection closed');

        if (isNetworkOrHandshake && attempt < 2) {
          continue;
        }
        break;
      }
    }

    // If streaming failed due to mobile network / TLS handshake drop,
    // fallback to robust non-streaming generateContent (single standard HTTP POST)
    if (buffer.isEmpty && lastError != null && _model != null) {
      try {
        _ensureSession();
        final response = await _model!
            .generateContent([Content.text(promptText)])
            .timeout(const Duration(seconds: 45));
        final textResp = response.text;
        if (textResp != null && textResp.isNotEmpty) {
          buffer.write(textResp);
          if (mounted) {
            setState(() => _messages[replyIndex] = {'role': 'model', 'text': buffer.toString()});
            _scrollToEnd();
          }
          lastError = null;
        }
      } catch (fallbackErr) {
        lastError = fallbackErr;
      }
    }

    if (!mounted) return;

    if (buffer.isEmpty) {
      final timedOut = lastError is TimeoutException;
      final errorMessage = timedOut
          ? 'AI request timed out. Please tap Retry to try again.'
          : _formatErrorMessage(lastError ?? 'No response received.');
      setState(() {
        _messages[replyIndex] = {
          'role': 'model',
          'text': errorMessage,
        };
        _lastFailed = true;
      });
    }

    setState(() => _loading = false);
    _scrollToEnd();
  }

  Future<void> _retry() async {
    if (_lastQuestion.isEmpty || _loading) return;
    if (_messages.isNotEmpty && _messages.last['role'] == 'model') {
      setState(() => _messages.removeLast());
    }
    if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
      setState(() => _messages.removeLast());
    }
    _chat = null;
    _ensureSession();
    await _send(_lastQuestion);
  }

  Future<void> _openSettings() async {
    final handler = widget.onOpenSettings;
    if (handler == null) return;
    await handler();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('gemini_api_key');
    final savedModel = prefs.getString('gemini_model');
    setState(() {
      if (savedKey != null) _key = AiChatPage.cleanApiKey(savedKey);
      if (savedModel != null && savedModel.isNotEmpty) _activeModel = savedModel;
      _model = null;
      _chat = null;
    });
    _ensureSession();
  }

  Widget _buildContextChip(BuildContext context) {
    final url = widget.pageUrl ?? '';
    if (url.isEmpty) return const SizedBox.shrink();
    final host = Uri.tryParse(url)?.host ?? url;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.language, size: 16, color: _accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Context: $host',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _accent, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text('Ask me anything',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 16)),
          const SizedBox(height: 4),
          Text('Powered by Gemini',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12)),
          if ((widget.pageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => _send('Summarize this page'),
              icon: const Icon(Icons.summarize_outlined, size: 16),
              label: const Text('Summarize this page'),
            ),
          ],
          if (_key.isEmpty) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('Set API Key'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBubble(BuildContext context, Map<String, String> msg) {
    final isUser = msg['role'] == 'user';
    final text = msg['text'] ?? '';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? _accent.withValues(alpha: 0.2)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? Radius.zero : null,
            bottomLeft: isUser ? null : Radius.zero,
          ),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: text.isEmpty && !isUser
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
              )
            : Text(text,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 20, color: _accent),
                SizedBox(width: 8),
                Text('AI Assistant'),
              ],
            ),
            Text(
              _activeModel,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
              onPressed: _resetChat,
            ),
          IconButton(
            icon: Icon(Icons.settings_outlined,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildContextChip(context),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildBubble(context, _messages[i]),
                  ),
          ),
          if (_loading && _messages.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
            ),
          if (_lastFailed && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 16, color: _accent),
                  label: const Text('Retry', style: TextStyle(color: _accent)),
                ),
              ),
            ),
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: _accent),
                  onPressed: () => _send(_msgCtrl.text.trim()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
