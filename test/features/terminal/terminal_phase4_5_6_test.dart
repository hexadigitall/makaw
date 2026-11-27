import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:makaw/core/services/terminal_sessions_store.dart';
import 'package:makaw/features/terminal/application/terminal_runtime_manager.dart';
import 'package:makaw/features/terminal/data/ai_tool_vault_service.dart';
import 'package:makaw/features/terminal/data/continuum_sync_service.dart';
import 'package:makaw/features/terminal/data/project_runbook_service.dart';
import 'package:makaw/features/terminal/data/toolchain_manager.dart';
import 'package:makaw/features/terminal/data/workstation_companion_service.dart';
import 'package:makaw/features/terminal/presentation/widgets/dev_ecosystem_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 4: RunbookDetector & TerminalLinkDetector', () {
    test('detects Flutter/Dart, Node scripts & Makefile runbooks from CWD',
        () async {
      final tmp = Directory.systemTemp.createTempSync('makaw_runbook_');
      try {
        File('${tmp.path}/pubspec.yaml')
            .writeAsStringSync('name: sample\ndependencies:\n  flutter:\n    sdk: flutter\n');
        File('${tmp.path}/package.json').writeAsStringSync(
            jsonEncode({'scripts': {'dev': 'vite', 'test': 'vitest'}}));
        File('${tmp.path}/Makefile').writeAsStringSync('build:\n\techo hi\n');

        final found = await RunbookDetector.detect(tmp.path);
        final commands = found.map((r) => r.command).toList();
        expect(commands, contains('flutter test --no-pub'));
        expect(commands, contains('flutter analyze --no-pub'));
        expect(commands, contains('npm run dev'));
        expect(commands, contains('npm test'));
        expect(commands, contains('make build'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('extracts localhost URLs & file:line stack traces cleanly', () {
      final term = Terminal(maxLines: 200);
      term.write(
        'Server listening at http://localhost:3000/api.\r\n'
        'Error in lib/features/terminal/terminal_sessions_page.dart:42:9!\r\n',
      );
      final links = TerminalLinkDetector.extractFromTerminal(term);
      expect(
        links.any(
            (l) => l.kind == TerminalLinkKind.url && l.target == 'http://localhost:3000/api'),
        isTrue,
      );
      expect(
        links.any((l) =>
            l.kind == TerminalLinkKind.file &&
            l.target.endsWith('terminal_sessions_page.dart') &&
            l.line == 42),
        isTrue,
      );
    });
  });

  group('Phase 4: AiToolVaultService & ToolchainManager', () {
    test('redacts API keys, tokens & private PEM blocks safely', () {
      const dirty =
          'export GEMINI_API_KEY=AIzaSyD1234567890ABCDEFGHIJK '
          'Authorization: Bearer my.secret.jwt '
          '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----';
      final clean = AiToolVaultService.redactSecrets(dirty);
      expect(clean, isNot(contains('AIzaSyD')));
      expect(clean, isNot(contains('my.secret.jwt')));
      expect(clean, isNot(contains('OPENSSH PRIVATE KEY-----')));
    });

    test('injects enabled AI keys & runs offline error diagnosis', () async {
      final vault = AiToolVaultService();
      await vault.saveConnector(
        AiToolConnector.builtInPresets.first,
        apiKey: 'AIzaTestMockKey1234567890123',
      );
      final env = await vault.buildSessionEnv();
      expect(env['GEMINI_API_KEY'], equals('AIzaTestMockKey1234567890123'));

      final diag = await vault.diagnoseFailure(
        command: 'docker ps',
        exitCode: 127,
        outputTail: 'docker: command not found',
      );
      expect(diag.explanation, contains('127'));
      expect(diag.suggestedCommand, equals('which docker'));
    });

    test('normalizes Git clone shorthand & HTTPS URLs', () {
      final gh = ToolchainManager.normalizeGitCloneTarget('hexadigitall/makaw');
      expect(gh?.url, equals('https://github.com/hexadigitall/makaw.git'));
      expect(gh?.folderName, equals('makaw'));

      final direct = ToolchainManager.normalizeGitCloneTarget(
          'https://gitlab.com/org/repo-name.git');
      expect(direct?.folderName, equals('repo-name'));
    });
  });

  group('Phase 5: WorkstationCompanionHost, FileExclusionFilter & ContinuumSync',
      () {
    test('enforces Bearer auth, FileExclusionFilter & Continuum LAN handoff',
        () async {
      final savedHttp = HttpOverrides.current;
      HttpOverrides.global = null;
      final root = Directory.systemTemp.createTempSync('makaw_companion_');
      final host = WorkstationCompanionHost(rootDir: root.path, token: 'TESTPAIR123');
      try {
        File('${root.path}/main.dart').writeAsStringSync('void main() {}');
        File('${root.path}/.env').writeAsStringSync('SECRET=topsecret');
        File('${root.path}/id_rsa.pem').writeAsStringSync('PRIVATE');

        final port = await host.start(preferredPort: 0);
        final pairing = CompanionPairing(
          name: 'Workstation-Test',
          host: '127.0.0.1',
          port: port,
          token: 'TESTPAIR123',
          rootDir: root.path,
        );

        final parsed = CompanionPairing.parsePairingUri(pairing.toPairingUri());
        expect(parsed?.token, equals('TESTPAIR123'));
        expect(parsed?.port, equals(port));

        // Unauthenticated requests MUST be rejected (401)
        final unauth = await http
            .get(Uri.parse('${pairing.baseUrl}/v1/fs/list?path=.'));
        expect(unauth.statusCode, equals(401));

        // Authenticated list exposes main.dart while hiding .env & .pem secrets
        final entries = await WorkstationCompanionClient.listRemoteDir(pairing);
        final names = entries.map((e) => e['name']).toList();
        expect(names, contains('main.dart'));
        expect(names, isNot(contains('.env')));
        expect(names, isNot(contains('id_rsa.pem')));

        // Remote read & write round-trip
        await WorkstationCompanionClient.writeRemoteFile(
            pairing, 'notes.txt', 'Synced from mobile');
        final readBack =
            await WorkstationCompanionClient.readRemoteFile(pairing, 'notes.txt');
        expect(readBack, equals('Synced from mobile'));

        // Live Continuum LAN push & pull
        final sync = MakawContinuumSync();
        final store = TerminalSessionsStore();
        await store.create('mobile-session',
            cwd: '/storage/emulated/0', shellId: 'makaw-sh');
        await sync.captureAndSync(
          store: store,
          sshHosts: const [],
          activeCwd: '/storage/emulated/0',
          handoffNote: 'Running phase 6 verification',
          companion: pairing,
        );
        final pulled = await sync.pullSnapshot(companion: pairing);
        expect(pulled?.handoffNote, equals('Running phase 6 verification'));
        expect(pulled?.sessions.first.name, equals('mobile-session'));
      } finally {
        HttpOverrides.global = savedHttp;
        await host.stop();
        root.deleteSync(recursive: true);
      }
    });
  });

  group('Phase 6: DevEcosystemSheet Widget Layout (360x640)', () {
    testWidgets('renders all 4 Developer Hub tabs cleanly without overflow',
        (tester) async {
      final mgr = TerminalRuntimeManager();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 640)),
            child: Scaffold(
              body: DevEcosystemSheet(manager: mgr),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Packages & Git'), findsOneWidget);
      expect(find.text('AI Tools'), findsOneWidget);

      await tester.tap(find.text('Continuum Sync'));
      await tester.pumpAndSettle();
      expect(find.text('Push State'), findsOneWidget);
      expect(tester.takeException(), isNull);
      mgr.dispose();
    });
  });
}
