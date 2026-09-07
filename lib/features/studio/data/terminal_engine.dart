import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../../core/platform/conditional_pty.dart';

/// A self-contained terminal engine backing the Code Studio IDE terminal pane.
///
/// Wraps an [xterm] [Terminal]/[TerminalController] with a real [Pty] process
/// started in a project working directory. On web (where PTY is unavailable)
/// it degrades to a read-only transcript that shows a notice.
class MakawTerminalEngine {
  final Terminal terminal = Terminal(maxLines: 10000);
  final TerminalController controller = TerminalController();
  Pty? _pty;

  bool get isRunning => _pty != null;
  String _cwd = '';
  String _shell = '';
  bool _disposed = false;

  /// Guards against stale process-exit handlers firing after the session has
  /// been deliberately restarted/killed.
  int _sessionGeneration = 0;

  String get workingDirectory => _cwd;

  /// Display name of the shell that backs this terminal, based on the
  /// current platform (updated if a fallback shell takes over).
  String get shellName {
    if (_shell.isNotEmpty) return _shell;
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'powershell';
    if (Platform.isAndroid) return 'sh';
    return 'bash';
  }

  /// Starts (or restarts) the PTY shell rooted at [workingDirectory] with an
  /// optional custom [executable]+[arguments] (e.g. `wsl.exe` / `ssh`).
  /// Safe (and silently a no-op) on web.
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
      final label = executable
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.exe', '');
      _spawn([(label, executable, arguments)]);
      return;
    }

    final List<(String, String, List<String>)> candidates;
    if (Platform.isWindows) {
      // Prefer PowerShell, but a broken PowerShell quits within a second of
      // launch (e.g. "Loading managed Windows PowerShell failed with
      // 0x8009001d"), so fall back to cmd.exe when that happens.
      candidates = [
        ('powershell', 'powershell.exe', ['-NoLogo', '-NoProfile']),
        ('cmd', 'cmd.exe', const []),
      ];
    } else if (Platform.isAndroid) {
      candidates = [
        ('sh', 'sh', ['-c', 'cd ${_shellQuote(workingDirectory.isEmpty ? '/storage/emulated/0' : workingDirectory)} && exec sh']),
      ];
    } else {
      candidates = [
        ('bash', 'bash', const []),
      ];
    }
    _spawn(candidates);
  }

  /// Restarts the underlying process, killing any in-flight shell first.
  void _killPty() {
    if (_pty == null) return;
    _sessionGeneration++;
    try {
      _pty!.kill();
    } catch (_) {}
    _pty = null;
  }

  void _spawn(List<(String, String, List<String>)> candidates) {
    if (_disposed) return;
    if (candidates.isEmpty) {
      terminal.write('\r\n[error starting PTY] no usable shell found');
      _pty = null;
      return;
    }
    final (display, executable, args) = candidates.first;
    final remaining = candidates.sublist(1);
    String? cwd = _cwd.isEmpty ? null : _cwd;
    if (Platform.isWindows && cwd == null) cwd = Platform.environment['USERPROFILE'];
    if (!Platform.isWindows && cwd == null) cwd = Platform.environment['HOME'];

    try {
      final pty = Pty.start(
        executable,
        arguments: args,
        environment: {'TERM': 'xterm-256color'},
        workingDirectory: cwd,
      );
      _pty = pty;
      _shell = display;
      final startedAt = DateTime.now();
      final output = StringBuffer();
      final generation = _sessionGeneration;
      pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen((chunk) {
        if (generation != _sessionGeneration) return;
        output.write(chunk);
        terminal.write(chunk);
      });
      // cmd shows garbage for UTF-8 output by default; switch it to UTF-8.
      if (Platform.isWindows && display == 'cmd') {
        pty.write(utf8.encode('chcp 65001>nul\r\n'));
      }
      terminal.write('\x1b[38;5;49mMakaw terminal — $display'
          '${cwd == null ? '' : ' • $cwd'}\x1b[0m\r\n'
          'Type here, Ctrl+C stops the running task, Ctrl+Shift+C copies, '
          'Ctrl+Shift+V pastes.\r\n');
      pty.exitCode.then((code) {
        if (generation != _sessionGeneration) return;
        _pty = null;
        // A shell that dies seconds after launch is crashing (e.g. a broken
        // PowerShell: "Loading managed Windows PowerShell failed with
        // 0x8009001d"). Retry the next candidate rather than dying silently.
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
        _pty?.write(const Utf8Encoder().convert(data));
      };
    } catch (e) {
      terminal.write('\r\n[error starting $executable]\r\n$e');
      _pty = null;
      if (remaining.isNotEmpty) _spawn(remaining);
    }
  }

  /// Writes raw [command] (plus a newline) to the running process.
  void writeCommand(String command) {
    _pty?.write(const Utf8Encoder().convert(command));
  }

  /// Sends raw bytes (e.g. '\x03' for Ctrl+C) to the process.
  void writeRaw(String bytes) {
    _pty?.write(const Utf8Encoder().convert(bytes));
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
    _pty?.kill();
    _pty = null;
    controller.dispose();
  }

  String _shellQuote(String path) => "'${path.replaceAll("'", r"'\''")}'";
}
