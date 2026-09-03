import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadata for a terminal session (the live PTY/terminal lives in the
/// terminal tool page; here we persist the identity so recently-created
/// sessions can be queued on the Terminal hub).
class TerminalSessionMeta {
  final int id;
  final String name;
  final DateTime createdAt;

  const TerminalSessionMeta({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TerminalSessionMeta.fromJson(Map<String, dynamic> j) => TerminalSessionMeta(
        id: j['id'] as int,
        name: (j['name'] as String?) ?? 'Terminal',
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now(),
      );
}

/// Persisted list of terminal sessions, most recent first. Shared with the
/// Terminal hub's "Recent Sessions" section.
class TerminalSessionsStore extends ChangeNotifier {
  static const _key = 'terminal_sessions';
  List<TerminalSessionMeta> _sessions = [];
  bool _loaded = false;

  List<TerminalSessionMeta> get sessions => _sessions;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _sessions = (jsonDecode(raw) as List)
            .map((e) => TerminalSessionMeta.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (_) {
        _sessions = [];
      }
    }
    _loaded = true;
  }

  Future<List<TerminalSessionMeta>> load() async {
    await _ensureLoaded();
    return _sessions;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_sessions.map((s) => s.toJson()).toList()));
  }

  /// Create a new session and pin it to the top of the recent list.
  Future<TerminalSessionMeta> create(String name) async {
    await _ensureLoaded();
    final session = TerminalSessionMeta(
      id: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
      name: name.isEmpty ? 'Terminal ${_sessions.length + 1}' : name,
      createdAt: DateTime.now(),
    );
    _sessions = [session, ..._sessions.where((s) => s.id != session.id)];
    _persist();
    notifyListeners();
    return session;
  }

  Future<void> remove(int id) async {
    await _ensureLoaded();
    _sessions = _sessions.where((s) => s.id != id).toList();
    _persist();
    notifyListeners();
  }

  Future<void> recentOpen(int id) async {
    await _ensureLoaded();
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final s = _sessions.removeAt(idx);
    _sessions = [TerminalSessionMeta(id: s.id, name: s.name, createdAt: DateTime.now()), ..._sessions];
    _persist();
    notifyListeners();
  }
}
