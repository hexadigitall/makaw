import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makaw/core/services/terminal_sessions_store.dart';
import 'package:makaw/features/terminal/application/terminal_runtime_manager.dart';
import 'package:makaw/features/terminal/data/makaw_hybrid_shell.dart';
import 'package:makaw/features/terminal/data/shell_discovery.dart';
import 'package:makaw/features/terminal/data/ssh_vault_service.dart';
import 'package:makaw/features/terminal/domain/terminal_models.dart';
import 'package:makaw/features/terminal/presentation/widgets/terminal_soft_keyboard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TerminalSessionsStore & Appearance', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists extended metadata and pin ordering', () async {
      final store = TerminalSessionsStore();
      final a = await store.create(
        'local-ps',
        shellId: 'pwsh',
        targetType: 'local',
        cwd: 'D:/projects',
      );
      final b = await store.create(
        'vps-prod',
        shellId: 'ssh',
        targetType: 'ssh',
        hostId: 'h1',
        cwd: '/srv/app',
      );
      expect((await store.load()).first.id, equals(b.id));

      await store.togglePin(a.id);
      final reloaded = TerminalSessionsStore();
      final list = await reloaded.load();
      expect(list.first.id, equals(a.id));
      expect(list.first.isPinned, isTrue);
      expect(list.first.shellId, equals('pwsh'));
      expect(list.first.cwd, equals('D:/projects'));
    });

    test('persists and clamps TerminalAppearancePrefs', () async {
      final store = TerminalSessionsStore();
      await store.saveAppearance(const TerminalAppearancePrefs(
        themeId: 'tokyo_night',
        fontSize: 18,
        cursorStyle: 'bar',
        showSoftKeys: true,
        showSoftKeyRow2: true,
      ));
      final loaded = await TerminalSessionsStore().loadAppearance();
      expect(loaded.themeId, equals('tokyo_night'));
      expect(loaded.fontSize, equals(18));
      expect(loaded.cursorStyle, equals('bar'));
      expect(loaded.showSoftKeyRow2, isTrue);
    });
  });

  group('ShellDiscovery & SshHostProfile', () {
    test('resolveDefaultCwd never falls back to raw system root on desktop', () {
      final cwd = ShellDiscovery.resolveDefaultCwd();
      expect(cwd, isNotEmpty);
      if (Platform.isWindows) {
        expect(cwd.toUpperCase(), isNot(equals(r'C:\')));
      }
    });

    test('discoverLocalShells includes makaw-sh and host OS shells', () async {
      final shells = await ShellDiscovery.discoverLocalShells();
      expect(shells, isNotEmpty);
      expect(shells.any((s) => s.id == 'makaw-sh'), isTrue);
      if (Platform.isWindows) {
        expect(shells.any((s) => s.id == 'powershell'), isTrue);
      }
    });

    test('parses SSH target strings accurately', () {
      final full = SshHostProfile.parseTarget('ssh://ubuntu@10.0.0.5:2222/var');
      expect(full?.username, equals('ubuntu'));
      expect(full?.host, equals('10.0.0.5'));
      expect(full?.port, equals(2222));

      final short = SshHostProfile.parseTarget('dev-box');
      expect(short?.username, equals('root'));
      expect(short?.host, equals('dev-box'));
      expect(short?.port, equals(22));
    });
  });

  group('SshVaultService Ed25519 Keygen', () {
    test('generates OpenSSH Ed25519 keypair accepted by dartssh2', () {
      final id = SshVaultService.generateEd25519KeyPair(comment: 'test@makaw');
      expect(id.privateKeyPem, contains('-----BEGIN OPENSSH PRIVATE KEY-----'));
      expect(id.publicKeyOpenSsh, startsWith('ssh-ed25519 '));
      expect(id.sha256Fingerprint, startsWith('SHA256:'));

      final parsed = SSHKeyPair.fromPem(id.privateKeyPem);
      expect(parsed, hasLength(1));
      expect(parsed.first, isA<OpenSSHEd25519KeyPair>());
    });
  });

  group('MakawHybridShell (makaw-sh)', () {
    late Directory tmpDir;
    late MakawHybridShell shell;
    final out = StringBuffer();

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('makaw_sh_test_');
      shell = MakawHybridShell(initialCwd: tmpDir.path);
      shell.output.listen(out.write);
      out.clear();
    });

    tearDown(() {
      shell.close();
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('executes POSIX file commands, redirection, grep, and zip/unzip', () async {
      expect(await shell.executeLine('mkdir -p sub && touch sub/notes.txt'), 0);
      expect(
        await shell.executeLine('echo "alpha beta" > sub/notes.txt && echo "gamma" >> sub/notes.txt'),
        0,
      );
      expect(await shell.executeLine('grep -n "alpha" sub/notes.txt'), 0);
      final plainOut =
          out.toString().replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
      expect(plainOut, contains('1:alpha beta'));

      expect(await shell.executeLine('zip bundle.zip sub'), 0);
      expect(File('${tmpDir.path}${Platform.pathSeparator}bundle.zip').existsSync(), isTrue);

      expect(await shell.executeLine('mkdir out && unzip bundle.zip -d out'), 0);
      expect(await shell.executeLine('cd sub && pwd'), 0);
      expect(shell.cwd, endsWith('sub'));
    });

    test('short-circuits && cleanly and respects quotes in tokenize', () async {
      final toks = MakawHybridShell.tokenize('echo "hello world" \'single \$RAW\'');
      expect(toks, equals(['echo', 'hello world', 'single \$RAW']));

      final code = await shell.executeLine('cat does_not_exist.txt && echo unreachable');
      expect(code, isNonZero);
      expect(out.toString(), isNot(contains('unreachable')));
    });
  });

  group('TerminalRuntimeManager Scrollback Search & Presets', () {
    test('finds case-insensitive matches across terminal buffer lines', () {
      final term = Terminal(maxLines: 500);
      term.write('Building Makaw APK...\r\nFAILED lib/main.dart:42\r\nDone.');
      final hits = TerminalRuntimeManager.searchScrollback(term, 'failed');
      expect(hits, hasLength(1));
      expect(hits.first.startCol, equals(0));
      expect(hits.first.endCol, equals(6));
    });

    test('provides 6 curated terminal themes', () {
      expect(MakawTerminalThemePreset.presets, hasLength(6));
      expect(MakawTerminalThemePreset.byId('dracula').label, equals('Dracula'));
    });
  });

  group('TerminalSoftKeyboard Widget (360x640 Mobile)', () {
    testWidgets('renders soft-keys, expandable row 2 & sticky CTRL without overflow',
        (tester) async {
      final term = Terminal();
      final ctrl = TerminalController();
      final emitted = <String>[];
      term.onOutput = emitted.add;

      var row2 = true;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 640)),
            child: Scaffold(
              body: StatefulBuilder(
                builder: (_, setState) => Align(
                  alignment: Alignment.bottomCenter,
                  child: TerminalSoftKeyboard(
                    terminal: term,
                    controller: ctrl,
                    showRow2: row2,
                    onToggleRow2: (v) => setState(() => row2 = v),
                    onCopySelection: () {},
                    onPasteClipboard: () {},
                    onClear: () {},
                    onOpenHosts: () {},
                    onToggleFind: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('ESC'), findsOneWidget);
      expect(find.text('CTRL'), findsOneWidget);

      await tester.tap(find.text('CTRL'));
      await tester.pump();
      expect(find.text('CTRL armed — tap a key'), findsOneWidget);

      await tester.tap(find.text('^C'));
      await tester.pump();
      expect(emitted, contains('\x03'));
      ctrl.dispose();
    });
  });
}
