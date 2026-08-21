import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CodeStudioProject {
  final String name;
  final Directory rootDir;
  final List<File> files;
  CodeStudioProject({required this.name, required this.rootDir, required this.files});
}

class CodeStudioService {
  static Future<Directory> get _baseProjectsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'MakawProjects'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static const Map<String, (String fileName, String starterCode)> _templates = {
    'javascript': ('main.js', '// JavaScript in Makaw Code Studio\nconsole.log("Hello from Makaw!");\n'),
    'python': ('main.py', '# Python in Makaw Code Studio\nprint("Hello from Makaw!")\n'),
    'dart': ('main.dart', 'void main() {\n  print("Hello from Makaw!");\n}\n'),
    'html': ('index.html', '<!DOCTYPE html>\n<html>\n<body>\n  <h1>Hello Makaw</h1>\n</body>\n</html>\n'),
    'css': ('style.css', '/* Makaw CSS */\nbody {\n  background: #0f172a;\n  color: #e2e8f0;\n}\n'),
    'typescript': ('main.ts', '// TypeScript in Makaw Code Studio\nconst greeting: string = "Hello from Makaw!";\nconsole.log(greeting);\n'),
  };

  static Future<CodeStudioProject> createProject(String projectName, String template) async {
    final base = await _baseProjectsDir;
    final projectDir = Directory(p.join(base.path, projectName));
    if (!await projectDir.exists()) await projectDir.create(recursive: true);

    final (fileName, starterCode) = _templates[template] ?? _templates['javascript']!;
    final file = File(p.join(projectDir.path, fileName));
    await file.writeAsString(starterCode, flush: true);

    return CodeStudioProject(name: projectName, rootDir: projectDir, files: [file]);
  }

  static Future<List<CodeStudioProject>> listProjects() async {
    final base = await _baseProjectsDir;
    final projects = <CodeStudioProject>[];
    if (!await base.exists()) return projects;
    for (final entry in base.listSync()) {
      if (entry is Directory) {
        final files = entry.listSync().whereType<File>().toList();
        projects.add(CodeStudioProject(
          name: p.basename(entry.path),
          rootDir: entry,
          files: files,
        ));
      }
    }
    return projects;
  }

  static Future<void> deleteProject(String projectName) async {
    final base = await _baseProjectsDir;
    final dir = Directory(p.join(base.path, projectName));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<File> createFile(Directory projectDir, String fileName) async {
    final file = File(p.join(projectDir.path, fileName));
    if (!await file.exists()) await file.writeAsString('', flush: true);
    return file;
  }

  static Future<void> deleteFile(File file) async {
    if (await file.exists()) await file.delete();
  }

  static String detectLanguage(String filePath) {
    final ext = p.extension(filePath).replaceAll('.', '').toLowerCase();
    const map = {
      'dart': 'dart', 'py': 'python', 'js': 'javascript', 'ts': 'typescript',
      'html': 'html', 'htm': 'html', 'css': 'css', 'json': 'json',
      'yaml': 'yaml', 'yml': 'yaml', 'xml': 'xml', 'sh': 'shell',
      'md': 'markdown', 'txt': 'plaintext',
    };
    return map[ext] ?? 'plaintext';
  }

  static Future<ProcessResult> executeCode(File file) async {
    final path = file.path;
    if (path.endsWith('.py')) return await Process.run('python', [path]);
    if (path.endsWith('.js')) return await Process.run('node', [path]);
    if (path.endsWith('.dart')) return await Process.run('dart', ['run', path]);
    if (path.endsWith('.sh')) return await Process.run('sh', [path]);
    throw UnsupportedError('No execution runner for ${p.basename(path)}');
  }
}
