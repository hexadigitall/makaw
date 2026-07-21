import 'dart:convert';
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

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    versionCode: json['versionCode'] as int,
    versionName: json['versionName'] as String? ?? '1.0.0',
    apkUrl: json['apkUrl'] as String,
    releaseNotes: json['releaseNotes'] as String? ?? '',
    mandatory: json['mandatory'] as bool? ?? false,
  );
}

enum UpdateCheckResult { upToDate, available, error }

class UpdateCheckResponse {
  final UpdateCheckResult result;
  final UpdateInfo? info;
  final String? error;

  UpdateCheckResponse({required this.result, this.info, this.error});
}

class UpdateService {
  final String updateUrl;
  final Dio _dio;
  PackageInfo? _packageInfo;

  UpdateService({required this.updateUrl, Dio? dio})
      : _dio = dio ?? Dio();

  Future<PackageInfo> get packageInfo async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!;
  }

  Future<UpdateCheckResponse> checkForUpdate() async {
    try {
      final info = await packageInfo;
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final response = await _dio.get(
        updateUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
          headers: {'Cache-Control': 'no-cache'},
        ),
      );

      if (response.statusCode != 200) {
        return UpdateCheckResponse(
          result: UpdateCheckResult.error,
          error: 'HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.data.toString());
      final remote = UpdateInfo.fromJson(data);

      if (remote.versionCode > currentBuild) {
        return UpdateCheckResponse(
          result: UpdateCheckResult.available,
          info: remote,
        );
      }

      return UpdateCheckResponse(result: UpdateCheckResult.upToDate);
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

      // Remove any partial download
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
          receiveTimeout: const Duration(seconds: 120),
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
      // Fallback: try am start intent
      try {
        await Process.run('am', [
          'start',
          '-t', 'application/vnd.android.package-archive',
          '-d', path,
        ]);
        return true;
      } catch (_) {
        return false;
      }
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
