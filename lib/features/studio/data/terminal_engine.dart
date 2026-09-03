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
  bool _started = false;

  bool get isRunning => _pty != null;
  String _cwd = '';

  String get workingDirectory => _cwd;

  /// Starts the PTY shell rooted at [workingDirectory]. No-op if already
  /// running. Safe (and silently a no-op) on web.
  void startSession({String workingDirectory = ''}) {
    _cwd = workingDirectory;
    if (_started) return;
    _started = true;
    if (kIsWeb) {
      terminal.write('Terminal is not available on web.\r\n');
      return;
    }
    try {
      final pty = Pty.start(
        Platform.isAndroid ? 'sh' : 'bash',
        arguments: Platform.isAndroid
            ? ['-c', 'cd ${_shellQuote(workingDirectory)} && exec sh']
            : [],
        environment: {'TERM': 'xterm-256color'},
        workingDirectory: workingDirectory.isEmpty ? null : workingDirectory,
      );
      _pty = pty;
      pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(terminal.write);
      pty.exitCode.then((_) {
        terminal.write('\r\n[process exited]');
        _pty = null;
      });
      terminal.onOutput = (data) {
        _pty?.write(const Utf8Encoder().convert(data));
      };
    } catch (_) {
      terminal.write('\r\n[error starting PTY]');
      _pty = null;
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
    _pty?.kill();
    _pty = null;
    controller.dispose();
  }

  String _shellQuote(String path) => "'${path.replaceAll("'", r"'\''")}'";
}
