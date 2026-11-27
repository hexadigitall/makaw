import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

/// Executable task/runbook item surfaced in Terminal 2.0's Runbook Bar & Command Palette.
class RunbookCommand {
  final String id;
  final String label;
  final String command;
  final String category; // 'run' | 'test' | 'build' | 'custom'
  final String source;
  final bool isCustom;

  const RunbookCommand({
    required this.id,
    required this.label,
    required this.command,
    this.category = 'run',
    this.source = 'auto',
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'command': command,
        'category': category,
        'source': source,
        'isCustom': isCustom,
      };

  factory RunbookCommand.fromJson(Map<String, dynamic> j) => RunbookCommand(
        id: (j['id'] as String?) ?? '',
        label: (j['label'] as String?) ?? '',
        command: (j['command'] as String?) ?? '',
        category: (j['category'] as String?) ?? 'custom',
        source: (j['source'] as String?) ?? 'custom',
        isCustom: (j['isCustom'] as bool?) ?? true,
      );
}

enum TerminalLinkKind { url, file }

/// Interactive link extracted from terminal scrollback output.
class DetectedTerminalLink {
  final TerminalLinkKind kind;
  final String label;
  final String target;
  final int? line;
  final int? column;

  const DetectedTerminalLink({
    required this.kind,
    required this.label,
    required this.target,
    this.line,
    this.column,
  });
}

/// Auto-detects runnable scripts from project files in [cwd] (`pubspec.yaml`,
/// `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Makefile`) and
/// manages user custom runbooks.
class RunbookDetector {
  static const _customKey = 'makaw_terminal_custom_runbooks_v1';

  static Future<List<RunbookCommand>> detect(String cwd) async {
    final results = <RunbookCommand>[];
    final cleanCwd = cwd.trim();
    if (cleanCwd.isEmpty || cleanCwd == '~') return results;
    final dir = Directory(cleanCwd);
    if (!dir.existsSync()) return results;

    try {
      // 1. Dart / Flutter
      final pubspec = File(p.join(cleanCwd, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final txt = pubspec.readAsStringSync();
        final isFlutter = txt.contains('sdk: flutter') || txt.contains('flutter:');
        if (isFlutter) {
          results.addAll(const [
            RunbookCommand(
                id: 'fl_test',
                label: 'Flutter Test',
                command: 'flutter test --no-pub',
                category: 'test',
                source: 'pubspec.yaml'),
            RunbookCommand(
                id: 'fl_analyze',
                label: 'Analyze',
                command: 'flutter analyze --no-pub',
                category: 'test',
                source: 'pubspec.yaml'),
            RunbookCommand(
                id: 'fl_run',
                label: 'Flutter Run',
                command: 'flutter run',
                category: 'run',
                source: 'pubspec.yaml'),
          ]);
        } else {
          results.addAll(const [
            RunbookCommand(
                id: 'dart_test',
                label: 'Dart Test',
                command: 'dart test',
                category: 'test',
                source: 'pubspec.yaml'),
            RunbookCommand(
                id: 'dart_analyze',
                label: 'Dart Analyze',
                command: 'dart analyze',
                category: 'test',
                source: 'pubspec.yaml'),
          ]);
        }
      }

      // 2. Node.js (`package.json` scripts)
      final pkgJson = File(p.join(cleanCwd, 'package.json'));
      if (pkgJson.existsSync()) {
        final runner = File(p.join(cleanCwd, 'pnpm-lock.yaml')).existsSync()
            ? 'pnpm'
            : (File(p.join(cleanCwd, 'bun.lockb')).existsSync()
                ? 'bun'
                : (File(p.join(cleanCwd, 'yarn.lock')).existsSync()
                    ? 'yarn'
                    : 'npm run'));
        final parsed = jsonDecode(pkgJson.readAsStringSync());
        if (parsed is Map && parsed['scripts'] is Map) {
          final scripts = parsed['scripts'] as Map;
          for (final entry in scripts.entries.take(6)) {
            final name = entry.key.toString();
            final cat = name.contains('test') || name.contains('lint')
                ? 'test'
                : (name.contains('build') ? 'build' : 'run');
            results.add(RunbookCommand(
              id: 'npm_$name',
              label: '$runner $name',
              command: runner == 'npm run' && name == 'test'
                  ? 'npm test'
                  : '$runner $name',
              category: cat,
              source: 'package.json',
            ));
          }
        }
      }

      // 3. Python
      if (File(p.join(cleanCwd, 'pyproject.toml')).existsSync() ||
          File(p.join(cleanCwd, 'requirements.txt')).existsSync()) {
        results.addAll(const [
          RunbookCommand(
              id: 'py_test',
              label: 'Pytest',
              command: 'pytest -q',
              category: 'test',
              source: 'python'),
          RunbookCommand(
              id: 'py_pip',
              label: 'Install Reqs',
              command: 'pip install -r requirements.txt',
              category: 'build',
              source: 'python'),
        ]);
      }

      // 4. Rust (`Cargo.toml`)
      if (File(p.join(cleanCwd, 'Cargo.toml')).existsSync()) {
        results.addAll(const [
          RunbookCommand(
              id: 'cargo_test',
              label: 'Cargo Test',
              command: 'cargo test',
              category: 'test',
              source: 'Cargo.toml'),
          RunbookCommand(
              id: 'cargo_run',
              label: 'Cargo Run',
              command: 'cargo run',
              category: 'run',
              source: 'Cargo.toml'),
        ]);
      }

      // 5. Go (`go.mod`)
      if (File(p.join(cleanCwd, 'go.mod')).existsSync()) {
        results.addAll(const [
          RunbookCommand(
              id: 'go_test',
              label: 'Go Test',
              command: 'go test ./...',
              category: 'test',
              source: 'go.mod'),
          RunbookCommand(
              id: 'go_run',
              label: 'Go Run',
              command: 'go run .',
              category: 'run',
              source: 'go.mod'),
        ]);
      }

      // 6. Makefile targets
      final makefile = File(p.join(cleanCwd, 'Makefile'));
      if (makefile.existsSync()) {
        final lines = makefile.readAsLinesSync();
        var count = 0;
        for (final line in lines) {
          final m = RegExp(r'^([a-zA-Z0-9_.-]+):(?!=)').firstMatch(line);
          if (m != null && !m.group(1)!.startsWith('.')) {
            final target = m.group(1)!;
            results.add(RunbookCommand(
              id: 'make_$target',
              label: 'make $target',
              command: 'make $target',
              category: target.contains('test') ? 'test' : 'run',
              source: 'Makefile',
            ));
            if (++count >= 4) break;
          }
        }
      }
    } catch (_) {}

    return results;
  }

  static Future<List<RunbookCommand>> loadCustom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_customKey);
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List)
          .map((e) => RunbookCommand.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveCustom(RunbookCommand cmd) async {
    final current = (await loadCustom()).toList();
    final updated = [
      cmd,
      ...current.where((c) => c.id != cmd.id),
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _customKey, jsonEncode(updated.map((c) => c.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> removeCustom(String id) async {
    final updated = (await loadCustom()).where((c) => c.id != id).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _customKey, jsonEncode(updated.map((c) => c.toJson()).toList()));
    } catch (_) {}
  }
}

/// Extracts actionable URLs (`http(s)://...`, `localhost:PORT`) and source code
/// stack trace targets (`path/to/file.dart:42:7`) from terminal scrollback.
class TerminalLinkDetector {
  TerminalLinkDetector._();

  static final RegExp _urlRegex = RegExp(
    r'''https?://[^\s<>"'\)\]]+''',
    caseSensitive: false,
  );
  static final RegExp _fileLineRegex = RegExp(
    r'''([A-Za-z0-9_.\-/\\]+\.(?:dart|py|js|ts|tsx|jsx|rs|go|java|kt|c|cpp|h|json|yaml|yml|md|sh|ps1)):(\d+)(?::(\d+))?''',
  );

  static List<DetectedTerminalLink> extractFromTerminal(
    Terminal terminal, {
    int maxRecentLines = 120,
    int limit = 16,
  }) {
    final lines = terminal.buffer.lines;
    final start = (lines.length - maxRecentLines).clamp(0, lines.length);
    final chunk = <String>[];
    for (var i = lines.length - 1; i >= start; i--) {
      final t = lines[i].getText().trim();
      if (t.isNotEmpty) chunk.add(t);
    }
    return extractFromText(chunk.join('\n'), limit: limit);
  }

  static List<DetectedTerminalLink> extractFromText(
    String text, {
    int limit = 16,
  }) {
    final results = <DetectedTerminalLink>[];
    final seen = <String>{};

    for (final m in _urlRegex.allMatches(text)) {
      var u = m.group(0) ?? '';
      while (u.isNotEmpty &&
          (u.endsWith('.') ||
              u.endsWith(',') ||
              u.endsWith(')') ||
              u.endsWith(';') ||
              u.endsWith(']'))) {
        u = u.substring(0, u.length - 1);
      }
      if (u.length > 8 && seen.add('url:$u')) {
        results.add(DetectedTerminalLink(
          kind: TerminalLinkKind.url,
          label: u.replaceFirst(RegExp(r'^https?://'), ''),
          target: u,
        ));
        if (results.length >= limit) return results;
      }
    }

    for (final m in _fileLineRegex.allMatches(text)) {
      final file = m.group(1)!.replaceAll(r'\', '/');
      final line = int.tryParse(m.group(2) ?? '');
      final col = int.tryParse(m.group(3) ?? '');
      final key = 'file:$file:${line ?? 0}';
      if (seen.add(key)) {
        results.add(DetectedTerminalLink(
          kind: TerminalLinkKind.file,
          label: '${file.split('/').last}:${line ?? 1}',
          target: file,
          line: line,
          column: col,
        ));
        if (results.length >= limit) break;
      }
    }

    return results;
  }
}
