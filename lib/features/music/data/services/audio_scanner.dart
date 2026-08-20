import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/entities.dart';

class MakawAudioScanner {
  static const MethodChannel _channel = MethodChannel('com.hexadigitall.makaw/metadata');

  static const List<String> blacklistedDirectories = [
    'whatsapp', 'telegram', 'recordings', 'notifications',
    'alarms', 'ringtones', 'call_recorder', 'voice_recorder',
    '.thumbnails', 'status', 'sticker',
  ];

  static const List<String> supportedExtensions = [
    '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus',
  ];

  static const int minDurationMs = 30000;
  static const int minFileSize = 800 * 1024;

  Future<List<SongInfo>> scanRealSongs() async {
    try {
      return await _methodChannelScan();
    } catch (e) {
      debugPrint('MakawAudioScanner: scan failed: $e');
      return [];
    }
  }

  Future<List<SongInfo>> _methodChannelScan() async {
    try {
      final dirs = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
      ];
      final found = <String>{};
      final files = <String>[];

      for (final dirPath in dirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final p = entity.path.toLowerCase();
            if (supportedExtensions.any((ext) => p.endsWith(ext)) && found.add(entity.path)) {
              files.add(entity.path);
            }
          }
        }
      }

      if (files.isEmpty) return [];

      final results = await _channel.invokeMethod<List<dynamic>>(
        'extractMetadataBatch',
        {'paths': files.take(500).toList()},
      );

      if (results == null) return [];

      int id = 1;
      return results.where((r) {
        final m = Map<String, dynamic>.from(r as Map);
        final duration = (m['duration'] as int?) ?? 0;
        final path = (m['path'] as String? ?? '').toLowerCase();
        final isLongEnough = duration >= minDurationMs;
        final isNotBlacklisted = !blacklistedDirectories.any((dir) => path.contains(dir));
        return isLongEnough && isNotBlacklisted;
      }).map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return SongInfo(
          id: id++,
          title: (m['title'] as String? ?? '').trim(),
          artist: (m['artist'] as String? ?? '').trim(),
          album: (m['album'] as String? ?? '').trim(),
          filePath: m['path'] as String? ?? '',
          duration: (m['duration'] as int?) ?? 0,
          size: 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('MakawAudioScanner: fallback scan failed: $e');
      return [];
    }
  }
}
