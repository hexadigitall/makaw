import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../../../core/platform/conditional_pty.dart';
import '../../../core/services/terminal_sessions_store.dart';
import '../../../app/providers/service_providers.dart';

/// A live terminal session: its own transcript buffer and PTY (started only
/// while active so we don't hold many processes open).
class _LiveSession {
  final int id;
  final String name;
  final Terminal term = Terminal(maxLines: 10000);
  final TerminalController controller = TerminalController();
  Pty? _pty;
  bool started = false;

  _LiveSession({required this.id, required this.name});
}

/// Terminal tool with multiple, user-created sessions. Sessions are persisted
/// so they can be queued as "Recent Sessions" on the Terminal hub. Only the
/// active session keeps a live PTY; switching sessions starts/resumes that
/// session's process while its transcript scrollback is retained.
class TerminalSessionsPage extends ConsumerStatefulWidget {
  final int? initialSessionId;
  const TerminalSessionsPage({super.key, this.initialSessionId});

  @override
  ConsumerState<TerminalSessionsPage> createState() => _TerminalSessionsPageState();
}

class _TerminalSessionsPageState extends ConsumerState<TerminalSessionsPage> {
  final Map<int, _LiveSession> _sessions = {};
  final List<int> _order = [];
  int? _activeId;
  final _nameCtrl = TextEditingController();
  bool _ready = false;

  TerminalSessionsStore get _store => ref.read(terminalSessionsStoreProvider) ?? TerminalSessionsStore();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final s in _sessions.values) {
      s._pty?.kill();
      s.controller.dispose();
    }
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final metas = await _store.load();
    for (final m in metas) {
      _sessions[m.id] = _LiveSession(id: m.id, name: m.name);
      _order.add(m.id);
    }
    if (widget.initialSessionId == -1) {
      final m = await _store.create('Terminal ${_order.length + 1}');
      _sessions[m.id] = _LiveSession(id: m.id, name: m.name);
      _order.add(m.id);
    } else if (_order.isEmpty) {
      final m = await _store.create('Terminal 1');
      _sessions[m.id] = _LiveSession(id: m.id, name: m.name);
      _order.add(m.id);
    }
    int? target = widget.initialSessionId;
    if (target == null || target == -1 || !_order.contains(target)) target = _order.first;
    if (!mounted) return;
    setState(() {
      _ready = true;
      _activeId = target;
    });
    _activate(target);
  }

  _LiveSession? get _active => _activeId == null ? null : _sessions[_activeId];

  void _activate(int id) {
    final previous = _active;
    if (previous != null && previous.id != id) {
      // Release the previous PTY but keep its transcript buffer.
      previous._pty?.kill();
      previous._pty = null;
      previous.started = false;
    }
    final session = _sessions[id];
    if (session == null) return;
    _activeId = id;
    _startSession(session);
    _store.recentOpen(id);
  }

  void _startSession(_LiveSession session) {
    if (session.started) return;
    if (kIsWeb) return;
    try {
      final pty = Pty.start(
        Platform.isAndroid ? 'sh' : 'bash',
        arguments: Platform.isAndroid ? ['-c', 'cd /storage/emulated/0 && sh'] : [],
        environment: {'TERM': 'xterm-256color'},
        workingDirectory: Platform.isAndroid ? '/storage/emulated/0' : null,
      );
      session._pty = pty;
      session.started = true;
      pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(session.term.write);
      pty.exitCode.then((_) => session.term.write('\r\n[process exited]'));
      session.term.onOutput = (data) {
        pty.write(const Utf8Encoder().convert(data));
      };
    } catch (_) {}
  }

  Future<void> _newSession() async {
    final name = await _promptName();
    if (name == null || !mounted) return;
    final m = await _store.create(name);
    if (!mounted) return;
    final session = _LiveSession(id: m.id, name: m.name);
    setState(() {
      _sessions[m.id] = session;
      _order.add(m.id);
    });
    _activate(m.id);
  }

  Future<String?> _promptName() async {
    _nameCtrl.clear();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('New Terminal Session', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: _nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Session name (optional)',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(_nameCtrl.text.trim()), child: const Text('Create', style: TextStyle(color: Color(0xFF818CF8)))),
        ],
      ),
    );
    return (name == null || name.isEmpty) ? null : name;
  }

  void _closeSession(int id) {
    if (_order.length <= 1) {
      _startSession(_sessions[id]!);
      return;
    }
    final idx = _order.indexOf(id);
    _sessions[id]?._pty?.kill();
    setState(() {
      _sessions.remove(id);
      _order.removeAt(idx);
      if (_activeId == id) {
        _activeId = _order[idx.clamp(0, _order.length - 1)];
      }
    });
    _store.remove(id);
    if (_activeId != null) _startSession(_sessions[_activeId!]!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Terminal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text(
              _active?.name ?? '',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.post_add, color: Theme.of(context).colorScheme.onSurface),
            onPressed: _newSession,
            tooltip: 'New session',
          ),
        ],
      ),
      body: !_ready
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          : Column(
              children: [
                _buildSessionBar(),
                Expanded(child: _buildTerminal()),
                _buildControls(),
              ],
            ),
    );
  }

  Widget _buildSessionBar() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final id in _order) _buildSessionChip(id),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.add, color: Color(0xFF818CF8), size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: _newSession,
              tooltip: 'New session',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionChip(int id) {
    final s = _sessions[id];
    if (s == null) return const SizedBox.shrink();
    final active = id == _activeId;
    return GestureDetector(
      onTap: () => setState(() => _activate(id)),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.only(left: 12, right: 6),
        height: 34,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF818CF8) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(s.name,
                style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _closeSession(id),
              child: Icon(Icons.close, size: 15, color: active ? Colors.black87 : Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminal() {
    final active = _active;
    if (active == null) return const SizedBox.shrink();
    if (kIsWeb) {
      return const Center(child: Text('Terminal is not available on web', style: TextStyle(color: Colors.white54)));
    }
    return TerminalView(
      active.term,
      controller: active.controller,
      theme: TerminalThemes.defaultTheme,
      autofocus: true,
    );
  }

  Widget _buildControls() {
    final active = _active;
    final pty = active?._pty;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.terminal, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(active?._pty != null ? '● ${active?.name}' : 'idle', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.block, size: 18),
            tooltip: 'Interrupt (Ctrl+C)',
            visualDensity: VisualDensity.compact,
            onPressed: pty == null ? null : () => pty.write(const Utf8Encoder().convert('\x03')),
          ),
          IconButton(
            icon: const Icon(Icons.stop, size: 18),
            tooltip: 'EOF (Ctrl+D)',
            visualDensity: VisualDensity.compact,
            onPressed: pty == null ? null : () => pty.write(const Utf8Encoder().convert('\x04')),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Clear',
            visualDensity: VisualDensity.compact,
            onPressed: () { active?.term.eraseDisplay(); active?.term.eraseScrollbackOnly(); },
          ),
        ],
      ),
    );
  }
}
