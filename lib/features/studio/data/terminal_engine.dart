import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../../core/platform/conditional_pty.dart';
import '../../terminal/data/makaw_hybrid_shell.dart';
import '../../terminal/data/shell_discovery.dart';
import '../../terminal/data/ssh_terminal_transport.dart';
import '../../terminal/data/ssh_vault_service.dart';
import '../../terminal/domain/terminal_models.dart';

/// A self-contained terminal engine backing the Code Studio IDE terminal pane.
///
/// Unifies native [Pty] shells (`pwsh`, `powershell`, `cmd`, `git-bash`, `wsl`,
/// `zsh`, `bash`), Makaw's built-in `makaw-sh` hybrid shell on stock Android,
/// and cross-platform `dartssh2` remote SSH sessions behind one controller.
class MakawTerminalEngine {
  final Terminal terminal = Terminal(maxLines: 10000);
  final TerminalController controller = TerminalController();
  Pty? _pty;
  MakawHybridShell? _hybrid;
  StreamSubscription<String>? _hybridSub;
  SshTerminalTransport? _ssh;

  bool get isRunning =>
      _pty != null ||
      _hybrid != null ||
      (_ssh != null && _ssh!.isConnected);
  String _cwd = '';
  String _shell = '';
  bool _disposed = false;

  /// Guards against stale process-exit handlers firing after the session has
  /// been deliberately restarted/killed.
  int _sessionGeneration = 0;

  String get workingDirectory => _cwd;

  /// Display name of the shell that backs this terminal.
  String get shellName {
    if (_shell.isNotEmpty) return _shell;
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'powershell';
    if (Platform.isAndroid) return 'makaw-sh';
    return 'bash';
  }

  /// Discovers Git Bash executable if installed on Windows.
  static String? findGitBash() => ShellDiscovery.findGitBash();

  /// Starts a Git Bash session directly on Windows if available.
  bool startGitBash({String workingDirectory = ''}) {
    final gitBash = findGitBash();
    if (gitBash == null) return false;
    startSession(
      workingDirectory: workingDirectory,
      executable: gitBash,
      arguments: ['--login', '-i'],
    );
    return true;
  }

  /// Starts a PowerShell 7 (`pwsh`) session directly on Windows if available.
  bool startPwsh({String workingDirectory = ''}) {
    final pwsh = ShellDiscovery.findPwsh();
    if (pwsh == null) return false;
    startSession(
      workingDirectory: workingDirectory,
      executable: pwsh,
      arguments: const ['-NoLogo'],
    );
    return true;
  }

  /// Starts a pure-Dart `dartssh2` remote shell session inside Studio's pane
  /// so SSH works seamlessly on both Android and Desktop.
  Future<bool> startSshSession(
    SshHostProfile host, {
    SshVaultService? vault,
    Future<String?> Function(String prompt)? onPromptPassword,
  }) async {
    _killPty();
    if (kIsWeb) {
      terminal.write('SSH is not available on web.\r\n');
      return false;
    }
    _shell = 'ssh:${host.name}';
    final transport = SshTerminalTransport(
      host: host,
      vault: vault ?? SshVaultService(),
      onPromptPassword: onPromptPassword,
    );
    _ssh = transport;
    final gen = _sessionGeneration;
    terminal.onResize = (w, h, pw, ph) {
      if (gen != _sessionGeneration) return;
      transport.resize(h, w);
    };
    return transport.attach(terminal);
  }

  /// Starts (or restarts) the PTY or hybrid shell rooted at [workingDirectory]
  /// with an optional custom [executable]+[arguments] (e.g. `wsl.exe`).
  void startSession({
    String workingDirectory = '',
    String? executable,
    List<String> arguments = const [],
  }) {
    _cwd = workingDirectory;
    _killPty();
    if (kIsWeb) {
      terminal.write('Terminal is not available on web.\r\n');
      return;
    }

    if (executable != null && executable.isNotEmpty) {
      if (executable == 'makaw-sh') {
        _startHybrid();
        return;
      }
      final label = executable
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.exe', '');
      _spawn([(label, executable, arguments)]);
      return;
    }

    if (Platform.isAndroid) {
      // Check for Termux zsh/bash first, otherwise boot Makaw Hybrid Shell
      // (`makaw-sh`) so core dev utilities & `ssh` work out of the box!
      const termuxBash = '/data/data/com.termux/files/usr/bin/bash';
      if (File(termuxBash).existsSync()) {
        _spawn([
          ('bash', termuxBash, const ['-l']),
          ('makaw-sh', 'makaw-sh', const []),
        ]);
        return;
      }
      _startHybrid();
      return;
    }

    final List<(String, String, List<String>)> candidates;
    if (Platform.isWindows) {
      final pwsh = ShellDiscovery.findPwsh();
      final gitBash = findGitBash();
      candidates = [
        if (pwsh != null) ('pwsh', pwsh, const ['-NoLogo']),
        ('powershell', 'powershell.exe', ['-NoLogo', '-NoProfile']),
        ('cmd', 'cmd.exe', const []),
        if (gitBash != null) ('git-bash', gitBash, ['--login', '-i']),
        ('wsl', 'wsl.exe', const []),
      ];
    } else {
      final envShell = Platform.environment['SHELL'];
      candidates = [
        if (envShell != null && envShell.isNotEmpty)
          (envShell.split('/').last, envShell, const ['-i']),
        ('zsh', '/bin/zsh', const ['-i']),
        ('bash', 'bash', const []),
      ];
    }
    _spawn(candidates);
  }

  void _startHybrid() {
    final cwd = ShellDiscovery.resolveDefaultCwd(_cwd);
    final hybrid = MakawHybridShell(initialCwd: cwd);
    _hybrid = hybrid;
    _shell = 'makaw-sh';
    final gen = _sessionGeneration;
    _hybridSub = hybrid.output.listen((chunk) {
      if (gen == _sessionGeneration) terminal.write(chunk);
    });
    terminal.onOutput = (data) {
      if (gen == _sessionGeneration) hybrid.feedInput(data);
    };
    hybrid.start();
  }

  /// Restarts the underlying process, killing any in-flight shell first.
  void _killPty() {
    _sessionGeneration++;
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
  }

  void _spawn(List<(String, String, List<String>)> candidates) {
    if (_disposed) return;
    if (candidates.isEmpty) {
      _startHybrid();
      return;
    }
    final (display, executable, args) = candidates.first;
    final remaining = candidates.sublist(1);
    if (executable == 'makaw-sh') {
      _startHybrid();
      return;
    }
    final cwd = ShellDiscovery.resolveDefaultCwd(_cwd);

    try {
      final pty = Pty.start(
        executable,
        arguments: args,
        environment: {'TERM': 'xterm-256color'},
        workingDirectory: cwd,
      );
      pty.resize(terminal.viewHeight.clamp(12, 120), terminal.viewWidth.clamp(40, 240));
      _pty = pty;
      _shell = display;
      final startedAt = DateTime.now();
      final output = StringBuffer();
      final generation = _sessionGeneration;
      pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) {
        if (generation != _sessionGeneration) return;
        output.write(chunk);
        terminal.write(chunk);
      });
      if (Platform.isWindows && display == 'cmd') {
        pty.write(utf8.encode('chcp 65001>nul\r\n'));
      }
      terminal.write('\x1b[38;5;49mMakaw terminal — $display'
          ' • $cwd\x1b[0m\r\n'
          'Type here, Ctrl+C stops the running task, Ctrl+Shift+C copies, '
          'Ctrl+Shift+V pastes.\r\n');
      pty.exitCode.then((code) {
        if (generation != _sessionGeneration) return;
        _pty = null;
        final crashedAtStartup = remaining.isNotEmpty &&
            (DateTime.now().difference(startedAt).inMilliseconds < 2000 ||
                output.toString().contains('8009001d') ||
                output.toString().contains('managed Windows PowerShell failed') ||
                output.toString().contains('Internal Windows PowerShell Error'));
        if (crashedAtStartup) {
          terminal.write(
              '\r\n[$display exited unexpectedly at startup — '
              'retrying with ${remaining.first.$1}]\r\n');
          _spawn(remaining);
          return;
        }
        terminal.write('\r\n[process exited]');
      });
      terminal.onOutput = (data) {
        if (generation != _sessionGeneration) return;
        _pty?.write(const Utf8Encoder().convert(data));
      };
      terminal.onResize = (w, h, pw, ph) {
        if (generation != _sessionGeneration) return;
        try {
          _pty?.resize(h, w);
        } catch (_) {}
      };
    } catch (e) {
      terminal.write('\r\n[error starting $executable]\r\n$e');
      _pty = null;
      if (remaining.isNotEmpty) _spawn(remaining);
    }
  }

  /// Writes raw [command] to the running process.
  void writeCommand(String command) => writeRaw(command);

  /// Sends raw bytes (e.g. '\x03' for Ctrl+C) to the process.
  void writeRaw(String bytes) {
    if (_pty != null) {
      _pty!.write(const Utf8Encoder().convert(bytes));
    } else if (_hybrid != null) {
      _hybrid!.feedInput(bytes);
    } else if (_ssh != null) {
      _ssh!.writeString(bytes);
    }
  }

  /// Interrupts the running process (Ctrl+C / SIGINT).
  void interrupt() => writeRaw('\x03');

  /// Sends EOF (Ctrl+D).
  void eof() => writeRaw('\x04');

  /// Clears the displayed buffer but keeps the process running.
  void clearDisplay() {
    terminal.eraseDisplay();
    terminal.eraseScrollbackOnly();
  }

  /// Stops the underlying process and releases the PTY.
  void dispose() {
    _disposed = true;
    _killPty();
    controller.dispose();
  }
}
