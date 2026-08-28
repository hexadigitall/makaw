import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String releaseNotes;
  final bool mandatory;

  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
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

  /// GitHub's unauthenticated API is rate-limited (60 req/hr/IP). These
  /// endpoints are NOT part of that API quota, so we fall back to them when
  /// the API is unavailable/rate-limited so update delivery is never silently
  /// blocked.
  String get _atomUrl =>
      'https://github.com/$repoOwner/$repoName/releases.atom';

  Future<PackageInfo> get packageInfo async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!;
  }

  Future<UpdateCheckResponse> checkForUpdate() async {
    final info = await packageInfo;
    final currentVersion = info.version;
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;

    // 1. Primary: GitHub API (gives full asset list + release notes).
    final apiResult = await _checkViaApi(currentVersion, currentBuild);
    if (apiResult.result != UpdateCheckResult.error) {
      return apiResult;
    }

    // 2. Fallback: parse the Atom feed (no API quota) for the latest tag,
    //    then build the APK download URL deterministically.
    final fallback = await _checkViaAtom(currentVersion, currentBuild);
    return fallback;
  }

  Future<UpdateCheckResponse> _checkViaApi(
    String currentVersion,
    int currentBuild,
  ) async {
    try {
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

  Future<UpdateCheckResponse> _checkViaAtom(
    String currentVersion,
    int currentBuild,
  ) async {
    try {
      final response = await _dio.get(
        _atomUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 15),
          followRedirects: true,
        ),
      );
      if (response.statusCode != 200) {
        return UpdateCheckResponse(
          result: UpdateCheckResult.error,
          error: 'Atom HTTP ${response.statusCode}',
        );
      }

      final html = response.data;
      final xml = html is String ? html : html.toString();
      final tag = _latestTagFromAtom(xml);
      if (tag == null) {
        return UpdateCheckResponse(
          result: UpdateCheckResult.error,
          error: 'No tag in atom feed',
        );
      }

      final remoteVersion = tag.replaceFirst(RegExp(r'^v'), '');
      final remoteParts = remoteVersion.split('.');
      final remoteBuild = remoteParts.length >= 3
          ? (int.tryParse(remoteParts[2]) ?? 0)
          : 0;

      if (remoteBuild <= currentBuild) {
        return UpdateCheckResponse(result: UpdateCheckResult.upToDate);
      }

      // Deterministic asset URL — the release APK names are fixed.
      final apkUrl =
          'https://github.com/$repoOwner/$repoName/releases/download/$tag/app-arm64-v8a-release.apk';

      return UpdateCheckResponse(
        result: UpdateCheckResult.available,
        info: UpdateInfo(
          versionCode: remoteBuild,
          versionName: remoteVersion,
          apkUrl: apkUrl,
          releaseNotes: 'Makaw v$remoteVersion is available.',
        ),
      );
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

  /// Extracts the most recent release tag from a GitHub Atom feed.
  String? _latestTagFromAtom(String xml) {
    // Example entry title: "Release Makaw v1.0.45" or the link contains the tag.
    final linkMatch =
        RegExp(r'<entry>[\s\S]*?<link[^>]*href="[^"]*/releases/tag/([^"]+)"')
            .firstMatch(xml);
    if (linkMatch != null) {
      return linkMatch.group(1)?.split('?').first;
    }
    final titleMatch = RegExp(r'Makaw\s+v?(\d+\.\d+\.\d+)').firstMatch(xml);
    if (titleMatch != null) {
      return 'v${titleMatch.group(1)}';
    }
    return null;
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

    String? apkUrl;
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith('.apk') &&
          (name.contains('arm64') || name.contains('universal'))) {
        apkUrl = asset['browser_download_url'] as String?;
        if (name.contains('arm64')) break;
      }
    }

    if (apkUrl == null && assets.isNotEmpty) {
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
    }

    if (apkUrl == null) {
      return UpdateCheckResponse(
        result: UpdateCheckResult.error,
        error: 'No APK found in release',
      );
    }

    return UpdateCheckResponse(
      result: UpdateCheckResult.available,
      info: UpdateInfo(
        versionCode: remoteBuild > 0 ? remoteBuild : currentBuild + 1,
        versionName: remoteVersion.isNotEmpty ? remoteVersion : currentVersion,
        apkUrl: apkUrl,
        releaseNotes: body,
      ),
    );
  }

  Future<String?> downloadApk(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory(p.join(dir.path, 'makaw_updates'));
      await downloadDir.create(recursive: true);

      final filename = 'makaw-${info.versionName}.apk';
      final savePath = p.join(downloadDir.path, filename);

      final existing = File(savePath);
      if (await existing.exists()) {
        await existing.delete();
      }

      await _dio.download(
        info.apkUrl,
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
      debugPrint('Download APK error: $e');
      return null;
    }
  }

  Future<bool> installApk(String path) async {
    try {
      final result = await OpenFilex.open(path);
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('Install APK error: $e');
      return false;
    }
  }

  Future<void> cleanOldApks() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory(p.join(dir.path, 'makaw_updates'));
      if (await downloadDir.exists()) {
        final files = await downloadDir.list().toList();
        for (final f in files) {
          if (f is File && f.path.endsWith('.apk')) {
            await f.delete();
          }
        }
      }
    } catch (_) {}
  }
}
