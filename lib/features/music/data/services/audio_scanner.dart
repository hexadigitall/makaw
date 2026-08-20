import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../domain/entities/entities.dart';

class MakawAudioScanner {
  final OnAudioQuery _audioQuery = OnAudioQuery();

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
    final hasPermission = await _audioQuery.checkAndRequest(retryRequest: true);
    if (!hasPermission) return [];

    try {
      final allSongs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      final realSongs = allSongs.where((song) {
        final duration = song.duration ?? 0;
        final size = song.size;
        final path = (song.data).toLowerCase();

        final isLongEnough = duration >= minDurationMs;
        final isLargeEnough = size >= minFileSize;
        final isNotBlacklisted = !blacklistedDirectories.any((dir) => path.contains(dir));
        final hasValidExt = supportedExtensions.any((ext) => path.endsWith(ext));

        return isLongEnough && isLargeEnough && isNotBlacklisted && hasValidExt;
      }).map((song) => SongInfo(
        id: song.id,
        title: (song.title ?? '').trim(),
        artist: (song.artist ?? '').trim(),
        album: (song.album ?? '').trim(),
        filePath: song.data,
        duration: song.duration ?? 0,
        albumId: song.albumId ?? -1,
        size: song.size,
      )).toList();

      realSongs.sort((a, b) => _compareAtoZ(a.title, b.title));
      return realSongs;
    } catch (e) {
      debugPrint('MakawAudioScanner: scan failed: $e');
      return _fallbackMethodChannelScan();
    }
  }

  Future<List<SongInfo>> _fallbackMethodChannelScan() async {
    const channel = MethodChannel('com.hexadigitall.makaw/metadata');
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

      final results = await channel.invokeMethod<List<dynamic>>(
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

  static int _compareAtoZ(String a, String b) {
    final cleanA = a.trim();
    final cleanB = b.trim();
    final isALetter = RegExp(r'^[a-zA-Z]').hasMatch(cleanA);
    final isBLetter = RegExp(r'^[a-zA-Z]').hasMatch(cleanB);

    if (isALetter && !isBLetter) return -1;
    if (!isALetter && isBLetter) return 1;
    return cleanA.toLowerCase().compareTo(cleanB.toLowerCase());
  }
}
