import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class MakawTerminalEngine {
  final Terminal terminal = Terminal(maxLines: 10000);
  Pty? _pty;
  StreamSubscription? _ptySubscription;

  void startSession({String? workingDirectory}) {
    if (kIsWeb) {
      terminal.write('\r\n\x1b[33mTerminal not available on web.\x1b[0m\r\n');
      return;
    }

    String executable;
    List<String> arguments = [];

    if (Platform.isAndroid) {
      executable = '/system/bin/sh';
    } else if (Platform.isWindows) {
      executable = 'powershell.exe';
    } else if (Platform.isMacOS || Platform.isLinux) {
      executable = Platform.environment['SHELL'] ?? '/bin/bash';
    } else {
      executable = '/bin/sh';
    }

    final env = Map<String, String>.from(Platform.environment);
    env['TERM'] = 'xterm-256color';
    if (Platform.isWindows) {
      env['HOME'] = Platform.environment['USERPROFILE'] ?? 'C:\\';
    }

    try {
      _pty = Pty.start(
        executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
        environment: env,
      );

      _ptySubscription = _pty!.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
        terminal.write(data);
      });

      terminal.onOutput = (data) {
        _pty?.write(const Utf8Encoder().convert(data));
      };

      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _pty?.resize(height, width);
      };
    } catch (e) {
      terminal.write('\r\n\x1b[31m[Makaw Terminal Failure]\x1b[0m: $e\r\n');
      if (Platform.isIOS) {
        terminal.write('\r\n\x1b[33mNote: Local POSIX shell is restricted on iOS sandbox.\x1b[0m\r\n');
      }
    }
  }

  void writeCommand(String cmd) {
    _pty?.write(utf8.encode('$cmd\n'));
  }

  void dispose() {
    _ptySubscription?.cancel();
    _pty?.kill();
  }
}
