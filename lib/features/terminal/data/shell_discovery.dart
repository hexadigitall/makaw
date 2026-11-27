import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/terminal_models.dart';

/// Shared shell discovery & default working directory resolver for both
/// standalone Makaw Terminal and Code Studio. Eliminates C:\ fallbacks on
/// Windows and discovers `pwsh`, `powershell`, `cmd`, `Git Bash`, `WSL`
/// (including installed Ubuntu/Debian distros), `zsh`, `bash`, `fish`, and
/// Makaw's built-in `makaw-sh` hybrid shell.
class ShellDiscovery {
  ShellDiscovery._();

  /// Resolves the best starting working directory instead of dropping users into
  /// restricted system roots like `C:\`.
  static String resolveDefaultCwd([String? preferredCwd]) {
    final pref = preferredCwd?.trim() ?? '';
    if (pref.isNotEmpty) {
      try {
        if (Directory(pref).existsSync()) return pref;
      } catch (_) {}
    }

    if (kIsWeb) return '/';

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        try {
          if (Directory(userProfile).existsSync()) return userProfile;
        } catch (_) {}
      }
      if (Directory(r'D:\projects').existsSync()) return r'D:\projects';
      if (Directory(r'D:\').existsSync()) return r'D:\';
      return Directory.current.path;
    }

    if (Platform.isAndroid) {
      const shared = '/storage/emulated/0';
      try {
        if (Directory(shared).existsSync()) return shared;
      } catch (_) {}
      return Directory.current.path;
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return home;
    return Directory.current.path;
  }

  /// Discovers Git Bash executable if installed on Windows.
  static String? findGitBash() {
    if (kIsWeb || !Platform.isWindows) return null;
    final env = Platform.environment;
    final candidates = [
      r'C:\Program Files\Git\bin\bash.exe',
      r'C:\Program Files\Git\usr\bin\bash.exe',
      r'C:\Program Files (x86)\Git\bin\bash.exe',
      if (env['LOCALAPPDATA'] != null)
        '${env['LOCALAPPDATA']}\\Programs\\Git\\bin\\bash.exe',
      if (env['USERPROFILE'] != null)
        '${env['USERPROFILE']}\\scoop\\apps\\git\\current\\bin\\bash.exe',
      r'D:\Program Files\Git\bin\bash.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Discovers PowerShell 7 (`pwsh.exe`) if installed on Windows.
  static String? findPwsh() {
    if (kIsWeb || !Platform.isWindows) return null;
    final env = Platform.environment;
    final candidates = [
      r'C:\Program Files\PowerShell\7\pwsh.exe',
      r'C:\Program Files\PowerShell\7-preview\pwsh.exe',
      if (env['LOCALAPPDATA'] != null)
        '${env['LOCALAPPDATA']}\\Microsoft\\WindowsApps\\pwsh.exe',
      if (env['USERPROFILE'] != null)
        '${env['USERPROFILE']}\\scoop\\apps\\pwsh\\current\\pwsh.exe',
      r'D:\Program Files\PowerShell\7\pwsh.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Lists installed WSL distros (e.g. `Ubuntu`, `Debian`) on Windows.
  static Future<List<String>> listWslDistros() async {
    if (kIsWeb || !Platform.isWindows) return const [];
    try {
      final res = await Process.run('wsl.exe', ['--list', '--quiet']);
      if (res.exitCode != 0) return const [];
      // wsl --list prints UTF-16LE on some Windows builds so strip NUL bytes cleanly.
      final cleaned = (res.stdout as String).replaceAll('\x00', '');
      return cleaned
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('Windows Subsystem'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Discovers all usable shell profiles on the current device.
  static Future<List<ShellProfile>> discoverLocalShells() async {
    final profiles = <ShellProfile>[];
    if (kIsWeb) return profiles;

    if (Platform.isWindows) {
      final pwsh = findPwsh();
      if (pwsh != null) {
        profiles.add(ShellProfile(
          id: 'pwsh',
          label: 'PowerShell 7 (pwsh)',
          subtitle: pwsh,
          executable: pwsh,
          arguments: const ['-NoLogo'],
          category: ShellCategory.powershell,
        ));
      }
      profiles.add(const ShellProfile(
        id: 'powershell',
        label: 'Windows PowerShell',
        subtitle: 'powershell.exe',
        executable: 'powershell.exe',
        arguments: ['-NoLogo', '-NoProfile'],
        category: ShellCategory.powershell,
      ));
      profiles.add(const ShellProfile(
        id: 'cmd',
        label: 'Command Prompt (cmd)',
        subtitle: 'cmd.exe · UTF-8 (chcp 65001)',
        executable: 'cmd.exe',
        category: ShellCategory.system,
      ));
      final gitBash = findGitBash();
      if (gitBash != null) {
        profiles.add(ShellProfile(
          id: 'git-bash',
          label: 'Git Bash',
          subtitle: gitBash,
          executable: gitBash,
          arguments: const ['--login', '-i'],
          category: ShellCategory.unix,
        ));
      }
      final distros = await listWslDistros();
      for (final d in distros) {
        profiles.add(ShellProfile(
          id: 'wsl:$d',
          label: 'WSL · $d',
          subtitle: 'wsl.exe -d $d',
          executable: 'wsl.exe',
          arguments: ['-d', d],
          category: ShellCategory.wsl,
        ));
      }
      profiles.add(const ShellProfile(
        id: 'makaw-sh',
        label: 'Makaw Hybrid Shell (makaw-sh)',
        subtitle: 'Built-in POSIX, ZIP/CURL, Git & SSH tools',
        executable: 'makaw-sh',
        category: ShellCategory.hybrid,
        isHybridBuiltIn: true,
      ));
      return profiles;
    }

    if (Platform.isAndroid) {
      // Primary Android shell: rich pure-Dart POSIX + Archive + HTTP + SSH engine
      // with transparent fallback to /system/bin/sh for native Android binaries.
      profiles.add(const ShellProfile(
        id: 'makaw-sh',
        label: 'Makaw Hybrid Shell',
        subtitle: 'POSIX utils, curl, zip, git info & built-in SSH',
        executable: 'makaw-sh',
        category: ShellCategory.hybrid,
        isHybridBuiltIn: true,
      ));
      for (final entry in const [
        ('termux-zsh', 'Termux Zsh', '/data/data/com.termux/files/usr/bin/zsh'),
        ('termux-bash', 'Termux Bash', '/data/data/com.termux/files/usr/bin/bash'),
      ]) {
        if (File(entry.$3).existsSync()) {
          profiles.add(ShellProfile(
            id: entry.$1,
            label: entry.$2,
            subtitle: entry.$3,
            executable: entry.$3,
            arguments: const ['-l'],
            category: ShellCategory.unix,
          ));
        }
      }
      profiles.add(const ShellProfile(
        id: 'sh',
        label: 'Android System Shell (/system/bin/sh)',
        subtitle: 'Stock Toybox shell',
        executable: '/system/bin/sh',
        category: ShellCategory.system,
      ));
      return profiles;
    }

    // macOS & Linux
    final envShell = Platform.environment['SHELL'];
    final candidates = <String>[
      if (envShell != null && envShell.isNotEmpty) envShell,
      '/bin/zsh',
      '/usr/bin/zsh',
      '/bin/bash',
      '/usr/bin/bash',
      '/usr/local/bin/fish',
      '/usr/bin/fish',
      '/bin/sh',
    ];
    final seen = <String>{};
    for (final path in candidates) {
      if (!seen.add(path)) continue;
      if (!File(path).existsSync()) continue;
      final name = path.split('/').last;
      if (profiles.any((p) => p.id == name)) continue;
      profiles.add(ShellProfile(
        id: name,
        label: name == envShell?.split('/').last ? '$name (Default)' : name,
        subtitle: path,
        executable: path,
        arguments: name == 'sh' ? const [] : const ['-i'],
        category: ShellCategory.unix,
      ));
    }
    profiles.add(const ShellProfile(
      id: 'makaw-sh',
      label: 'Makaw Hybrid Shell (makaw-sh)',
      subtitle: 'Built-in POSIX, ZIP/CURL, Git & SSH tools',
      executable: 'makaw-sh',
      category: ShellCategory.hybrid,
      isHybridBuiltIn: true,
    ));
    return profiles;
  }

  /// Selects the best profile matching a requested [preferredShellId] or defaults
  /// gracefully to the most capable shell on this device (`makaw-sh` on Android,
  /// `pwsh`/`powershell` on Windows, user `$SHELL`/`zsh`/`bash` on macOS/Linux).
  static ShellProfile selectPreferredProfile(
    List<ShellProfile> available, {
    String? preferredShellId,
  }) {
    if (preferredShellId != null && preferredShellId.isNotEmpty) {
      final exact = available.where((p) => p.id == preferredShellId);
      if (exact.isNotEmpty) return exact.first;
      // Alias matching: 'ubuntu' -> 'wsl:Ubuntu*'
      final lower = preferredShellId.toLowerCase();
      final alias = available.where(
          (p) => p.id.toLowerCase().contains(lower) || p.label.toLowerCase().contains(lower));
      if (alias.isNotEmpty) return alias.first;
    }
    return available.first;
  }
}
