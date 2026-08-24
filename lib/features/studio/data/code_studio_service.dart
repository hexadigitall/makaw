import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class StudioProject {
  final String name;
  final Directory directory;
  final DateTime lastModified;

  StudioProject({required this.name, required this.directory, required this.lastModified});
}

class CodeStudioService {
  static Future<Directory> get rootWorkspacesDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/MakawProjects');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<StudioProject> createProject(String projectName, String template) async {
    final root = await rootWorkspacesDir;
    final projectDir = Directory('${root.path}/$projectName');
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    if (template == 'dart') {
      await File('${projectDir.path}/main.dart').writeAsString(
        'void main() {\n  print("Hello from Makaw Studio!");\n}\n',
      );
    } else if (template == 'python') {
      await File('${projectDir.path}/main.py').writeAsString(
        '# Python Project in Makaw\nprint("Hello from Makaw!")\n',
      );
    } else if (template == 'web') {
      await File('${projectDir.path}/index.html').writeAsString(
        '<!DOCTYPE html>\n<html>\n<head><title>$projectName</title></head>\n<body>\n  <h1>Hello Makaw Web</h1>\n</body>\n</html>\n',
      );
      await File('${projectDir.path}/style.css').writeAsString('body { font-family: sans-serif; padding: 20px; }');
      await File('${projectDir.path}/app.js').writeAsString('console.log("App initialized");');
    } else {
      await File('${projectDir.path}/script.js').writeAsString('console.log("Hello from Makaw!");\n');
    }

    return StudioProject(name: projectName, directory: projectDir, lastModified: DateTime.now());
  }

  static Future<List<StudioProject>> getProjects() async {
    final root = await rootWorkspacesDir;
    final List<StudioProject> list = [];
    if (await root.exists()) {
      for (var entity in root.listSync()) {
        if (entity is Directory) {
          list.add(StudioProject(
            name: entity.path.split(Platform.pathSeparator).last,
            directory: entity,
            lastModified: entity.statSync().modified,
          ));
        }
      }
    }
    list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return list;
  }

  static Future<void> deleteProject(Directory projectDir) async {
    if (await projectDir.exists()) {
      await projectDir.delete(recursive: true);
    }
  }

  static Future<File> createFile(Directory parent, String name, {String content = ''}) async {
    final file = File('${parent.path}/$name');
    if (!await file.exists()) {
      await file.writeAsString(content, flush: true);
    }
    return file;
  }

  static Future<Directory> createFolder(Directory parent, String name) async {
    final dir = Directory('${parent.path}/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> deleteEntity(FileSystemEntity entity) async {
    if (await entity.exists()) {
      await entity.delete(recursive: true);
    }
  }

  static Future<ProcessResult> executeCode(File file) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      return ProcessResult(0, 0, '', 'Code execution is not supported on mobile/web platforms.\nUse Windows, macOS, or Linux.');
    }
    final path = file.path;
    if (path.endsWith('.py')) return await Process.run('python', [path]);
    if (path.endsWith('.js')) return await Process.run('node', [path]);
    if (path.endsWith('.dart')) return await Process.run('dart', ['run', path]);
    if (path.endsWith('.sh')) return await Process.run('sh', [path]);
    throw UnsupportedError('No execution runner for ${p.basename(path)}');
  }
}
