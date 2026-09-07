import 'dart:io';

import 'package:flutter/foundation.dart';

/// Platform-aware filesystem roots.
///
/// The media/document/file-explorer services historically hardcoded Android
/// paths (`/storage/emulated/0/...`), which made every scanner return empty on
/// Windows/Linux/macOS. This utility centralizes the platform branch so each
/// service can derive real scan roots per platform.
class PlatformPaths {
  PlatformPaths._();

  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Home directory for the current user (desktop platforms only).
  static String home() =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';

  /// Documents-style scan roots. Android uses the legacy emulated storage;
  /// desktop uses the OS-native user folders.
  static List<String> documentScanDirs() {
    if (Platform.isAndroid) {
      return [
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Books',
        '/storage/emulated/0/eBooks',
        '/storage/emulated/0/PDF',
        '/storage/emulated/0/Notes',
      ];
    }
    if (Platform.isIOS && !kIsWeb) return [];
    if (kIsWeb) return [];
    final h = home();
    if (h.isEmpty) return [];
    final sep = Platform.pathSeparator;
    if (Platform.isWindows) {
      return [
        '$h${sep}Documents',
        '$h${sep}Downloads',
        '$h${sep}Desktop',
        '$h${sep}Pictures',
      ];
    }
    // Linux / macOS
    final xdgDirs = Platform.environment['XDG_DOCUMENTS_DIR'];
    return [
      if (xdgDirs != null && xdgDirs.isNotEmpty) xdgDirs,
      '$h${sep}Documents',
      '$h${sep}Downloads',
      '$h${sep}Desktop',
    ];
  }

  /// Quick-access roots for the full-device file explorer.
  static List<({String label, String path, String kind})> quickAccessRoots() {
    if (Platform.isAndroid) {
      const base = '/storage/emulated/0';
      return [
        (label: 'Downloads', path: '$base/Download', kind: 'download'),
        (label: 'Documents', path: '$base/Documents', kind: 'doc'),
        (label: 'Pictures', path: '$base/Pictures', kind: 'picture'),
        (label: 'Music', path: '$base/Music', kind: 'music'),
        (label: 'Movies', path: '$base/Movies', kind: 'video'),
        (label: 'DCIM', path: '$base/DCIM', kind: 'video'),
        (label: 'Android / data', path: '$base/Android', kind: 'android'),
        (label: 'Device root', path: '/', kind: 'root'),
      ];
    }
    if (Platform.isIOS && !kIsWeb) return [];
    if (kIsWeb) return [];
    final h = home();
    final sep = Platform.pathSeparator;
    final roots = <({String label, String path, String kind})>[
      if (h.isNotEmpty) ...[
        (label: 'Downloads', path: '$h${sep}Downloads', kind: 'download'),
        (label: 'Documents', path: '$h${sep}Documents', kind: 'doc'),
        (label: 'Pictures', path: '$h${sep}Pictures', kind: 'picture'),
        (label: 'Music', path: '$h${sep}Music', kind: 'music'),
        (label: 'Videos', path: '$h${sep}Videos', kind: 'video'),
        (label: 'Desktop', path: '$h${sep}Desktop', kind: 'doc'),
      ],
    ];
    if (Platform.isWindows) {
      // Common fixed drives.
      for (final letter in ['C', 'D', 'E', 'F', 'G']) {
        final drive = '$letter:\\';
        try {
          if (Directory(drive).existsSync()) {
            roots.add((label: 'Drive ($letter:)', path: drive, kind: 'root'));
          }
        } catch (_) {}
      }
    } else {
      roots.add((label: 'File system root', path: '/', kind: 'root'));
    }
    return roots;
  }

  /// Video scan roots (top-level directories to search for media).
  static List<String> videoScanRoots() {
    if (Platform.isAndroid) {
      return [
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/WhatsApp',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Camera',
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Videos',
        '/storage/emulated/0/Video',
        '/storage/emulated/0/Filmora',
        '/storage/emulated/0/WhatsApp Business',
        '/storage/emulated/0/Podcasts',
        '/storage/emulated/0/Recordings',
        '/storage/emulated/0/ScreenRecorder',
        '/storage/emulated/0/Screenshots',
        '/storage/emulated/0/Edited',
        '/storage/emulated/0/Insave',
        '/storage/emulated/0/ShareChat',
        '/storage/emulated/0/MX Player',
        '/storage/emulated/0/VMate',
        '/storage/emulated/0/Likee',
        '/storage/emulated/0/Clip',
        '/storage/emulated/0/TikTok',
        '/storage/emulated/0/CapCut',
        '/storage/emulated/0/KineMaster',
        '/storage/emulated/0/Alight Motion',
        '/storage/emulated/0/PowerDirector',
        '/storage/emulated/0/FilmoraGo',
        '/storage/emulated/0/VLLO',
        '/storage/emulated/0/Snapchat',
        '/storage/emulated/0/Instagram',
        '/storage/emulated/0/Facebook',
        '/storage/emulated/0/Telegram',
      ];
    }
    if (!isDesktop) return [];
    final h = home();
    if (h.isEmpty) return [];
    final sep = Platform.pathSeparator;
    return [
      '$h${sep}Videos',
      '$h${sep}Movies',
      '$h${sep}Downloads',
      '$h${sep}Desktop',
      '$h${sep}Pictures',
    ];
  }

  /// Image scan roots.
  static List<String> imageScanRoots() {
    if (Platform.isAndroid) {
      return [
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Screenshots',
        '/storage/emulated/0/Download',
      ];
    }
    if (!isDesktop) return [];
    final h = home();
    if (h.isEmpty) return [];
    final sep = Platform.pathSeparator;
    return [
      '$h${sep}Pictures',
      '$h${sep}Downloads',
      '$h${sep}Desktop',
      '$h${sep}Screenshots',
      '$h${sep}Documents',
    ];
  }

  /// Music scan roots.
  static List<String> musicScanRoots() {
    if (Platform.isAndroid) {
      return [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/download',
      ];
    }
    if (!isDesktop) return [];
    final h = home();
    if (h.isEmpty) return [];
    final sep = Platform.pathSeparator;
    return [
      '$h${sep}Music',
      '$h${sep}music',
      '$h${sep}Downloads',
      '$h${sep}downloads',
      '$h${sep}Desktop',
    ];
  }

  /// Human-readable default download location hint for the current platform.
  static String defaultDownloadsHint() {
    if (Platform.isAndroid) return '/storage/emulated/0/Download/Makaw';
    if (!isDesktop) return '';
    final h = home();
    if (h.isEmpty) return '';
    return '${h}${Platform.pathSeparator}Downloads';
  }
}