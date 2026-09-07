import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/git_service.dart';

/// VS Code-style Source Control panel backed by the real `git` CLI:
/// branch, staged/unstaged changes, stage/stage-all, commit, push/pull and a
/// recent commit log. Diffs open in a read-only viewer.
class SourceControlPanel extends StatefulWidget {
  final Directory projectDir;
  final void Function() onChanged;

  const SourceControlPanel({
    super.key,
    required this.projectDir,
    required this.onChanged,
  });

  @override
  State<SourceControlPanel> createState() => SourceControlPanelState();
}

class SourceControlPanelState extends State<SourceControlPanel> {
  late final GitService _git;
  GitStatus _status = const GitStatus(entries: [], branch: '', aheadBehind: '');
  List<String> _log = [];
  bool _busy = false;
  bool _isRepo = false;

  @override
  void initState() {
    super.initState();
    _git = GitService(widget.projectDir);
    _refresh();
  }

  /// Re-polls `git status`/`log`. Safe to call from the parent workspace after
  /// filesystem changes.
  Future<void> refresh() => _refresh();

  @override
  void didUpdateWidget(SourceControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectDir.path != widget.projectDir.path) {
      _status = const GitStatus(entries: [], branch: '', aheadBehind: '');
      _log = [];
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    final repo = _git.isRepo;
    _isRepo = repo;
    if (repo) {
      final status = await _git.status();
      final log = await _git.log(15);
      if (mounted) {
        setState(() {
          _status = status;
          _log = log;
        });
      }
    }
    _busy = false;
  }

  Future<void> _runAction(Future<bool> Function() action) async {
    final okb = await action();
    if (!okb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Operation failed')));
      }
    }
    await _refresh();
  }

  Future<void> _commit() async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Commit message', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'feat: describe your change',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF60A5FA))),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Commit')),
        ],
      ),
    );
    if (message != null && message.trim().isNotEmpty) {
      await _runAction(() => _git.commit(message.trim()));
    }
  }

  Future<void> _showDiff(GitStatusEntry entry) async {
    final text = await _git.diff(entry.path, cached: entry.staged) ?? '(no diff)';
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0B1121),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 760,
          height: 480,
          child: Column(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Icon(entry.staged ? Icons.pending_actions : Icons.change_history, size: 16, color: const Color(0xFF60A5FA)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(entry.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13))),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    text.isEmpty ? '(clean)' : text,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Path copied'), duration: Duration(seconds: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Colors.white12),
          Expanded(child: _buildBody()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.call_split, size: 16, color: Color(0xFF60A5FA)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isRepo && _status.branch.isNotEmpty ? _status.branch : 'Not a git repo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 16, color: Colors.white54),
            onPressed: _refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_git.isRepo) {
      return const Center(
        child: Text('No repository. Run "git init" in the project folder.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }
    final unstaged = _status.entries.where((e) => !e.staged).toList();
    final staged = _status.entries.where((e) => e.staged).toList();
    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        if (_status.aheadBehind.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(_status.aheadBehind,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        _buildSectionHeader('Staged ${staged.length > 0 ? '(${staged.length})' : ''}'),
        if (staged.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('No staged changes', style: TextStyle(color: Colors.white24, fontSize: 12)),
          )
        else
          for (final e in staged) _buildEntry(e),
        _buildSectionHeader('Changes ${unstaged.length > 0 ? '(${unstaged.length})' : ''}'),
        if (unstaged.isEmpty && staged.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('Working tree clean', style: TextStyle(color: Colors.white24, fontSize: 12)),
          )
        else
          for (final e in unstaged) _buildEntry(e),
        _buildSectionHeader('Log'),
        for (final l in _log.take(10))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontFamily: 'monospace', fontSize: 11.5)),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Text(title, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
    );
  }

  Widget _buildEntry(GitStatusEntry e) {
    return InkWell(
      onTap: () => _showDiff(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _statusIcon(e),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.path, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontFamily: 'monospace')),
                  if (e.shortCode.isNotEmpty)
                    Text(e.shortCode, style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.more_horiz, size: 14, color: Colors.white38),
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onSelected: (action) async {
                switch (action) {
                    case 'stage':
                      await _runAction(() => _git.stage(e.path));
                    case 'unstage':
                      await _runAction(() => _git.unstage(e.path));
                    case 'discard_work':
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E293B),
                          title: const Text('Discard changes?', style: TextStyle(color: Colors.white, fontSize: 16)),
                          content: Text(e.path, style: const TextStyle(color: Colors.white70)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard', style: TextStyle(color: Colors.redAccent))),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await _runAction(() => _git.discard(e.path));
                      }
                    case 'discard_staged':
                      if (e.staged) {
                        await _runAction(() => _git.unstage(e.path));
                        await _runAction(() => _git.discard(e.path));
                      }
                    case 'diff':
                      _showDiff(e);
                    case 'copy':
                      await copyToClipboard(e.path);
                  }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: e.staged ? 'unstage' : 'stage', child: Text(e.staged ? 'Unstage' : 'Stage', style: const TextStyle(color: Colors.white, fontSize: 13))),
                const PopupMenuItem(value: 'diff', child: Text('Open Diff', style: TextStyle(color: Colors.white, fontSize: 13))),
                const PopupMenuItem(value: 'copy', child: Text('Copy Path', style: TextStyle(color: Colors.white, fontSize: 13))),
                if (!e.staged)
                  const PopupMenuItem(value: 'discard_work', child: Text('Discard Work', style: TextStyle(color: Colors.redAccent, fontSize: 13))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(GitStatusEntry e) {
    final (color, icon) = switch (e.kind) {
      GitEntryKind.untracked => (const Color(0xFF94A3B8), Icons.help_outline),
      GitEntryKind.added => (const Color(0xFF34D399), Icons.add_circle_outline),
      GitEntryKind.modified => (const Color(0xFFFBBF24), Icons.edit_outlined),
      GitEntryKind.deleted => (const Color(0xFFF87171), Icons.remove_circle_outline),
      GitEntryKind.conflicted => (const Color(0xFFF87171), Icons.error_outline),
    };
    return Icon(icon, size: 15, color: color);
  }

  Widget _buildFooter() {
    return _git.isRepo
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Commit',
                  icon: const Icon(Icons.verified_outlined, size: 18, color: Color(0xFF60A5FA)),
                  onPressed: _status.entries.isEmpty ? null : _commit,
                ),
                IconButton(
                  tooltip: 'Push',
                  icon: const Icon(Icons.upload_rounded, size: 18, color: Colors.white54),
                  onPressed: () => _runAction(() => _git.push()),
                ),
                IconButton(
                  tooltip: 'Pull',
                  icon: const Icon(Icons.download_rounded, size: 18, color: Colors.white54),
                  onPressed: () => _runAction(() => _git.pull()),
                ),
                IconButton(
                  tooltip: 'Stage All',
                  icon: const Icon(Icons.add_box_outlined, size: 18, color: Colors.white54),
                  onPressed: () => _runAction(() => _git.stageAll()), 
                ),
                const Spacer(),
                Text('${_status.entries.length} change(s)',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          )
        : const SizedBox.shrink();
  }
}