import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configured external AI CLI / agent / MCP endpoint available inside Makaw
/// Terminal sessions and `mk doctor`.
class AiToolConnector {
  final String id;
  final String name;
  final String cliCommand;
  final String envVarName;
  final String endpoint;
  final String model;
  final bool enabled;

  const AiToolConnector({
    required this.id,
    required this.name,
    required this.cliCommand,
    required this.envVarName,
    this.endpoint = '',
    this.model = '',
    this.enabled = true,
  });

  AiToolConnector copyWith({
    String? name,
    String? cliCommand,
    String? envVarName,
    String? endpoint,
    String? model,
    bool? enabled,
  }) =>
      AiToolConnector(
        id: id,
        name: name ?? this.name,
        cliCommand: cliCommand ?? this.cliCommand,
        envVarName: envVarName ?? this.envVarName,
        endpoint: endpoint ?? this.endpoint,
        model: model ?? this.model,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cliCommand': cliCommand,
        'envVarName': envVarName,
        'endpoint': endpoint,
        'model': model,
        'enabled': enabled,
      };

  factory AiToolConnector.fromJson(Map<String, dynamic> j) => AiToolConnector(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        cliCommand: (j['cliCommand'] as String?) ?? '',
        envVarName: (j['envVarName'] as String?) ?? '',
        endpoint: (j['endpoint'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
        enabled: (j['enabled'] as bool?) ?? true,
      );

  static const List<AiToolConnector> builtInPresets = [
    AiToolConnector(
      id: 'gemini_cli',
      name: 'Gemini CLI',
      cliCommand: 'gemini',
      envVarName: 'GEMINI_API_KEY',
      model: 'gemini-2.5-flash',
    ),
    AiToolConnector(
      id: 'claude_code',
      name: 'Claude Code',
      cliCommand: 'claude',
      envVarName: 'ANTHROPIC_API_KEY',
      model: 'claude-sonnet-4-20250514',
    ),
    AiToolConnector(
      id: 'codex_cli',
      name: 'OpenAI Codex CLI',
      cliCommand: 'codex',
      envVarName: 'OPENAI_API_KEY',
      model: 'gpt-4.1',
    ),
    AiToolConnector(
      id: 'aider',
      name: 'Aider AI Pair',
      cliCommand: 'aider',
      envVarName: 'OPENAI_API_KEY',
    ),
    AiToolConnector(
      id: 'ollama',
      name: 'Ollama Local LLM',
      cliCommand: 'ollama run',
      envVarName: 'OLLAMA_HOST',
      endpoint: 'http://127.0.0.1:11434',
      model: 'qwen2.5-coder',
    ),
  ];
}

/// Encrypted vault for AI CLI tools, env-var injection per session, secret
/// redaction, and AI Error Doctor (`✗ 1 -> Explain & Fix`).
class AiToolVaultService {
  static const _connectorsKey = 'makaw_ai_connectors_v1';
  static const _secretPrefix = 'makaw_ai_secret_v1_';

  final FlutterSecureStorage _secureStorage;
  final Map<String, String> _memoryFallback = {};
  List<AiToolConnector> _connectors = List.of(AiToolConnector.builtInPresets);
  bool _loaded = false;

  AiToolVaultService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  List<AiToolConnector> get connectors => List.unmodifiable(_connectors);

  Future<List<AiToolConnector>> loadConnectors() async {
    if (_loaded) return connectors;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_connectorsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = (jsonDecode(raw) as List)
            .map((e) => AiToolConnector.fromJson(e as Map<String, dynamic>))
            .where((c) => c.id.isNotEmpty)
            .toList();
        if (decoded.isNotEmpty) _connectors = decoded;
      }
    } catch (_) {}
    _loaded = true;
    return connectors;
  }

  Future<void> saveConnector(AiToolConnector connector, {String? apiKey}) async {
    await loadConnectors();
    final idx = _connectors.indexWhere((c) => c.id == connector.id);
    if (idx >= 0) {
      _connectors[idx] = connector;
    } else {
      _connectors.add(connector);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _connectorsKey, jsonEncode(_connectors.map((c) => c.toJson()).toList()));
    } catch (_) {}

    if (apiKey != null) {
      final keyName = '$_secretPrefix${connector.id}';
      if (apiKey.trim().isEmpty) {
        _memoryFallback.remove(keyName);
        try {
          await _secureStorage.delete(key: keyName);
        } catch (_) {}
      } else {
        _memoryFallback[keyName] = apiKey.trim();
        try {
          await _secureStorage.write(key: keyName, value: apiKey.trim());
        } catch (_) {}
      }
    }
  }

  Future<String?> readApiKey(String connectorId) async {
    final keyName = '$_secretPrefix$connectorId';
    try {
      final v = await _secureStorage.read(key: keyName);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return _memoryFallback[keyName];
  }

  /// Resolves all enabled AI CLI secrets & endpoints into a session env map.
  Future<Map<String, String>> buildSessionEnv() async {
    await loadConnectors();
    final envMap = <String, String>{};
    for (final c in _connectors) {
      if (!c.enabled) continue;
      if (c.endpoint.isNotEmpty && c.envVarName == 'OLLAMA_HOST') {
        envMap['OLLAMA_HOST'] = c.endpoint;
      }
      final key = await readApiKey(c.id);
      if (key != null && key.isNotEmpty && c.envVarName.isNotEmpty) {
        envMap[c.envVarName] = key;
      }
    }
    return envMap;
  }

  /// Redacts API keys, JWTs, Bearer tokens, & PEM blocks before logging/AI.
  static String redactSecrets(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'AIza[0-9A-Za-z\-_]{20,}'), '[REDACTED_GEMINI_KEY]');
    s = s.replaceAll(RegExp(r'sk-(?:proj-|ant-)?[0-9A-Za-z\-_]{16,}'), '[REDACTED_API_KEY]');
    s = s.replaceAll(RegExp(r'ghp_[0-9A-Za-z]{20,}'), '[REDACTED_GITHUB_TOKEN]');
    s = s.replaceAll(
        RegExp(r'Bearer\s+[0-9A-Za-z\-_.=]+', caseSensitive: false),
        'Bearer [REDACTED]');
    s = s.replaceAll(
        RegExp(
          r'-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----',
        ),
        '[REDACTED_PRIVATE_KEY]');
    return s;
  }

  /// Diagnoses a failed terminal command via Gemini (if a key is available)
  /// cleanly with redacted context, falling back gracefully to instant offline
  /// heuristics when offline or without an API key.
  Future<({String explanation, String? suggestedCommand})> diagnoseFailure({
    required String command,
    required int exitCode,
    required String outputTail,
  }) async {
    final safeTail = redactSecrets(outputTail);
    var geminiKey = await readApiKey('gemini_cli');
    if (geminiKey == null || geminiKey.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        geminiKey = prefs.getString('gemini_api_key');
      } catch (_) {}
    }

    if (geminiKey != null && geminiKey.trim().isNotEmpty) {
      try {
        final model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: geminiKey.trim(),
        );
        final prompt = '''
You are Makaw Terminal's concise AI Error Doctor.
A command failed with exit code $exitCode.
Command: $command
Output tail:
$safeTail

Reply in plain text with 2 concise sections:
CAUSE: <1-2 sentences explaining root cause>
FIX: <exact single shell command to fix or verify, or NONE>
''';
        final resp = await model.generateContent([Content.text(prompt)]);
        final text = resp.text?.trim() ?? '';
        if (text.isNotEmpty) {
          String? suggested;
          final fixMatch = RegExp(r'FIX:\s*(.+)$', multiLine: true).firstMatch(text);
          if (fixMatch != null) {
            final cand = fixMatch.group(1)!.trim().replaceAll('`', '');
            if (cand.isNotEmpty && cand.toUpperCase() != 'NONE') {
              suggested = cand;
            }
          }
          return (explanation: text, suggestedCommand: suggested);
        }
      } catch (_) {}
    }

    // Deterministic offline diagnostics when offline or no key set yet.
    final lower = safeTail.toLowerCase();
    if (exitCode == 127 || lower.contains('command not found')) {
      return (
        explanation:
            'Exit 127: Executable was not found in the active shell PATH. Check installed packages or switch to a desktop/SSH target.',
        suggestedCommand: 'which ${command.split(' ').first}',
      );
    }
    if (lower.contains('eaddrinuse') || lower.contains('address already in use')) {
      return (
        explanation:
            'The server port is already bound by another running process.',
        suggestedCommand: null,
      );
    }
    if (lower.contains('permission denied')) {
      return (
        explanation:
            'Insufficient permissions for that directory or binary. Inside Android, use ~/ or app storage.',
        suggestedCommand: 'pwd && ls -la',
      );
    }
    return (
      explanation:
          'Command "$command" failed with exit code $exitCode. Review output above or add a Gemini key in AI Tool Vault for deep diagnosis.',
      suggestedCommand: null,
    );
  }
}
