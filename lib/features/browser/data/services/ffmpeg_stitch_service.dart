import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../../../core/platform/session_paths.dart';

class FfmpegStitchService {
  /// Stitch a list of segment URLs (HLS `.ts` / DASH `.m4s`) into a single
  /// `.mp4` file using `ffmpeg -f concat -c copy`.
  ///
  /// Returns the path to the stitched output file, or `null` on failure.
  Future<String?> stitch({
    required List<String> segmentUrls,
    required String outputFilename,
  }) async {
    if (segmentUrls.isEmpty) return null;

    final tmpDir = await getTemporaryDirectory();
    final stitchDir = Directory(
      '${tmpDir.path}${Platform.pathSeparator}makaw_stitch_${DateTime.now().millisecondsSinceEpoch}',
    );
    await stitchDir.create(recursive: true);

    try {
      // Download all segments to numbered files.
      final concatLines = <String>[];
      final client = http.Client();
      try {
        for (var i = 0; i < segmentUrls.length; i++) {
          final url = segmentUrls[i];
          final ext = _guessExt(url);
          final fileName =
              'seg_${i.toString().padLeft(6, '0')}$ext';
          final filePath =
              '${stitchDir.path}${Platform.pathSeparator}$fileName';
          final resp = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 30));
          if (resp.statusCode != 200) return null;
          await File(filePath).writeAsBytes(resp.bodyBytes);
          concatLines.add("file '$filePath'");
        }
      } finally {
        client.close();
      }

      // Write concat list file.
      final listFile = File(
        '${stitchDir.path}${Platform.pathSeparator}concat.txt',
      );
      await listFile.writeAsString(concatLines.join('\n'));

      // Determine output path.
      final outDir = await SessionPaths.downloadsDir();
      final outputPath = '$outDir${Platform.pathSeparator}$outputFilename';

      // Run ffmpeg concat.
      final command =
          "-f concat -safe 0 -i '${listFile.path}' -c copy '$outputPath'";
      final session = await FFmpegKit.execute(command);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) {
        return outputPath;
      }
      return null;
    } finally {
      // Clean up temp directory.
      try {
        await stitchDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  String _guessExt(String url) {
    final path = Uri.parse(url).path;
    final lastDot = path.lastIndexOf('.');
    if (lastDot >= 0 && lastDot < path.length - 1) {
      final ext = path.substring(lastDot);
      if (ext.length <= 5) return ext;
    }
    return '.ts';
  }
}
