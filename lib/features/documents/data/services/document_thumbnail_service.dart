import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

/// Asynchronous, bounded thumbnail extractor for Makaw Documents cards/grid.
///
/// Extracts embedded covers from EPUB (OPF manifest), Office/OpenDocument ZIPs
/// (`docProps/thumbnail.*`, `Thumbnails/thumbnail.png`, `QuickLook/Thumbnail.jpg`),
/// and first image frames from CBZ/CBT comic archives.
class DocumentThumbnailService {
  DocumentThumbnailService._();

  static final LinkedHashMap<String, String> _resolvedThumbPaths = LinkedHashMap();
  static final Set<String> _missPaths = <String>{};
  static final Map<String, Future<String?>> _inFlight = {};
  static Directory? _cacheDir;

  static const int _maxMemoryCache = 240;

  static Future<Directory> _ensureCacheDir() async {
    if (_cacheDir != null && _cacheDir!.existsSync()) return _cacheDir!;
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'makaw_doc_thumbs'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  static String? peekCachedPath(String filePath) => _resolvedThumbPaths[filePath];

  static Future<String?> getThumbnailPath(String filePath) {
    final existing = _resolvedThumbPaths[filePath];
    if (existing != null && File(existing).existsSync()) {
      return Future.value(existing);
    }
    if (_missPaths.contains(filePath)) return Future.value(null);
    return _inFlight.putIfAbsent(filePath, () async {
      try {
        final cacheDir = await _ensureCacheDir();
        final outPath = p.join(cacheDir.path, '${filePath.hashCode.toUnsigned(32)}.img');
        final outFile = File(outPath);
        if (outFile.existsSync() && outFile.lengthSync() > 0) {
          _rememberHit(filePath, outPath);
          return outPath;
        }
        final ext = p.extension(filePath).replaceAll('.', '').toLowerCase();
        final bytes = await compute(_extractCoverIsolate, {'path': filePath, 'ext': ext});
        if (bytes != null && bytes.isNotEmpty) {
          await outFile.writeAsBytes(bytes, flush: false);
          _rememberHit(filePath, outPath);
          return outPath;
        }
        _missPaths.add(filePath);
        return null;
      } catch (_) {
        _missPaths.add(filePath);
        return null;
      } finally {
        _inFlight.remove(filePath);
      }
    });
  }

  static void _rememberHit(String sourcePath, String thumbPath) {
    if (_resolvedThumbPaths.length >= _maxMemoryCache) {
      _resolvedThumbPaths.remove(_resolvedThumbPaths.keys.first);
    }
    _resolvedThumbPaths[sourcePath] = thumbPath;
  }

  static Uint8List? _extractCoverIsolate(Map<String, String> args) {
    final path = args['path']!;
    final ext = args['ext'] ?? '';
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      // Guard memory: skip huge > 90MB archives when generating card thumbnails.
      final len = file.lengthSync();
      if (len <= 0 || len > 90 * 1024 * 1024) return null;

      if (ext == 'cbt' || ext == 'tar') {
        final archive = TarDecoder().decodeBytes(file.readAsBytesSync());
        return _firstImageFromArchive(archive);
      }
      if (const {
        'cbz', 'epub', 'docx', 'docm', 'dotx', 'dotm', 'pptx', 'pptm', 'ppsx', 'potx',
        'xlsx', 'xlsm', 'odt', 'ott', 'odp', 'otp', 'ods', 'ots', 'odg', 'pages', 'key', 'numbers',
      }.contains(ext)) {
        final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
        if (ext == 'cbz') return _firstImageFromArchive(archive);
        if (ext == 'epub') return _extractEpubCover(archive);
        return _extractOfficeThumbnail(archive);
      }
    } catch (_) {}
    return null;
  }

  static Uint8List? _firstImageFromArchive(Archive archive) {
    final images = archive.files
        .where((f) =>
            f.isFile &&
            !f.name.contains('__MACOSX') &&
            RegExp(r'\.(jpe?g|png|webp|gif)$', caseSensitive: false).hasMatch(f.name))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (images.isEmpty) return null;
    return Uint8List.fromList(images.first.content as List<int>);
  }

  static Uint8List? _extractOfficeThumbnail(Archive archive) {
    const candidates = [
      'docProps/thumbnail.jpeg',
      'docProps/thumbnail.jpg',
      'docProps/thumbnail.png',
      'Thumbnails/thumbnail.png',
      'QuickLook/Thumbnail.jpg',
      'preview.jpg',
    ];
    for (final c in candidates) {
      final hit = archive.files.where((f) => f.isFile && f.name.toLowerCase() == c.toLowerCase()).firstOrNull;
      if (hit != null) return Uint8List.fromList(hit.content as List<int>);
    }
    return null;
  }

  static Uint8List? _extractEpubCover(Archive archive) {
    // Try explicit cover manifest item from container.xml -> .opf
    try {
      final container = archive.findFile('META-INF/container.xml');
      if (container != null) {
        final doc = XmlDocument.parse(String.fromCharCodes(container.content as List<int>));
        final opfPath = doc
            .findAllElements('rootfile')
            .map((e) => e.getAttribute('full-path'))
            .whereType<String>()
            .firstOrNull;
        if (opfPath != null) {
          final opfFile = archive.findFile(opfPath);
          if (opfFile != null) {
            final opfDoc = XmlDocument.parse(String.fromCharCodes(opfFile.content as List<int>));
            final metaCoverId = opfDoc
                .findAllElements('meta')
                .where((m) => m.getAttribute('name') == 'cover')
                .map((m) => m.getAttribute('content'))
                .whereType<String>()
                .firstOrNull;
            final items = opfDoc.findAllElements('item');
            final coverHref = items
                .where((i) =>
                    (metaCoverId != null && i.getAttribute('id') == metaCoverId) ||
                    (i.getAttribute('properties')?.contains('cover-image') ?? false))
                .map((i) => i.getAttribute('href'))
                .whereType<String>()
                .firstOrNull;
            if (coverHref != null) {
              final dir = p.posix.dirname(opfPath);
              final resolved = dir == '.' ? coverHref : p.posix.normalize('$dir/$coverHref');
              final hit = archive.findFile(resolved) ??
                  archive.files.where((f) => f.isFile && f.name.endsWith(coverHref)).firstOrNull;
              if (hit != null) return Uint8List.fromList(hit.content as List<int>);
            }
          }
        }
      }
    } catch (_) {}
    // Heuristic fallback: image named *cover*
    final coverFile = archive.files
        .where((f) =>
            f.isFile &&
            f.name.toLowerCase().contains('cover') &&
            RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(f.name))
        .firstOrNull;
    if (coverFile != null) return Uint8List.fromList(coverFile.content as List<int>);
    return _firstImageFromArchive(archive);
  }
}
