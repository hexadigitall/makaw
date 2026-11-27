import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../domain/terminal_models.dart';
import 'ssh_vault_service.dart';

/// Cross-platform interactive SSH session powered by pure-Dart `dartssh2`.
/// Works identically on Android, Windows, macOS, and Linux without requiring an
/// external `ssh` OS binary. Supports password auth, encrypted/plain PEM keys,
/// optional `tmux` auto-resume, initial remote directory `cd`, and terminal resize.
class SshTerminalTransport {
  final SshHostProfile host;
  final SshVaultService vault;
  final Future<String?> Function(String prompt)? onPromptPassword;

  SSHClient? _client;
  SSHSession? _shell;
  bool _closed = false;

  bool get isConnected => _client != null && !(_client!.isClosed) && _shell != null;

  SshTerminalTransport({
    required this.host,
    required this.vault,
    this.onPromptPassword,
  });

  /// Connects and attaches an interactive PTY shell to [terminal], returning a
  /// status message if connection setup failed.
  Future<bool> attach(
    Terminal terminal, {
    VoidCallback? onConnected,
    void Function(String reason)? onDisconnected,
  }) async {
    try {
      terminal.write(
          '\x1b[38;5;45m[SSH] Connecting to ${host.displayTarget}...\x1b[0m\r\n');
      final secrets = await vault.readSecrets(host.id);
      List<SSHKeyPair>? identities;
      if (host.authMethod == 'key' &&
          secrets.privateKeyPem != null &&
          secrets.privateKeyPem!.isNotEmpty) {
        try {
          final encrypted = SSHKeyPair.isEncryptedPem(secrets.privateKeyPem!);
          String? passphrase = secrets.passphrase;
          if (encrypted && (passphrase == null || passphrase.isEmpty)) {
            passphrase = await onPromptPassword
                ?.call('Enter passphrase for ${host.name} key');
          }
          identities = SSHKeyPair.fromPem(secrets.privateKeyPem!, passphrase);
        } catch (e) {
          terminal.write('\x1b[31m[SSH] Failed to load key: $e\x1b[0m\r\n');
        }
      }

      final socket = await SSHSocket.connect(
        host.host,
        host.port,
        timeout: const Duration(seconds: 12),
      );

      final client = SSHClient(
        socket,
        username: host.username,
        identities: identities,
        keepAliveInterval: const Duration(seconds: 15),
        onPasswordRequest: () async {
          if (secrets.password != null && secrets.password!.isNotEmpty) {
            return secrets.password;
          }
          return onPromptPassword?.call('SSH password for ${host.displayTarget}');
        },
        onUserInfoRequest: (req) async {
          if (req.prompts.isEmpty) return const [];
          final answers = <String>[];
          for (final p in req.prompts) {
            if (secrets.password != null &&
                secrets.password!.isNotEmpty &&
                req.prompts.length == 1 &&
                p.promptText.toLowerCase().contains('password')) {
              answers.add(secrets.password!);
            } else {
              final v = await onPromptPassword?.call(p.promptText) ?? '';
              answers.add(v);
            }
          }
          return answers;
        },
      );
      _client = client;

      final shell = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth.clamp(40, 240),
          height: terminal.viewHeight.clamp(12, 120),
        ),
      );
      _shell = shell;

      terminal.write(
          '\x1b[32m[SSH] Connected to ${host.displayTarget}\x1b[0m\r\n');
      onConnected?.call();

      shell.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) {
        if (!_closed) terminal.write(chunk);
      });
      shell.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) {
        if (!_closed) terminal.write(chunk);
      });

      terminal.onOutput = (data) {
        if (!_closed) {
          shell.write(Uint8List.fromList(utf8.encode(data)));
        }
      };

      // Optional remote directory jump & tmux auto-attach for seamless continuity.
      if (host.defaultRemoteDir.isNotEmpty) {
        final safeDir = host.defaultRemoteDir.replaceAll("'", r"'\''");
        shell.write(Uint8List.fromList(utf8.encode("cd '$safeDir'\n")));
      }
      if (host.autoTmux) {
        final tmuxName = host.tmuxSession.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        shell.write(Uint8List.fromList(utf8.encode(
            'command -v tmux >/dev/null 2>&1 && tmux new -As $tmuxName\n')));
      }

      unawaited(shell.done.then((_) {
        if (_closed) return;
        terminal.write('\r\n\x1b[33m[SSH session closed]\x1b[0m\r\n');
        onDisconnected?.call('SSH session closed');
      }));
      return true;
    } catch (e) {
      terminal.write('\r\n\x1b[31m[SSH error] $e\x1b[0m\r\n');
      onDisconnected?.call(e.toString());
      return false;
    }
  }

  void writeString(String text) {
    if (_closed || _shell == null) return;
    _shell!.write(Uint8List.fromList(utf8.encode(text)));
  }

  void resize(int rows, int cols) {
    if (_closed || _shell == null) return;
    if (cols > 0 && rows > 0) {
      _shell!.resizeTerminal(cols, rows);
    }
  }

  void dispose() {
    _closed = true;
    try {
      _shell?.close();
    } catch (_) {}
    try {
      _client?.close();
    } catch (_) {}
    _shell = null;
    _client = null;
  }
}

typedef VoidCallback = void Function();
