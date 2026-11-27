import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../documents/data/services/archive_service.dart';
import '../domain/terminal_models.dart';
import 'shell_discovery.dart';

/// Pure-Dart + native-passthrough hybrid interactive shell (`makaw-sh`).
///
/// Gives Android (and Desktop fallback tabs) full core POSIX utilities, archive
/// tools (`zip`/`unzip`), HTTP requests (`curl`/`wget`), git inspection, shell
/// switching (`bash`/`zsh`/`pwsh`/`ubuntu`), SSH launch (`ssh user@host`),
/// line editing, arrow-key history, tab completion, `&&`/`;` chaining, `$VAR`
/// expansion, and `>`/`>>` redirection cleanly over a VT100 stream.
class MakawHybridShell {
  final StreamController<String> _outCtrl = StreamController<String>.broadcast();
  final Completer<int> _exitCompleter = Completer<int>();

  final Map<String, String> env = {};
  final List<String> history = [];
  int _historyIdx = -1;
  String _cwd;
  String _prevCwd;
  int _lastExitCode = 0;
  bool _closed = false;

  // Interactive line editor state
  final StringBuffer _line = StringBuffer();
  int _cursor = 0;
  String _escBuf = '';
  bool _inEsc = false;
  int _cols = Platform.isAndroid ? 42 : 80;
  int _promptVisibleLen = 10;
  int _renderedCursorRow = 0;
  DateTime? _lastBackspaceAt;

  // Currently running passthrough process (can be Ctrl+C interrupted)
  Process? _activeChild;
  bool _busy = false;

  // Integration callbacks injected by TerminalRuntimeManager
  final Future<void> Function(String target)? onConnectSsh;
  final Future<void> Function(String shellQuery)? onSwitchShell;
  final Future<void> Function(String filePath)? onOpenFile;
  final Future<List<SshHostProfile>> Function()? onListSshHosts;
  final void Function(String cwd)? onCwdChanged;
  final void Function(String command, int exitCode)? onCommandCompleted;

  MakawHybridShell({
    String? initialCwd,
    this.onConnectSsh,
    this.onSwitchShell,
    this.onOpenFile,
    this.onListSshHosts,
    this.onCwdChanged,
    this.onCommandCompleted,
  })  : _cwd = ShellDiscovery.resolveDefaultCwd(initialCwd),
        _prevCwd = ShellDiscovery.resolveDefaultCwd(initialCwd) {
    env['HOME'] = ShellDiscovery.resolveDefaultCwd(initialCwd);
    env['USER'] = Platform.environment['USER'] ??
        Platform.environment['USERNAME'] ??
        'makaw';
    env['SHELL'] = 'makaw-sh';
    env['TERM'] = 'xterm-256color';
    env['PWD'] = _cwd;
    env['OLDPWD'] = _prevCwd;
  }

  Stream<String> get output => _outCtrl.stream;
  Future<int> get exitCode => _exitCompleter.future;
  String get cwd => _cwd;
  int get lastExitCode => _lastExitCode;
  int get columns => _cols;

  /// Keeps wrap/redraw calculations matched to the attached xterm viewport.
  void resize(int cols, int rows) {
    if (cols >= 20) _cols = cols;
  }

  /// Re-prints the active prompt + input buffer after clearing the display.
  void reprintPrompt() {
    _renderedCursorRow = 0;
    _printPrompt();
    if (_line.isNotEmpty) {
      _redrawLine(forceFromOrigin: true);
    }
  }

  void start() {
    if (_closed) return;
    _emit(
      '\x1b[38;5;45mMakaw Hybrid Shell (makaw-sh)\x1b[0m · ${_shortCwd()}\r\n'
      '\x1b[90mTools: ls, cd, cat, grep, find, mkdir, cp, mv, rm, zip, unzip, curl, git, ssh, hosts\x1b[0m\r\n'
      '\x1b[90mType \x1b[37mhelp\x1b[90m for commands or \x1b[37mssh user@host\x1b[90m for remote servers.\x1b[0m\r\n',
    );
    _printPrompt();
  }

  void _emit(String s) {
    if (!_closed && !_outCtrl.isClosed) _outCtrl.add(s);
  }

  String _shortCwd() {
    final home = env['HOME'] ?? '';
    String display;
    if (home.isNotEmpty && _cwd == home) {
      display = '~';
    } else if (home.isNotEmpty &&
        _cwd.startsWith('$home${Platform.pathSeparator}')) {
      display = '~/${_cwd.substring(home.length + 1).replaceAll(r'\', '/')}';
    } else {
      display = _cwd.replaceAll(r'\', '/');
    }
    // Keep prompt compact on narrow phone screens so typing starts well before wrap.
    final maxLen = _cols < 56 ? 14 : 28;
    if (display.length > maxLen) {
      final tail = display.split('/').last;
      if (tail.isNotEmpty && tail.length + 2 <= maxLen) {
        return '…/$tail';
      }
      return '…${display.substring(display.length - (maxLen - 1))}';
    }
    return display;
  }

  int _visualRow(int linearPos) =>
      linearPos <= 0 ? 0 : (linearPos - 1) ~/ _cols;

  ({String ansi, int visibleLen}) _buildPrompt() {
    final short = _shortCwd();
    if (_lastExitCode == 0) {
      final visible = '✓ $short \$ ';
      return (
        ansi: '\x1b[32m✓\x1b[0m \x1b[33m$short\x1b[0m \$ ',
        visibleLen: visible.length,
      );
    } else {
      final visible = '✗ $_lastExitCode $short \$ ';
      return (
        ansi: '\x1b[31m✗ $_lastExitCode\x1b[0m \x1b[33m$short\x1b[0m \$ ',
        visibleLen: visible.length,
      );
    }
  }

  void _printPrompt() {
    final p = _buildPrompt();
    _promptVisibleLen = p.visibleLen;
    _renderedCursorRow = _visualRow(_promptVisibleLen);
    _emit(p.ansi);
  }

  /// Erases the prompt + all wrapped continuation rows cleanly and rewrites the
  /// buffer, placing the cursor accurately even across row-wrap boundaries.
  void _redrawLine({bool forceFromOrigin = false}) {
    final text = _line.toString();
    if (!forceFromOrigin) {
      _emit('\r');
      if (_renderedCursorRow > 0) {
        _emit('\x1b[${_renderedCursorRow}A');
      }
      _emit('\x1b[J');
    } else {
      _emit('\r\x1b[J');
    }

    final p = _buildPrompt();
    _promptVisibleLen = p.visibleLen;
    _emit(p.ansi);
    _emit(text);

    final endLinear = _promptVisibleLen + text.length;
    final endRow = _visualRow(endLinear);

    if (_cursor == text.length) {
      _renderedCursorRow = endRow;
      return;
    }

    final targetLinear = _promptVisibleLen + _cursor;
    final targetRow = targetLinear ~/ _cols;
    final targetCol = targetLinear % _cols;
    final up = endRow - targetRow;
    if (up > 0) _emit('\x1b[${up}A');
    _emit('\r');
    if (targetCol > 0) _emit('\x1b[${targetCol}C');
    _renderedCursorRow = targetRow;
  }

  void _moveCursor(int nextCursor) {
    final clamped = nextCursor.clamp(0, _line.length);
    if (clamped == _cursor) return;
    final targetLinear = _promptVisibleLen + clamped;
    final targetRow = targetLinear ~/ _cols;
    final targetCol = targetLinear % _cols;
    final deltaRow = targetRow - _renderedCursorRow;
    if (deltaRow > 0) {
      _emit('\x1b[${deltaRow}B');
    } else if (deltaRow < 0) {
      _emit('\x1b[${-deltaRow}A');
    }
    _emit('\r');
    if (targetCol > 0) _emit('\x1b[${targetCol}C');
    _cursor = clamped;
    _renderedCursorRow = targetRow;
  }

  /// Processes raw terminal input sequences from `Terminal.onOutput`.
  void feedInput(String data) {
    if (_closed) return;
    // If a child native binary is running, forward input directly to it except Ctrl+C.
    if (_activeChild != null) {
      if (data == '\x03') {
        _interruptActiveChild();
      } else {
        try {
          _activeChild!.stdin.add(utf8.encode(data));
        } catch (_) {}
      }
      return;
    }

    for (var i = 0; i < data.length; i++) {
      final ch = data[i];
      if (_inEsc) {
        _escBuf += ch;
        // Wait for complete CSI / SS3 sequences without swallowing Meta/normal text.
        if ((_escBuf == '[' || _escBuf == 'O') && i + 1 < data.length) {
          continue;
        }
        if ((_escBuf == '[' || _escBuf == 'O') && i + 1 >= data.length) {
          continue;
        }
        if (_escBuf.startsWith('[') &&
            _escBuf.length < 8 &&
            !RegExp(r'[A-Za-z~]$').hasMatch(_escBuf)) {
          continue;
        }
        _handleEscape(_escBuf);
        _inEsc = false;
        _escBuf = '';
        continue;
      }

      final code = ch.codeUnitAt(0);
      if (ch == '\x1b') {
        _inEsc = true;
        _escBuf = '';
      } else if (ch == '\r' || ch == '\n') {
        _moveCursor(_line.length);
        _emit('\r\n');
        final cmd = _line.toString();
        _line.clear();
        _cursor = 0;
        _renderedCursorRow = 0;
        _historyIdx = -1;
        unawaited(_submitLine(cmd));
      } else if (ch == '\x03') {
        // Ctrl+C
        _moveCursor(_line.length);
        _line.clear();
        _cursor = 0;
        _renderedCursorRow = 0;
        _historyIdx = -1;
        _emit('^C\r\n');
        _printPrompt();
      } else if (ch == '\x0c') {
        // Ctrl+L
        _emit('\x1b[2J\x1b[H');
        reprintPrompt();
      } else if (ch == '\x04') {
        // Ctrl+D
        if (_line.isEmpty) {
          _emit('exit\r\n');
          close(0);
          return;
        }
      } else if (ch == '\t') {
        _handleTabComplete();
      } else if (code == 127 || ch == '\b') {
        // Guard against Android OEM keyboards firing dual KeyEvent + IME delete in <6ms.
        final now = DateTime.now();
        if (Platform.isAndroid &&
            _lastBackspaceAt != null &&
            now.difference(_lastBackspaceAt!).inMilliseconds < 6) {
          continue;
        }
        _lastBackspaceAt = now;
        if (_cursor > 0) {
          final current = _line.toString();
          final updated =
              current.substring(0, _cursor - 1) + current.substring(_cursor);
          _line
            ..clear()
            ..write(updated);
          _cursor--;
          _redrawLine();
        }
      } else if (code >= 32) {
        final current = _line.toString();
        if (_cursor == current.length) {
          _line.write(ch);
          _cursor++;
          _emit(ch);
          _renderedCursorRow = _visualRow(_promptVisibleLen + _cursor);
        } else {
          final updated = current.substring(0, _cursor) +
              ch +
              current.substring(_cursor);
          _line
            ..clear()
            ..write(updated);
          _cursor++;
          _redrawLine();
        }
      }
    }
  }

  void _handleEscape(String seq) {
    if (seq == '[A') {
      // Up arrow -> previous command in history
      if (history.isEmpty) return;
      if (_historyIdx < 0) {
        _historyIdx = history.length - 1;
      } else if (_historyIdx > 0) {
        _historyIdx--;
      }
      _replaceLine(history[_historyIdx]);
    } else if (seq == '[B') {
      // Down arrow
      if (history.isEmpty || _historyIdx < 0) return;
      if (_historyIdx < history.length - 1) {
        _historyIdx++;
        _replaceLine(history[_historyIdx]);
      } else {
        _historyIdx = -1;
        _replaceLine('');
      }
    } else if (seq == '[D') {
      _moveCursor(_cursor - 1);
    } else if (seq == '[C') {
      _moveCursor(_cursor + 1);
    } else if (seq == '[H' || seq == '[1~') {
      _moveCursor(0);
    } else if (seq == '[F' || seq == '[4~') {
      _moveCursor(_line.length);
    } else if (seq == '[3~') {
      // Forward delete
      final current = _line.toString();
      if (_cursor < current.length) {
        final updated =
            current.substring(0, _cursor) + current.substring(_cursor + 1);
        _line
          ..clear()
          ..write(updated);
        _redrawLine();
      }
    }
  }

  void _replaceLine(String next) {
    _line
      ..clear()
      ..write(next);
    _cursor = next.length;
    _redrawLine();
  }

  void _handleTabComplete() {
    final before = _line.toString().substring(0, _cursor);
    final parts = before.split(RegExp(r'\s+'));
    final prefix = parts.last;

    if (parts.length == 1 && !prefix.contains('/') && !prefix.contains(r'\')) {
      final matches = _builtInNames
          .where((n) => n.startsWith(prefix))
          .toList()
        ..sort();
      if (matches.length == 1) {
        final completion = '${matches.first} ';
        final rest = _line.toString().substring(_cursor);
        _line
          ..clear()
          ..write('$completion$rest');
        _cursor = completion.length;
        _redrawLine();
        return;
      }
      if (matches.length > 1) {
        _moveCursor(_line.length);
        _emit('\r\n${_formatCandidates(matches)}\r\n');
        _redrawLine(forceFromOrigin: true);
        return;
      }
    }

    // Complete file/directory names in CWD (or subdir prefix)
    final sepIdx = prefix.lastIndexOf(RegExp(r'[/\\]'));
    final dirPart = sepIdx >= 0 ? prefix.substring(0, sepIdx + 1) : '';
    final namePrefix = sepIdx >= 0 ? prefix.substring(sepIdx + 1) : prefix;
    final searchDir = Directory(_resolvePath(dirPart.isEmpty ? '.' : dirPart));
    if (!searchDir.existsSync()) return;
    final candidates = <String>[];
    try {
      for (final entity in searchDir.listSync()) {
        final name = p.basename(entity.path);
        if (name.startsWith(namePrefix)) {
          candidates.add(entity is Directory ? '$name/' : name);
        }
      }
    } catch (_) {}
    if (candidates.length == 1) {
      final replacement = '$dirPart${candidates.first}';
      final updatedBefore =
          before.substring(0, before.length - prefix.length) + replacement;
      final rest = _line.toString().substring(_cursor);
      _line
        ..clear()
        ..write('$updatedBefore$rest');
      _cursor = updatedBefore.length;
      _redrawLine();
    } else if (candidates.length > 1) {
      candidates.sort();
      _moveCursor(_line.length);
      _emit('\r\n${_formatCandidates(candidates)}\r\n');
      _redrawLine(forceFromOrigin: true);
    }
  }

  /// Wraps tab-completion items along item boundaries (never splitting filenames
  /// mid-word across narrow mobile terminal rows).
  String _formatCandidates(List<String> items) {
    final buf = StringBuffer();
    var col = 0;
    final shown = items.take(40).toList();
    for (final item in shown) {
      final piece = '$item  ';
      if (col > 0 && col + piece.length > _cols) {
        buf.write('\r\n');
        col = 0;
      }
      buf.write(piece);
      col += piece.length;
    }
    if (items.length > shown.length) {
      buf.write('\r\n… (+${items.length - shown.length} more)');
    }
    return buf.toString().trimRight();
  }

  void _interruptActiveChild() {
    if (_activeChild != null) {
      try {
        _activeChild!.kill(ProcessSignal.sigint);
      } catch (_) {}
      _emit('^C\r\n');
    }
  }

  Future<void> _submitLine(String raw) async {
    if (_busy) return;
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) {
      if (history.isEmpty || history.last != trimmed) {
        history.add(trimmed);
        if (history.length > 200) history.removeAt(0);
      }
      _busy = true;
      _lastExitCode = await executeLine(trimmed);
      _busy = false;
      onCommandCompleted?.call(trimmed, _lastExitCode);
    }
    if (!_closed) _printPrompt();
  }

  /// Splits and executes chained statements (`&&` and `;`) and writes formatted
  /// output + error codes directly to this shell's ANSI stream. Returns final
  /// exit status (`0` on success). Directly unit-testable without a widget host.
  Future<int> executeLine(String rawLine) async {
    final segments = _splitStatements(rawLine);
    var code = 0;
    for (final seg in segments) {
      final cmdText = seg.text.trim();
      if (cmdText.isEmpty) continue;
      code = await _executeSingleStatement(cmdText);
      _lastExitCode = code;
      if (seg.connector == '&&' && code != 0) break;
    }
    return code;
  }

  Future<int> _executeSingleStatement(String statement) async {
    final tokens = tokenize(statement);
    if (tokens.isEmpty) return 0;

    // Handle output redirection (`>` / `>>`) cleanly at tail
    String? redirectFile;
    var appendMode = false;
    final cleanTokens = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if ((t == '>' || t == '>>') && i + 1 < tokens.length) {
        appendMode = t == '>>';
        redirectFile = _resolvePath(tokens[i + 1]);
        i++;
      } else {
        cleanTokens.add(_expandEnv(t));
      }
    }
    if (cleanTokens.isEmpty) return 0;

    final sink = redirectFile != null ? StringBuffer() : null;
    void writeOut(String text) {
      if (sink != null) {
        sink.write(text.replaceAll(RegExp(r'\x1b\[[0-9;]*[A-Za-z]'), ''));
      } else {
        _emit(text.replaceAll('\n', '\r\n'));
      }
    }

    final cmd = cleanTokens.first;
    final args = cleanTokens.sublist(1);
    final code = await _dispatch(cmd, args, writeOut);

    if (redirectFile != null && sink != null) {
      try {
        final f = File(redirectFile);
        await f.parent.create(recursive: true);
        await f.writeAsString(
          sink.toString(),
          mode: appendMode ? FileMode.append : FileMode.write,
        );
      } catch (e) {
        _emit('\x1b[31mredirect failed ($redirectFile): $e\x1b[0m\r\n');
        return 1;
      }
    }
    return code;
  }

  Future<int> _dispatch(
    String cmd,
    List<String> args,
    void Function(String) writeOut,
  ) async {
    switch (cmd) {
      case 'help':
      case '?':
        writeOut(_helpText());
        return 0;

      case 'mk':
        if (args.isEmpty || args.first == 'help') {
          writeOut(_helpText());
          return 0;
        }
        return _dispatch(args.first, args.sublist(1), writeOut);

      case 'clear':
      case 'cls':
        _emit('\x1b[2J\x1b[H');
        return 0;

      case 'exit':
      case 'quit':
        close(0);
        return 0;

      case 'pwd':
        writeOut('$_cwd\n');
        return 0;

      case 'cd':
        return _cmdCd(args, writeOut);

      case 'ls':
      case 'dir':
        return _cmdLs(args, writeOut);

      case 'tree':
        return _cmdTree(args, writeOut);

      case 'cat':
        return _cmdCat(args, writeOut);

      case 'head':
        return _cmdHeadTail(args, isHead: true, writeOut: writeOut);

      case 'tail':
        return _cmdHeadTail(args, isHead: false, writeOut: writeOut);

      case 'wc':
        return _cmdWc(args, writeOut);

      case 'touch':
        return _cmdTouch(args, writeOut);

      case 'mkdir':
        return _cmdMkdir(args, writeOut);

      case 'cp':
        return _cmdCp(args, writeOut);

      case 'mv':
        return _cmdMv(args, writeOut);

      case 'rm':
        return _cmdRm(args, writeOut);

      case 'stat':
        return _cmdStat(args, writeOut);

      case 'grep':
        return _cmdGrep(args, writeOut);

      case 'find':
        return _cmdFind(args, writeOut);

      case 'zip':
        return _cmdZip(args, writeOut);

      case 'unzip':
        return _cmdUnzip(args, writeOut);

      case 'tar':
        return _cmdTar(args, writeOut);

      case 'curl':
      case 'wget':
        return _cmdHttp(cmd, args, writeOut);

      case 'git':
        return _cmdGit(args, writeOut);

      case 'hosts':
        return _cmdHosts(writeOut);

      case 'ssh':
        return _cmdSsh(args, writeOut);

      case 'open':
      case 'edit':
        if (args.isEmpty) {
          writeOut('Usage: $cmd <file>\n');
          return 1;
        }
        final target = _resolvePath(args.first);
        if (!File(target).existsSync() && !Directory(target).existsSync()) {
          writeOut('Not found: ${args.first}\n');
          return 1;
        }
        await onOpenFile?.call(target);
        return 0;

      case 'echo':
        writeOut('${args.join(' ')}\n');
        return 0;

      case 'env':
        final combined = {...Platform.environment, ...env};
        for (final entry in combined.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
          writeOut('${entry.key}=${entry.value}\n');
        }
        return 0;

      case 'export':
        if (args.isEmpty) return _dispatch('env', const [], writeOut);
        for (final a in args) {
          final eq = a.indexOf('=');
          if (eq > 0) env[a.substring(0, eq)] = a.substring(eq + 1);
        }
        return 0;

      case 'unset':
        for (final k in args) {
          env.remove(k);
        }
        return 0;

      case 'which':
        return _cmdWhich(args, writeOut);

      case 'history':
        for (var i = 0; i < history.length; i++) {
          writeOut('${(i + 1).toString().padLeft(4)}  ${history[i]}\n');
        }
        return 0;

      case 'whoami':
        writeOut('${env['USER'] ?? 'makaw'}\n');
        return 0;

      case 'date':
        writeOut('${DateTime.now().toLocal()}\n');
        return 0;

      case 'uname':
        writeOut(
            'Makaw ${Platform.operatingSystem} (${Platform.version.split(' ').first}) ${Platform.operatingSystemVersion}\n');
        return 0;

      case 'bash':
      case 'zsh':
      case 'fish':
      case 'pwsh':
      case 'powershell':
      case 'cmd':
      case 'ubuntu':
      case 'wsl':
        return _cmdSwitchOrExplainShell(cmd, args, writeOut);

      default:
        return _runNativePassthrough(cmd, args, writeOut);
    }
  }

  int _cmdCd(List<String> args, void Function(String) writeOut) {
    final targetArg = args.isEmpty ? '~' : args.first;
    String next;
    if (targetArg == '-') {
      next = _prevCwd;
    } else if (targetArg == '~') {
      next = env['HOME'] ?? _cwd;
    } else {
      next = _resolvePath(targetArg);
    }
    final dir = Directory(next);
    if (!dir.existsSync()) {
      writeOut('\x1b[31mcd: no such directory: $targetArg\x1b[0m\n');
      return 1;
    }
    _prevCwd = _cwd;
    _cwd = p.normalize(dir.absolute.path);
    env['PWD'] = _cwd;
    env['OLDPWD'] = _prevCwd;
    onCwdChanged?.call(_cwd);
    return 0;
  }

  int _cmdLs(List<String> args, void Function(String) writeOut) {
    var showAll = false;
    var longFmt = false;
    final paths = <String>[];
    for (final a in args) {
      if (a.startsWith('-')) {
        if (a.contains('a')) showAll = true;
        if (a.contains('l')) longFmt = true;
      } else {
        paths.add(a);
      }
    }
    final targetPath = _resolvePath(paths.isEmpty ? '.' : paths.first);
    final dir = Directory(targetPath);
    if (!dir.existsSync()) {
      final f = File(targetPath);
      if (f.existsSync()) {
        writeOut('${p.basename(f.path)}\n');
        return 0;
      }
      writeOut('\x1b[31mls: cannot access $targetPath\x1b[0m\n');
      return 1;
    }
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync();
    } catch (e) {
      writeOut('\x1b[31mls: permission denied: $e\x1b[0m\n');
      return 1;
    }
    entries.sort((a, b) {
      final aDir = a is Directory ? 0 : 1;
      final bDir = b is Directory ? 0 : 1;
      if (aDir != bDir) return aDir.compareTo(bDir);
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });

    for (final e in entries) {
      final name = p.basename(e.path);
      if (!showAll && name.startsWith('.')) continue;
      final isDir = e is Directory;
      final colored = isDir ? '\x1b[34m$name/\x1b[0m' : name;
      if (longFmt) {
        final stat = e.statSync();
        final sizeStr = isDir ? '<DIR>' : _fmtSize(stat.size);
        final ts = stat.modified.toLocal().toString().substring(0, 16);
        writeOut('${isDir ? 'd' : '-'}rwx  ${sizeStr.padLeft(8)}  $ts  $colored\n');
      } else {
        writeOut('$colored\n');
      }
    }
    return 0;
  }

  int _cmdTree(List<String> args, void Function(String) writeOut) {
    var maxDepth = 3;
    String target = '.';
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '-L' && i + 1 < args.length) {
        maxDepth = int.tryParse(args[++i]) ?? 3;
      } else if (!args[i].startsWith('-')) {
        target = args[i];
      }
    }
    final root = Directory(_resolvePath(target));
    if (!root.existsSync()) {
      writeOut('\x1b[31mtree: directory not found: $target\x1b[0m\n');
      return 1;
    }
    writeOut('\x1b[34m${root.path}\x1b[0m\n');
    void walk(Directory d, String indent, int depth) {
      if (depth >= maxDepth) return;
      List<FileSystemEntity> list;
      try {
        list = d.listSync()
          ..sort((a, b) =>
              p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      } catch (_) {
        return;
      }
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        final last = i == list.length - 1;
        final branch = last ? '└── ' : '├── ';
        writeOut('$indent$branch${e is Directory ? '\x1b[34m$name/\x1b[0m' : name}\n');
        if (e is Directory) {
          walk(e, '$indent${last ? '    ' : '│   '}', depth + 1);
        }
      }
    }

    walk(root, '', 0);
    return 0;
  }

  int _cmdCat(List<String> args, void Function(String) writeOut) {
    if (args.isEmpty) {
      writeOut('Usage: cat <file...>\n');
      return 1;
    }
    for (final a in args) {
      final f = File(_resolvePath(a));
      if (!f.existsSync()) {
        writeOut('\x1b[31mcat: $a: No such file\x1b[0m\n');
        return 1;
      }
      final content = f.readAsStringSync();
      writeOut(content.endsWith('\n') ? content : '$content\n');
    }
    return 0;
  }

  int _cmdHeadTail(List<String> args,
      {required bool isHead, required void Function(String) writeOut}) {
    var count = 10;
    final files = <String>[];
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '-n' && i + 1 < args.length) {
        count = int.tryParse(args[++i]) ?? 10;
      } else if (args[i].startsWith('-') && args[i].length > 1) {
        count = int.tryParse(args[i].substring(1)) ?? count;
      } else {
        files.add(args[i]);
      }
    }
    if (files.isEmpty) {
      writeOut('Usage: ${isHead ? 'head' : 'tail'} [-n N] <file>\n');
      return 1;
    }
    final f = File(_resolvePath(files.first));
    if (!f.existsSync()) {
      writeOut('\x1b[31mNo such file: ${files.first}\x1b[0m\n');
      return 1;
    }
    final lines = const LineSplitter().convert(f.readAsStringSync());
    final slice = isHead
        ? lines.take(count)
        : lines.skip((lines.length - count).clamp(0, lines.length));
    for (final l in slice) {
      writeOut('$l\n');
    }
    return 0;
  }

  int _cmdWc(List<String> args, void Function(String) writeOut) {
    final files = args.where((a) => !a.startsWith('-')).toList();
    if (files.isEmpty) {
      writeOut('Usage: wc <file>\n');
      return 1;
    }
    for (final name in files) {
      final f = File(_resolvePath(name));
      if (!f.existsSync()) {
        writeOut('\x1b[31mwc: $name: No such file\x1b[0m\n');
        return 1;
      }
      final text = f.readAsStringSync();
      final lines = '\n'.allMatches(text).length;
      final words = text.trim().isEmpty
          ? 0
          : text.trim().split(RegExp(r'\s+')).length;
      final bytes = utf8.encode(text).length;
      writeOut('${lines.toString().padLeft(6)} ${words.toString().padLeft(6)} ${bytes.toString().padLeft(7)} $name\n');
    }
    return 0;
  }

  int _cmdTouch(List<String> args, void Function(String) writeOut) {
    if (args.isEmpty) {
      writeOut('Usage: touch <file...>\n');
      return 1;
    }
    for (final a in args) {
      final f = File(_resolvePath(a));
      f.parent.createSync(recursive: true);
      if (!f.existsSync()) {
        f.createSync();
      } else {
        f.setLastModifiedSync(DateTime.now());
      }
    }
    return 0;
  }

  int _cmdMkdir(List<String> args, void Function(String) writeOut) {
    final recursive = args.contains('-p');
    final dirs = args.where((a) => !a.startsWith('-')).toList();
    if (dirs.isEmpty) {
      writeOut('Usage: mkdir [-p] <dir...>\n');
      return 1;
    }
    for (final d in dirs) {
      Directory(_resolvePath(d)).createSync(recursive: recursive);
    }
    return 0;
  }

  int _cmdCp(List<String> args, void Function(String) writeOut) {
    final recursive = args.any((a) => a == '-r' || a == '-R' || a == '-a');
    final paths = args.where((a) => !a.startsWith('-')).toList();
    if (paths.length < 2) {
      writeOut('Usage: cp [-r] <src> <dst>\n');
      return 1;
    }
    final srcPath = _resolvePath(paths[0]);
    var dstPath = _resolvePath(paths[1]);
    if (File(srcPath).existsSync()) {
      if (Directory(dstPath).existsSync()) {
        dstPath = p.join(dstPath, p.basename(srcPath));
      }
      File(dstPath).parent.createSync(recursive: true);
      File(srcPath).copySync(dstPath);
      return 0;
    }
    final srcDir = Directory(srcPath);
    if (srcDir.existsSync()) {
      if (!recursive) {
        writeOut('\x1b[31mcp: omitting directory $srcPath (use -r)\x1b[0m\n');
        return 1;
      }
      _copyDirSync(srcDir, Directory(dstPath));
      return 0;
    }
    writeOut('\x1b[31mcp: cannot stat ${paths[0]}\x1b[0m\n');
    return 1;
  }

  void _copyDirSync(Directory src, Directory dst) {
    dst.createSync(recursive: true);
    for (final entity in src.listSync()) {
      final target = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyDirSync(entity, Directory(target));
      } else if (entity is File) {
        entity.copySync(target);
      }
    }
  }

  int _cmdMv(List<String> args, void Function(String) writeOut) {
    final paths = args.where((a) => !a.startsWith('-')).toList();
    if (paths.length < 2) {
      writeOut('Usage: mv <src> <dst>\n');
      return 1;
    }
    final src = _resolvePath(paths[0]);
    var dst = _resolvePath(paths[1]);
    if (Directory(dst).existsSync()) {
      dst = p.join(dst, p.basename(src));
    }
    if (File(src).existsSync()) {
      File(src).renameSync(dst);
      return 0;
    }
    if (Directory(src).existsSync()) {
      Directory(src).renameSync(dst);
      return 0;
    }
    writeOut('\x1b[31mmv: cannot stat ${paths[0]}\x1b[0m\n');
    return 1;
  }

  int _cmdRm(List<String> args, void Function(String) writeOut) {
    var recursive = false;
    var force = false;
    final targets = <String>[];
    for (final a in args) {
      if (a.startsWith('-')) {
        if (a.contains('r') || a.contains('R')) recursive = true;
        if (a.contains('f')) force = true;
      } else {
        targets.add(a);
      }
    }
    if (targets.isEmpty) {
      writeOut('Usage: rm [-rf] <path...>\n');
      return 1;
    }
    for (final t in targets) {
      final resolved = _resolvePath(t);
      if (File(resolved).existsSync()) {
        File(resolved).deleteSync();
      } else if (Directory(resolved).existsSync()) {
        if (!recursive) {
          writeOut('\x1b[31mrm: $t is a directory (use -r)\x1b[0m\n');
          return 1;
        }
        Directory(resolved).deleteSync(recursive: true);
      } else if (!force) {
        writeOut('\x1b[31mrm: cannot remove $t: No such file or directory\x1b[0m\n');
        return 1;
      }
    }
    return 0;
  }

  int _cmdStat(List<String> args, void Function(String) writeOut) {
    if (args.isEmpty) {
      writeOut('Usage: stat <path>\n');
      return 1;
    }
    final resolved = _resolvePath(args.first);
    final stat = FileStat.statSync(resolved);
    if (stat.type == FileSystemEntityType.notFound) {
      writeOut('\x1b[31mstat: not found: ${args.first}\x1b[0m\n');
      return 1;
    }
    writeOut('Path:     $resolved\nType:     ${stat.type}\nSize:     ${stat.size} bytes (${_fmtSize(stat.size)})\nModified: ${stat.modified.toLocal()}\nMode:     ${stat.modeString()}\n');
    return 0;
  }

  int _cmdGrep(List<String> args, void Function(String) writeOut) {
    var ignoreCase = false;
    var lineNum = false;
    var recursive = false;
    final positional = <String>[];
    for (final a in args) {
      if (a.startsWith('-') && a.length > 1) {
        if (a.contains('i')) ignoreCase = true;
        if (a.contains('n')) lineNum = true;
        if (a.contains('r') || a.contains('R')) recursive = true;
      } else {
        positional.add(a);
      }
    }
    if (positional.length < 2) {
      writeOut('Usage: grep [-inr] <pattern> <path...>\n');
      return 1;
    }
    final pattern = RegExp(positional.first, caseSensitive: !ignoreCase);
    var hits = 0;

    void searchFile(File f, {required bool prefixFile}) {
      try {
        final lines = const LineSplitter().convert(f.readAsStringSync());
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) {
            hits++;
            final pre = StringBuffer();
            if (prefixFile) pre.write('\x1b[35m${f.path}\x1b[0m:');
            if (lineNum) pre.write('\x1b[32m${i + 1}\x1b[0m:');
            writeOut('$pre${lines[i]}\n');
          }
        }
      } catch (_) {}
    }

    for (final rawPath in positional.sublist(1)) {
      final resolved = _resolvePath(rawPath);
      if (File(resolved).existsSync()) {
        searchFile(File(resolved), prefixFile: positional.length > 2);
      } else if (Directory(resolved).existsSync() && recursive) {
        for (final e in Directory(resolved).listSync(recursive: true)) {
          if (e is File) searchFile(e, prefixFile: true);
        }
      }
    }
    return hits > 0 ? 0 : 1;
  }

  int _cmdFind(List<String> args, void Function(String) writeOut) {
    String rootArg = '.';
    String? nameGlob;
    for (var i = 0; i < args.length; i++) {
      if ((args[i] == '-name' || args[i] == '-iname') && i + 1 < args.length) {
        nameGlob = args[++i];
      } else if (!args[i].startsWith('-')) {
        rootArg = args[i];
      }
    }
    final root = Directory(_resolvePath(rootArg));
    if (!root.existsSync()) {
      writeOut('\x1b[31mfind: $rootArg: No such directory\x1b[0m\n');
      return 1;
    }
    final regex = nameGlob != null ? _globToRegex(nameGlob) : null;
    for (final entity in root.listSync(recursive: true)) {
      final base = p.basename(entity.path);
      if (regex == null || regex.hasMatch(base)) {
        writeOut('${entity.path}\n');
      }
    }
    return 0;
  }

  Future<int> _cmdZip(List<String> args, void Function(String) writeOut) async {
    if (args.length < 2) {
      writeOut('Usage: zip <output.zip> <paths...>\n');
      return 1;
    }
    final outPath = _resolvePath(args.first);
    final sources = args.sublist(1).map(_resolvePath).toList();
    final res = await ArchiveService.createZip(
      sourcePaths: sources,
      outputZipPath: outPath,
    );
    writeOut('${res.message}\n');
    return res.success ? 0 : 1;
  }

  Future<int> _cmdUnzip(List<String> args, void Function(String) writeOut) async {
    String? dest;
    final archives = <String>[];
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '-d' && i + 1 < args.length) {
        dest = _resolvePath(args[++i]);
      } else if (!args[i].startsWith('-')) {
        archives.add(args[i]);
      }
    }
    if (archives.isEmpty) {
      writeOut('Usage: unzip <archive.zip> [-d dest]\n');
      return 1;
    }
    final archivePath = _resolvePath(archives.first);
    dest ??= p.dirname(archivePath);
    final res = await ArchiveService.extractArchive(
      archivePath: archivePath,
      destinationDir: dest,
    );
    writeOut('${res.message}\n');
    return res.success ? 0 : 1;
  }

  Future<int> _cmdTar(List<String> args, void Function(String) writeOut) async {
    // Support pure-Dart extraction (`tar -xf file.tar.gz [-C dest]`) via ArchiveService.
    final xfIdx = args.indexWhere((a) => a.contains('f'));
    if (xfIdx >= 0 && xfIdx + 1 < args.length && args.any((a) => a.contains('x'))) {
      final archivePath = _resolvePath(args[xfIdx + 1]);
      var dest = _cwd;
      final cIdx = args.indexOf('-C');
      if (cIdx >= 0 && cIdx + 1 < args.length) dest = _resolvePath(args[cIdx + 1]);
      final res = await ArchiveService.extractArchive(
        archivePath: archivePath,
        destinationDir: dest,
      );
      writeOut('${res.message}\n');
      return res.success ? 0 : 1;
    }
    return _runNativePassthrough('tar', args, writeOut);
  }

  Future<int> _cmdHttp(
    String cmd,
    List<String> args,
    void Function(String) writeOut,
  ) async {
    var method = 'GET';
    var headOnly = false;
    var followRedirects = true;
    String? outFile;
    String? body;
    final headers = <String, String>{};
    String? url;

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '-I' || a == '--head') {
        headOnly = true;
        method = 'HEAD';
      } else if (a == '-X' && i + 1 < args.length) {
        method = args[++i].toUpperCase();
      } else if (a == '-L') {
        followRedirects = true;
      } else if ((a == '-H' || a == '--header') && i + 1 < args.length) {
        final hdr = args[++i];
        final colon = hdr.indexOf(':');
        if (colon > 0) {
          headers[hdr.substring(0, colon).trim()] = hdr.substring(colon + 1).trim();
        }
      } else if ((a == '-d' || a == '--data') && i + 1 < args.length) {
        body = args[++i];
        if (method == 'GET') method = 'POST';
      } else if ((a == '-o' || a == '-O') && i + 1 < args.length) {
        outFile = _resolvePath(args[++i]);
      } else if (!a.startsWith('-')) {
        url = a;
      }
    }

    if (url == null || url.isEmpty) {
      writeOut('Usage: $cmd [-I] [-X METHOD] [-H "K: V"] [-d body] [-o file] <url>\n');
      return 1;
    }
    final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    if (uri == null || !uri.hasAuthority) {
      writeOut('\x1b[31m$cmd: invalid URL: $url\x1b[0m\n');
      return 1;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(method, uri);
      req.followRedirects = followRedirects;
      headers.forEach(req.headers.set);
      if (body != null) req.write(body);
      final resp = await req.close();
      final bytes = await resp.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));

      if (headOnly) {
        writeOut('HTTP ${resp.statusCode} ${resp.reasonPhrase}\n');
        resp.headers.forEach((k, vals) => writeOut('$k: ${vals.join(', ')}\n'));
      }
      if (outFile != null || (cmd == 'wget' && outFile == null)) {
        final savePath = outFile ??
            _resolvePath(uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
                ? 'index.html'
                : uri.pathSegments.last);
        await File(savePath).parent.create(recursive: true);
        await File(savePath).writeAsBytes(bytes);
        writeOut('Saved ${_fmtSize(bytes.length)} -> $savePath (HTTP ${resp.statusCode})\n');
      } else if (!headOnly) {
        writeOut('${utf8.decode(bytes, allowMalformed: true)}\n');
      }
      return resp.statusCode >= 400 ? 1 : 0;
    } catch (e) {
      writeOut('\x1b[31m$cmd: request failed: $e\x1b[0m\n');
      return 1;
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _cmdGit(List<String> args, void Function(String) writeOut) async {
    // 1) Try native OS git binary first (Desktop or Termux).
    try {
      final probe = await Process.run('git', ['--version']);
      if (probe.exitCode == 0) {
        return _runNativePassthrough('git', args, writeOut);
      }
    } catch (_) {}

    // 2) Pure-Dart fallback inspection for stock Android repos (.git/).
    final gitDir = Directory(p.join(_cwd, '.git'));
    if (!gitDir.existsSync()) {
      writeOut('\x1b[33mgit: native git binary unavailable & no .git/ in $_cwd\x1b[0m\n'
          'Tip: connect a remote host via \x1b[36mssh user@host\x1b[0m or pair your Desktop workstation.\n');
      return 1;
    }
    final sub = args.isEmpty ? 'status' : args.first;
    final headFile = File(p.join(gitDir.path, 'HEAD'));
    final head = headFile.existsSync() ? headFile.readAsStringSync().trim() : 'detached';
    final branch = head.startsWith('ref: ') ? head.split('/').last : head;

    if (sub == 'branch') {
      final headsDir = Directory(p.join(gitDir.path, 'refs', 'heads'));
      if (headsDir.existsSync()) {
        for (final e in headsDir.listSync()) {
          final b = p.basename(e.path);
          writeOut('${b == branch ? '* \x1b[32m' : '  '}$b\x1b[0m\n');
        }
      } else {
        writeOut('* $branch\n');
      }
      return 0;
    }
    if (sub == 'status') {
      writeOut('On branch \x1b[36m$branch\x1b[0m (Makaw pure-Dart inspection)\n');
      return 0;
    }
    if (sub == 'remote') {
      final cfg = File(p.join(gitDir.path, 'config'));
      if (cfg.existsSync()) writeOut('${cfg.readAsStringSync()}\n');
      return 0;
    }
    writeOut('On branch $branch. Full "$sub" requires native git (run inside SSH/Desktop workstation).\n');
    return 1;
  }

  Future<int> _cmdHosts(void Function(String) writeOut) async {
    final hosts = await onListSshHosts?.call() ?? const [];
    if (hosts.isEmpty) {
      writeOut('No saved SSH hosts yet. Tap Hosts in the top bar or run ssh user@host.\n');
      return 0;
    }
    for (final h in hosts) {
      writeOut('  \x1b[36m${h.name.padRight(18)}\x1b[0m ${h.displayTarget}  [${h.authMethod}${h.autoTmux ? ' + tmux' : ''}]\n');
    }
    return 0;
  }

  Future<int> _cmdSsh(List<String> args, void Function(String) writeOut) async {
    if (args.isEmpty) {
      await _cmdHosts(writeOut);
      writeOut('Usage: ssh <saved-name | user@host[:port]>\n');
      return 1;
    }
    if (onConnectSsh != null) {
      await onConnectSsh!(args.join(' '));
      return 0;
    }
    return _runNativePassthrough('ssh', args, writeOut);
  }

  Future<int> _cmdWhich(List<String> args, void Function(String) writeOut) async {
    if (args.isEmpty) return 1;
    final target = args.first;
    if (_builtInNames.contains(target)) {
      writeOut('$target: makaw-sh built-in\n');
      return 0;
    }
    final shells = await ShellDiscovery.discoverLocalShells();
    for (final s in shells) {
      if (s.id == target || s.label.toLowerCase().contains(target.toLowerCase())) {
        writeOut('${s.executable}\n');
        return 0;
      }
    }
    return _runNativePassthrough('which', args, writeOut);
  }

  Future<int> _cmdSwitchOrExplainShell(
    String shellName,
    List<String> args,
    void Function(String) writeOut,
  ) async {
    // Allow inline `-c "command"` execution if OS shell exists.
    final available = await ShellDiscovery.discoverLocalShells();
    final match = available.where((p) =>
        p.id.toLowerCase() == shellName ||
        p.id.toLowerCase().startsWith('$shellName:') ||
        p.label.toLowerCase().contains(shellName));
    if (match.isNotEmpty && !match.first.isHybridBuiltIn) {
      if (args.isNotEmpty) {
        return _runNativePassthrough(match.first.executable, [...match.first.arguments, ...args], writeOut);
      }
      if (onSwitchShell != null) {
        writeOut('\x1b[36mSwitching tab to ${match.first.label}...\x1b[0m\n');
        await onSwitchShell!(match.first.id);
        return 0;
      }
    }
    writeOut('\x1b[33mShell "$shellName" is not installed locally on ${Platform.operatingSystem}.\x1b[0m\n'
        'You can continue using \x1b[36mmakaw-sh\x1b[0m locally OR connect to a Linux/Windows workstation via \x1b[36mssh user@host\x1b[0m or the Hosts menu.\n');
    return 1;
  }

  Future<int> _runNativePassthrough(
    String cmd,
    List<String> args,
    void Function(String) writeOut,
  ) async {
    try {
      final Process proc;
      if (Platform.isWindows) {
        proc = await Process.start(
          'cmd.exe',
          ['/c', cmd, ...args],
          workingDirectory: _cwd,
        );
      } else {
        proc = await Process.start(
          cmd,
          args,
          workingDirectory: _cwd,
          environment: {...Platform.environment, ...env},
        );
      }
      _activeChild = proc;
      final subOut = proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((s) => _emit(s.replaceAll('\n', '\r\n')));
      final subErr = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((s) => _emit('\x1b[31m${s.replaceAll('\n', '\r\n')}\x1b[0m'));
      final code = await proc.exitCode;
      await subOut.cancel();
      await subErr.cancel();
      _activeChild = null;
      return code;
    } on ProcessException {
      writeOut('\x1b[31m$cmd: command not found\x1b[0m (type \x1b[36mhelp\x1b[0m or \x1b[36mssh user@host\x1b[0m)\n');
      return 127;
    } catch (e) {
      writeOut('\x1b[31m$cmd failed: $e\x1b[0m\n');
      return 1;
    } finally {
      _activeChild = null;
    }
  }

  void close([int code = 0]) {
    if (_closed) return;
    _closed = true;
    try {
      _activeChild?.kill();
    } catch (_) {}
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
    if (!_outCtrl.isClosed) _outCtrl.close();
  }

  String _resolvePath(String raw) {
    var expanded = _expandEnv(raw).trim();
    if (expanded == '~') return env['HOME'] ?? _cwd;
    if (expanded.startsWith('~/') || expanded.startsWith(r'~\')) {
      expanded = p.join(env['HOME'] ?? _cwd, expanded.substring(2));
    }
    return p.normalize(p.isAbsolute(expanded) ? expanded : p.join(_cwd, expanded));
  }

  String _expandEnv(String raw) {
    return raw.replaceAllMapped(RegExp(r'\$\{?([A-Za-z0-9_?]+)\}?'), (m) {
      final key = m.group(1)!;
      if (key == '?') return '$_lastExitCode';
      return env[key] ?? Platform.environment[key] ?? '';
    });
  }

  /// Splits shell statements on `&&` and `;` outside quotes.
  static List<({String text, String connector})> _splitStatements(String line) {
    final result = <({String text, String connector})>[];
    final buf = StringBuffer();
    var inSingle = false;
    var inDouble = false;

    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == "'" && !inDouble) {
        inSingle = !inSingle;
        buf.write(ch);
      } else if (ch == '"' && !inSingle) {
        inDouble = !inDouble;
        buf.write(ch);
      } else if (!inSingle && !inDouble) {
        if (ch == '&' && i + 1 < line.length && line[i + 1] == '&') {
          result.add((text: buf.toString(), connector: '&&'));
          buf.clear();
          i++;
          continue;
        }
        if (ch == ';') {
          result.add((text: buf.toString(), connector: ';'));
          buf.clear();
          continue;
        }
        buf.write(ch);
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) result.add((text: buf.toString(), connector: ''));
    return result;
  }

  /// POSIX-style quote-aware argument tokenizer.
  static List<String> tokenize(String input) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    var hasToken = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == r'\' && !inSingle && i + 1 < input.length) {
        buf.write(input[++i]);
        hasToken = true;
      } else if (ch == "'" && !inDouble) {
        inSingle = !inSingle;
        hasToken = true;
      } else if (ch == '"' && !inSingle) {
        inDouble = !inDouble;
        hasToken = true;
      } else if (!inSingle && !inDouble && ch.trim().isEmpty) {
        if (hasToken) {
          tokens.add(buf.toString());
          buf.clear();
          hasToken = false;
        }
      } else {
        buf.write(ch);
        hasToken = true;
      }
    }
    if (hasToken) tokens.add(buf.toString());
    return tokens;
  }

  static RegExp _globToRegex(String glob) {
    final escaped = RegExp.escape(glob)
        .replaceAll(r'\*', '.*')
        .replaceAll(r'\?', '.');
    return RegExp('^$escaped\$', caseSensitive: false);
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }

  static const Set<String> _builtInNames = {
    'help', 'mk', 'clear', 'cls', 'exit', 'quit', 'pwd', 'cd', 'ls', 'dir',
    'tree', 'cat', 'head', 'tail', 'wc', 'touch', 'mkdir', 'cp', 'mv', 'rm',
    'stat', 'grep', 'find', 'zip', 'unzip', 'tar', 'curl', 'wget', 'git',
    'hosts', 'ssh', 'open', 'edit', 'echo', 'env', 'export', 'unset', 'which',
    'history', 'whoami', 'date', 'uname', 'bash', 'zsh', 'pwsh', 'powershell',
    'cmd', 'ubuntu', 'wsl',
  };

  String _helpText() => '''
\x1b[36mMakaw Hybrid Shell (makaw-sh)\x1b[0m
  \x1b[33mFiles & Nav:\x1b[0m  pwd, cd [dir|~|-], ls [-la], tree [-L n], cat, head, tail, wc
               touch, mkdir [-p], cp [-r], mv, rm [-rf], stat, grep [-inr], find [-name]
  \x1b[33mArchives:\x1b[0m     zip <out.zip> <paths...>, unzip <file.zip> [-d dir], tar -xf
  \x1b[33mNetwork:\x1b[0m      curl [-I|-X|-H|-d|-o] <url>, wget [-O] <url>
  \x1b[33mRemote/Git:\x1b[0m   hosts, ssh <name|user@host[:port]>, git <status|branch|remote>, open <file>
  \x1b[33mShell/Misc:\x1b[0m   pwsh, bash, zsh, ubuntu, wsl, env, export K=V, which, history, clear, exit
''';
}
