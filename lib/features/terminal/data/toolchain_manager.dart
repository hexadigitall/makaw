import 'dart:io';

import 'package:flutter/foundation.dart';

/// Status of a language/package toolchain probed on the current device.
class ToolchainStatus {
  final String id;
  final String name;
  final String executable;
  final bool installed;
  final String version;
  final String installCommand;
  final String updateCommand;

  const ToolchainStatus({
    required this.id,
    required this.name,
    required this.executable,
    required this.installed,
    this.version = '',
    required this.installCommand,
    required this.updateCommand,
  });
}

/// Cross-platform package manager, Git repo cloner, & developer toolchain
/// helper (`MakawPkg` / `ToolchainManager`).
class ToolchainManager {
  ToolchainManager._();

  static const List<({
    String id,
    String name,
    String exe,
    List<String> versionArgs,
    String winInstall,
    String posixInstall,
    String updateCmd,
  })> _registry = [
    (
      id: 'git',
      name: 'Git',
      exe: 'git',
      versionArgs: ['--version'],
      winInstall: 'winget install --id Git.Git -e',
      posixInstall: 'sudo apt install -y git || brew install git',
      updateCmd: 'git --version',
    ),
    (
      id: 'flutter',
      name: 'Flutter SDK',
      exe: 'flutter',
      versionArgs: ['--version'],
      winInstall: 'winget install --id Google.Flutter -e',
      posixInstall: 'brew install --cask flutter',
      updateCmd: 'flutter upgrade',
    ),
    (
      id: 'dart',
      name: 'Dart SDK',
      exe: 'dart',
      versionArgs: ['--version'],
      winInstall: 'winget install --id Google.DartSDK -e',
      posixInstall: 'brew install dart-sdk',
      updateCmd: 'dart pub upgrade',
    ),
    (
      id: 'node',
      name: 'Node.js & npm',
      exe: 'node',
      versionArgs: ['-v'],
      winInstall: 'winget install OpenJS.NodeJS.LTS',
      posixInstall: 'sudo apt install -y nodejs npm || brew install node',
      updateCmd: 'npm install -g npm@latest',
    ),
    (
      id: 'python',
      name: 'Python / pip',
      exe: 'python',
      versionArgs: ['--version'],
      winInstall: 'winget install Python.Python.3.12',
      posixInstall: 'sudo apt install -y python3 python3-pip || brew install python',
      updateCmd: 'python -m pip install --upgrade pip',
    ),
    (
      id: 'cargo',
      name: 'Rust / Cargo',
      exe: 'cargo',
      versionArgs: ['--version'],
      winInstall: 'winget install Rustlang.Rustup',
      posixInstall: 'curl https://sh.rustup.rs -sSf | sh',
      updateCmd: 'rustup update',
    ),
    (
      id: 'go',
      name: 'Go Toolchain',
      exe: 'go',
      versionArgs: ['version'],
      winInstall: 'winget install GoLang.Go',
      posixInstall: 'sudo apt install -y golang || brew install go',
      updateCmd: 'go version',
    ),
    (
      id: 'docker',
      name: 'Docker CLI',
      exe: 'docker',
      versionArgs: ['--version'],
      winInstall: 'winget install Docker.DockerDesktop',
      posixInstall: 'curl -fsSL https://get.docker.com | sh',
      updateCmd: 'docker system df',
    ),
  ];

  static Future<List<ToolchainStatus>> probeAll() async {
    final results = <ToolchainStatus>[];
    if (kIsWeb) return results;

    for (final spec in _registry) {
      var installed = false;
      var version = '';
      // On stock Android, Process.run probing non-existent binaries safely returns not found.
      try {
        final exeName = (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) &&
                spec.exe == 'python'
            ? 'python3'
            : spec.exe;
        final res = await Process.run(exeName, spec.versionArgs)
            .timeout(const Duration(seconds: 2));
        if (res.exitCode == 0) {
          installed = true;
          final raw = ((res.stdout as String).trim().isNotEmpty
                  ? res.stdout as String
                  : res.stderr as String)
              .trim();
          version = raw.split(RegExp(r'\r?\n')).first.trim();
        }
      } catch (_) {}

      results.add(ToolchainStatus(
        id: spec.id,
        name: spec.name,
        executable: spec.exe,
        installed: installed,
        version: version,
        installCommand: Platform.isWindows ? spec.winInstall : spec.posixInstall,
        updateCommand: spec.updateCmd,
      ));
    }
    return results;
  }

  /// Normalizes repo shorthand (`owner/repo`) or HTTPS/SSH Git URLs into a
  /// clean cloneable URL and repository folder name.
  static ({String url, String folderName})? normalizeGitCloneTarget(
    String raw, {
    String defaultProvider = 'github.com',
  }) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$').hasMatch(s)) {
      s = 'https://$defaultProvider/$s.git';
    }
    if (!(s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('git@') ||
        s.startsWith('ssh://'))) {
      return null;
    }
    var last = s.split('/').last.split(':').last;
    if (last.endsWith('.git')) last = last.substring(0, last.length - 4);
    if (last.isEmpty) return null;
    return (url: s, folderName: last);
  }
}
