import 'dart:io';

/// A single code project that can be opened in the Makaw Code Studio IDE.
///
/// A project is a directory on disk containing source files. The IDE reads and
/// writes files inside [directory] and exposes them through a file explorer,
/// editor, terminal and live preview.
class StudioProject {
  final Directory directory;

  StudioProject(this.directory);

  String get name => directory.path.split(Platform.pathSeparator).last;

  String get path => directory.path;
}
