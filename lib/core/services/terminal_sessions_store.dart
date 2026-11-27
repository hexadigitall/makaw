import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted metadata for a terminal session. Backwards compatible with older
/// `{id, name, createdAt}` entries while storing working directory, shell/target
/// profile, linked SSH host ID, pin state, and last command for seamless
/// resumption across restarts and between Terminal & Studio.
class TerminalSessionMeta {
  final int id;
  final String name;
  final String targetType; // 'local' | 'hybrid' | 'wsl' | 'ssh'
  final String shellId; // e.g. 'pwsh', 'powershell', 'makaw-sh', 'wsl:Ubuntu', 'ssh'
  final String cwd;
  final String? hostId;
  final String lastCommand;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TerminalSessionMeta({
    required this.id,
    required this.name,
    this.targetType = 'local',
    this.shellId = '',
    this.cwd = '',
    this.hostId,
    this.lastCommand = '',
    this.isPinned = false,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  TerminalSessionMeta copyWith({
    String? name,
    String? targetType,
    String? shellId,
    String? cwd,
    String? hostId,
    bool clearHostId = false,
    String? lastCommand,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TerminalSessionMeta(
      id: id,
      name: name ?? this.name,
      targetType: targetType ?? this.targetType,
      shellId: shellId ?? this.shellId,
      cwd: cwd ?? this.cwd,
      hostId: clearHostId ? null : (hostId ?? this.hostId),
      lastCommand: lastCommand ?? this.lastCommand,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targetType': targetType,
        'shellId': shellId,
        'cwd': cwd,
        if (hostId != null) 'hostId': hostId,
        'lastCommand': lastCommand,
        'isPinned': isPinned,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TerminalSessionMeta.fromJson(Map<String, dynamic> j) {
    final created =
        DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now();
    final updated =
        DateTime.tryParse((j['updatedAt'] as String?) ?? '') ?? created;
    return TerminalSessionMeta(
      id: j['id'] as int,
      name: (j['name'] as String?) ?? 'Terminal',
      targetType: (j['targetType'] as String?) ?? 'local',
      shellId: (j['shellId'] as String?) ?? '',
      cwd: (j['cwd'] as String?) ?? '',
      hostId: j['hostId'] as String?,
      lastCommand: (j['lastCommand'] as String?) ?? '',
      isPinned: (j['isPinned'] as bool?) ?? false,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

/// Visual & UX preferences for Makaw Terminal, persisted locally.
class TerminalAppearancePrefs {
  final String themeId;
  final double fontSize;
  final String cursorStyle; // 'block' | 'underline' | 'bar'
  final bool showSoftKeys;
  final bool showSoftKeyRow2;

  const TerminalAppearancePrefs({
    this.themeId = 'obsidian',
    this.fontSize = 13.5,
    this.cursorStyle = 'block',
    this.showSoftKeys = true,
    this.showSoftKeyRow2 = false,
  });

  TerminalAppearancePrefs copyWith({
    String? themeId,
    double? fontSize,
    String? cursorStyle,
    bool? showSoftKeys,
    bool? showSoftKeyRow2,
  }) =>
      TerminalAppearancePrefs(
        themeId: themeId ?? this.themeId,
        fontSize: fontSize ?? this.fontSize,
        cursorStyle: cursorStyle ?? this.cursorStyle,
        showSoftKeys: showSoftKeys ?? this.showSoftKeys,
        showSoftKeyRow2: showSoftKeyRow2 ?? this.showSoftKeyRow2,
      );

  Map<String, dynamic> toJson() => {
        'themeId': themeId,
        'fontSize': fontSize,
        'cursorStyle': cursorStyle,
        'showSoftKeys': showSoftKeys,
        'showSoftKeyRow2': showSoftKeyRow2,
      };

  factory TerminalAppearancePrefs.fromJson(Map<String, dynamic> j) =>
      TerminalAppearancePrefs(
        themeId: (j['themeId'] as String?) ?? 'obsidian',
        fontSize: ((j['fontSize'] as num?)?.toDouble() ?? 13.5).clamp(10.0, 24.0),
        cursorStyle: (j['cursorStyle'] as String?) ?? 'block',
        showSoftKeys: (j['showSoftKeys'] as bool?) ?? true,
        showSoftKeyRow2: (j['showSoftKeyRow2'] as bool?) ?? false,
      );
}

/// Persisted list of terminal sessions, pinned-first then most recent first.
/// Shared between [TerminalRuntimeManager], `TerminalSessionsPage`, and the
/// Home/Terminal hub's "Recent Sessions" section.
class TerminalSessionsStore extends ChangeNotifier {
  static const _key = 'terminal_sessions';
  static const _prefsKey = 'terminal_appearance_v1';

  List<TerminalSessionMeta> _sessions = [];
  TerminalAppearancePrefs _appearance = const TerminalAppearancePrefs();
  bool _loaded = false;

  List<TerminalSessionMeta> get sessions => _sessions;
  TerminalAppearancePrefs get appearance => _appearance;

  static int _compareSessions(TerminalSessionMeta a, TerminalSessionMeta b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        try {
          _sessions = (jsonDecode(raw) as List)
              .map((e) => TerminalSessionMeta.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort(_compareSessions);
        } catch (_) {
          _sessions = [];
        }
      }
      final appRaw = prefs.getString(_prefsKey);
      if (appRaw != null) {
        try {
          _appearance = TerminalAppearancePrefs.fromJson(
              jsonDecode(appRaw) as Map<String, dynamic>);
        } catch (_) {}
      }
    } catch (_) {
      // Safe fallback when SharedPreferences is uninitialized in headless unit tests.
    }
    _loaded = true;
  }

  Future<List<TerminalSessionMeta>> load() async {
    await _ensureLoaded();
    return _sessions;
  }

  Future<TerminalAppearancePrefs> loadAppearance() async {
    await _ensureLoaded();
    return _appearance;
  }

  Future<void> saveAppearance(TerminalAppearancePrefs next) async {
    await _ensureLoaded();
    _appearance = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_appearance.toJson()));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode(_sessions.map((s) => s.toJson()).toList()));
    } catch (_) {}
  }

  /// Create a new session and pin it to the top of the recent list.
  Future<TerminalSessionMeta> create(
    String name, {
    String targetType = 'local',
    String shellId = '',
    String cwd = '',
    String? hostId,
    bool isPinned = false,
  }) async {
    await _ensureLoaded();
    final now = DateTime.now();
    final session = TerminalSessionMeta(
      id: now.microsecondsSinceEpoch & 0x7fffffff,
      name: name.isEmpty ? 'Terminal ${_sessions.length + 1}' : name,
      targetType: targetType,
      shellId: shellId,
      cwd: cwd,
      hostId: hostId,
      isPinned: isPinned,
      createdAt: now,
      updatedAt: now,
    );
    _sessions = [session, ..._sessions.where((s) => s.id != session.id)]
      ..sort(_compareSessions);
    _persist();
    notifyListeners();
    return session;
  }

  Future<void> updateMeta(
    int id, {
    String? name,
    String? targetType,
    String? shellId,
    String? cwd,
    String? hostId,
    bool clearHostId = false,
    String? lastCommand,
    bool? isPinned,
  }) async {
    await _ensureLoaded();
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _sessions[idx] = _sessions[idx].copyWith(
      name: name,
      targetType: targetType,
      shellId: shellId,
      cwd: cwd,
      hostId: hostId,
      clearHostId: clearHostId,
      lastCommand: lastCommand,
      isPinned: isPinned,
      updatedAt: DateTime.now(),
    );
    _sessions.sort(_compareSessions);
    _persist();
    notifyListeners();
  }

  Future<void> togglePin(int id) async {
    await _ensureLoaded();
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _sessions[idx] = _sessions[idx].copyWith(
      isPinned: !_sessions[idx].isPinned,
      updatedAt: DateTime.now(),
    );
    _sessions.sort(_compareSessions);
    _persist();
    notifyListeners();
  }

  Future<void> remove(int id) async {
    await _ensureLoaded();
    _sessions = _sessions.where((s) => s.id != id).toList();
    _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _ensureLoaded();
    _sessions = [];
    _persist();
    notifyListeners();
  }

  Future<void> recentOpen(int id) async {
    await _ensureLoaded();
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _sessions[idx] = _sessions[idx].copyWith(updatedAt: DateTime.now());
    _sessions.sort(_compareSessions);
    _persist();
    notifyListeners();
  }
}
