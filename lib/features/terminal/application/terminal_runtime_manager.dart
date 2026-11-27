import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../../core/platform/conditional_pty.dart';
import '../../../core/services/terminal_sessions_store.dart';
import '../data/makaw_hybrid_shell.dart';
import '../data/shell_discovery.dart';
import '../data/ssh_terminal_transport.dart';
import '../data/ssh_vault_service.dart';
import '../domain/terminal_models.dart';

enum TerminalSessionState { idle, connecting, running, exited, error }

class TerminalSearchMatch {
  final int lineIndex;
  final int startCol;
  final int endCol;
  const TerminalSearchMatch({
    required this.lineIndex,
    required this.startCol,
    required this.endCol,
  });
}

/// Live in-memory runtime for a single terminal tab. Held by
/// [TerminalRuntimeManager] at app scope so switching tabs or navigating across
/// Makaw routes never terminates running commands or SSH connections.
class TerminalSessionRuntime {
  final int id;
  String name;
  String targetType; // 'local' | 'hybrid' | 'wsl' | 'ssh'
  String shellId;
  String shellLabel;
  String cwd;
  String? hostId;
  String lastCommand;
  int? lastExitCode;
  bool isPinned;
  TerminalSessionState state;

  final Terminal terminal = Terminal(maxLines: 10000);
  final TerminalController controller = TerminalController();

  Pty? _pty;
  MakawHybridShell? _hybrid;
  SshTerminalTransport? _ssh;
  StreamSubscription<String>? _hybridSub;
  int _generation = 0;

  TerminalSessionRuntime({
    required this.id,
    required this.name,
    required this.targetType,
    required this.shellId,
    required this.shellLabel,
    required this.cwd,
    this.hostId,
    this.lastCommand = '',
    this.lastExitCode,
    this.isPinned = false,
    this.state = TerminalSessionState.idle,
  });

  bool get isAlive =>
      _pty != null ||
      _hybrid != null ||
      (_ssh != null && _ssh!.isConnected);

  void writeString(String text) {
    if (_pty != null) {
      _pty!.write(utf8.encode(text));
    } else if (_hybrid != null) {
      _hybrid!.feedInput(text);
    } else if (_ssh != null) {
      _ssh!.writeString(text);
    }
  }

  void resize(int cols, int rows) {
    if (cols <= 0 || rows <= 0) return;
    try {
      _pty?.resize(rows, cols);
    } catch (_) {}
    _hybrid?.resize(cols, rows);
    _ssh?.resize(rows, cols);
  }

  void interrupt() => writeString('\x03');
  void eof() => writeString('\x04');

  void clearDisplay() {
    terminal.eraseDisplay();
    terminal.eraseScrollbackOnly();
    _hybrid?.reprintPrompt();
  }

  void stopProcess() {
    _generation++;
    try {
      _pty?.kill();
    } catch (_) {}
    _pty = null;

    _hybridSub?.cancel();
    _hybridSub = null;
    try {
      _hybrid?.close();
    } catch (_) {}
    _hybrid = null;

    _ssh?.dispose();
    _ssh = null;

    state = TerminalSessionState.exited;
  }

  void dispose() {
    stopProcess();
    controller.dispose();
  }
}

/// Singleton session & process orchestrator for Makaw Terminal 2.0.
///
/// Owns all live PTY, `makaw-sh` hybrid shell, and `dartssh2` SSH transports
/// above widget lifecycles, exposes multi-shell discovery, scrollback search,
/// split-pane secondary selection, and persisted appearance settings.
class TerminalRuntimeManager extends ChangeNotifier {
  final TerminalSessionsStore store;
  final SshVaultService sshVault;

  final Map<int, TerminalSessionRuntime> _runtimes = {};
  final List<int> _order = [];
  int? _activeId;
  int? _splitSecondaryId;
  bool _splitEnabled = false;
  TerminalAppearancePrefs _appearance = const TerminalAppearancePrefs();
  List<ShellProfile> _availableShells = [];
  bool _initialized = false;

  /// Optional interactive secret prompt injected by the active Terminal UI.
  Future<String?> Function(String prompt)? onPromptPassword;

  /// Optional file opener callback (`open <file>` from `makaw-sh`).
  Future<void> Function(String filePath)? onOpenFile;

  TerminalRuntimeManager({
    TerminalSessionsStore? store,
    SshVaultService? sshVault,
  })  : store = store ?? TerminalSessionsStore(),
        sshVault = sshVault ?? SshVaultService();

  bool get initialized => _initialized;
  List<int> get order => List.unmodifiable(_order);
  TerminalSessionRuntime? get activeSession =>
      _activeId == null ? null : _runtimes[_activeId];
  int? get activeId => _activeId;
  bool get splitEnabled => _splitEnabled;
  int? get splitSecondaryId => _splitSecondaryId;
  TerminalSessionRuntime? get splitSecondarySession =>
      _splitSecondaryId == null ? null : _runtimes[_splitSecondaryId];
  TerminalAppearancePrefs get appearance => _appearance;
  List<ShellProfile> get availableShells => List.unmodifiable(_availableShells);

  TerminalSessionRuntime? sessionById(int id) => _runtimes[id];
  bool isSessionRunning(int id) => _runtimes[id]?.isAlive ?? false;

  Future<void> ensureInitialized({int? requestedSessionId}) async {
    if (!_initialized) {
      _appearance = await store.loadAppearance();
      _availableShells = await ShellDiscovery.discoverLocalShells();
      await sshVault.loadHosts();
      final metas = await store.load();
      for (final m in metas) {
        if (_runtimes.containsKey(m.id)) continue;
        _runtimes[m.id] = _runtimeFromMeta(m);
        _order.add(m.id);
      }
      _initialized = true;
    }

    if (requestedSessionId == -1) {
      await createLocalSession();
      return;
    }

    if (_order.isEmpty) {
      await createLocalSession();
      return;
    }

    final target = (requestedSessionId != null && _order.contains(requestedSessionId))
        ? requestedSessionId
        : (_activeId != null && _order.contains(_activeId) ? _activeId! : _order.first);
    await activateSession(target);
  }

  TerminalSessionRuntime _runtimeFromMeta(TerminalSessionMeta m) {
    final defaultShell = _availableShells.isNotEmpty
        ? ShellDiscovery.selectPreferredProfile(_availableShells, preferredShellId: m.shellId)
        : null;
    final resolvedShellId = m.shellId.isNotEmpty
        ? m.shellId
        : (defaultShell?.id ?? (Platform.isAndroid ? 'makaw-sh' : 'powershell'));
    return TerminalSessionRuntime(
      id: m.id,
      name: m.name,
      targetType: m.targetType.isNotEmpty
          ? m.targetType
          : (defaultShell?.targetType ?? 'local'),
      shellId: resolvedShellId,
      shellLabel: defaultShell?.label ?? resolvedShellId,
      cwd: m.cwd.isNotEmpty ? m.cwd : ShellDiscovery.resolveDefaultCwd(),
      hostId: m.hostId,
      lastCommand: m.lastCommand,
      isPinned: m.isPinned,
    );
  }

  Future<void> refreshEnvironment() async {
    _availableShells = await ShellDiscovery.discoverLocalShells();
    await sshVault.loadHosts();
    notifyListeners();
  }

  Future<TerminalSessionRuntime> createLocalSession({
    String? name,
    ShellProfile? profile,
    String? cwd,
  }) async {
    if (!_initialized) await ensureInitialized();
    final chosen = profile ??
        (_availableShells.isNotEmpty
            ? ShellDiscovery.selectPreferredProfile(_availableShells)
            : const ShellProfile(
                id: 'makaw-sh',
                label: 'Makaw Hybrid Shell',
                subtitle: 'Built-in shell',
                executable: 'makaw-sh',
                category: ShellCategory.hybrid,
                isHybridBuiltIn: true,
              ));
    final resolvedCwd = ShellDiscovery.resolveDefaultCwd(cwd);
    final label = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (chosen.id == 'makaw-sh' ? 'makaw ${_order.length + 1}' : chosen.label.split(' ').first);

    final meta = await store.create(
      label,
      targetType: chosen.targetType,
      shellId: chosen.id,
      cwd: resolvedCwd,
    );
    final rt = TerminalSessionRuntime(
      id: meta.id,
      name: meta.name,
      targetType: chosen.targetType,
      shellId: chosen.id,
      shellLabel: chosen.label,
      cwd: resolvedCwd,
    );
    _runtimes[meta.id] = rt;
    _order.add(meta.id);
    await activateSession(meta.id);
    return rt;
  }

  Future<TerminalSessionRuntime> createSshSession(SshHostProfile host) async {
    if (!_initialized) await ensureInitialized();
    final meta = await store.create(
      host.name,
      targetType: 'ssh',
      shellId: 'ssh',
      cwd: host.defaultRemoteDir.isNotEmpty ? host.defaultRemoteDir : '~',
      hostId: host.id,
    );
    final rt = TerminalSessionRuntime(
      id: meta.id,
      name: meta.name,
      targetType: 'ssh',
      shellId: 'ssh',
      shellLabel: 'SSH · ${host.displayTarget}',
      cwd: meta.cwd,
      hostId: host.id,
    );
    _runtimes[meta.id] = rt;
    _order.add(meta.id);
    await activateSession(meta.id);
    return rt;
  }

  /// Activates [id] WITHOUT killing any other background tab!
  Future<void> activateSession(int id) async {
    final rt = _runtimes[id];
    if (rt == null) return;
    _activeId = id;
    unawaited(store.recentOpen(id));
    if (!rt.isAlive && rt.state == TerminalSessionState.idle) {
      await startOrRestartRuntime(rt);
    } else {
      notifyListeners();
    }
  }

  Future<void> restartSession(int id, {ShellProfile? newProfile}) async {
    final rt = _runtimes[id];
    if (rt == null) return;
    rt.stopProcess();
    if (newProfile != null) {
      rt.shellId = newProfile.id;
      rt.shellLabel = newProfile.label;
      rt.targetType = newProfile.targetType;
      rt.hostId = null;
      await store.updateMeta(
        id,
        shellId: newProfile.id,
        targetType: newProfile.targetType,
        clearHostId: true,
      );
    }
    await startOrRestartRuntime(rt);
  }

  Future<void> startOrRestartRuntime(TerminalSessionRuntime rt) async {
    rt.stopProcess();
    final gen = ++rt._generation;

    // 1) SSH Target
    if (rt.targetType == 'ssh' && rt.hostId != null) {
      final host = sshVault.findByIdOrName(rt.hostId!);
      if (host != null) {
        await _attachSsh(rt, host, gen);
        return;
      }
    }

    // 2) Hybrid built-in shell (`makaw-sh`)
    final profile = ShellDiscovery.selectPreferredProfile(
      _availableShells,
      preferredShellId: rt.shellId,
    );
    if (profile.isHybridBuiltIn || kIsWeb) {
      if (kIsWeb) {
        rt.terminal.write('Terminal PTY is not available on Web.\r\n');
        rt.state = TerminalSessionState.idle;
        notifyListeners();
        return;
      }
      _startHybridShell(rt, gen);
      return;
    }

    // 3) Native OS PTY with cascade fallback
    final fallbackChain = <ShellProfile>[
      profile,
      ..._availableShells.where((p) => p.id != profile.id),
    ];
    _spawnPtyChain(rt, fallbackChain, gen);
  }

  void _startHybridShell(TerminalSessionRuntime rt, int gen) {
    final hybrid = MakawHybridShell(
      initialCwd: rt.cwd,
      onListSshHosts: () => sshVault.loadHosts(),
      onConnectSsh: (target) async {
        final saved = sshVault.findByIdOrName(target);
        if (saved != null) {
          await createSshSession(saved);
          return;
        }
        final parsed = SshHostProfile.parseTarget(target);
        if (parsed == null) {
          rt.terminal.write(
              '\x1b[31mInvalid SSH target "$target". Try user@host[:port].\x1b[0m\r\n');
          return;
        }
        final adhoc = await sshVault.saveHost(SshHostProfile(
          id: '',
          name: parsed.host,
          host: parsed.host,
          port: parsed.port,
          username: parsed.username,
          authMethod: 'password',
          createdAt: DateTime.now(),
        ));
        await createSshSession(adhoc);
      },
      onSwitchShell: (shellId) async {
        final match = ShellDiscovery.selectPreferredProfile(
          _availableShells,
          preferredShellId: shellId,
        );
        if (!match.isHybridBuiltIn) {
          await restartSession(rt.id, newProfile: match);
        }
      },
      onOpenFile: (path) async => onOpenFile?.call(path),
      onCwdChanged: (newCwd) {
        rt.cwd = newCwd;
        unawaited(store.updateMeta(rt.id, cwd: newCwd));
        notifyListeners();
      },
      onCommandCompleted: (cmd, exitCode) {
        rt.lastCommand = cmd;
        rt.lastExitCode = exitCode;
        unawaited(store.updateMeta(rt.id, lastCommand: cmd));
        notifyListeners();
      },
    );

    rt._hybrid = hybrid;
    rt.state = TerminalSessionState.running;
    rt.shellLabel = 'Makaw Hybrid Shell';
    if (rt.terminal.viewWidth > 0) {
      hybrid.resize(rt.terminal.viewWidth, rt.terminal.viewHeight);
    }

    rt._hybridSub = hybrid.output.listen((chunk) {
      if (gen != rt._generation) return;
      rt.terminal.write(chunk);
    });

    rt.terminal.onOutput = (data) {
      if (gen != rt._generation) return;
      hybrid.feedInput(data);
    };
    rt.terminal.onResize = (w, h, pw, ph) {
      if (gen != rt._generation) return;
      rt.resize(w, h);
    };

    hybrid.exitCode.then((code) {
      if (gen != rt._generation) return;
      rt._hybrid = null;
      rt.lastExitCode = code;
      rt.state = TerminalSessionState.exited;
      rt.terminal.write('\r\n\x1b[90m[makaw-sh exited ($code)]\x1b[0m');
      notifyListeners();
    });

    hybrid.start();
    notifyListeners();
  }

  void _spawnPtyChain(
    TerminalSessionRuntime rt,
    List<ShellProfile> chain,
    int gen,
  ) {
    if (chain.isEmpty) {
      _startHybridShell(rt, gen);
      return;
    }
    final chosen = chain.first;
    final remaining = chain.sublist(1);
    if (chosen.isHybridBuiltIn) {
      _startHybridShell(rt, gen);
      return;
    }

    final cwd = ShellDiscovery.resolveDefaultCwd(rt.cwd);
    try {
      final pty = Pty.start(
        chosen.executable,
        arguments: chosen.arguments,
        environment: {'TERM': 'xterm-256color'},
        workingDirectory: cwd,
      );
      pty.resize(rt.terminal.viewHeight.clamp(12, 120), rt.terminal.viewWidth.clamp(40, 240));
      rt._pty = pty;
      rt.cwd = cwd;
      rt.shellId = chosen.id;
      rt.shellLabel = chosen.label;
      rt.state = TerminalSessionState.running;

      final startedAt = DateTime.now();
      final outBuf = StringBuffer();

      pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) {
        if (gen != rt._generation) return;
        outBuf.write(chunk);
        rt.terminal.write(chunk);
      });

      if (Platform.isWindows && chosen.id == 'cmd') {
        pty.write(utf8.encode('chcp 65001>nul\r\n'));
      }

      rt.terminal.onOutput = (data) {
        if (gen != rt._generation) return;
        pty.write(utf8.encode(data));
      };
      rt.terminal.onResize = (w, h, pw, ph) {
        if (gen != rt._generation) return;
        rt.resize(w, h);
      };

      pty.exitCode.then((code) {
        if (gen != rt._generation) return;
        rt._pty = null;
        final text = outBuf.toString();
        final crashedAtStartup = remaining.isNotEmpty &&
            (DateTime.now().difference(startedAt).inMilliseconds < 2000 ||
                text.contains('8009001d') ||
                text.contains('managed Windows PowerShell failed') ||
                text.contains('Internal Windows PowerShell Error'));
        if (crashedAtStartup) {
          rt.terminal.write(
              '\r\n\x1b[33m[${chosen.label} exited at startup — retrying ${remaining.first.label}]\x1b[0m\r\n');
          _spawnPtyChain(rt, remaining, gen);
          return;
        }
        rt.lastExitCode = code;
        rt.state = TerminalSessionState.exited;
        rt.terminal.write('\r\n\x1b[90m[process exited ($code)]\x1b[0m');
        notifyListeners();
      });

      notifyListeners();
    } catch (e) {
      rt.terminal.write('\r\n\x1b[33m[failed to launch ${chosen.label}: $e]\x1b[0m\r\n');
      _spawnPtyChain(rt, remaining, gen);
    }
  }

  Future<void> _attachSsh(
    TerminalSessionRuntime rt,
    SshHostProfile host,
    int gen,
  ) async {
    rt.state = TerminalSessionState.connecting;
    rt.shellLabel = 'SSH · ${host.displayTarget}';
    notifyListeners();

    final transport = SshTerminalTransport(
      host: host,
      vault: sshVault,
      onPromptPassword: (prompt) async {
        final pw = await onPromptPassword?.call(prompt);
        return pw;
      },
    );
    rt._ssh = transport;

    rt.terminal.onResize = (w, h, pw, ph) {
      if (gen != rt._generation) return;
      rt.resize(w, h);
    };

    final ok = await transport.attach(
      rt.terminal,
      onConnected: () {
        if (gen != rt._generation) return;
        rt.state = TerminalSessionState.running;
        notifyListeners();
      },
      onDisconnected: (reason) {
        if (gen != rt._generation) return;
        rt.state = TerminalSessionState.exited;
        notifyListeners();
      },
    );

    if (!ok && gen == rt._generation) {
      rt.state = TerminalSessionState.error;
      notifyListeners();
    }
  }

  Future<void> closeSession(int id) async {
    final rt = _runtimes[id];
    if (_order.length <= 1 && rt != null) {
      await restartSession(id);
      return;
    }
    final idx = _order.indexOf(id);
    rt?.dispose();
    _runtimes.remove(id);
    if (idx >= 0) _order.removeAt(idx);
    if (_splitSecondaryId == id) {
      _splitSecondaryId = null;
      _splitEnabled = false;
    }
    if (_activeId == id) {
      _activeId = _order.isEmpty
          ? null
          : _order[idx.clamp(0, _order.length - 1)];
    }
    await store.remove(id);
    if (_activeId != null) {
      await activateSession(_activeId!);
    } else {
      notifyListeners();
    }
  }

  Future<void> renameSession(int id, String nextName) async {
    final clean = nextName.trim();
    if (clean.isEmpty) return;
    final rt = _runtimes[id];
    if (rt != null) rt.name = clean;
    await store.updateMeta(id, name: clean);
    notifyListeners();
  }

  Future<void> togglePin(int id) async {
    final rt = _runtimes[id];
    if (rt != null) rt.isPinned = !rt.isPinned;
    await store.togglePin(id);
    notifyListeners();
  }

  Future<void> updateAppearance(TerminalAppearancePrefs next) async {
    _appearance = next;
    await store.saveAppearance(next);
    notifyListeners();
  }

  void toggleSplitPane() {
    if (_order.length < 2) return;
    _splitEnabled = !_splitEnabled;
    if (_splitEnabled &&
        (_splitSecondaryId == null ||
            _splitSecondaryId == _activeId ||
            !_runtimes.containsKey(_splitSecondaryId))) {
      _splitSecondaryId =
          _order.firstWhere((id) => id != _activeId, orElse: () => _order.first);
      final sec = _runtimes[_splitSecondaryId!];
      if (sec != null && !sec.isAlive && sec.state == TerminalSessionState.idle) {
        unawaited(startOrRestartRuntime(sec));
      }
    }
    notifyListeners();
  }

  void setSplitSecondary(int id) {
    if (!_runtimes.containsKey(id) || id == _activeId) return;
    _splitSecondaryId = id;
    _splitEnabled = true;
    final sec = _runtimes[id];
    if (sec != null && !sec.isAlive && sec.state == TerminalSessionState.idle) {
      unawaited(startOrRestartRuntime(sec));
    }
    notifyListeners();
  }

  /// Searches [terminal] buffer lines case-insensitively (up to scrollback cap)
  /// and returns line + column ranges for match highlighting & navigation.
  static List<TerminalSearchMatch> searchScrollback(
    Terminal terminal,
    String query, {
    bool caseSensitive = false,
  }) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final needle = caseSensitive ? q : q.toLowerCase();
    final matches = <TerminalSearchMatch>[];
    final lines = terminal.buffer.lines;
    for (var row = 0; row < lines.length; row++) {
      final raw = lines[row].getText();
      if (raw.isEmpty) continue;
      final haystack = caseSensitive ? raw : raw.toLowerCase();
      var idx = 0;
      while (true) {
        final found = haystack.indexOf(needle, idx);
        if (found < 0) break;
        matches.add(TerminalSearchMatch(
          lineIndex: row,
          startCol: found,
          endCol: found + needle.length,
        ));
        idx = found + needle.length;
      }
    }
    return matches;
  }

  TerminalCursorType get cursorType => switch (_appearance.cursorStyle) {
        'underline' => TerminalCursorType.underline,
        'bar' => TerminalCursorType.verticalBar,
        _ => TerminalCursorType.block,
      };

  @override
  void dispose() {
    for (final rt in _runtimes.values) {
      rt.dispose();
    }
    _runtimes.clear();
    super.dispose();
  }
}
