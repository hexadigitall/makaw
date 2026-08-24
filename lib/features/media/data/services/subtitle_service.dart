import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class SubtitleResult {
  final String id;
  final String fileName;
  final String language;
  final int fileId;
  final double rating;

  SubtitleResult({
    required this.id,
    required this.fileName,
    required this.language,
    required this.fileId,
    required this.rating,
  });
}

class MakawSubtitleService {
  static const String _baseUrl = "https://api.opensubtitles.com/api/v1";
  static const String _apiKey = "YOUR_OPENSUBTITLES_API_KEY";

  static Future<List<SubtitleResult>> searchSubtitles(String query, {String language = 'en'}) async {
    final cleanQuery = query
        .replaceAll(RegExp(r'\.(mp4|mkv|avi|webm)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[._]'), ' ')
        .trim();

    final uri = Uri.parse("$_baseUrl/subtitles?query=${Uri.encodeComponent(cleanQuery)}&languages=$language");
    final response = await http.get(uri, headers: {
      "Api-Key": _apiKey,
      "User-Agent": "MakawApp v1.0.0",
    });

    if (response.statusCode != 200) return [];

    final Map<String, dynamic> json = jsonDecode(response.body);
    final List<dynamic> data = json['data'] ?? [];

    return data.map((item) {
      final attr = item['attributes'];
      final files = attr['files'] as List<dynamic>;
      final fileId = files.isNotEmpty ? files.first['file_id'] as int : 0;

      return SubtitleResult(
        id: item['id'] as String,
        fileName: (attr['release'] ?? cleanQuery) as String,
        language: (attr['language'] ?? language) as String,
        fileId: fileId,
        rating: (attr['ratings'] as num?)?.toDouble() ?? 0.0,
      );
    }).where((sub) => sub.fileId != 0).toList();
  }

  static Future<File?> downloadSubtitle(int fileId, String targetVideoPath) async {
    final downloadUri = Uri.parse("$_baseUrl/download");
    final response = await http.post(
      downloadUri,
      headers: {
        "Api-Key": _apiKey,
        "User-Agent": "MakawApp v1.0.0",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"file_id": fileId}),
    );

    if (response.statusCode != 200) return null;

    final downloadData = jsonDecode(response.body);
    final link = downloadData['link'] as String?;
    if (link == null) return null;

    final srtResponse = await http.get(Uri.parse(link));
    if (srtResponse.statusCode != 200) return null;

    final srtPath = targetVideoPath.substring(0, targetVideoPath.lastIndexOf('.')) + '.srt';
    final srtFile = File(srtPath);
    await srtFile.writeAsBytes(srtResponse.bodyBytes, flush: true);
    return srtFile;
  }
}
