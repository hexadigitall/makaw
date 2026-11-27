import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Category of shell runtime available on the host OS or hybrid engine.
enum ShellCategory {
  hybrid,
  powershell,
  unix,
  wsl,
  system,
  ssh,
}

/// Discovered shell executable/runtime profile.
class ShellProfile {
  final String id;
  final String label;
  final String subtitle;
  final String executable;
  final List<String> arguments;
  final ShellCategory category;
  final bool isHybridBuiltIn;

  const ShellProfile({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.executable,
    this.arguments = const [],
    required this.category,
    this.isHybridBuiltIn = false,
  });

  String get targetType => switch (category) {
        ShellCategory.hybrid => 'hybrid',
        ShellCategory.wsl => 'wsl',
        ShellCategory.ssh => 'ssh',
        _ => 'local',
      };
}

/// Saved SSH workstation/server host configuration. Secret credentials
/// (passwords, PEM private keys, key passphrases) live separately inside
/// [FlutterSecureStorage] keyed by [id].
class SshHostProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authMethod; // 'password' | 'key'
  final bool autoTmux;
  final String tmuxSession;
  final String defaultRemoteDir;
  final DateTime createdAt;

  const SshHostProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authMethod = 'password',
    this.autoTmux = false,
    this.tmuxSession = 'makaw',
    this.defaultRemoteDir = '',
    required this.createdAt,
  });

  String get target => '$username@$host';
  String get displayTarget => port == 22 ? target : '$target:$port';

  SshHostProfile copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? authMethod,
    bool? autoTmux,
    String? tmuxSession,
    String? defaultRemoteDir,
  }) =>
      SshHostProfile(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        authMethod: authMethod ?? this.authMethod,
        autoTmux: autoTmux ?? this.autoTmux,
        tmuxSession: tmuxSession ?? this.tmuxSession,
        defaultRemoteDir: defaultRemoteDir ?? this.defaultRemoteDir,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod,
        'autoTmux': autoTmux,
        'tmuxSession': tmuxSession,
        'defaultRemoteDir': defaultRemoteDir,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SshHostProfile.fromJson(Map<String, dynamic> j) => SshHostProfile(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        host: (j['host'] as String?) ?? '',
        port: (j['port'] as num?)?.toInt() ?? 22,
        username: (j['username'] as String?) ?? 'root',
        authMethod: (j['authMethod'] as String?) ?? 'password',
        autoTmux: (j['autoTmux'] as bool?) ?? false,
        tmuxSession: (j['tmuxSession'] as String?) ?? 'makaw',
        defaultRemoteDir: (j['defaultRemoteDir'] as String?) ?? '',
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ??
            DateTime.now(),
      );

  /// Parses CLI SSH target expressions such as `ubuntu@192.168.1.20:2222` or
  /// `ssh://dev@mybox` or bare `mybox`.
  static ({String username, String host, int port})? parseTarget(
    String raw, {
    int defaultPort = 22,
    String defaultUser = 'root',
  }) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('ssh://')) s = s.substring(6);
    final slashIdx = s.indexOf('/');
    if (slashIdx >= 0) s = s.substring(0, slashIdx);

    var user = defaultUser;
    final atIdx = s.indexOf('@');
    if (atIdx > 0) {
      user = s.substring(0, atIdx).trim();
      s = s.substring(atIdx + 1).trim();
    }

    var port = defaultPort;
    var host = s;
    final colonIdx = s.lastIndexOf(':');
    if (colonIdx > 0 && !s.contains(']')) {
      final parsedPort = int.tryParse(s.substring(colonIdx + 1).trim());
      if (parsedPort != null && parsedPort > 0 && parsedPort <= 65535) {
        port = parsedPort;
        host = s.substring(0, colonIdx).trim();
      }
    }
    if (host.isEmpty) return null;
    return (username: user, host: host, port: port);
  }
}

/// Curated palette preset for Makaw Terminal 2.0.
class MakawTerminalThemePreset {
  final String id;
  final String label;
  final bool isLight;
  final TerminalTheme theme;

  const MakawTerminalThemePreset({
    required this.id,
    required this.label,
    this.isLight = false,
    required this.theme,
  });

  static const List<MakawTerminalThemePreset> presets = [
    MakawTerminalThemePreset(
      id: 'obsidian',
      label: 'Makaw Obsidian',
      theme: TerminalTheme(
        cursor: Color(0xFF38BDF8),
        selection: Color(0x5538BDF8),
        foreground: Color(0xFFE2E8F0),
        background: Color(0xFF090D16),
        black: Color(0xFF1E293B),
        red: Color(0xFFF87171),
        green: Color(0xFF34D399),
        yellow: Color(0xFFFBBF24),
        blue: Color(0xFF60A5FA),
        magenta: Color(0xFFC084FC),
        cyan: Color(0xFF22D3EE),
        white: Color(0xFFE2E8F0),
        brightBlack: Color(0xFF64748B),
        brightRed: Color(0xFFFCA5A5),
        brightGreen: Color(0xFF6EE7B7),
        brightYellow: Color(0xFFFDE68A),
        brightBlue: Color(0xFF93C5FD),
        brightMagenta: Color(0xFFD8B4FE),
        brightCyan: Color(0xFF67E8F9),
        brightWhite: Color(0xFFFFFFFF),
        searchHitBackground: Color(0xFFFBBF24),
        searchHitBackgroundCurrent: Color(0xFF22D3EE),
        searchHitForeground: Color(0xFF090D16),
      ),
    ),
    MakawTerminalThemePreset(
      id: 'tokyo_night',
      label: 'Tokyo Night',
      theme: TerminalTheme(
        cursor: Color(0xFF7AA2F7),
        selection: Color(0x557AA2F7),
        foreground: Color(0xFFA9B1D6),
        background: Color(0xFF1A1B26),
        black: Color(0xFF414868),
        red: Color(0xFFF7768E),
        green: Color(0xFF9ECE6A),
        yellow: Color(0xFFE0AF68),
        blue: Color(0xFF7AA2F7),
        magenta: Color(0xFFBB9AF7),
        cyan: Color(0xFF7DCFFF),
        white: Color(0xFFC0CAF5),
        brightBlack: Color(0xFF565F89),
        brightRed: Color(0xFFF7768E),
        brightGreen: Color(0xFF9ECE6A),
        brightYellow: Color(0xFFE0AF68),
        brightBlue: Color(0xFF7AA2F7),
        brightMagenta: Color(0xFFBB9AF7),
        brightCyan: Color(0xFF7DCFFF),
        brightWhite: Color(0xFFFFFFFF),
        searchHitBackground: Color(0xFFE0AF68),
        searchHitBackgroundCurrent: Color(0xFF9ECE6A),
        searchHitForeground: Color(0xFF1A1B26),
      ),
    ),
    MakawTerminalThemePreset(
      id: 'dracula',
      label: 'Dracula',
      theme: TerminalTheme(
        cursor: Color(0xFFF8F8F2),
        selection: Color(0x5544475A),
        foreground: Color(0xFFF8F8F2),
        background: Color(0xFF282A36),
        black: Color(0xFF21222C),
        red: Color(0xFFFF5555),
        green: Color(0xFF50FA7B),
        yellow: Color(0xFFF1FA8C),
        blue: Color(0xFFBD93F9),
        magenta: Color(0xFFFF79C6),
        cyan: Color(0xFF8BE9FD),
        white: Color(0xFFF8F8F2),
        brightBlack: Color(0xFF6272A4),
        brightRed: Color(0xFFFF6E6E),
        brightGreen: Color(0xFF69FF94),
        brightYellow: Color(0xFFFFFFA5),
        brightBlue: Color(0xFFD6ACFF),
        brightMagenta: Color(0xFFFF92DF),
        brightCyan: Color(0xFFA4FFFF),
        brightWhite: Color(0xFFFFFFFF),
        searchHitBackground: Color(0xFFF1FA8C),
        searchHitBackgroundCurrent: Color(0xFF50FA7B),
        searchHitForeground: Color(0xFF282A36),
      ),
    ),
    MakawTerminalThemePreset(
      id: 'solarized_dark',
      label: 'Solarized Dark',
      theme: TerminalTheme(
        cursor: Color(0xFF93A1A1),
        selection: Color(0x55073642),
        foreground: Color(0xFF839496),
        background: Color(0xFF002B36),
        black: Color(0xFF073642),
        red: Color(0xFFDC322F),
        green: Color(0xFF859900),
        yellow: Color(0xFFB58900),
        blue: Color(0xFF268BD2),
        magenta: Color(0xFFD33682),
        cyan: Color(0xFF2AA198),
        white: Color(0xFFEEE8D5),
        brightBlack: Color(0xFF586E75),
        brightRed: Color(0xFFCB4B16),
        brightGreen: Color(0xFF586E75),
        brightYellow: Color(0xFF657B83),
        brightBlue: Color(0xFF839496),
        brightMagenta: Color(0xFF6C71C4),
        brightCyan: Color(0xFF93A1A1),
        brightWhite: Color(0xFFFDF6E3),
        searchHitBackground: Color(0xFFB58900),
        searchHitBackgroundCurrent: Color(0xFF2AA198),
        searchHitForeground: Color(0xFF002B36),
      ),
    ),
    MakawTerminalThemePreset(
      id: 'paper_light',
      label: 'Paper Light',
      isLight: true,
      theme: TerminalTheme(
        cursor: Color(0xFF2563EB),
        selection: Color(0x443B82F6),
        foreground: Color(0xFF1E293B),
        background: Color(0xFFF8FAFC),
        black: Color(0xFF1E293B),
        red: Color(0xFFDC2626),
        green: Color(0xFF15803D),
        yellow: Color(0xFFB45309),
        blue: Color(0xFF2563EB),
        magenta: Color(0xFF7C3AED),
        cyan: Color(0xFF0E7490),
        white: Color(0xFF64748B),
        brightBlack: Color(0xFF475569),
        brightRed: Color(0xFFEF4444),
        brightGreen: Color(0xFF16A34A),
        brightYellow: Color(0xFFD97706),
        brightBlue: Color(0xFF3B82F6),
        brightMagenta: Color(0xFF8B5CF6),
        brightCyan: Color(0xFF06B6D4),
        brightWhite: Color(0xFF0F172A),
        searchHitBackground: Color(0xFFFDE047),
        searchHitBackgroundCurrent: Color(0xFF38BDF8),
        searchHitForeground: Color(0xFF0F172A),
      ),
    ),
    MakawTerminalThemePreset(
      id: 'oled_contrast',
      label: 'OLED Black',
      theme: TerminalThemes.whiteOnBlack,
    ),
  ];

  static MakawTerminalThemePreset byId(String id) {
    return presets.firstWhere(
      (p) => p.id == id,
      orElse: () => presets.first,
    );
  }
}
