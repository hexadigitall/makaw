import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/core/platform/file_exclusion_filter.dart';

void main() {
  group('FileExclusionFilter', () {
    test('identifies system and hidden files', () {
      expect(FileExclusionFilter.isSystemOrHidden('desktop.ini'), isTrue);
      expect(FileExclusionFilter.isSystemOrHidden(r'C:\Users\User\desktop.ini'), isTrue);
      expect(FileExclusionFilter.isSystemOrHidden('thumbs.db'), isTrue);
      expect(FileExclusionFilter.isSystemOrHidden('.DS_Store'), isTrue);
      expect(FileExclusionFilter.isSystemOrHidden('.gitignore'), isTrue);
      expect(FileExclusionFilter.isSystemOrHidden(r'~$Document.docx'), isTrue);
      expect(FileExclusionFilter.isSystemOrHidden('file.tmp'), isTrue);
      expect(FileExclusionFilter.isSystemOrHidden('normal_report.pdf'), isFalse);
      expect(FileExclusionFilter.isSystemOrHidden('source_code.dart'), isFalse);
    });

    test('identifies sensitive credential files', () {
      expect(FileExclusionFilter.isSensitive('Chrome Passwords2.csv'), isTrue);
      expect(FileExclusionFilter.isSensitive(r'D:\Downloads\my-passwords.txt'), isTrue);
      expect(FileExclusionFilter.isSensitive('aws_credentials.json'), isTrue);
      expect(FileExclusionFilter.isSensitive('api_tokens.md'), isTrue);
      expect(FileExclusionFilter.isSensitive('client_secret.json'), isTrue);
      expect(FileExclusionFilter.isSensitive('id_rsa'), isTrue);
      expect(FileExclusionFilter.isSensitive('server.key'), isTrue);
      expect(FileExclusionFilter.isSensitive('certificate.pem'), isTrue);
      expect(FileExclusionFilter.isSensitive('release.jks'), isTrue);
      expect(FileExclusionFilter.isSensitive('.env'), isTrue);
      expect(FileExclusionFilter.isSensitive('.env.production'), isTrue);
      expect(FileExclusionFilter.isSensitive('annual_budget_2026.xlsx'), isFalse);
      expect(FileExclusionFilter.isSensitive('whitepaper.pdf'), isFalse);
    });

    test('shouldExclude filters both system and sensitive files', () {
      expect(FileExclusionFilter.shouldExclude('desktop.ini'), isTrue);
      expect(FileExclusionFilter.shouldExclude('Chrome Passwords2.csv'), isTrue);
      expect(FileExclusionFilter.shouldExclude('.env'), isTrue);
      expect(FileExclusionFilter.shouldExclude('tutorial.epub'), isFalse);
    });

    test('identifies system directories to skip', () {
      expect(FileExclusionFilter.isSystemDirectory('.git'), isTrue);
      expect(FileExclusionFilter.isSystemDirectory('node_modules'), isTrue);
      expect(FileExclusionFilter.isSystemDirectory('AppData'), isTrue);
      expect(FileExclusionFilter.isSystemDirectory('Windows'), isTrue);
      expect(FileExclusionFilter.isSystemDirectory('MyDocuments'), isFalse);
      expect(FileExclusionFilter.isSystemDirectory('Projects'), isFalse);
    });
  });
}
