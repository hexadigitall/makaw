import 'dart:io';

/// File / folder CRUD helpers for the Code Studio IDE.
///
/// All paths are resolved relative to a project root [root]. This keeps the
/// explorer operations contained to a single project directory.
class CodeStudioService {
  CodeStudioService._();

  /// Resolves [relativePath] against [root] and returns a normalized [File].
  static File fileIn(Directory root, String relativePath) {
    final base = root.path.endsWith(Platform.pathSeparator) ? root.path : '${root.path}${Platform.pathSeparator}';
    final safe = relativePath.replaceAll('\\', Platform.pathSeparator).replaceAll('/', Platform.pathSeparator);
    return File('$base$safe');
  }

  /// Resolves [relativePath] against [root] and returns a normalized [Directory].
  static Directory dirIn(Directory root, String relativePath) {
    final base = root.path.endsWith(Platform.pathSeparator) ? root.path : '${root.path}${Platform.pathSeparator}';
    final safe = relativePath.replaceAll('\\', Platform.pathSeparator).replaceAll('/', Platform.pathSeparator);
    return Directory('$base$safe');
  }

  /// Creates a file at [relativePath] within [root], creating parent folders
  /// as needed. Returns the created [File].
  static Future<File> createFile(Directory root, String relativePath, {String content = ''}) async {
    final file = fileIn(root, relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    return file;
  }

  /// Creates a folder (and any parents) at [relativePath] within [root].
  /// Returns the created [Directory].
  static Future<Directory> createFolder(Directory root, String relativePath, {bool recursive = true}) async {
    final dir = dirIn(root, relativePath);
    await dir.create(recursive: recursive);
    return dir;
  }

  /// Deletes a file or folder. Folders are removed recursively.
  static Future<void> deleteEntity(FileSystemEntity entity) async {
    if (entity is Directory) {
      if (await entity.exists()) await entity.delete(recursive: true);
    } else if (entity is File) {
      if (await entity.exists()) await entity.delete();
    }
  }

  /// Deletes the file at [relativePath] within [root].
  static Future<void> deleteFile(Directory root, String relativePath) =>
      deleteEntity(fileIn(root, relativePath));

  /// Lists all files under [root], recursively.
  static List<File> listFiles(Directory root) {
    if (!root.existsSync()) return [];
    return root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.contains('${Platform.pathSeparator}.git${Platform.pathSeparator}'))
        .toList();
  }

  /// Relative path of [file] from [root], using forward slashes.
  static String relativePath(Directory root, File file) {
    final rp = root.path;
    final fp = file.path;
    var rel = fp;
    if (rp.endsWith(Platform.pathSeparator)) {
      rel = fp.startsWith(rp) ? fp.substring(rp.length) : fp;
    } else if (fp.startsWith(rp + Platform.pathSeparator)) {
      rel = fp.substring(rp.length + 1);
    }
    return rel.replaceAll(Platform.pathSeparator, '/');
  }

  /// Basename (file name) of a full file path.
  static String baseName(String path) =>
      path.split(Platform.pathSeparator).last;

  /// The directory portion of a relative path ('' for root children).
  static String parentRelative(Directory root, File file) {
    final rel = relativePath(root, file);
    final idx = rel.lastIndexOf('/');
    return idx < 0 ? '' : rel.substring(0, idx);
  }
}
