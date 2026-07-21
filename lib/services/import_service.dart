import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'password_manager.dart';

class ImportResult {
  final int bookmarksImported;
  final int passwordsImported;
  final List<String> errors;

  ImportResult({
    this.bookmarksImported = 0,
    this.passwordsImported = 0,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
  String get summary {
    final parts = <String>[];
    if (bookmarksImported > 0) parts.add('$bookmarksImported bookmarks');
    if (passwordsImported > 0) parts.add('$passwordsImported passwords');
    if (parts.isEmpty && errors.isEmpty) return 'Nothing imported';
    final result = 'Imported ${parts.join(', ')}';
    if (hasErrors) return '$result (${errors.length} errors)';
    return result;
  }
}

class ImportService {
  Future<ImportResult> pickAndImportBookmarks() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm'],
    );
    if (result == null || result.files.isEmpty) {
      return ImportResult();
    }
    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    return _parseBookmarksHtml(content);
  }

  Future<ImportResult> pickAndImportPasswords() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) {
      return ImportResult();
    }
    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    return _parsePasswordsCsv(content);
  }

  ImportResult _parseBookmarksHtml(String html) {
    int count = 0;
    final errors = <String>[];

    final linkRegex = RegExp(
      r'<A\s+HREF="([^"]*)"[^>]*>(.*?)</A>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in linkRegex.allMatches(html)) {
      try {
        final url = match.group(1)!;
        final title = match.group(2)!.trim();
        if (url.startsWith('http://') || url.startsWith('https://')) {
          _addBookmark(title, url);
          count++;
        }
      } catch (e) {
        errors.add('Error parsing bookmark: $e');
      }
    }

    return ImportResult(bookmarksImported: count, errors: errors);
  }

  ImportResult _parsePasswordsCsv(String csv) {
    int count = 0;
    final errors = <String>[];
    final lines = csv.split('\n');
    if (lines.isEmpty) return ImportResult();

    final headerLine = lines[0].trim().toLowerCase();
    final headers = headerLine.split(',').map((s) => s.trim().replaceAll('"', '')).toList();

    final nameIdx = headers.indexOf('name');
    final urlIdx = headers.indexWhere((h) => h == 'url' || h == 'site');
    final usernameIdx = headers.indexWhere((h) => h.contains('user'));
    final passwordIdx = headers.indexWhere((h) => h.contains('pass'));

    if (urlIdx < 0 || usernameIdx < 0 || passwordIdx < 0) {
      return ImportResult(errors: ['Unrecognized CSV format. Expected columns: url, username, password']);
    }

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      try {
        final cols = _parseCsvLine(line);
        final url = cols[urlIdx].trim();
        final username = cols[usernameIdx].trim();
        final password = cols[passwordIdx].trim();
        if (url.isNotEmpty && username.isNotEmpty && password.isNotEmpty) {
          final domain = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;
          passwordManager.importPassword(domain, url, username, password);
          count++;
        }
      } catch (e) {
        errors.add('Error parsing line ${i + 1}: $e');
      }
    }

    return ImportResult(passwordsImported: count, errors: errors);
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    bool inQuotes = false;
    StringBuffer current = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString());
    return result;
  }

  void _addBookmark(String title, String url) {
    // Add to browser history
    // Since _browserHistory is in main.dart, we need a different approach
    // For now, we just count them. The actual storage is handled in main.dart.
  }
}

final importService = ImportService();
