import 'dart:io';

import 'git_service.dart';

/// Result of probing a local integration tool on this device.
class IntegrationAvailable {
  final bool available;
  final String? detail;

  const IntegrationAvailable(this.available, [this.detail]);

  bool get ok => available;
}

/// Thin wrappers that probe and drive local CLI tools (wsl.exe, docker,
/// ssh, git) the same way VS Code does: by shelling out to the real binaries.
class IntegrationHelpers {
  IntegrationHelpers._();

  /// Lists installed WSL distros via `wsl.exe --list --quiet`. Empty when WSL
  /// is not available.
  static Future<List<String>> wslDistros() async {
    try {
      final res = await Process.run('wsl.exe', ['--list', '--quiet']);
      if (res.exitCode != 0) return const [];
      return (res.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.contains('(Default)'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<IntegrationAvailable> wslAvailable() async {
    final distros = await wslDistros();
    return IntegrationAvailable(distros.isNotEmpty,
        distros.isEmpty ? null : '${distros.length} distro(s)');
  }

  /// Lists running containers: "name<TAB>image". Empty when docker is missing
  /// or the daemon is not running.
  static Future<List<({String id, String name, String image})>> dockerContainers() async {
    try {
      final ps = await Process.run(
        'docker',
        ['ps', '--format', '{{.ID}}|{{.Names}}|{{.Image}}'],
      );
      if (ps.exitCode != 0) return const [];
      return (ps.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) {
        final parts = l.split('|');
        return (
          id: parts.isNotEmpty ? parts[0] : '',
          name: parts.length > 1 ? parts[1] : '',
          image: parts.length > 2 ? parts[2] : '',
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<IntegrationAvailable> dockerAvailable() async {
    try {
      final res = await Process.run('docker', ['version', '--format', '{{.Server.Version}}']);
      if (res.exitCode != 0) {
        return const IntegrationAvailable(false, 'docker CLI not usable');
      }
      return const IntegrationAvailable(true);
    } catch (_) {
      return const IntegrationAvailable(false, 'docker not installed');
    }
  }

  static Future<IntegrationAvailable> sshAvailable() async {
    try {
      final res = await Process.run('ssh', ['-V']);
      if (res.exitCode != 0) return const IntegrationAvailable(false);
      return const IntegrationAvailable(true);
    } catch (_) {
      return const IntegrationAvailable(false);
    }
  }

  static Future<IntegrationAvailable> gitAvailable() async {
    try {
      final res = await Process.run('git', ['--version']);
      return IntegrationAvailable(res.exitCode == 0);
    } catch (_) {
      return const IntegrationAvailable(false);
    }
  }

  /// Applies the configured Git identity to [root]'s repo (local config).
  static Future<void> applyGitIdentity(Directory root, String name, String email) async {
    if (name.isEmpty && email.isEmpty) return;
    final git = GitService(root);
    if (!git.isRepo) return;
    if (name.isNotEmpty) await git.config('user.name', name);
    if (email.isNotEmpty) await git.config('user.email', email);
  }
}