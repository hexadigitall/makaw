import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service to detect, request, and execute commands with root (superuser) access on Android/Linux.
class RootService {
  RootService._();
  static final RootService instance = RootService._();

  static const List<String> _suPaths = [
    '/system/bin/su',
    '/system/xbin/su',
    '/sbin/su',
    '/system/sd/xbin/su',
    '/system/bin/failsafe/su',
    '/data/local/xbin/su',
    '/data/local/bin/su',
    '/data/local/su',
    '/su/bin/su',
    '/magisk/.core/bin/su',
  ];

  bool? _isRootAvailable;
  bool? _isRootGranted;

  /// Checks if the `su` binary exists on the system.
  Future<bool> isRootAvailable() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isLinux) return false;
    if (_isRootAvailable != null) return _isRootAvailable!;

    for (final path in _suPaths) {
      try {
        if (File(path).existsSync()) {
          _isRootAvailable = true;
          return true;
        }
      } catch (_) {}
    }

    try {
      final res = await Process.run('which', ['su']).timeout(const Duration(seconds: 2));
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        _isRootAvailable = true;
        return true;
      }
    } catch (_) {}

    _isRootAvailable = false;
    return false;
  }

  /// Checks if root permission has been granted to the app by superuser (Magisk/KernelSU/etc.).
  Future<bool> isRootGranted() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isLinux) return false;
    if (_isRootGranted != null) return _isRootGranted!;

    final available = await isRootAvailable();
    if (!available) {
      _isRootGranted = false;
      return false;
    }

    try {
      final res = await runRootCommand('id').timeout(const Duration(seconds: 3));
      final out = res.stdout.toString();
      _isRootGranted = res.exitCode == 0 && (out.contains('uid=0') || out.contains('root'));
      return _isRootGranted!;
    } catch (_) {
      _isRootGranted = false;
      return false;
    }
  }

  /// Prompts the superuser manager to grant root access to Makaw.
  Future<bool> requestRootAccess() async {
    _isRootGranted = null;
    return await isRootGranted();
  }

  /// Runs a command as root using `su -c`.
  Future<ProcessResult> runRootCommand(String command) async {
    if (kIsWeb) {
      return ProcessResult(0, -1, '', 'Root is not supported on web');
    }
    try {
      return await Process.run('su', ['-c', command]).timeout(const Duration(seconds: 15));
    } catch (e) {
      return ProcessResult(0, -1, '', e.toString());
    }
  }
}
