import 'dart:io';

/// Lightweight Git integration for a project rooted at [root], invoking the
/// real `git` CLI so workflows match what developers already know.
class GitService {
  final Directory root;

  GitService(this.root);

  bool get isRepo {
    if (!root.existsSync()) return false;
    return Directory('${root.path}${Platform.pathSeparator}.git').existsSync() ||
        File('${root.path}${Platform.pathSeparator}.git').existsSync();
  }

  Future<String?> _run(List<String> args) async {
    try {
      final r = await Process.run(
        'git',
        ['--no-optional-locks', ...args],
        workingDirectory: root.path,
      );
      return r.exitCode == 0 ? (r.stdout as String) : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ok(List<String> args) async {
    try {
      final r = await Process.run('git', args, workingDirectory: root.path);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<GitStatus> status() async {
    if (!isRepo) return const GitStatus(entries: [], branch: '', aheadBehind: '');
    final out = await _run(['status', '--porcelain=v1', '-b']);
    if (out == null) {
      return const GitStatus(entries: [], branch: '', aheadBehind: '');
    }
    final entries = <GitStatusEntry>[];
    var branch = '';
    var aheadBehind = '';
    for (final line in out.split('\n')) {
      if (line.startsWith('## ')) {
        final head = line.substring(3).trim();
        final sep = head.indexOf('...');
        branch = sep >= 0 ? head.substring(0, sep) : head;
        if (sep >= 0) {
          final after = head.substring(sep + 3);
          final idx = after.indexOf(' [');
          aheadBehind = idx >= 0 ? after.substring(idx + 1) : '';
        }
      } else if (line.length >= 4) {
        final code = line.substring(0, 2);
        final rawPath = line.substring(3);
        String path = rawPath;
        var kind = GitEntryKind.modified;
        if (code.startsWith('??')) {
          kind = GitEntryKind.untracked;
        } else if (code.startsWith('A') || code.startsWith('R') || code.startsWith('C')) {
          kind = GitEntryKind.added;
        } else if (code.startsWith('D')) {
          kind = GitEntryKind.deleted;
        } else if (code.startsWith('U')) {
          kind = GitEntryKind.conflicted;
        }
        if (code.contains(' -> ')) {
          // rename/copy: "old -> new"
          final parts = rawPath.split(' -> ');
          path = parts.last;
        }
        final staged = code[0] != ' ' && code != '??' && code[0] != '?';
        entries.add(GitStatusEntry(
          path: path,
          kind: kind,
          staged: staged,
          shortCode: code,
        ));
      }
    }
    return GitStatus(entries: entries, branch: branch, aheadBehind: aheadBehind);
  }

  Future<List<String>> log(int count) async {
    final out = await _run(['log', '--oneline', '-${count < 1 ? 15 : count}']);
    if (out == null || out.trim().isEmpty) return const [];
    return out.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
  }

  Future<String?> diff(String path, {bool cached = false}) {
    final args = ['diff'];
    if (cached) args.add('--cached');
    args.addAll(['--', path]);
    return _run(args);
  }

  Future<bool> stage(String path) => _ok(['add', '--', path]);

  Future<bool> unstage(String path) => _ok(['restore', '--staged', '--', path]);

  /// Discards working-tree changes for [path] (files restored from HEAD).
  Future<bool> discard(String path) => _ok(['restore', '--', path]);

  Future<bool> stageAll() => _ok(['add', '-A']);

  Future<bool> commit(String message) => _ok(['commit', '-m', message]);

  /// Sets a repo-local git config key (e.g. user.name / user.email).
  Future<bool> config(String key, String value) => _ok(['config', key, value]);

  Future<bool> push() => _ok(['push']);

  Future<bool> pull() => _ok(['pull', '--ff-only']);

  Future<String?> currentBranch() async {
    final out = await _run(['branch', '--show-current']);
    if (out == null) return null;
    return out.trim().isEmpty ? null : out.trim();
  }
}

enum GitEntryKind { untracked, added, modified, deleted, conflicted }

class GitStatusEntry {
  final String path;
  final GitEntryKind kind;
  final bool staged;
  final String shortCode;

  const GitStatusEntry({
    required this.path,
    required this.kind,
    required this.staged,
    required this.shortCode,
  });
}

class GitStatus {
  final List<GitStatusEntry> entries;
  final String branch;
  final String aheadBehind;

  const GitStatus({required this.entries, required this.branch, required this.aheadBehind});

  bool get isEmpty => entries.isEmpty;
}