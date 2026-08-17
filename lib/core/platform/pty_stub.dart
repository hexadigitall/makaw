import 'dart:async';

class Pty {
  final Stream<List<int>> _output = const Stream.empty();
  final Completer<int> _exitCode = Completer<int>();

  Stream<List<int>> get output => _output;
  Future<int> get exitCode => _exitCode.future;

  void write(List<int> bytes) {}
  void kill() {}

  static Pty start(
    String executable, {
    List<String> arguments = const [],
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) {
    throw UnsupportedError('PTY is not supported on web');
  }
}
