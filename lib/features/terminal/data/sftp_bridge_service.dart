import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../domain/terminal_models.dart';
import 'ssh_terminal_transport.dart';
import 'ssh_vault_service.dart';

/// Remote entry returned by [SftpBridgeService.listDirectory].
class SftpRemoteEntry {
  final String name;
  final String fullPath;
  final bool isDir;
  final int size;
  final DateTime? modifyTime;

  const SftpRemoteEntry({
    required this.name,
    required this.fullPath,
    required this.isDir,
    required this.size,
    this.modifyTime,
  });
}

/// Pure-Dart SFTP client wrapper allowing mobile & desktop Makaw users to
/// browse remote workstation/server folders, read & edit remote source files,
/// and sync changes back directly over SSH2 without OS native binaries.
class SftpBridgeService {
  final SshHostProfile host;
  final SshVaultService vault;
  final Future<String?> Function(String prompt)? onPromptPassword;

  SSHClient? _client;
  SftpClient? _sftp;

  SftpBridgeService({
    required this.host,
    required this.vault,
    this.onPromptPassword,
  });

  bool get isConnected => _client != null && !_client!.isClosed && _sftp != null;

  /// Joins POSIX remote paths reliably regardless of client host OS (Windows).
  static String joinPosix(String dir, String name) {
    if (name.startsWith('/')) return name;
    final cleanDir = dir.trim().isEmpty ? '/' : dir.trim();
    if (cleanDir == '/') return '/$name';
    return cleanDir.endsWith('/') ? '$cleanDir$name' : '$cleanDir/$name';
  }

  /// Computes parent POSIX path cleanly.
  static String parentPosix(String path) {
    final clean = path.trim();
    if (clean.isEmpty || clean == '/') return '/';
    final trimmed = clean.endsWith('/') && clean.length > 1
        ? clean.substring(0, clean.length - 1)
        : clean;
    final idx = trimmed.lastIndexOf('/');
    if (idx <= 0) return '/';
    return trimmed.substring(0, idx);
  }

  Future<SftpClient> ensureConnected() async {
    if (isConnected) return _sftp!;
    _client = await SshClientFactory.connect(
      host: host,
      vault: vault,
      onPromptPassword: onPromptPassword,
    );
    _sftp = await _client!.sftp();
    return _sftp!;
  }

  Future<String> resolveStartPath([String? preferred]) async {
    final sftp = await ensureConnected();
    final target = (preferred != null && preferred.trim().isNotEmpty)
        ? preferred.trim()
        : (host.defaultRemoteDir.trim().isNotEmpty
            ? host.defaultRemoteDir.trim()
            : '.');
    try {
      return await sftp.absolute(target);
    } catch (_) {
      return target == '.' ? '/' : target;
    }
  }

  Future<List<SftpRemoteEntry>> listDirectory(String remoteDir) async {
    final sftp = await ensureConnected();
    final raw = await sftp.listdir(remoteDir);
    final entries = <SftpRemoteEntry>[];
    for (final item in raw) {
      if (item.filename == '.' || item.filename == '..') continue;
      final isDir = item.attr.isDirectory;
      final full = joinPosix(remoteDir, item.filename);
      final mtime = item.attr.modifyTime != null
          ? DateTime.fromMillisecondsSinceEpoch(item.attr.modifyTime! * 1000)
          : null;
      entries.add(SftpRemoteEntry(
        name: item.filename,
        fullPath: full,
        isDir: isDir,
        size: item.attr.size ?? 0,
        modifyTime: mtime,
      ));
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<Uint8List> readBytes(String remotePath, {int maxBytes = 4 * 1024 * 1024}) async {
    final sftp = await ensureConnected();
    final file = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    try {
      final bytes = await file.readBytes(length: maxBytes);
      return bytes;
    } finally {
      await file.close();
    }
  }

  Future<String> readTextFile(String remotePath) async {
    final bytes = await readBytes(remotePath);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> writeBytes(String remotePath, Uint8List data) async {
    final sftp = await ensureConnected();
    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    try {
      await file.writeBytes(data);
    } finally {
      await file.close();
    }
  }

  Future<void> writeTextFile(String remotePath, String content) async {
    await writeBytes(remotePath, Uint8List.fromList(utf8.encode(content)));
  }

  Future<File> downloadToLocal(String remotePath, String localDestPath) async {
    final sftp = await ensureConnected();
    final out = File(localDestPath);
    await out.parent.create(recursive: true);
    final sink = out.openWrite();
    try {
      await sftp.download(remotePath, sink);
      await sink.flush();
    } finally {
      await sink.close();
    }
    return out;
  }

  Future<void> uploadFromLocal(String localPath, String remoteDestPath) async {
    final bytes = await File(localPath).readAsBytes();
    await writeBytes(remoteDestPath, bytes);
  }

  Future<void> mkdir(String remotePath) async {
    final sftp = await ensureConnected();
    await sftp.mkdir(remotePath);
  }

  Future<void> rename(String oldPath, String newPath) async {
    final sftp = await ensureConnected();
    await sftp.rename(oldPath, newPath);
  }

  Future<void> delete(String remotePath, {required bool isDir}) async {
    final sftp = await ensureConnected();
    if (isDir) {
      await sftp.rmdir(remotePath);
    } else {
      await sftp.remove(remotePath);
    }
  }

  /// Generates a clean local workspace cache path mirroring a remote file for
  /// local viewer/Studio inspection.
  static String localMirrorPath(String baseDir, SshHostProfile host, String remotePath) {
    final safeHost = host.host.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final rel = remotePath.replaceFirst(RegExp(r'^/+'), '');
    return p.join(baseDir, '.makaw_sftp', safeHost, rel);
  }

  void dispose() {
    try {
      _sftp?.close();
    } catch (_) {}
    try {
      _client?.close();
    } catch (_) {}
    _sftp = null;
    _client = null;
  }
}
