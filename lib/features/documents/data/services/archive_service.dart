import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Metadata about a single entry inside an archive.
class ArchiveEntryInfo {
  final String name;
  final int size;
  final bool isDirectory;
  final String? compressionInfo;

  const ArchiveEntryInfo({
    required this.name,
    required this.size,
    required this.isDirectory,
    this.compressionInfo,
  });
}

/// Result of an archive creation or extraction operation.
class ArchiveResult {
  final bool success;
  final String outputPath;
  final int fileCount;
  final String message;
  final bool canTryExternalFallback;

  const ArchiveResult({
    required this.success,
    required this.outputPath,
    this.fileCount = 0,
    required this.message,
    this.canTryExternalFallback = false,
  });
}

/// High-performance background archive engine for Makaw File Explorer.
///
/// Supports creating `.zip` / `.tar.gz` archives and inspecting/extracting
/// `.zip`, `.tar`, `.gz`, `.tgz`, `.bz2`, `.xz`, `.epub`, `.apk`, `.jar`,
/// plus RAR4/RAR5 inspection and extraction (native `tar` on Windows,
/// stored/CLI fallback on POSIX/Android).
class ArchiveService {
  ArchiveService._();

  static const Set<String> supportedArchiveExts = {
    'zip',
    'rar',
    'tar',
    'gz',
    'tgz',
    'bz2',
    'xz',
    '7z',
    'jar',
    'apk',
  };

  static bool isArchivePath(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return supportedArchiveExts.contains(ext);
  }

  /// Ensures a non-colliding output path if target file/folder already exists.
  static String uniquePath(String targetPath) {
    if (!File(targetPath).existsSync() && !Directory(targetPath).existsSync()) {
      return targetPath;
    }
    final dir = p.dirname(targetPath);
    final ext = p.extension(targetPath);
    final base = p.basenameWithoutExtension(targetPath);
    int i = 1;
    while (true) {
      final cand = ext.isNotEmpty ? p.join(dir, '$base ($i)$ext') : p.join(dir, '$base ($i)');
      if (!File(cand).existsSync() && !Directory(cand).existsSync()) return cand;
      i++;
    }
  }

  /// Compresses [sourcePaths] (files and/or directories) into a `.zip` file at [outputZipPath].
  static Future<ArchiveResult> createZip({
    required List<String> sourcePaths,
    required String outputZipPath,
  }) async {
    return Isolate.run(() {
      try {
        final encoder = ZipFileEncoder();
        encoder.create(outputZipPath);
        int count = 0;

        for (final src in sourcePaths) {
          final type = FileSystemEntity.typeSync(src, followLinks: false);
          if (type == FileSystemEntityType.directory) {
            final dir = Directory(src);
            final parent = dir.parent.path;
            for (final entity in dir.listSync(recursive: true, followLinks: false)) {
              if (entity is File) {
                final rel = p.relative(entity.path, from: parent).replaceAll('\\', '/');
                encoder.addFileSync(entity, rel);
                count++;
              }
            }
          } else if (type == FileSystemEntityType.file) {
            final file = File(src);
            encoder.addFileSync(file, p.basename(src));
            count++;
          }
        }
        encoder.closeSync();
        return ArchiveResult(
          success: true,
          outputPath: outputZipPath,
          fileCount: count,
          message: 'Created ${p.basename(outputZipPath)} ($count files)',
        );
      } catch (e) {
        return ArchiveResult(
          success: false,
          outputPath: outputZipPath,
          message: 'Failed to create zip: $e',
        );
      }
    });
  }

  /// Compresses [sourcePaths] into a `.tar.gz` archive at [outputPath].
  static Future<ArchiveResult> createTarGz({
    required List<String> sourcePaths,
    required String outputPath,
  }) async {
    return Isolate.run(() {
      try {
        final archive = Archive();
        int count = 0;

        for (final src in sourcePaths) {
          final type = FileSystemEntity.typeSync(src, followLinks: false);
          if (type == FileSystemEntityType.directory) {
            final dir = Directory(src);
            final parent = dir.parent.path;
            for (final entity in dir.listSync(recursive: true, followLinks: false)) {
              if (entity is File) {
                final rel = p.relative(entity.path, from: parent).replaceAll('\\', '/');
                final bytes = entity.readAsBytesSync();
                archive.addFile(ArchiveFile(rel, bytes.length, bytes));
                count++;
              }
            }
          } else if (type == FileSystemEntityType.file) {
            final file = File(src);
            final bytes = file.readAsBytesSync();
            archive.addFile(ArchiveFile(p.basename(src), bytes.length, bytes));
            count++;
          }
        }

        final tarBytes = TarEncoder().encode(archive);
        final gzBytes = GZipEncoder().encode(tarBytes);
        File(outputPath).writeAsBytesSync(gzBytes);
        return ArchiveResult(
          success: true,
          outputPath: outputPath,
          fileCount: count,
          message: 'Created ${p.basename(outputPath)} ($count files)',
        );
      } catch (e) {
        return ArchiveResult(
          success: false,
          outputPath: outputPath,
          message: 'Failed to create tar.gz: $e',
        );
      }
    });
  }

  /// Lists contents inside an archive without modifying disk.
  static Future<List<ArchiveEntryInfo>> inspectArchive(String archivePath) async {
    return Isolate.run(() {
      final lower = archivePath.toLowerCase();
      if (lower.endsWith('.rar')) {
        return _inspectRarHeaders(File(archivePath).readAsBytesSync());
      }
      if (lower.endsWith('.zip') || lower.endsWith('.jar') || lower.endsWith('.apk') || lower.endsWith('.epub')) {
        final input = InputFileStream(archivePath);
        try {
          final archive = ZipDecoder().decodeStream(input);
          return archive.files
              .map((f) => ArchiveEntryInfo(
                    name: f.name,
                    size: f.size,
                    isDirectory: f.isDirectory,
                  ))
              .toList();
        } finally {
          input.closeSync();
        }
      }
      if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        final raw = File(archivePath).readAsBytesSync();
        final tarBytes = GZipDecoder().decodeBytes(raw);
        final archive = TarDecoder().decodeBytes(tarBytes);
        return archive.files
            .map((f) => ArchiveEntryInfo(name: f.name, size: f.size, isDirectory: f.isDirectory))
            .toList();
      }
      if (lower.endsWith('.tar')) {
        final raw = File(archivePath).readAsBytesSync();
        final archive = TarDecoder().decodeBytes(raw);
        return archive.files
            .map((f) => ArchiveEntryInfo(name: f.name, size: f.size, isDirectory: f.isDirectory))
            .toList();
      }
      if (lower.endsWith('.tar.bz2') || lower.endsWith('.tbz2')) {
        final raw = File(archivePath).readAsBytesSync();
        final tarBytes = BZip2Decoder().decodeBytes(raw);
        final archive = TarDecoder().decodeBytes(tarBytes);
        return archive.files
            .map((f) => ArchiveEntryInfo(name: f.name, size: f.size, isDirectory: f.isDirectory))
            .toList();
      }
      if (lower.endsWith('.gz')) {
        final stem = p.basenameWithoutExtension(archivePath);
        return [ArchiveEntryInfo(name: stem, size: File(archivePath).lengthSync(), isDirectory: false)];
      }
      return const <ArchiveEntryInfo>[];
    });
  }

  /// Extracts [archivePath] safely into [destinationDir].
  static Future<ArchiveResult> extractArchive({
    required String archivePath,
    required String destinationDir,
  }) async {
    final lower = archivePath.toLowerCase();

    // Windows built-in bsdtar natively extracts .rar, .7z, .zip, .tar.gz, .xz, etc.
    if (Platform.isWindows && (lower.endsWith('.rar') || lower.endsWith('.7z'))) {
      try {
        await Directory(destinationDir).create(recursive: true);
        final canonicalRoot = p.normalize(Directory(destinationDir).absolute.path);
        final listing = await Process.run('tar.exe', ['-tf', archivePath]);
        if (listing.exitCode != 0) {
          return ArchiveResult(
            success: false,
            outputPath: destinationDir,
            message: 'Could not verify archive contents before extraction.',
            canTryExternalFallback: true,
          );
        }
        final unsafe = listing.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .any((name) {
          final clean = name.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
          final target = p.normalize(p.join(canonicalRoot, clean));
          return target != canonicalRoot && !p.isWithin(canonicalRoot, target);
        });
        if (unsafe) {
          return ArchiveResult(
            success: false,
            outputPath: destinationDir,
            message: 'Archive contains unsafe paths and was not extracted.',
          );
        }
        final res = await Process.run('tar.exe', ['-xf', archivePath, '-C', destinationDir]);
        if (res.exitCode == 0) {
          final count = Directory(destinationDir).listSync(recursive: true).whereType<File>().length;
          return ArchiveResult(
            success: true,
            outputPath: destinationDir,
            fileCount: count,
            message: 'Extracted $count files to ${p.basename(destinationDir)}',
          );
        }
      } catch (_) {}
    }

    return Isolate.run(() async {
      try {
        final destRoot = Directory(destinationDir);
        destRoot.createSync(recursive: true);
        final canonicalRoot = p.normalize(destRoot.absolute.path);

        String? safeTarget(String entryName) {
          final clean = entryName.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
          if (clean.isEmpty) return null;
          final target = p.normalize(p.join(canonicalRoot, clean));
          if (target != canonicalRoot && !p.isWithin(canonicalRoot, target)) return null;
          return target;
        }

        if (lower.endsWith('.rar')) {
          return _extractRarBestEffort(archivePath, canonicalRoot, safeTarget);
        }

        int count = 0;
        void writeArchive(Archive archive) {
          for (final file in archive) {
            final target = safeTarget(file.name);
            if (target == null) continue;
            if (file.isDirectory) {
              Directory(target).createSync(recursive: true);
            } else {
              final outFile = File(target);
              outFile.parent.createSync(recursive: true);
              final output = OutputFileStream(outFile.path);
              try {
                file.writeContent(output);
              } finally {
                output.closeSync();
              }
              count++;
            }
          }
        }

        if (lower.endsWith('.zip') || lower.endsWith('.jar') || lower.endsWith('.apk') || lower.endsWith('.epub')) {
          final input = InputFileStream(archivePath);
          try {
            final archive = ZipDecoder().decodeStream(input);
            writeArchive(archive);
          } finally {
            input.closeSync();
          }
        } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
          final tarBytes = GZipDecoder().decodeBytes(File(archivePath).readAsBytesSync());
          writeArchive(TarDecoder().decodeBytes(tarBytes));
        } else if (lower.endsWith('.tar.bz2') || lower.endsWith('.tbz2')) {
          final tarBytes = BZip2Decoder().decodeBytes(File(archivePath).readAsBytesSync());
          writeArchive(TarDecoder().decodeBytes(tarBytes));
        } else if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
          final tarBytes = XZDecoder().decodeBytes(File(archivePath).readAsBytesSync());
          writeArchive(TarDecoder().decodeBytes(tarBytes));
        } else if (lower.endsWith('.tar')) {
          writeArchive(TarDecoder().decodeBytes(File(archivePath).readAsBytesSync()));
        } else if (lower.endsWith('.gz')) {
          final outBytes = GZipDecoder().decodeBytes(File(archivePath).readAsBytesSync());
          final outName = p.basenameWithoutExtension(archivePath);
          final target = safeTarget(outName);
          if (target != null) {
            File(target).writeAsBytesSync(outBytes);
            count = 1;
          }
        } else if (lower.endsWith('.bz2')) {
          final outBytes = BZip2Decoder().decodeBytes(File(archivePath).readAsBytesSync());
          final outName = p.basenameWithoutExtension(archivePath);
          final target = safeTarget(outName);
          if (target != null) {
            File(target).writeAsBytesSync(outBytes);
            count = 1;
          }
        } else if (lower.endsWith('.xz')) {
          final outBytes = XZDecoder().decodeBytes(File(archivePath).readAsBytesSync());
          final outName = p.basenameWithoutExtension(archivePath);
          final target = safeTarget(outName);
          if (target != null) {
            File(target).writeAsBytesSync(outBytes);
            count = 1;
          }
        } else {
          return ArchiveResult(
            success: false,
            outputPath: destinationDir,
            message: 'Format not supported natively — opening with system handler.',
            canTryExternalFallback: true,
          );
        }

        return ArchiveResult(
          success: true,
          outputPath: destinationDir,
          fileCount: count,
          message: 'Extracted $count ${count == 1 ? 'file' : 'files'} to ${p.basename(destinationDir)}',
        );
      } catch (e) {
        return ArchiveResult(
          success: false,
          outputPath: destinationDir,
          message: 'Extraction failed: $e',
          canTryExternalFallback: true,
        );
      }
    });
  }

  // ── RAR4 Header Inspector + Uncompressed Store Extractor ──────────────────

  static List<ArchiveEntryInfo> _inspectRarHeaders(Uint8List data) {
    final entries = <ArchiveEntryInfo>[];
    if (data.length < 7) return entries;

    // Check RAR5 magic: 52 61 72 21 1A 07 01 00
    final isRar5 = data.length >= 8 &&
        data[0] == 0x52 && data[1] == 0x61 && data[2] == 0x72 && data[3] == 0x21 &&
        data[4] == 0x1A && data[5] == 0x07 && data[6] == 0x01 && data[7] == 0x00;

    if (isRar5) {
      int pos = 8;
      while (pos + 6 < data.length) {
        pos += 4; // skip CRC32
        final sizePair = _readVint(data, pos);
        if (sizePair == null) break;
        final headerSize = sizePair.$1;
        pos = sizePair.$2;
        final headerEnd = pos + headerSize;
        if (headerEnd > data.length) break;

        final typePair = _readVint(data, pos);
        if (typePair == null) break;
        final hdrType = typePair.$1;
        var cur = typePair.$2;

        final flagsPair = _readVint(data, cur);
        if (flagsPair == null) break;
        final hdrFlags = flagsPair.$1;
        cur = flagsPair.$2;

        int extraSize = 0;
        if ((hdrFlags & 0x0001) != 0) {
          final ex = _readVint(data, cur);
          if (ex == null) break;
          extraSize = ex.$1;
          cur = ex.$2;
        }
        int dataSize = 0;
        if ((hdrFlags & 0x0002) != 0) {
          final ds = _readVint(data, cur);
          if (ds == null) break;
          dataSize = ds.$1;
          cur = ds.$2;
        }

        if (hdrType == 2 && cur < headerEnd) {
          // File header
          final fileFlags = _readVint(data, cur);
          if (fileFlags != null) {
            cur = fileFlags.$2;
            final isDir = (fileFlags.$1 & 0x0001) != 0;
            final unpSize = _readVint(data, cur);
            if (unpSize != null) {
              cur = unpSize.$2;
              final attrs = _readVint(data, cur);
              if (attrs != null) {
                cur = attrs.$2;
                if ((fileFlags.$1 & 0x0002) != 0) cur += 4; // mtime
                if ((fileFlags.$1 & 0x0004) != 0) cur += 4; // crc32
                final compInfo = _readVint(data, cur);
                if (compInfo != null) {
                  cur = compInfo.$2;
                  final hostOs = _readVint(data, cur);
                  if (hostOs != null) {
                    cur = hostOs.$2;
                    final nameLen = _readVint(data, cur);
                    if (nameLen != null) {
                      cur = nameLen.$2;
                      final endName = (cur + nameLen.$1).clamp(cur, headerEnd - extraSize);
                      final name = utf8.decode(data.sublist(cur, endName), allowMalformed: true);
                      final method = (compInfo.$1 >> 7) & 0x07;
                      entries.add(ArchiveEntryInfo(
                        name: name,
                        size: unpSize.$1,
                        isDirectory: isDir,
                        compressionInfo: method == 0 ? 'Stored' : 'RAR5 compressed',
                      ));
                    }
                  }
                }
              }
            }
          }
        }
        pos = headerEnd + dataSize;
      }
      return entries;
    }

    // Check RAR4 magic: 52 61 72 21 1A 07 00
    final isRar4 = data[0] == 0x52 && data[1] == 0x61 && data[2] == 0x72 && data[3] == 0x21 &&
        data[4] == 0x1A && data[5] == 0x07 && data[6] == 0x00;
    if (!isRar4) return entries;

    int pos = 7;
    while (pos + 7 <= data.length) {
      final hdrType = data[pos + 2];
      final flags = data[pos + 3] | (data[pos + 4] << 8);
      final hdrSize = data[pos + 5] | (data[pos + 6] << 8);
      if (hdrSize < 7 || pos + hdrSize > data.length) break;

      int addSize = 0;
      if ((flags & 0x8000) != 0 || hdrType == 0x74) {
        if (pos + 11 <= data.length) {
          addSize = data[pos + 7] | (data[pos + 8] << 8) | (data[pos + 9] << 16) | (data[pos + 10] << 24);
        }
      }

      if (hdrType == 0x74 && pos + 32 <= pos + hdrSize) {
        final unpSize = data[pos + 11] | (data[pos + 12] << 8) | (data[pos + 13] << 16) | (data[pos + 14] << 24);
        final method = data[pos + 25];
        final nameLen = data[pos + 26] | (data[pos + 27] << 8);
        final fileAttrs = data[pos + 28] | (data[pos + 29] << 8) | (data[pos + 30] << 16) | (data[pos + 31] << 24);
        final nameStart = pos + 32;
        final nameEnd = (nameStart + nameLen).clamp(nameStart, pos + hdrSize);
        final name = utf8.decode(data.sublist(nameStart, nameEnd), allowMalformed: true).split('\x00').first;
        final isDir = (fileAttrs & 0x10) != 0 || (flags & 0xE0) == 0xE0;
        entries.add(ArchiveEntryInfo(
          name: name,
          size: unpSize,
          isDirectory: isDir,
          compressionInfo: method == 0x30 ? 'Stored' : 'RAR4 compressed',
        ));
      }
      pos += hdrSize + addSize;
      if (hdrType == 0x7B) break; // ENDARC
    }
    return entries;
  }

  static ArchiveResult _extractRarBestEffort(
    String archivePath,
    String canonicalRoot,
    String? Function(String) safeTarget,
  ) {
    final data = File(archivePath).readAsBytesSync();
    if (data.length < 7) {
      return ArchiveResult(success: false, outputPath: canonicalRoot, message: 'Invalid RAR archive.');
    }

    // Attempt RAR4 uncompressed (Store 0x30) extraction cleanly in pure Dart
    final isRar4 = data[0] == 0x52 && data[1] == 0x61 && data[2] == 0x72 && data[3] == 0x21 &&
        data[4] == 0x1A && data[5] == 0x07 && data[6] == 0x00;

    if (isRar4) {
      int pos = 7;
      int extracted = 0;
      bool sawCompressed = false;
      while (pos + 7 <= data.length) {
        final hdrType = data[pos + 2];
        final flags = data[pos + 3] | (data[pos + 4] << 8);
        final hdrSize = data[pos + 5] | (data[pos + 6] << 8);
        if (hdrSize < 7 || pos + hdrSize > data.length) break;

        int addSize = 0;
        if ((flags & 0x8000) != 0 || hdrType == 0x74) {
          if (pos + 11 <= data.length) {
            addSize = data[pos + 7] | (data[pos + 8] << 8) | (data[pos + 9] << 16) | (data[pos + 10] << 24);
          }
        }
        if (hdrType == 0x74 && pos + 32 <= pos + hdrSize) {
          final method = data[pos + 25];
          final nameLen = data[pos + 26] | (data[pos + 27] << 8);
          final fileAttrs = data[pos + 28] | (data[pos + 29] << 8) | (data[pos + 30] << 16) | (data[pos + 31] << 24);
          final nameStart = pos + 32;
          final nameEnd = (nameStart + nameLen).clamp(nameStart, pos + hdrSize);
          final name = utf8.decode(data.sublist(nameStart, nameEnd), allowMalformed: true).split('\x00').first;
          final isDir = (fileAttrs & 0x10) != 0 || (flags & 0xE0) == 0xE0;
          final target = safeTarget(name);
          if (target != null) {
            if (isDir) {
              Directory(target).createSync(recursive: true);
            } else if (method == 0x30) {
              final dataStart = pos + hdrSize;
              final dataEnd = (dataStart + addSize).clamp(dataStart, data.length);
              final out = File(target);
              out.parent.createSync(recursive: true);
              out.writeAsBytesSync(data.sublist(dataStart, dataEnd));
              extracted++;
            } else {
              sawCompressed = true;
            }
          }
        }
        pos += hdrSize + addSize;
        if (hdrType == 0x7B) break;
      }

      if (extracted > 0 && !sawCompressed) {
        return ArchiveResult(
          success: true,
          outputPath: canonicalRoot,
          fileCount: extracted,
          message: 'Extracted $extracted files',
        );
      }
      if (sawCompressed) {
        return ArchiveResult(
          success: false,
          outputPath: canonicalRoot,
          fileCount: extracted,
          message: 'Compressed RAR archives require native WinRAR/ZArchiver on Android; tap "Open Externally" or re-pack as .zip.',
          canTryExternalFallback: true,
        );
      }
    }

    return ArchiveResult(
      success: false,
      outputPath: canonicalRoot,
      message: 'Compressed RAR5/proprietary archives require an external unarchiver on Android.',
      canTryExternalFallback: true,
    );
  }

  static (int, int)? _readVint(Uint8List data, int offset) {
    int val = 0;
    int shift = 0;
    int pos = offset;
    while (pos < data.length && shift < 63) {
      final b = data[pos++];
      val |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return (val, pos);
      shift += 7;
    }
    return null;
  }
}
