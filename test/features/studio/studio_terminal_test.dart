import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/features/studio/data/studio_project.dart';
import 'package:makaw/features/studio/data/terminal_engine.dart';

void main() {
  group('StudioProject', () {
    test('extracts project name and path from directory', () {
      final dir = Directory('D:/projects/makaw');
      final project = StudioProject(dir);
      expect(project.directory.path, equals('D:/projects/makaw'));
      expect(project.path, equals('D:/projects/makaw'));
      expect(project.name, isNotEmpty);
    });
  });

  group('MakawTerminalEngine', () {
    late MakawTerminalEngine engine;

    setUp(() {
      engine = MakawTerminalEngine();
    });

    tearDown(() {
      engine.dispose();
    });

    test('initializes with default properties', () {
      expect(engine.isRunning, isFalse);
      expect(engine.workingDirectory, isEmpty);
      expect(engine.shellName, isNotEmpty);
      if (Platform.isWindows) {
        expect(engine.shellName, equals('powershell'));
      }
    });

    test('findGitBash discovers existing Git Bash executable or returns null', () {
      final gitBash = MakawTerminalEngine.findGitBash();
      if (Platform.isWindows && gitBash != null) {
        expect(File(gitBash).existsSync(), isTrue);
        expect(gitBash.toLowerCase(), contains('bash.exe'));
      }
    });

    test('safe operations when shell is idle do not throw', () {
      expect(() => engine.clearDisplay(), returnsNormally);
      expect(() => engine.interrupt(), returnsNormally);
      expect(() => engine.eof(), returnsNormally);
    });
  });
}
