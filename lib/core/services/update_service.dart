import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String downloadUrl;
  final String fileName;
  final String platformLabel;
  final String releaseNotes;
  final bool mandatory;

  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    required this.fileName,
    required this.platformLabel,
    this.releaseNotes = '',
    this.mandatory = false,
  });
}

enum UpdateCheckResult { upToDate, available, error }

class UpdateCheckResponse {
  final UpdateCheckResult result;
  final UpdateInfo? info;
  final String? error;

  UpdateCheckResponse({required this.result, this.info, this.error});
}

class UpdateService {
  final String repoOwner;
  final String repoName;
  final Dio _dio;
  PackageInfo? _packageInfo;

  UpdateService({
    required this.repoOwner,
    required this.repoName,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  String get _apiUrl =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  String get _releasePageUrl =>
      'https://github.com/$repoOwner/$repoName/releases/latest';

  Future<PackageInfo> get packageInfo async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!;
  }

  Future<UpdateCheckResponse> checkForUpdate() async {
    try {
      final info = await packageInfo;
      final currentVersion = info.version;
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final response = await _dio.get(
        _apiUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
          headers: {
            'Cache-Control': 'no-cache',
            'Accept': 'application/vnd.github+json',
          },
        ),
      );

      if (response.statusCode != 200) {
        return UpdateCheckResponse(
          result: UpdateCheckResult.error,
          error: 'HTTP ${response.statusCode}',
        );
      }

      final data = response.data as Map<String, dynamic>;
      return _parseGitHubRelease(data, currentVersion, currentBuild);
    } on DioException catch (e) {
      return UpdateCheckResponse(
        result: UpdateCheckResult.error,
        error: e.message ?? 'Network error',
      );
    } catch (e) {
      return UpdateCheckResponse(
        result: UpdateCheckResult.error,
        error: e.toString(),
      );
    }
  }

  UpdateCheckResponse _parseGitHubRelease(
    Map<String, dynamic> data,
    String currentVersion,
    int currentBuild,
  ) {
    final tagName = data['tag_name'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final assets = data['assets'] as List<dynamic>? ?? [];

    final remoteVersion = tagName.replaceFirst(RegExp(r'^v'), '');
    final remoteParts = remoteVersion.split('.');
    final remoteBuild = remoteParts.length >= 3
        ? (int.tryParse(remoteParts[2]) ?? 0)
        : 0;

    if (remoteBuild <= currentBuild) {
      return UpdateCheckResponse(result: UpdateCheckResult.upToDate);
    }

    final asset = _findPlatformAsset(assets);
    if (asset == null) {
      return UpdateCheckResponse(
        result: UpdateCheckResult.error,
        error: 'No compatible file found in release for ${_platformName}',
      );
    }

    return UpdateCheckResponse(
      result: UpdateCheckResult.available,
      info: UpdateInfo(
        versionCode: remoteBuild > 0 ? remoteBuild : currentBuild + 1,
        versionName: remoteVersion.isNotEmpty ? remoteVersion : currentVersion,
        downloadUrl: asset['browser_download_url'] as String,
        fileName: asset['name'] as String,
        platformLabel: _platformName,
        releaseNotes: body,
      ),
    );
  }

  Map<String, dynamic>? _findPlatformAsset(List<dynamic> assets) {
    if (Platform.isAndroid) {
      return _findAndroidAsset(assets);
    } else if (Platform.isWindows) {
      return _findWindowsAsset(assets);
    } else if (Platform.isLinux) {
      return _findLinuxAsset(assets);
    } else if (Platform.isMacOS) {
      return _findMacAsset(assets);
    }
    return null;
  }

  Map<String, dynamic>? _findAndroidAsset(List<dynamic> assets) {
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith('.apk') && name.contains('arm64')) return asset;
    }
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith('.apk') && name.contains('universal')) return asset;
    }
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith('.apk')) return asset;
    }
    return null;
  }

  Map<String, dynamic>? _findWindowsAsset(List<dynamic> assets) {
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.contains('windows') && name.endsWith('.zip')) return asset;
    }
    return null;
  }

  Map<String, dynamic>? _findLinuxAsset(List<dynamic> assets) {
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.contains('linux') && name.endsWith('.tar.gz')) return asset;
    }
    return null;
  }

  Map<String, dynamic>? _findMacAsset(List<dynamic> assets) {
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.contains('macos') && name.endsWith('.zip')) return asset;
    }
    return null;
  }

  String get _platformName {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return 'Unknown';
  }

  String get _fileExtension {
    if (Platform.isAndroid) return '.apk';
    if (Platform.isWindows) return '.zip';
    if (Platform.isLinux) return '.tar.gz';
    if (Platform.isMacOS) return '.zip';
    return '';
  }

  Future<String?> downloadUpdate(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory(p.join(dir.path, 'makaw_updates'));
      await downloadDir.create(recursive: true);

      final filename = 'makaw-${info.versionName}${_fileExtension}';
      final savePath = p.join(downloadDir.path, filename);

      final existing = File(savePath);
      if (await existing.exists()) {
        await existing.delete();
      }

      await _dio.download(
        info.downloadUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 300),
        ),
      );

      return savePath;
    } catch (e) {
      debugPrint('Download update error: $e');
      return null;
    }
  }

  Future<bool> openUpdateFile(String path) async {
    try {
      if (Platform.isAndroid) {
        final result = await OpenFilex.open(path);
        return result.type == ResultType.done;
      } else {
        return await openReleasePage();
      }
    } catch (e) {
      debugPrint('Open update error: $e');
      return false;
    }
  }

  Future<bool> openReleasePage() async {
    try {
      final uri = Uri.parse(_releasePageUrl);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Open release page error: $e');
      return false;
    }
  }

  String get updateActionLabel {
    if (Platform.isAndroid) return 'Install';
    return 'Open Release Page';
  }

  String get updateActionHint {
    if (Platform.isAndroid) return '';
    return 'The file will be downloaded, then the release page will open for instructions.';
  }

  Future<void> cleanOldDownloads() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory(p.join(dir.path, 'makaw_updates'));
      if (await downloadDir.exists()) {
        final files = await downloadDir.list().toList();
        for (final f in files) {
          if (f is File) {
            await f.delete();
          }
        }
      }
    } catch (_) {}
  }
}
