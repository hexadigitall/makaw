import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/platform/session_paths.dart';
import '../../data/services/ai_pdf_exporter.dart';
import '../widgets/ai_markdown_view.dart';

// ── Models ───────────────────────────────────────────────────────────────────

enum AiAttachmentType { file, repo, link, image }

class AiAttachment {
  final String id;
  final String name;
  final AiAttachmentType type;
  final String? path;
  final String? textContent;
  final Uint8List? bytes;
  final String? mimeType;
  final int sizeInBytes;

  const AiAttachment({
    required this.id,
    required this.name,
    required this.type,
    this.path,
    this.textContent,
    this.bytes,
    this.mimeType,
    required this.sizeInBytes,
  });

  String get formattedSize {
    if (sizeInBytes <= 0) return '';
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'path': path,
    'textContent': textContent,
    'mimeType': mimeType,
    'sizeInBytes': sizeInBytes,
  };

  factory AiAttachment.fromJson(Map<String, dynamic> json) => AiAttachment(
    id: json['id'] as String? ?? UniqueKey().toString(),
    name: json['name'] as String? ?? 'attachment',
    type: AiAttachmentType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => AiAttachmentType.file,
    ),
    path: json['path'] as String?,
    textContent: json['textContent'] as String?,
    mimeType: json['mimeType'] as String?,
    sizeInBytes: (json['sizeInBytes'] as num?)?.toInt() ?? 0,
  );
}

class AiChatMessage {
  final String id;
  final String role; // 'user' or 'model'
  String text;
  final DateTime timestamp;
  final List<AiAttachment> attachments;
  bool isError;

  AiChatMessage({
    required this.id,
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.attachments = const [],
    this.isError = false,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'isError': isError,
  };

  factory AiChatMessage.fromJson(Map<String, dynamic> json) => AiChatMessage(
    id: json['id'] as String? ?? UniqueKey().toString(),
    role: json['role'] as String? ?? 'user',
    text: json['text'] as String? ?? '',
    timestamp: json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
        : DateTime.now(),
    attachments: (json['attachments'] as List?)
            ?.map((a) => AiAttachment.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList() ??
        const [],
    isError: json['isError'] as bool? ?? false,
  );
}

class AiChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<AiChatMessage> messages;

  AiChatSession({
    required this.id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<AiChatMessage>? messages,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory AiChatSession.fromJson(Map<String, dynamic> json) => AiChatSession(
    id: json['id'] as String? ?? UniqueKey().toString(),
    title: json['title'] as String? ?? 'New Chat',
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
    updatedAt: json['updatedAt'] != null
        ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
    messages: (json['messages'] as List?)
            ?.map((m) => AiChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList() ??
        [],
  );
}

// ── Screen Widget ────────────────────────────────────────────────────────────

class AiChatPage extends StatefulWidget {
  final String apiKey;
  final String? initialModel;
  final Future<String?> Function()? onOpenSettings;
  final void Function(String filePath)? onOpenFile;

  /// Optional page context (opened from Browser AI mode).
  final String? pageTitle;
  final String? pageUrl;

  const AiChatPage({
    super.key,
    required this.apiKey,
    this.initialModel,
    this.onOpenSettings,
    this.onOpenFile,
    this.pageTitle,
    this.pageUrl,
  });

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
  static const _kStorageKey = 'makaw_ai_chat_sessions_v2';

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
    'gemini-3.5-flash-lite',
    'gemini-3.0-flash',
    'gemini-2.5-flash',
  ];

  // Sessions and History
  List<AiChatSession> _sessions = [];
  String _currentSessionId = '';

  // Pending attachments for the next query
  final List<AiAttachment> _pendingAttachments = [];

  // TTS Read aloud
  FlutterTts? _tts;
  String? _currentlySpeakingMessageId;

  AiChatSession get _currentSession {
    final idx = _sessions.indexWhere((s) => s.id == _currentSessionId);
    if (idx != -1) return _sessions[idx];
    if (_sessions.isNotEmpty) return _sessions.first;
    final fresh = AiChatSession(id: DateTime.now().millisecondsSinceEpoch.toString(), title: 'New Chat');
    _sessions.add(fresh);
    _currentSessionId = fresh.id;
    return fresh;
  }

  @override
  void initState() {
    super.initState();
    _key = AiChatPage.cleanApiKey(widget.apiKey);
    if (widget.initialModel != null && widget.initialModel!.trim().isNotEmpty) {
      _activeModel = widget.initialModel!.trim();
    }
    _initTts();
    _loadSessions().then((_) {
      _ensureSession();
    });
  }

  Future<void> _initTts() async {
    try {
      _tts = FlutterTts();
      await _tts?.setLanguage('en-US');
      await _tts?.setSpeechRate(0.5);
      await _tts?.setVolume(1.0);
      await _tts?.setPitch(1.0);
      _tts?.setCompletionHandler(() {
        if (mounted) setState(() => _currentlySpeakingMessageId = null);
      });
      _tts?.setErrorHandler((_) {
        if (mounted) setState(() => _currentlySpeakingMessageId = null);
      });
    } catch (_) {}
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
    _tts?.stop();
    super.dispose();
  }

  // ── Session persistence ────────────────────────────────────────────────────

  Future<void> _loadSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        _sessions = decoded
            .map((s) => AiChatSession.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList();
      }
    } catch (_) {}

    if (_sessions.isEmpty) {
      final initial = AiChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'New Chat',
      );
      _sessions.add(initial);
      _currentSessionId = initial.id;
    } else {
      _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _currentSessionId = _sessions.first.id;
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_sessions.map((s) => s.toJson()).toList());
      await prefs.setString(_kStorageKey, raw);
    } catch (_) {}
  }

  void _createNewChat() {
    final fresh = AiChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New Chat',
    );
    setState(() {
      _sessions.insert(0, fresh);
      _currentSessionId = fresh.id;
      _pendingAttachments.clear();
      _chat = null;
    });
    _saveSessions();
    _ensureSession();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop(); // close drawer
    }
  }

  void _switchChat(String sessionId) {
    if (_currentSessionId == sessionId) {
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {
      _currentSessionId = sessionId;
      _pendingAttachments.clear();
      _chat = null;
    });
    _ensureSession();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    _scrollToEnd();
  }

  Future<void> _deleteChat(String sessionId) async {
    setState(() {
      _sessions.removeWhere((s) => s.id == sessionId);
      if (_sessions.isEmpty) {
        final fresh = AiChatSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'New Chat',
        );
        _sessions.add(fresh);
        _currentSessionId = fresh.id;
      } else if (_currentSessionId == sessionId) {
        _currentSessionId = _sessions.first.id;
      }
      _chat = null;
    });
    await _saveSessions();
    _ensureSession();
  }

  Future<void> _renameChat(AiChatSession session) async {
    final ctrl = TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: const Text('Rename Chat'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter chat title',
            filled: true,
            fillColor: Theme.of(ctx).cardColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty) {
      setState(() {
        session.title = newTitle;
        session.updatedAt = DateTime.now();
      });
      await _saveSessions();
    }
  }

  // ── Gemini session ─────────────────────────────────────────────────────────

  bool _ensureSession({String? model, bool resetHttpClient = false}) {
    if (_key.isEmpty) return false;
    final m = model ?? _activeModel;
    _activeModel = m;
    try {
      if (resetHttpClient || _httpClient == null) {
        _httpClient?.close();
        _httpClient = http.Client();
      }
      _model = GenerativeModel(
        model: m,
        apiKey: _key,
        httpClient: _httpClient,
      );
      // Window recent conversation turns to keep prompt payload fast and compact
      final validMsgs = _currentSession.messages
          .where((msg) => msg.text.isNotEmpty && !msg.isError)
          .toList();
      final windowed = validMsgs.length > 16
          ? validMsgs.sublist(validMsgs.length - 16)
          : validMsgs;
      final history = <Content>[];
      for (final msg in windowed) {
        if (msg.role == 'user') {
          history.add(Content.text(msg.text));
        } else {
          history.add(Content.model([TextPart(msg.text)]));
        }
      }
      _chat = _model!.startChat(history: history.isNotEmpty ? history : null);
      return true;
    } catch (_) {
      return false;
    }
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

  // ── Attachments Handling ───────────────────────────────────────────────────

  Future<void> _showAttachmentMenu() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  'Add Context to AI Query',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.description_outlined, color: _accent, size: 22),
                ),
                title: const Text('Attach File / Document'),
                subtitle: const Text('Code, text, markdown, json, pdf, etc.'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFile();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.folder_open_outlined, color: Colors.blueAccent, size: 22),
                ),
                title: const Text('Attach Code Repo / Workspace Folder'),
                subtitle: const Text('Summarize directory structure and files'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickDirectory();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.purpleAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.image_outlined, color: Colors.purpleAccent, size: 22),
                ),
                title: const Text('Attach Image'),
                subtitle: const Text('Ask Gemini to analyze screenshots or diagrams'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.amberAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.link_rounded, color: Colors.amberAccent, size: 22),
                ),
                title: const Text('Attach Web Link / URL'),
                subtitle: const Text('Reference a web page or article'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showAddLinkDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (res != null && res.files.isNotEmpty) {
        final f = res.files.first;
        Uint8List? bytes = f.bytes;
        if (bytes == null && f.path != null) {
          final file = File(f.path!);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
          }
        }
        final ext = p.extension(f.name).toLowerCase();
        String? content;
        String? mime;
        Uint8List? binaryPayload;

        if (ext == '.pdf') {
          mime = 'application/pdf';
          binaryPayload = bytes;
        } else if (['.png', '.jpg', '.jpeg', '.webp'].contains(ext)) {
          mime = ext == '.png' ? 'image/png' : (ext == '.webp' ? 'image/webp' : 'image/jpeg');
          binaryPayload = bytes;
        } else if (bytes != null) {
          try {
            final decoded = utf8.decode(bytes);
            content = decoded.length > 60000
                ? '${decoded.substring(0, 60000)}\n... [truncated after 60KB]'
                : decoded;
          } catch (_) {
            content = 'Binary file (${f.name}, ${bytes.length} bytes)';
          }
        }
        setState(() {
          _pendingAttachments.add(AiAttachment(
            id: UniqueKey().toString(),
            name: f.name,
            type: (ext != '.pdf' && mime != null && mime.startsWith('image/'))
                ? AiAttachmentType.image
                : AiAttachmentType.file,
            path: f.path,
            textContent: content,
            bytes: binaryPayload,
            mimeType: mime,
            sizeInBytes: f.size,
          ));
        });
      }
    } catch (e) {
      _showToast('Failed to attach file: $e');
    }
  }

  Future<void> _pickDirectory() async {
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath != null && dirPath.isNotEmpty) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final buffer = StringBuffer();
          buffer.writeln('Repository/Directory: ${p.basename(dirPath)}');
          buffer.writeln('Path: $dirPath\n');
          buffer.writeln('Contents summary:');
          final sampleFiles = <File>[];
          int count = 0;
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            final ep = entity.path;
            if (ep.contains('.git') ||
                ep.contains('.dart_tool') ||
                ep.contains('${Platform.pathSeparator}build') ||
                ep.contains('node_modules')) {
              continue;
            }
            final rel = p.relative(ep, from: dirPath);
            if (count < 120) {
              buffer.writeln('- $rel');
            }
            count++;
            if (entity is File && sampleFiles.length < 10) {
              final lower = rel.toLowerCase();
              if (lower.endsWith('readme.md') ||
                  lower.endsWith('pubspec.yaml') ||
                  lower.endsWith('package.json') ||
                  lower.endsWith('.dart') ||
                  lower.endsWith('.py') ||
                  lower.endsWith('.ts') ||
                  lower.endsWith('.js')) {
                sampleFiles.add(entity);
              }
            }
          }
          if (count > 120) {
            buffer.writeln('... (+${count - 120} more items)');
          }

          int inlinedBytes = 0;
          for (final sf in sampleFiles) {
            if (inlinedBytes >= 24000) break;
            try {
              final len = await sf.length();
              if (len > 12000) continue;
              final txt = await sf.readAsString();
              final rel = p.relative(sf.path, from: dirPath);
              buffer.writeln('\n--- $rel ---\n$txt');
              inlinedBytes += txt.length;
            } catch (_) {}
          }

          setState(() {
            _pendingAttachments.add(AiAttachment(
              id: UniqueKey().toString(),
              name: p.basename(dirPath),
              type: AiAttachmentType.repo,
              path: dirPath,
              textContent: buffer.toString(),
              sizeInBytes: buffer.length,
            ));
          });
        }
      }
    } catch (e) {
      _showToast('Failed to attach directory: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (res != null && res.files.isNotEmpty) {
        final f = res.files.first;
        Uint8List? bytes = f.bytes;
        if (bytes == null && f.path != null) {
          bytes = await File(f.path!).readAsBytes();
        }
        final ext = p.extension(f.name).toLowerCase();
        final mime = ext == '.png' ? 'image/png' : 'image/jpeg';
        setState(() {
          _pendingAttachments.add(AiAttachment(
            id: UniqueKey().toString(),
            name: f.name,
            type: AiAttachmentType.image,
            path: f.path,
            bytes: bytes,
            mimeType: mime,
            sizeInBytes: f.size,
          ));
        });
      }
    } catch (e) {
      _showToast('Failed to attach image: $e');
    }
  }

  Future<void> _showAddLinkDialog() async {
    final ctrl = TextEditingController();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clip = data?.text?.trim() ?? '';
    if (clip.startsWith('http://') || clip.startsWith('https://')) {
      ctrl.text = clip;
    }
    if (!mounted) return;
    final link = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: const Text('Attach Web Link'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'https://example.com',
            filled: true,
            fillColor: Theme.of(ctx).cardColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Attach'),
          ),
        ],
      ),
    );
    if (link != null && link.isNotEmpty) {
      setState(() {
        _pendingAttachments.add(AiAttachment(
          id: UniqueKey().toString(),
          name: Uri.tryParse(link)?.host ?? link,
          type: AiAttachmentType.link,
          textContent: link,
          sizeInBytes: link.length,
        ));
      });
    }
  }

  // ── Send and Processing ───────────────────────────────────────────────────

  Future<String> _fetchUrlContext(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) return url;
      final client = _httpClient ?? http.Client();
      final res = await client.get(
        uri,
        headers: {'User-Agent': 'Makaw/1.0 (AI Reader)'},
      ).timeout(const Duration(seconds: 7));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return 'URL: $url (HTTP ${res.statusCode})';
      }
      var body = res.body;
      body = body
          .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (body.length > 9000) body = '${body.substring(0, 9000)}...';
      return 'URL: $url\nExtracted page text:\n$body';
    } catch (_) {
      return url;
    }
  }

  Future<void> _send(String text) async {
    final queryText = text.trim();
    if (queryText.isEmpty && _pendingAttachments.isEmpty) return;
    if (_loading) return;

    if (!_ensureSession()) {
      _showToast('Set your Gemini API key first');
      await _openSettings();
      return;
    }

    _msgCtrl.clear();
    final attached = List<AiAttachment>.from(_pendingAttachments);
    _pendingAttachments.clear();

    final userMsg = AiChatMessage(
      id: UniqueKey().toString(),
      role: 'user',
      text: queryText.isNotEmpty ? queryText : 'Analyze attached input',
      attachments: attached,
    );
    final modelMsg = AiChatMessage(
      id: UniqueKey().toString(),
      role: 'model',
      text: '',
    );

    final session = _currentSession;
    if (session.messages.isEmpty && session.title == 'New Chat' && queryText.isNotEmpty) {
      session.title = queryText.length > 28 ? '${queryText.substring(0, 28)}...' : queryText;
    }
    session.updatedAt = DateTime.now();

    setState(() {
      session.messages.add(userMsg);
      session.messages.add(modelMsg);
      _loading = true;
      _lastFailed = false;
      _lastQuestion = userMsg.text;
    });
    _scrollToEnd();
    await _saveSessions();

    // Prepare prompt bundle with context and attachments
    final promptBuffer = StringBuffer();
    if ((widget.pageUrl ?? '').isNotEmpty) {
      promptBuffer.writeln('Browser Context Title: ${widget.pageTitle ?? ""}');
      promptBuffer.writeln(await _fetchUrlContext(widget.pageUrl!));
      promptBuffer.writeln();
    }
    final binaryParts = <DataPart>[];
    for (final att in attached) {
      if (att.bytes != null && att.mimeType != null) {
        binaryParts.add(DataPart(att.mimeType!, att.bytes!));
      }
      if (att.type == AiAttachmentType.file || att.type == AiAttachmentType.repo) {
        promptBuffer.writeln('### Attached ${att.name}:');
        if (att.textContent != null && att.textContent!.isNotEmpty) {
          promptBuffer.writeln(att.textContent);
        } else if (att.path != null) {
          promptBuffer.writeln('File path: ${att.path}');
        }
        promptBuffer.writeln();
      } else if (att.type == AiAttachmentType.link && att.textContent != null) {
        promptBuffer.writeln('### Referenced Web Link:');
        promptBuffer.writeln(await _fetchUrlContext(att.textContent!));
        promptBuffer.writeln();
      }
    }
    promptBuffer.write(userMsg.text);
    final finalPrompt = promptBuffer.toString();

    final orderedModels = <String>[
      _activeModel,
      ..._candidateModels.where((m) => m != _activeModel),
    ];
    final buffer = StringBuffer();
    Object? lastError;

    for (int attempt = 0; attempt < orderedModels.length; attempt++) {
      final candidate = orderedModels[attempt];
      try {
        if (attempt > 0) {
          final errStr = (lastError ?? '').toString().toLowerCase();
          final isSocketDrop = errStr.contains('handshake') ||
              errStr.contains('socket') ||
              errStr.contains('connection terminated');
          _ensureSession(model: candidate, resetHttpClient: isSocketDrop);
          await Future.delayed(const Duration(milliseconds: 220));
        }

        if (binaryParts.isNotEmpty) {
          final content = Content.multi([
            TextPart(finalPrompt),
            ...binaryParts,
          ]);
          final resp = await _model!.generateContent([content]).timeout(const Duration(seconds: 40));
          if (resp.text != null && resp.text!.isNotEmpty) {
            buffer.write(resp.text);
            modelMsg.text = buffer.toString();
            if (mounted) setState(() {});
            break;
          }
        } else {
          final stream = _chat!
              .sendMessageStream(Content.text(finalPrompt))
              .timeout(const Duration(seconds: 40));

          buffer.clear();
          await for (final chunk in stream) {
            final piece = chunk.text;
            if (piece == null || piece.isEmpty) continue;
            buffer.write(piece);
            modelMsg.text = buffer.toString();
            if (mounted) {
              setState(() {});
              _scrollToEnd();
            }
          }
          if (buffer.isNotEmpty) {
            lastError = null;
            break;
          }
        }
      } catch (e) {
        lastError = e;
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('api_key_invalid') || errStr.contains('api key not valid')) {
          break;
        }
        continue;
      }
    }

    // Fallback standard generateContent using current healthy _model (never a hardcoded stale model)
    if (buffer.isEmpty && lastError != null && _model != null && binaryParts.isEmpty && !lastError.toString().toLowerCase().contains('api_key_invalid')) {
      try {
        _ensureSession(resetHttpClient: true);
        final resp = await _model!.generateContent([Content.text(finalPrompt)]).timeout(const Duration(seconds: 40));
        if (resp.text != null && resp.text!.isNotEmpty) {
          buffer.write(resp.text);
          modelMsg.text = buffer.toString();
          lastError = null;
        }
      } catch (fallbackErr) {
        lastError = fallbackErr;
      }
    }

    if (!mounted) return;

    if (buffer.isEmpty) {
      final msg = _formatErrorMessage(lastError ?? 'No response received.');
      modelMsg.text = msg;
      modelMsg.isError = true;
      _lastFailed = true;
    } else {
      modelMsg.text = buffer.toString();
      modelMsg.isError = false;
    }

    setState(() => _loading = false);
    _scrollToEnd();
    await _saveSessions();
  }

  Future<void> _retry() async {
    if (_lastQuestion.isEmpty || _loading) return;
    final session = _currentSession;
    if (session.messages.isNotEmpty && session.messages.last.role == 'model') {
      session.messages.removeLast();
    }
    if (session.messages.isNotEmpty && session.messages.last.role == 'user') {
      session.messages.removeLast();
    }
    _chat = null;
    _ensureSession();
    await _send(_lastQuestion);
  }

  // ── Actions & Exports ──────────────────────────────────────────────────────

  void _copyToClipboard(String text, String confirmation) {
    Clipboard.setData(ClipboardData(text: text));
    _showToast(confirmation);
  }

  Future<void> _speak(AiChatMessage msg) async {
    if (_tts == null) return;
    if (_currentlySpeakingMessageId == msg.id) {
      await _tts?.stop();
      setState(() => _currentlySpeakingMessageId = null);
      return;
    }
    await _tts?.stop();
    setState(() => _currentlySpeakingMessageId = msg.id);
    await _tts?.speak(msg.text);
  }

  Future<void> _exportResponseModal(AiChatMessage msg) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  'Export & Convert Response',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent),
                title: const Text('Export as PDF Document (.pdf)'),
                subtitle: const Text('Portable multi-page PDF ready for Makaw PDF Reader & sharing'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportToFile(msg, 'pdf');
                },
              ),
              ListTile(
                leading: const Icon(Icons.description_rounded, color: Colors.indigoAccent),
                title: const Text('Export as Word Document (.doc)'),
                subtitle: const Text('Preserves bold, italics, tables, and styling in Word / Docs'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportToFile(msg, 'doc');
                },
              ),
              ListTile(
                leading: const Icon(Icons.html_rounded, color: Colors.orangeAccent),
                title: const Text('Export as HTML Document (.html)'),
                subtitle: const Text('Interactive responsive web page with styled typography'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportToFile(msg, 'html');
                },
              ),
              ListTile(
                leading: const Icon(Icons.code_rounded, color: _accent),
                title: const Text('Export as Markdown (.md)'),
                subtitle: const Text('Preserves markdown tables, lists, and formatting'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportToFile(msg, 'md');
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_snippet_outlined, color: Colors.blueAccent),
                title: const Text('Export as Plain Text (.txt)'),
                subtitle: const Text('Clean plain text document without markdown symbols'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportToFile(msg, 'txt');
                },
              ),
              ListTile(
                leading: const Icon(Icons.data_object_rounded, color: Colors.greenAccent),
                title: const Text('Export as JSON (.json)'),
                subtitle: const Text('Structured prompt, model and response object'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportToFile(msg, 'json');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSavedFile(String path) {
    if (widget.onOpenFile != null) {
      widget.onOpenFile!(path);
    } else {
      OpenFilex.open(path);
    }
  }

  Future<void> _exportToFile(AiChatMessage msg, String format) async {
    try {
      final downloadDir = await SessionPaths.downloadsDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'Makaw_AI_Response_$stamp.$format';
      final file = File(p.join(downloadDir, filename));

      if (format == 'pdf') {
        final pdfBytes = AiPdfExporter.buildPdfBytes(
          title: 'Makaw AI Assistant Response',
          model: _activeModel,
          markdownText: msg.text,
        );
        await file.writeAsBytes(pdfBytes);
      } else {
        String content = '';
        if (format == 'md') {
          content = '''# Makaw AI Assistant Response
Model: $_activeModel
Date: ${DateTime.now().toLocal()}

---

${msg.text}
''';
        } else if (format == 'txt') {
          content = AiMarkdownView.stripMarkdown(msg.text);
        } else if (format == 'html') {
          content = AiMarkdownView.markdownToHtml(
            msg.text,
            title: 'Makaw AI Response',
            model: _activeModel,
          );
        } else if (format == 'doc') {
          content = AiMarkdownView.markdownToDoc(
            msg.text,
            title: 'Makaw AI Response',
            model: _activeModel,
          );
        } else if (format == 'json') {
          content = const JsonEncoder.withIndent('  ').convert({
            'generator': 'Makaw AI Assistant',
            'model': _activeModel,
            'timestamp': DateTime.now().toIso8601String(),
            'response': msg.text,
            'plainText': AiMarkdownView.stripMarkdown(msg.text),
          });
        }
        await file.writeAsString(content);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${p.basename(file.path)}'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Open in Makaw',
            textColor: _accent,
            onPressed: () => _openSavedFile(file.path),
          ),
        ),
      );
    } catch (e) {
      _showToast('Failed to export response: $e');
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
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

  // ── Render Helpers & Markdown Parser ──────────────────────────────────────

  Widget _buildBubble(AiChatMessage msg) {
    final isUser = msg.role == 'user';
    final isSpeaking = _currentlySpeakingMessageId == msg.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? _accent.withValues(alpha: 0.18)
                    : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18).copyWith(
                  bottomRight: isUser ? Radius.zero : null,
                  bottomLeft: isUser ? null : Radius.zero,
                ),
                border: Border.all(
                  color: isUser ? _accent.withValues(alpha: 0.35) : Colors.transparent,
                ),
              ),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
              child: msg.text.isEmpty && !isUser
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.attachments.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: msg.attachments.map((a) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      a.type == AiAttachmentType.image
                                          ? Icons.image
                                          : a.type == AiAttachmentType.link
                                              ? Icons.link
                                              : a.type == AiAttachmentType.repo
                                                  ? Icons.folder
                                                  : Icons.description,
                                      size: 14,
                                      color: _accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      a.name,
                                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        if (msg.attachments.isNotEmpty) const SizedBox(height: 8),
                        if (isUser)
                          SelectableText(
                            msg.text,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14.5,
                              height: 1.45,
                            ),
                          )
                        else
                          AiMarkdownView(
                            text: msg.text,
                            accentColor: _accent,
                            onCopyCode: (code, lang) => _copyToClipboard(code, 'Code snippet copied'),
                            onSaveCode: (code, lang) async {
                              try {
                                final ext = lang.trim().isNotEmpty ? lang.trim().toLowerCase() : 'txt';
                                final dir = await SessionPaths.downloadsDir();
                                final file = File(p.join(dir, 'snippet_${DateTime.now().millisecondsSinceEpoch}.$ext'));
                                await file.writeAsString(code);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Saved ${p.basename(file.path)}'),
                                    action: SnackBarAction(
                                      label: 'Open in Makaw',
                                      textColor: _accent,
                                      onPressed: () => _openSavedFile(file.path),
                                    ),
                                  ),
                                );
                              } catch (e) {
                                _showToast('Failed to save snippet: $e');
                              }
                            },
                          ),
                      ],
                    ),
            ),
          ),
          // Action row below each bubble
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
            child: isUser
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: 'Copy query',
                        visualDensity: VisualDensity.compact,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        onPressed: () => _copyToClipboard(msg.text, 'Query copied to clipboard'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        tooltip: 'Edit query',
                        visualDensity: VisualDensity.compact,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        onPressed: () {
                          _msgCtrl.text = msg.text;
                          _msgCtrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: _msgCtrl.text.length),
                          );
                        },
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: 'Copy response',
                        visualDensity: VisualDensity.compact,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        onPressed: () => _copyToClipboard(msg.text, 'Response copied to clipboard'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.share_outlined, size: 16),
                        tooltip: 'Share response',
                        visualDensity: VisualDensity.compact,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        onPressed: () => Share.share(msg.text, subject: 'Makaw AI Response'),
                      ),
                      IconButton(
                        icon: Icon(
                          isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                          size: 17,
                          color: isSpeaking ? Colors.redAccent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        tooltip: isSpeaking ? 'Stop speaking' : 'Read aloud',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _speak(msg),
                      ),
                      IconButton(
                        icon: const Icon(Icons.file_download_outlined, size: 17),
                        tooltip: 'Export / Download',
                        visualDensity: VisualDensity.compact,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        onPressed: () => _exportResponseModal(msg),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        tooltip: 'Regenerate',
                        visualDensity: VisualDensity.compact,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        onPressed: _retry,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryDrawer() {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, color: _accent, size: 22),
                  const SizedBox(width: 8),
                  const Text('Chat History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: _accent),
                    tooltip: 'New Chat',
                    onPressed: _createNewChat,
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _sessions.isEmpty
                  ? const Center(child: Text('No previous chats'))
                  : ListView.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (ctx, i) {
                        final s = _sessions[i];
                        final isSelected = s.id == _currentSessionId;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: _accent.withValues(alpha: 0.12),
                          leading: Icon(
                            Icons.chat_outlined,
                            size: 18,
                            color: isSelected ? _accent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          title: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected ? _accent : Theme.of(context).colorScheme.onSurface,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '${s.messages.length} messages',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            onSelected: (val) {
                              if (val == 'rename') {
                                _renameChat(s);
                              } else if (val == 'delete') {
                                _deleteChat(s.id);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(value: 'rename', child: Text('Rename')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                            ],
                          ),
                          onTap: () => _switchChat(s.id),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: _accent.withValues(alpha: 0.15),
                ),
                onPressed: _createNewChat,
                icon: const Icon(Icons.add_rounded, color: _accent),
                label: const Text('Start New Chat', style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            'Ask me anything',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Powered by Gemini • $_activeModel',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12),
          ),
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

  @override
  Widget build(BuildContext context) {
    final messages = _currentSession.messages;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildHistoryDrawer(),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
              tooltip: 'Close (Swipe down)',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        title: InkWell(
          onTap: () => _renameChat(_currentSession),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('AI Assistant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '• ${_currentSession.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _accent),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 12, color: _accent),
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
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New Chat',
            onPressed: _createNewChat,
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Chat History',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'AI Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Column(
          children: [
            if ((widget.pageUrl ?? '').isNotEmpty)
              Container(
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
                        'Context: ${Uri.tryParse(widget.pageUrl!)?.host ?? widget.pageUrl}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _accent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SelectionArea(
                child: messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: messages.length,
                        itemBuilder: (_, i) => _buildBubble(messages[i]),
                      ),
              ),
            ),
            if (_loading && messages.isNotEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                ),
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
            // Input attachments bar
            if (_pendingAttachments.isNotEmpty)
              Container(
                color: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _pendingAttachments.map((att) {
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _accent.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              att.type == AiAttachmentType.image
                                  ? Icons.image
                                  : att.type == AiAttachmentType.link
                                      ? Icons.link
                                      : att.type == AiAttachmentType.repo
                                          ? Icons.folder
                                          : Icons.description,
                              size: 16,
                              color: _accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              att.name.length > 20 ? '${att.name.substring(0, 20)}...' : att.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (att.formattedSize.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(${att.formattedSize})',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                setState(() => _pendingAttachments.removeWhere((a) => a.id == att.id));
                              },
                              child: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            // Bottom input bar
            Container(
              color: Theme.of(context).colorScheme.surface,
              padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: _accent, size: 26),
                    tooltip: 'Attach file, repo, link or image',
                    onPressed: _showAttachmentMenu,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Ask Gemini anything...',
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: _accent),
                    tooltip: 'Send message',
                    onPressed: () => _send(_msgCtrl.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
