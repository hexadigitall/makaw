import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Gemini chat screen.
///
/// Owns its own message list: the previous implementation built the page once
/// inside a `MaterialPageRoute` and called `setState` on the *host* app state,
/// so prompts were sent and then silently dropped because the pushed route was
/// never rebuilt.
class AiChatPage extends StatefulWidget {
  final String apiKey;
  final Future<String?> Function()? onOpenSettings;

  const AiChatPage({super.key, required this.apiKey, this.onOpenSettings});

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
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _key = widget.apiKey;
    _ensureSession();
  }

  @override
  void didUpdateWidget(AiChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.apiKey != _key) {
      _key = widget.apiKey;
      _model = null;
      _chat = null;
      _ensureSession();
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool _ensureSession() {
    if (_key.isEmpty) return false;
    _model ??= GenerativeModel(model: 'gemini-2.0-flash', apiKey: _key);
    _chat ??= _model!.startChat();
    return true;
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
    final replyIndex = _messages.length + 1;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _messages.add({'role': 'model', 'text': ''});
      _loading = true;
    });
    _scrollToEnd();

    final buffer = StringBuffer();
    try {
      await for (final chunk in _chat!.sendMessageStream(Content.text(text))) {
        final piece = chunk.text;
        if (piece == null || piece.isEmpty) continue;
        buffer.write(piece);
        if (!mounted) return;
        setState(() => _messages[replyIndex] = {'role': 'model', 'text': buffer.toString()});
        _scrollToEnd();
      }
      if (!mounted) return;
      if (buffer.isEmpty) {
        setState(() => _messages[replyIndex] = {'role': 'model', 'text': 'No response received.'});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages[replyIndex] = {
            'role': 'model',
            'text': 'Error: $e\n\nCheck that the API key is valid and has access '
                'to gemini-2.0-flash.',
          });
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToEnd();
    }
  }

  Future<void> _openSettings() async {
    final handler = widget.onOpenSettings;
    if (handler == null) return;
    final key = await handler();
    if (!mounted || key == null || key.isEmpty) return;
    setState(() {
      _key = key;
      _model = null;
      _chat = null;
    });
    _ensureSession();
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
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome, size: 20, color: _accent),
          const SizedBox(width: 8),
          const Text('AI Assistant'),
        ]),
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
