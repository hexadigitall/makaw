import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

enum DownloadState { queued, downloading, paused, completed, failed }

class DownloadItem {
  final String id;
  final String url;
  final String filename;
  DownloadState state;
  double progress;
  int receivedBytes;
  int totalBytes;
  String? savePath;
  String? error;
  DateTime createdAt;
  DateTime? completedAt;
  CancelToken? cancelToken;
  StreamSubscription? subscription;
  double speed;
  int _lastBytes;
  DateTime _lastTime;

  DownloadItem({
    required this.id,
    required this.url,
    required this.filename,
    this.state = DownloadState.queued,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.savePath,
    this.error,
    DateTime? createdAt,
    this.completedAt,
    this.speed = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        _lastBytes = 0,
        _lastTime = DateTime.now();

  String get sizeStr {
    if (totalBytes <= 0) return '--';
    return _formatBytes(totalBytes);
  }

  String get receivedStr => _formatBytes(receivedBytes);

  String get speedStr => _formatBytes(speed.round()) + '/s';

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'url': url, 'filename': filename, 'state': state.name,
    'progress': progress, 'receivedBytes': receivedBytes, 'totalBytes': totalBytes,
    'savePath': savePath, 'error': error, 'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  void updateSpeed() {
    final now = DateTime.now();
    final dt = now.difference(_lastTime).inMilliseconds / 1000.0;
    if (dt > 0) {
      speed = (receivedBytes - _lastBytes) / dt;
    }
    _lastBytes = receivedBytes;
    _lastTime = now;
  }
}

class DownloadService extends ChangeNotifier {
  final List<DownloadItem> _downloads = [];
  final Dio _dio;
  final String Function() _getDownloadDir;
  final void Function(String message) _showNotification;
  final void Function(DownloadItem item)? onComplete;
  Timer? _speedTimer;
  int _maxParallel = 3;

  DownloadService({
    required Dio dio,
    required String Function() getDownloadDir,
    required void Function(String message) showNotification,
    this.onComplete,
  }) : _dio = dio,
       _getDownloadDir = getDownloadDir,
       _showNotification = showNotification {
    _speedTimer = Timer.periodic(Duration(seconds: 1), (_) {
      bool changed = false;
      for (final d in _downloads.where((d) => d.state == DownloadState.downloading)) {
        d.updateSpeed();
        changed = true;
      }
      if (changed) notifyListeners();
    });
    _loadHistory();
  }

  int get maxParallel => _maxParallel;
  set maxParallel(int v) {
    _maxParallel = v;
    _processQueue();
  }

  List<DownloadItem> get downloads => List.unmodifiable(_downloads);
  List<DownloadItem> get activeDownloads => _downloads.where((d) => d.state == DownloadState.downloading || d.state == DownloadState.queued).toList();
  List<DownloadItem> get completedDownloads => _downloads.where((d) => d.state == DownloadState.completed).toList();
  List<DownloadItem> get failedDownloads => _downloads.where((d) => d.state == DownloadState.failed).toList();

  int get activeCount => activeDownloads.length;
  int get maxSimultaneous => _maxParallel;

  Future<String> _defaultDownloadDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory(p.join(dir.path, 'makaw_downloads'));
    await downloadDir.create(recursive: true);
    return downloadDir.path;
  }

  String _mimeFromUrl(String url) {
    final u = url.toLowerCase();
    final mimeMap = {
      'mp4': 'video/mp4', 'webm': 'video/webm', 'mkv': 'video/x-matroska',
      'avi': 'video/x-msvideo', 'mov': 'video/quicktime', '3gp': 'video/3gpp',
      'ts': 'video/mp2t', 'm3u8': 'application/x-mpegURL',
      'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'ogg': 'audio/ogg',
      'aac': 'audio/aac', 'flac': 'audio/flac', 'wma': 'audio/x-ms-wma',
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'pdf': 'application/pdf',
      'zip': 'application/zip', 'gz': 'application/gzip', '7z': 'application/x-7z-compressed',
      'rar': 'application/vnd.rar', 'tar': 'application/x-tar',
    };
    for (final e in mimeMap.entries) {
      if (u.contains('.${e.key}') || u.contains('${e.key}/')) return e.value;
    }
    return 'application/octet-stream';
  }

  String ensureExtension(String url, String filename) {
    if (filename.contains('.')) return filename;
    final path = Uri.tryParse(url)?.path ?? '';
    final ext = p.extension(path);
    if (ext.isNotEmpty) return filename + ext;
    final mime = _mimeFromUrl(url);
    if (mime.contains('video/mp4')) return '$filename.mp4';
    if (mime.contains('video/webm')) return '$filename.webm';
    if (mime.contains('video/')) return '$filename.mp4';
    if (mime.contains('audio/')) return '$filename.mp3';
    if (mime.contains('image/')) return '$filename.jpg';
    if (mime.contains('pdf')) return '$filename.pdf';
    return '$filename.bin';
  }

  bool _supportsRange(String url) {
    final u = url.toLowerCase();
    return !u.contains('.m3u8') && !u.contains('.ts');
  }

  Future<DownloadItem> enqueue(String url, {String? filename}) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final name = filename ?? url.split('/').last.split('?').first.split('#').first;
    final safeName = ensureExtension(url, Uri.decodeComponent(name));
    final item = DownloadItem(id: id, url: url, filename: safeName);
    _downloads.insert(0, item);
    notifyListeners();
    _saveHistory();
    _processQueue();
    return item;
  }

  void _processQueue() {
    final running = _downloads.where((d) => d.state == DownloadState.downloading).length;
    final queued = _downloads.where((d) => d.state == DownloadState.queued).toList();
    final slots = _maxParallel - running;
    for (int i = 0; i < slots && i < queued.length; i++) {
      startDownload(queued[i]);
    }
  }

  Future<void> startDownload(DownloadItem item, {bool useRange = true}) async {
    if (item.state == DownloadState.downloading) return;
    item.state = DownloadState.downloading;
    item.error = null;
    item.cancelToken = CancelToken();
    notifyListeners();

    final dir = _getDownloadDir();
    final savePath = p.join(dir, item.filename);
    item.savePath = savePath;

    int existingBytes = 0;
    final partialFile = File('$savePath.part');
    if (await partialFile.exists()) {
      existingBytes = await partialFile.length();
    }

    try {
      final headers = <String, dynamic>{};
      if (useRange && _supportsRange(item.url) && existingBytes > 0) {
        headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await _dio.download(
        item.url,
        savePath,
        cancelToken: item.cancelToken,
        onReceiveProgress: (received, total) {
          item.receivedBytes = existingBytes + received;
          item.totalBytes = total > 0 ? existingBytes + total : 0;
          item.progress = item.totalBytes > 0 ? item.receivedBytes / item.totalBytes : 0;
          notifyListeners();
        },
        options: Options(
          followRedirects: true,
          receiveTimeout: Duration(seconds: 120),
          sendTimeout: Duration(seconds: 30),
          headers: headers,
          extra: {'savePath': '$savePath.part'},
        ),
      );
      if (response.statusCode == 200 || response.statusCode == 206) {
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
        item.state = DownloadState.completed;
        item.progress = 1.0;
        item.receivedBytes = item.totalBytes;
        item.completedAt = DateTime.now();
        _showNotification('Downloaded: ${item.filename}');
        onComplete?.call(item);
        notifyListeners();
        _saveHistory();
      } else {
        item.state = DownloadState.failed;
        item.error = 'HTTP ${response.statusCode}';
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        item.state = DownloadState.paused;
        if (existingBytes > 0 || item.receivedBytes > 0) {
          final dlDir = _getDownloadDir();
          final partPath = p.join(dlDir, '${item.filename}.part');
          try {
            await File(savePath).rename(partPath);
          } catch (_) {}
        }
      } else {
        item.state = DownloadState.failed;
        item.error = e.message ?? 'Download failed';
        if (e.response?.statusCode != null) {
          item.error = 'HTTP ${e.response!.statusCode}';
        }
      }
    } catch (e) {
      item.state = DownloadState.failed;
      item.error = e.toString();
    }
    notifyListeners();
    _saveHistory();
    _processQueue();
  }

  void pause(DownloadItem item) {
    if (item.state != DownloadState.downloading) return;
    item.cancelToken?.cancel('Paused by user');
    item.state = DownloadState.paused;
    notifyListeners();
    _saveHistory();
  }

  void resume(DownloadItem item) {
    if (item.state != DownloadState.paused) return;
    item.state = DownloadState.queued;
    notifyListeners();
    _processQueue();
  }

  void cancel(DownloadItem item) {
    item.cancelToken?.cancel('Cancelled by user');
    if (item.savePath != null) {
      File('${item.savePath!}.part').delete().catchError((_) {});
      File(item.savePath!).delete().catchError((_) {});
    }
    item.state = DownloadState.paused;
    item.receivedBytes = 0;
    item.progress = 0;
    notifyListeners();
    _saveHistory();
  }

  void retry(DownloadItem item) {
    if (item.savePath != null) {
      File('${item.savePath!}.part').delete().catchError((_) {});
      File(item.savePath!).delete().catchError((_) {});
    }
    item.state = DownloadState.queued;
    item.progress = 0;
    item.receivedBytes = 0;
    item.totalBytes = 0;
    item.error = null;
    item.savePath = null;
    notifyListeners();
    _processQueue();
  }

  void remove(DownloadItem item) {
    cancel(item);
    _downloads.remove(item);
    notifyListeners();
    _saveHistory();
  }

  void clearCompleted() {
    _downloads.removeWhere((d) => d.state == DownloadState.completed);
    notifyListeners();
    _saveHistory();
  }

  void retryAllFailed() {
    for (final d in _downloads.where((d) => d.state == DownloadState.failed)) {
      retry(d);
    }
  }

  void dispose() {
    _speedTimer?.cancel();
    for (final d in _downloads.where((d) => d.state == DownloadState.downloading)) {
      d.cancelToken?.cancel('Disposed');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'makaw_downloads.json'));
      final data = _downloads.map((d) => d.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'makaw_downloads.json'));
      if (!file.existsSync()) return;
      final data = jsonDecode(await file.readAsString()) as List;
      for (final d in data) {
        final item = DownloadItem(
          id: d['id'], url: d['url'], filename: d['filename'],
          state: d['state'] == 'completed' ? DownloadState.completed : DownloadState.paused,
          progress: (d['progress'] as num).toDouble(),
          receivedBytes: d['receivedBytes'], totalBytes: d['totalBytes'],
          savePath: d['savePath'], error: d['error'],
          createdAt: DateTime.parse(d['createdAt']),
          completedAt: d['completedAt'] != null ? DateTime.parse(d['completedAt']) : null,
        );
        _downloads.add(item);
      }
    } catch (_) {}
  }
}
