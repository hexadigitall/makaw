import 'package:xterm/xterm.dart';

class MakawTerminalEngine {
  final Terminal terminal = Terminal(maxLines: 10000);

  void startSession({String? workingDirectory}) {
    terminal.write('\r\n\x1b[33mTerminal not available on web.\x1b[0m\r\n');
  }

  void writeCommand(String cmd) {}

  void dispose() {}
}
