import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/session_paths.dart';
import 'lyric_service.dart';

/// A single timestamped lyric line.
class LrcLine {
  Duration time;
  String text;
  LrcLine(this.time, this.text);

  LrcLine copyWith({Duration? time, String? text}) =>
      LrcLine(time ?? this.time, text ?? this.text);
}

/// Complete resolved lyrics payload for a track.
class ResolvedLyrics {
  final List<LrcLine> syncedLines;
  final String plainText;
  final String sourceLabel;
  final String? lrcFilePath;

  const ResolvedLyrics({
    this.syncedLines = const [],
    this.plainText = '',
    this.sourceLabel = '',
    this.lrcFilePath,
  });

  bool get hasSynced => syncedLines.isNotEmpty;
  bool get hasAny => hasSynced || plainText.trim().isNotEmpty;
}

/// Manages universal `.lrc` files inside Makaw's `MakawLyrics` folder,
/// sidecar `.lrc` files alongside audio tracks, SQLite [LyricService], and
/// online lookup (`lrclib.net` + `lyrics.ovh`).
class LrcStorageService {
  LrcStorageService._();

  /// User-accessible Lyrics folder inside Downloads (`Download/MakawLyrics`).
  static Future<String> lyricsFolderPath() async {
    final dlRoot = await SessionPaths.downloadsDir();
    final dir = Directory(p.join(dlRoot, 'MakawLyrics'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<List<File>> listFolderLrcFiles() async {
    final dir = Directory(await lyricsFolderPath());
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => const {'.lrc', '.txt'}.contains(p.extension(f.path).toLowerCase()))
        .toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  static String safeBaseName(String artist, String title) {
    final cleanArtist = artist.trim().toLowerCase() == 'unknown artist' || artist.trim().isEmpty
        ? ''
        : artist.trim();
    final raw = cleanArtist.isNotEmpty ? '$cleanArtist - ${title.trim()}' : title.trim();
    return raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Parses universal `.lrc` text (including multi-tag lines `[00:12.30][01:45.00]Text`).
  static List<LrcLine> parseLrc(String raw) {
    final lines = <LrcLine>[];
    final tagRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]');
    for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
      final matches = tagRegex.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;
      final lyricText = rawLine.replaceAll(tagRegex, '').trim();
      if (lyricText.isEmpty) continue;
      for (final m in matches) {
        final min = int.tryParse(m.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
        final fracRaw = m.group(3) ?? '0';
        final ms = int.tryParse(fracRaw.padRight(3, '0').substring(0, 3)) ?? 0;
        lines.add(LrcLine(Duration(milliseconds: min * 60000 + sec * 1000 + ms), lyricText));
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// Formats lines into a standard universal `.lrc` string.
  static String formatLrc({
    required String title,
    String artist = '',
    String album = '',
    required List<LrcLine> lines,
  }) {
    final buf = StringBuffer();
    if (title.trim().isNotEmpty) buf.writeln('[ti:${title.trim()}]');
    if (artist.trim().isNotEmpty && artist.trim().toLowerCase() != 'unknown artist') {
      buf.writeln('[ar:${artist.trim()}]');
    }
    if (album.trim().isNotEmpty) buf.writeln('[al:${album.trim()}]');
    buf.writeln('[by:Makaw Lyrics Studio]');
    buf.writeln();

    final sorted = List<LrcLine>.from(lines)..sort((a, b) => a.time.compareTo(b.time));
    for (final l in sorted) {
      final totalMs = l.time.inMilliseconds.clamp(0, 99999999);
      final mm = (totalMs ~/ 60000).toString().padLeft(2, '0');
      final ss = ((totalMs % 60000) ~/ 1000).toString().padLeft(2, '0');
      final xx = ((totalMs % 1000) ~/ 10).toString().padLeft(2, '0');
      buf.writeln('[$mm:$ss.$xx]${l.text.trim()}');
    }
    return buf.toString();
  }

  /// Searches offline sources (sidecar `.lrc`, `MakawLyrics` folder, SQLite DB)
  /// and optionally online (`lrclib.net`, `lyrics.ovh`). Automatically saves hits
  /// locally when found online.
  static Future<ResolvedLyrics> resolveLyrics({
    required String songPath,
    required String title,
    required String artist,
    String album = '',
    bool allowOnline = true,
  }) async {
    // 1. Check sidecar .lrc next to the audio file
    if (songPath.isNotEmpty) {
      final sidecarLrc = File(songPath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc'));
      if (await sidecarLrc.exists()) {
        final raw = await sidecarLrc.readAsString();
        final parsed = parseLrc(raw);
        if (parsed.isNotEmpty) {
          await _syncToDb(title: title, artist: artist, synced: parsed);
          return ResolvedLyrics(
            syncedLines: parsed,
            sourceLabel: 'Offline Sidecar (.lrc)',
            lrcFilePath: sidecarLrc.path,
          );
        } else if (raw.trim().isNotEmpty) {
          return ResolvedLyrics(
            plainText: raw.trim(),
            sourceLabel: 'Offline Sidecar',
            lrcFilePath: sidecarLrc.path,
          );
        }
      }
    }

    // 2. Check MakawLyrics folder (exact + fuzzy filename match)
    try {
      final folder = await lyricsFolderPath();
      final exactName = safeBaseName(artist, title);
      final songStem = songPath.isNotEmpty ? p.basenameWithoutExtension(songPath) : '';
      final candidates = <String>[
        if (exactName.isNotEmpty) '$exactName.lrc',
        if (title.trim().isNotEmpty) '${safeBaseName('', title)}.lrc',
        if (songStem.isNotEmpty) '$songStem.lrc',
        if (exactName.isNotEmpty) '$exactName.txt',
      ];
      for (final name in candidates) {
        final f = File(p.join(folder, name));
        if (await f.exists()) {
          final raw = await f.readAsString();
          final parsed = parseLrc(raw);
          if (parsed.isNotEmpty) {
            await _syncToDb(title: title, artist: artist, synced: parsed);
            return ResolvedLyrics(
              syncedLines: parsed,
              sourceLabel: 'MakawLyrics Folder (.lrc)',
              lrcFilePath: f.path,
            );
          } else if (raw.trim().isNotEmpty) {
            await _syncToDb(title: title, artist: artist, plain: raw.trim());
            return ResolvedLyrics(
              plainText: raw.trim(),
              sourceLabel: 'MakawLyrics Folder (.txt)',
              lrcFilePath: f.path,
            );
          }
        }
      }

      // Fuzzy match inside MakawLyrics folder
      final normTitle = _norm(title);
      if (normTitle.length >= 3) {
        for (final entity in Directory(folder).listSync()) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          if (ext != '.lrc' && ext != '.txt') continue;
          final normFile = _norm(p.basenameWithoutExtension(entity.path));
          if (normFile.contains(normTitle) || normTitle.contains(normFile)) {
            final raw = await entity.readAsString();
            final parsed = parseLrc(raw);
            if (parsed.isNotEmpty) {
              return ResolvedLyrics(
                syncedLines: parsed,
                sourceLabel: 'MakawLyrics Folder (.lrc)',
                lrcFilePath: entity.path,
              );
            } else if (raw.trim().isNotEmpty) {
              return ResolvedLyrics(
                plainText: raw.trim(),
                sourceLabel: 'MakawLyrics Folder',
                lrcFilePath: entity.path,
              );
            }
          }
        }
      }
    } catch (_) {}

    // 3. Check SQLite LyricService offline cache
    final songId = '$title — $artist';
    try {
      final dbLines = await LyricService.linesForSong(songId);
      if (dbLines.isNotEmpty) {
        return ResolvedLyrics(
          syncedLines: dbLines
              .map((l) => LrcLine(Duration(milliseconds: l.startMs ?? 0), l.text))
              .toList(),
          sourceLabel: 'Offline Library Cache',
        );
      }
      final full = await LyricService.fullLyricForSong(songId);
      if (full != null && full.text.trim().isNotEmpty) {
        final parsed = parseLrc(full.text);
        if (parsed.isNotEmpty) {
          return ResolvedLyrics(syncedLines: parsed, sourceLabel: 'Offline Library Cache');
        }
        return ResolvedLyrics(plainText: full.text.trim(), sourceLabel: 'Offline Library Cache');
      }
    } catch (_) {}

    if (!allowOnline) {
      return const ResolvedLyrics();
    }

    // Check user preference for auto-saving online lyrics into MakawLyrics folder
    bool saveOnlineToFolder = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      saveOnlineToFolder = prefs.getBool('music_save_lrc_folder') ?? true;
    } catch (_) {}

    final cleanArtist = artist.replaceAll('Unknown Artist', '').trim();
    final encArtist = Uri.encodeComponent(cleanArtist);
    final encTitle = Uri.encodeComponent(title);

    // 4a. Online lrclib.net/api/get
    try {
      final res = await http.get(
        Uri.parse('https://lrclib.net/api/get?artist_name=$encArtist&track_name=$encTitle'),
        headers: {'User-Agent': 'Makaw/1.0'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final hit = await _consumeOnlinePayload(
          data,
          songPath: songPath,
          title: title,
          artist: artist,
          album: album,
          sourceLabel: 'LRCLIB Synced',
          saveToFolder: saveOnlineToFolder,
        );
        if (hit != null) return hit;
      }
    } catch (_) {}

    // 4b. Online lrclib.net/api/search fallback (handles Missing/Unknown artist tags)
    try {
      final q = Uri.encodeComponent(cleanArtist.isNotEmpty ? '$cleanArtist $title' : title);
      final res = await http.get(
        Uri.parse('https://lrclib.net/api/search?q=$q'),
        headers: {'User-Agent': 'Makaw/1.0'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          // Prefer synced result first
          Map<String, dynamic>? chosen;
          for (final item in list) {
            if (item is Map<String, dynamic> && (item['syncedLyrics']?.toString().isNotEmpty ?? false)) {
              chosen = item;
              break;
            }
          }
          chosen ??= list.first is Map<String, dynamic> ? list.first as Map<String, dynamic> : null;
          if (chosen != null) {
            final hit = await _consumeOnlinePayload(
              chosen,
              songPath: songPath,
              title: title,
              artist: artist,
              album: album,
              sourceLabel: 'LRCLIB Search',
              saveToFolder: saveOnlineToFolder,
            );
            if (hit != null) return hit;
          }
        }
      }
    } catch (_) {}

    // 5. Fallback lyrics.ovh
    if (cleanArtist.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse('https://api.lyrics.ovh/v1/$encArtist/$encTitle'))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final lyrics = (data['lyrics'] as String?)?.trim() ?? '';
          if (lyrics.isNotEmpty) {
            String? savedPath;
            if (saveOnlineToFolder) {
              savedPath = await saveLyricsForSong(
                songPath: songPath,
                title: title,
                artist: artist,
                album: album,
                plainText: lyrics,
                writeSidecar: false,
              );
            } else {
              await _syncToDb(title: title, artist: artist, plain: lyrics);
            }
            return ResolvedLyrics(
              plainText: lyrics,
              sourceLabel: 'Lyrics.ovh Online',
              lrcFilePath: savedPath,
            );
          }
        }
      } catch (_) {}
    }

    return const ResolvedLyrics();
  }

  static Future<ResolvedLyrics?> _consumeOnlinePayload(
    Map<String, dynamic> data, {
    required String songPath,
    required String title,
    required String artist,
    required String album,
    required String sourceLabel,
    required bool saveToFolder,
  }) async {
    final synced = data['syncedLyrics'] as String?;
    final plain = data['plainLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) {
      final parsed = parseLrc(synced);
      if (parsed.isNotEmpty) {
        String? savedPath;
        if (saveToFolder) {
          savedPath = await saveLyricsForSong(
            songPath: songPath,
            title: title,
            artist: artist,
            album: album,
            syncedLines: parsed,
            writeSidecar: false,
          );
        } else {
          await _syncToDb(title: title, artist: artist, synced: parsed);
        }
        return ResolvedLyrics(
          syncedLines: parsed,
          sourceLabel: sourceLabel,
          lrcFilePath: savedPath,
        );
      }
    }
    if (plain != null && plain.trim().isNotEmpty) {
      await _syncToDb(title: title, artist: artist, plain: plain.trim());
      return ResolvedLyrics(plainText: plain.trim(), sourceLabel: '$sourceLabel (Plain)');
    }
    return null;
  }

  /// Saves lyrics as `.lrc` (or `.txt` if plain only) into MakawLyrics folder,
  /// optionally writes sidecar `.lrc` beside audio file, and saves to SQLite DB.
  /// Returns path inside `MakawLyrics`.
  static Future<String> saveLyricsForSong({
    required String songPath,
    required String title,
    required String artist,
    String album = '',
    List<LrcLine> syncedLines = const [],
    String plainText = '',
    bool writeSidecar = true,
  }) async {
    final folder = await lyricsFolderPath();
    final base = safeBaseName(artist, title);
    final isSynced = syncedLines.isNotEmpty;
    final ext = isSynced ? 'lrc' : 'txt';
    final content = isSynced
        ? formatLrc(title: title, artist: artist, album: album, lines: syncedLines)
        : plainText.trim();

    final mainFile = File(p.join(folder, '${base.isEmpty ? 'lyrics_${DateTime.now().millisecondsSinceEpoch}' : base}.$ext'));
    await mainFile.writeAsString(content);

    if (writeSidecar && songPath.isNotEmpty && isSynced) {
      try {
        final sidecar = File(songPath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc'));
        await sidecar.writeAsString(content);
      } catch (_) {}
    }

    await _syncToDb(
      title: title,
      artist: artist,
      synced: syncedLines,
      plain: plainText,
    );
    return mainFile.path;
  }

  static Future<void> _syncToDb({
    required String title,
    required String artist,
    List<LrcLine> synced = const [],
    String plain = '',
  }) async {
    final songId = '$title — $artist';
    final now = DateTime.now();
    if (synced.isNotEmpty) {
      try {
        final dbLines = <Lyric>[];
        for (int i = 0; i < synced.length; i++) {
          final l = synced[i];
          final startMs = l.time.inMilliseconds;
          final endMs = (i + 1 < synced.length)
              ? (synced[i + 1].time.inMilliseconds - 1).clamp(startMs, 1 << 62)
              : startMs + 3500;
          dbLines.add(Lyric(
            songId: songId,
            songTitle: title,
            artist: artist,
            text: l.text,
            startMs: startMs,
            endMs: endMs,
            createdAt: now,
            updatedAt: now,
          ));
        }
        await LyricService.saveTimedLyrics(
          songId: songId,
          songTitle: title,
          artist: artist,
          lines: dbLines,
        );
      } catch (_) {}
    } else if (plain.trim().isNotEmpty) {
      try {
        await LyricService.saveFullLyric(
          songId: songId,
          songTitle: title,
          artist: artist,
          text: plain.trim(),
        );
      } catch (_) {}
    }
  }

  static String _norm(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
