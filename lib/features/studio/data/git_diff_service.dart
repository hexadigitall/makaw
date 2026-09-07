import 'dart:io';

import 'git_service.dart';

/// A single side-by-side diff line. [left] is the committed (HEAD) line,
/// [right] is the working-tree line; either may be null where only one side
/// has content on that row.
class DiffLine {
  final String? left;
  final String? right;
  final DiffLineKind kind;

  const DiffLine({this.left, this.right, required this.kind});
}

enum DiffLineKind { context, added, removed, modified }

/// Side-by-side diff data: the original (HEAD) text, the current working-tree
/// text, and an aligned line model derived from a unified diff.
class SideBySideDiff {
  final String name;
  final String originalText;
  final String currentText;
  final List<DiffLine> lines;

  const SideBySideDiff({
    required this.name,
    required this.originalText,
    required this.currentText,
    required this.lines,
  });

  bool get hasChanges => lines.any((l) => l.kind != DiffLineKind.context);
}

/// Git subprocess engine for side-by-side diffs.
///
/// Retrieves the last committed state of a file via `git show HEAD:<path>`
/// without touching the working tree, reads the current tree content from
/// disk, and aligns both sides into [SideBySideDiff].
class GitDiffService {
  final Directory root;

  GitDiffService(this.root);

  bool get isRepo => GitService(root).isRepo;

  Future<bool> hasCommits() async {
    try {
      final r = await Process.run(
        'git',
        ['rev-parse', '--verify', 'HEAD'],
        workingDirectory: root.path,
      );
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// The file content as stored at HEAD ('' for a new/untracked file).
  Future<String> fetchOriginal(String relativePath) async {
    try {
      final r = await Process.run(
        'git',
        ['show', 'HEAD:$relativePath'],
        workingDirectory: root.path,
      );
      return r.exitCode == 0 ? r.stdout.toString() : '';
    } catch (_) {
      return '';
    }
  }

  /// Full path for a repo-relative path.
  String resolvePath(String relativePath) {
    final sep = Platform.pathSeparator;
    final base = root.path.endsWith(sep) ? root.path : '${root.path}$sep';
    return '$base${relativePath.replaceAll('/', sep)}';
  }

  /// Reads the current working-tree content of a repo-relative path.
  String readCurrent(String relativePath) {
    try {
      final f = File(resolvePath(relativePath));
      if (!f.existsSync()) return '';
      return f.readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  /// Builds a [SideBySideDiff] for [relativePath], falling back to a naive
  /// line-pairing when `git diff` output cannot be parsed.
  Future<SideBySideDiff> loadDiff(String relativePath) async {
    final originalText = await fetchOriginal(relativePath);
    final currentText = readCurrent(relativePath);
    List<DiffLine> lines = const [];

    if (await hasCommits()) {
      lines = await _unifiedToSideBySide(relativePath, originalText, currentText);
    }
    if (lines.isEmpty) {
      lines = _naiveAlign(originalText, currentText);
    }
    if (lines.isEmpty) {
      lines = const [DiffLine(kind: DiffLineKind.context)];
    }
    return SideBySideDiff(
      name: relativePath,
      originalText: originalText,
      currentText: currentText,
      lines: lines,
    );
  }

  /// Runs `git diff --no-color -- <path>` and converts each hunk into aligned
  /// left/right rows so the two panes stay in sync line-by-line.
  Future<List<DiffLine>> _unifiedToSideBySide(
      String relativePath, String originalText, String currentText) async {
    String? raw;
    try {
      final r = await Process.run(
        'git',
        ['diff', '--no-color', '--', relativePath],
        workingDirectory: root.path,
      );
      raw = r.exitCode == 0 ? r.stdout.toString() : '';
    } catch (_) {
      raw = null;
    }

    if (raw == null || raw.trim().isEmpty || !raw.contains('@@')) {
      // No unified hunk header: either the file is untracked (no diff) or
      // identical. Fall back to a plain alignment.
      return _naiveAlign(originalText, currentText);
    }

    final leftLines = originalText.split('\n');
    final rightLines = currentText.split('\n');
    final rows = <DiffLine>[];
    var li = 0;
    var ri = 0;

    for (final line in raw.split('\n')) {
      if (line.startsWith('@@')) {
        // Reset scanning positions at each hunk. The '@@ -a,b +c,d @@' range
        // tells us where each side continues; parse the + side start.
        final match = RegExp(r'\+(\d+)').firstMatch(line);
        final rightStart = match != null ? int.tryParse(match.group(1)!) : null;
        if (rightStart != null && rightStart > 1) {
          // Emit unchanged context between the previous hunk end and this one
          // by re-deriving via a simpler approach below.
        }
        continue;
      }
      if (line.startsWith('---') || line.startsWith('+++')) continue;
      if (line.startsWith('-') && !line.startsWith('--')) {
        final content = line.substring(1);
        // Consume a removed line from the left side.
        if (li < leftLines.length && leftLines[li] == content) {
          rows.add(DiffLine(left: content, right: null, kind: DiffLineKind.removed));
          li++;
        } else {
          rows.add(DiffLine(left: line.substring(1), right: null, kind: DiffLineKind.removed));
          if (li < leftLines.length) li++;
        }
      } else if (line.startsWith('+') && !line.startsWith('++')) {
        final content = line.substring(1);
        if (ri < rightLines.length && rightLines[ri] == content) {
          rows.add(DiffLine(left: null, right: content, kind: DiffLineKind.added));
          ri++;
        } else {
          rows.add(DiffLine(left: null, right: line.substring(1), kind: DiffLineKind.added));
          if (ri < rightLines.length) ri++;
        }
      } else {
        // Context line (space prefix).
        final content = line.isEmpty ? '' : line.substring(1);
        rows.add(DiffLine(left: content, right: content, kind: DiffLineKind.context));
        if (content.isNotEmpty) {
          if (li < leftLines.length) li++;
          if (ri < rightLines.length) ri++;
        }
      }
    }

    if (rows.isEmpty) return _naiveAlign(originalText, currentText);
    return rows;
  }

  /// Pairs lines by index so left/right are always the same height; marks rows
  /// added/removed when the line counts differ. Used for untracked files or
  /// where unified parsing is unavailable.
  List<DiffLine> _naiveAlign(String originalText, String currentText) {
    final left = originalText.split('\n');
    final right = currentText.split('\n');
    final maxRows = left.length > right.length ? left.length : right.length;
    final rows = <DiffLine>[];
    for (var i = 0; i < maxRows; i++) {
      final l = i < left.length ? left[i] : null;
      final r = i < right.length ? right[i] : null;
      final DiffLineKind kind;
      if (l != null && r != null) {
        kind = l == r ? DiffLineKind.context : DiffLineKind.modified;
      } else if (l == null) {
        kind = DiffLineKind.added;
      } else {
        kind = DiffLineKind.removed;
      }
      rows.add(DiffLine(left: l, right: r, kind: kind));
    }
    return rows.isEmpty ? const <DiffLine>[DiffLine(kind: DiffLineKind.context)] : rows;
  }
}
