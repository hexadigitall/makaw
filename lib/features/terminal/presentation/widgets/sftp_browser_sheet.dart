import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/ui/makaw_toast.dart';
import '../../data/sftp_bridge_service.dart';
import '../../data/shell_discovery.dart';
import '../../data/ssh_vault_service.dart';
import '../../domain/terminal_models.dart';

/// Interactive SFTP Explorer & Live Remote File Editor modal.
///
/// Connects cleanly over `dartssh2` (`SftpBridgeService`) on Android & Desktop,
/// lets users browse remote folders, edit source files directly & push (`Save
/// to Remote`), upload/download files, create folders/files, and rename/delete.
class SftpBrowserSheet extends StatefulWidget {
  final SshHostProfile host;
  final SshVaultService vault;
  final void Function(String remoteDir)? onOpenInTerminal;

  const SftpBrowserSheet({
    super.key,
    required this.host,
    required this.vault,
    this.onOpenInTerminal,
  });

  @override
  State<SftpBrowserSheet> createState() => _SftpBrowserSheetState();
}

class _SftpBrowserSheetState extends State<SftpBrowserSheet> {
  late final SftpBridgeService _sftp = SftpBridgeService(
    host: widget.host,
    vault: widget.vault,
    onPromptPassword: _promptSecret,
  );

  String _currentDir = '/';
  List<SftpRemoteEntry> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initConnect();
  }

  @override
  void dispose() {
    _sftp.dispose();
    super.dispose();
  }

  Future<String?> _promptSecret(String prompt) async {
    if (!mounted) return null;
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(prompt,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('Authenticate')),
        ],
      ),
    );
    ctrl.dispose();
    return res;
  }

  Future<void> _initConnect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final startDir = await _sftp.resolveStartPath();
      await _loadDir(startDir);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'SFTP connection failed: $e';
        });
      }
    }
  }

  Future<void> _loadDir(String dir) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _sftp.listDirectory(dir);
      if (!mounted) return;
      setState(() {
        _currentDir = dir;
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not list $dir: $e';
        });
      }
    }
  }

  Future<void> _openEditor(SftpRemoteEntry entry) async {
    setState(() => _loading = true);
    try {
      final content = await _sftp.readTextFile(entry.fullPath);
      if (!mounted) return;
      setState(() => _loading = false);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: const Color(0xFF090D16),
        builder: (_) => _RemoteTextEditorSheet(
          entry: entry,
          initialContent: content,
          onSaveRemote: (updated) => _sftp.writeTextFile(entry.fullPath, updated),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        MakawToast.error(context, 'Failed to read remote file: $e');
      }
    }
  }

  Future<void> _downloadEntry(SftpRemoteEntry entry) async {
    try {
      final base = Platform.isAndroid
          ? Directory(ShellDiscovery.resolveDefaultCwd('/storage/emulated/0/Download'))
          : await getDownloadsDirectory() ??
              Directory(ShellDiscovery.resolveDefaultCwd());
      final dest = p.join(base.path, 'Makaw_SFTP', widget.host.host, entry.name);
      await _sftp.downloadToLocal(entry.fullPath, dest);
      if (mounted) {
        MakawToast.success(context, 'Saved to $dest', title: 'SFTP Downloaded');
      }
    } catch (e) {
      if (mounted) MakawToast.error(context, 'Download failed: $e');
    }
  }

  Future<void> _uploadLocal() async {
    try {
      final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (picked == null || picked.files.isEmpty) return;
      setState(() => _loading = true);
      for (final f in picked.files) {
        if (f.path == null) continue;
        final dest = SftpBridgeService.joinPosix(_currentDir, f.name);
        await _sftp.uploadFromLocal(f.path!, dest);
      }
      await _loadDir(_currentDir);
      if (mounted) MakawToast.success(context, 'Uploaded via SFTP');
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        MakawToast.error(context, 'Upload failed: $e');
      }
    }
  }

  Future<void> _createItem({required bool isDir}) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(isDir ? 'New Remote Folder' : 'New Remote File',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: isDir ? 'folder_name' : 'script.py',
            hintStyle: const TextStyle(color: Colors.white38),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    final remotePath = SftpBridgeService.joinPosix(_currentDir, name);
    try {
      if (isDir) {
        await _sftp.mkdir(remotePath);
      } else {
        await _sftp.writeTextFile(remotePath, '');
      }
      await _loadDir(_currentDir);
    } catch (e) {
      if (mounted) MakawToast.error(context, 'Failed: $e');
    }
  }

  Future<void> _deleteEntry(SftpRemoteEntry entry) async {
    try {
      await _sftp.delete(entry.fullPath, isDir: entry.isDir);
      await _loadDir(_currentDir);
      if (mounted) MakawToast.info(context, 'Deleted ${entry.name}');
    } catch (e) {
      if (mounted) MakawToast.error(context, 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.88;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SFTP · ${widget.host.name}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                          Text(_currentDir,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Color(0xFF38BDF8), fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward,
                          color: Colors.white70, size: 19),
                      tooltip: 'Up folder',
                      onPressed: () =>
                          _loadDir(SftpBridgeService.parentPosix(_currentDir)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.upload_file_outlined,
                          color: Color(0xFF34D399), size: 19),
                      tooltip: 'Upload file',
                      onPressed: _uploadLocal,
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.add, color: Color(0xFF38BDF8)),
                      color: const Color(0xFF0F172A),
                      onSelected: (v) {
                        if (v == 'file') _createItem(isDir: false);
                        if (v == 'dir') _createItem(isDir: true);
                        if (v == 'refresh') _loadDir(_currentDir);
                        if (v == 'term') {
                          Navigator.of(context).pop();
                          widget.onOpenInTerminal?.call(_currentDir);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'file',
                            child: Text('New remote file',
                                style: TextStyle(color: Colors.white))),
                        PopupMenuItem(
                            value: 'dir',
                            child: Text('New remote folder',
                                style: TextStyle(color: Colors.white))),
                        PopupMenuItem(
                            value: 'refresh',
                            child: Text('Refresh',
                                style: TextStyle(color: Colors.white))),
                        PopupMenuItem(
                            value: 'term',
                            child: Text('Open SSH shell here',
                                style: TextStyle(color: Colors.white))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Color(0xFFF87171), size: 36),
                              const SizedBox(height: 10),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 12),
                              FilledButton(
                                  onPressed: _initConnect,
                                  child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : _entries.isEmpty
                        ? const Center(
                            child: Text('Remote directory is empty',
                                style: TextStyle(color: Colors.white54)))
                        : ListView.separated(
                            itemCount: _entries.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (_, idx) {
                              final e = _entries[idx];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  e.isDir
                                      ? Icons.folder_rounded
                                      : Icons.description_outlined,
                                  color: e.isDir
                                      ? const Color(0xFFFBBF24)
                                      : const Color(0xFF38BDF8),
                                ),
                                title: Text(e.name,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13.5)),
                                subtitle: Text(
                                  e.isDir ? 'Directory' : '${e.size} bytes',
                                  style: const TextStyle(
                                      color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!e.isDir)
                                      IconButton(
                                        icon: const Icon(Icons.download_rounded,
                                            color: Colors.white60, size: 18),
                                        tooltip: 'Download',
                                        onPressed: () => _downloadEntry(e),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Color(0xFFF87171), size: 18),
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteEntry(e),
                                    ),
                                  ],
                                ),
                                onTap: () => e.isDir
                                    ? _loadDir(e.fullPath)
                                    : _openEditor(e),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _RemoteTextEditorSheet extends StatefulWidget {
  final SftpRemoteEntry entry;
  final String initialContent;
  final Future<void> Function(String updated) onSaveRemote;

  const _RemoteTextEditorSheet({
    required this.entry,
    required this.initialContent,
    required this.onSaveRemote,
  });

  @override
  State<_RemoteTextEditorSheet> createState() => _RemoteTextEditorSheetState();
}

class _RemoteTextEditorSheetState extends State<_RemoteTextEditorSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialContent);
  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSaveRemote(_ctrl.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      MakawToast.success(context, 'Saved ${widget.entry.name} over SFTP');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        MakawToast.error(context, 'Save failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.88;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.entry.name}${_dirty ? ' *' : ''}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        widget.entry.fullPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: Text(_saving ? 'Pushing...' : 'Save Remote',
                      style: const TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                onChanged: (_) {
                  if (!_dirty) setState(() => _dirty = true);
                },
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 13,
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
