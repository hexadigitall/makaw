import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/makaw_toast.dart';
import '../../application/terminal_runtime_manager.dart';
import '../../data/ai_tool_vault_service.dart';
import '../../data/continuum_sync_service.dart';
import '../../data/project_runbook_service.dart';
import '../../data/shell_discovery.dart';
import '../../data/toolchain_manager.dart';
import '../../data/workstation_companion_service.dart';

/// Unified Developer Ecosystem Hub for Makaw Terminal 2.0:
///   1. Toolchains, Package Installers & 1-Tap Git Repo Cloner
///   2. AI Tool Connector Vault (Gemini CLI / Claude Code / Codex / Ollama) & Error Doctor
///   3. Workstation Companion Host / Pair + Remote Desktop Folder Browser
///   4. Continuum Cross-Device Snapshot Sync
class DevEcosystemSheet extends StatefulWidget {
  final TerminalRuntimeManager manager;
  final int initialTab;

  const DevEcosystemSheet({
    super.key,
    required this.manager,
    this.initialTab = 0,
  });

  @override
  State<DevEcosystemSheet> createState() => _DevEcosystemSheetState();
}

class _DevEcosystemSheetState extends State<DevEcosystemSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.initialTab);

  List<ToolchainStatus>? _toolchains;
  List<AiToolConnector> _connectors = [];
  List<CompanionPairing> _pairings = [];
  ContinuumSnapshot? _lastSnap;
  bool _loadingTools = true;

  final _cloneCtrl = TextEditingController();
  final _pairUriCtrl = TextEditingController();
  final _cloudRoomCtrl = TextEditingController(text: 'makaw-workspace');
  final _handoffNoteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _cloneCtrl.dispose();
    _pairUriCtrl.dispose();
    _cloudRoomCtrl.dispose();
    _handoffNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final conns = await widget.manager.aiVault.loadConnectors();
    final savedPairs = await WorkstationCompanionClient.loadSaved();
    final snap = await widget.manager.continuum.loadLocalSnapshot();
    final chains = await ToolchainManager.probeAll();
    if (!mounted) return;
    setState(() {
      _connectors = conns;
      _pairings = savedPairs;
      _lastSnap = snap;
      _toolchains = chains;
      _loadingTools = false;
    });
  }

  void _runInActiveTerminal(String command) {
    Navigator.of(context).pop();
    widget.manager.runQuickCommand(command);
  }

  Future<void> _configureAiKey(AiToolConnector c) async {
    final existingKey = await widget.manager.aiVault.readApiKey(c.id);
    if (!mounted) return;
    final keyCtrl = TextEditingController(text: existingKey ?? '');
    final endpointCtrl = TextEditingController(text: c.endpoint);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text('${c.name} Settings',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: '${c.envVarName} (encrypted)',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
            if (c.id == 'ollama' || c.endpoint.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextField(
                controller: endpointCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Endpoint URL',
                  labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await widget.manager.aiVault.saveConnector(
        c.copyWith(endpoint: endpointCtrl.text.trim()),
        apiKey: keyCtrl.text,
      );
      await widget.manager.syncAiEnvToActiveSession();
      await _loadAll();
      if (mounted) MakawToast.success(context, 'Updated ${c.name}');
    }
    keyCtrl.dispose();
    endpointCtrl.dispose();
  }

  Future<void> _pairFromInput() async {
    final parsed = CompanionPairing.parsePairingUri(_pairUriCtrl.text);
    if (parsed == null) {
      MakawToast.warning(
          context, 'Paste a valid makaw-pair://host:port?token=... URI');
      return;
    }
    final ping = await WorkstationCompanionClient.ping(parsed);
    await WorkstationCompanionClient.savePairing(parsed);
    await _loadAll();
    if (mounted) {
      if (ping != null) {
        MakawToast.success(context, 'Paired with ${ping['hostname']}');
      } else {
        MakawToast.info(
            context, 'Saved pairing (workstation offline or on different LAN)');
      }
      _pairUriCtrl.clear();
    }
  }

  Future<void> _openCompanionExplorer(CompanionPairing pairing) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF090D16),
      builder: (_) => _CompanionFilesSheet(pairing: pairing),
    );
  }

  Future<void> _pushContinuum() async {
    final active = widget.manager.activeSession;
    final snap = await widget.manager.continuum.captureAndSync(
      store: widget.manager.store,
      sshHosts: widget.manager.sshVault.hosts,
      activeCwd: active?.cwd ?? '',
      handoffNote: _handoffNoteCtrl.text.trim().isNotEmpty
          ? _handoffNoteCtrl.text.trim()
          : (active?.lastCommand ?? 'Active workspace'),
      companion: _pairings.isNotEmpty ? _pairings.first : null,
      cloudSyncRoomId: _cloudRoomCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _lastSnap = snap);
    MakawToast.success(context, 'Synced snapshot for ${snap.deviceName}');
  }

  Future<void> _pullContinuum() async {
    final snap = await widget.manager.continuum.pullSnapshot(
      companion: _pairings.isNotEmpty ? _pairings.first : null,
      cloudSyncRoomId: _cloudRoomCtrl.text.trim(),
    );
    if (!mounted) return;
    if (snap == null) {
      MakawToast.info(context, 'No remote or local Continuum snapshot found yet');
      return;
    }
    for (final h in snap.sshHosts) {
      if (widget.manager.sshVault.findByIdOrName(h.id) == null) {
        await widget.manager.sshVault.saveHost(h);
      }
    }
    for (final r in snap.customRunbooks) {
      await RunbookDetector.saveCustom(r);
    }
    setState(() => _lastSnap = snap);
    if (mounted) {
      MakawToast.success(
        context,
        'Restored state from ${snap.deviceName} (${snap.sshHosts.length} hosts)',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.86;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.hub_outlined,
                        color: Color(0xFF38BDF8), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Makaw Developer Hub',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  indicatorColor: const Color(0xFF38BDF8),
                  labelColor: const Color(0xFF38BDF8),
                  unselectedLabelColor: const Color(0xFF94A3B8),
                  tabs: const [
                    Tab(text: 'Packages & Git'),
                    Tab(text: 'AI Tools'),
                    Tab(text: 'Workstation'),
                    Tab(text: 'Continuum Sync'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildPackagesTab(),
                _buildAiTab(),
                _buildWorkstationTab(),
                _buildContinuumTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackagesTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text('Quick Clone Git Repository',
            style: TextStyle(
                color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cloneCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'owner/repo or https://github.com/...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final target =
                    ToolchainManager.normalizeGitCloneTarget(_cloneCtrl.text);
                if (target == null) {
                  MakawToast.warning(context, 'Enter a valid GitHub/Git repo');
                  return;
                }
                _runInActiveTerminal(
                    'git clone "${target.url}" && cd "${target.folderName}"');
              },
              child: const Text('Clone'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Toolchains & Package Managers',
            style: TextStyle(
                color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_loadingTools)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ))
        else
          for (final t in _toolchains ?? const <ToolchainStatus>[])
            Card(
              color: const Color(0xFF1E293B),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: Icon(
                  t.installed ? Icons.check_circle : Icons.download_for_offline_outlined,
                  color: t.installed
                      ? const Color(0xFF34D399)
                      : const Color(0xFFFBBF24),
                ),
                title: Text(t.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(
                  t.installed
                      ? (t.version.isNotEmpty ? t.version : 'Installed')
                      : t.installCommand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                trailing: OutlinedButton(
                  onPressed: () => _runInActiveTerminal(
                      t.installed ? t.updateCommand : t.installCommand),
                  child: Text(t.installed ? 'Update' : 'Install',
                      style: const TextStyle(fontSize: 11.5)),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildAiTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text(
          'API keys & endpoints are encrypted with FlutterSecureStorage and injected into terminal environment variables automatically.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        const SizedBox(height: 10),
        for (final c in _connectors)
          Card(
            color: const Color(0xFF1E293B),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.auto_awesome, color: Color(0xFF818CF8)),
              title: Text(c.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${c.envVarName} · cli: ${c.cliCommand}',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.vpn_key_outlined,
                        color: Color(0xFF38BDF8), size: 18),
                    tooltip: 'Set API Key',
                    onPressed: () => _configureAiKey(c),
                  ),
                  FilledButton(
                    onPressed: () => _runInActiveTerminal(c.cliCommand),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Run', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWorkstationTab() {
    final hostRunning = widget.manager.companionHost?.isRunning ?? false;
    final pairingUri = widget.manager.companionPairingUri ?? '';

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
          Card(
            color: const Color(0xFF1E293B),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.computer_rounded,
                          color: Color(0xFF34D399)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Workstation Companion Host',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                      Switch(
                        value: hostRunning,
                        onChanged: (v) async {
                          if (v) {
                            await widget.manager.startCompanionHost(
                              rootDir: ShellDiscovery.resolveDefaultCwd(
                                  widget.manager.activeSession?.cwd),
                            );
                          } else {
                            await widget.manager.stopCompanionHost();
                          }
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  const Text(
                    'Shares authorized local workspace over LAN (FileExclusionFilter + Bearer token protected).',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                  ),
                  if (hostRunning && pairingUri.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(pairingUri,
                        style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11.5,
                            fontFamily: 'monospace')),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: pairingUri));
                        MakawToast.success(context, 'Pairing URI copied');
                      },
                      icon: const Icon(Icons.copy, size: 15),
                      label: const Text('Copy Pairing URI'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Text('Pair with Desktop Workstation',
            style: TextStyle(
                color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pairUriCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'makaw-pair://192.168.1.25:47791?token=...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _pairFromInput, child: const Text('Pair')),
          ],
        ),
        const SizedBox(height: 12),
        for (final p in _pairings)
          Card(
            color: const Color(0xFF1E293B),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              leading:
                  const Icon(Icons.laptop_mac_rounded, color: Color(0xFF38BDF8)),
              title: Text(p.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              subtitle: Text('${p.host}:${p.port}',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.folder_open_rounded,
                        color: Color(0xFFFBBF24), size: 19),
                    tooltip: 'Remote Desktop Folders',
                    onPressed: () => _openCompanionExplorer(p),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      unawaited(widget.manager.createCompanionSession(p));
                    },
                    child: const Text('Shell', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContinuumTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text(
          'Synchronizes Terminal tabs, working directories, SSH Host profiles, and custom Runbooks seamlessly across Desktop, Tablet & Mobile.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _cloudRoomCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Continuum Workspace Channel ID',
            labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _handoffNoteCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Handoff Note (optional)',
            hintText: 'e.g. Fixing payment API tests on feature branch',
            labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _pushContinuum,
                icon: const Icon(Icons.cloud_upload_outlined, size: 17),
                label: const Text('Push State'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pullContinuum,
                icon: const Icon(Icons.cloud_download_outlined, size: 17),
                label: const Text('Pull State'),
              ),
            ),
          ],
        ),
        if (_lastSnap != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Snapshot · ${_lastSnap!.deviceName} (${_lastSnap!.os})',
                  style: const TextStyle(
                      color: Color(0xFF34D399),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                if (_lastSnap!.handoffNote.isNotEmpty)
                  Text('Note: ${_lastSnap!.handoffNote}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                Text(
                  '${_lastSnap!.sessions.length} session(s) · ${_lastSnap!.sshHosts.length} SSH host(s) · ${_lastSnap!.updatedAt.toLocal()}',
                  style:
                      const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CompanionFilesSheet extends StatefulWidget {
  final CompanionPairing pairing;
  const _CompanionFilesSheet({required this.pairing});

  @override
  State<_CompanionFilesSheet> createState() => _CompanionFilesSheetState();
}

class _CompanionFilesSheetState extends State<_CompanionFilesSheet> {
  String _relPath = '.';
  List<Map<String, dynamic>> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load('.');
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await WorkstationCompanionClient.listRemoteDir(
          widget.pairing,
          path: path);
      if (!mounted) return;
      setState(() {
        _relPath = path;
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _editFile(String rel) async {
    setState(() => _loading = true);
    try {
      final content =
          await WorkstationCompanionClient.readRemoteFile(widget.pairing, rel);
      if (!mounted) return;
      setState(() => _loading = false);
      final ctrl = TextEditingController(text: content);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: const Color(0xFF090D16),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.85,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop()),
                    Expanded(
                      child: Text(rel,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    FilledButton(
                      onPressed: () async {
                        await WorkstationCompanionClient.writeRemoteFile(
                            widget.pairing, rel, ctrl.text);
                        if (ctx.mounted) {
                          MakawToast.success(ctx, 'Saved to Desktop');
                        }
                      },
                      child: const Text('Save to Desktop'),
                    ),
                  ],
                ),
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 13),
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      ctrl.dispose();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        MakawToast.error(context, 'Failed to read Desktop file: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop()),
                Expanded(
                  child: Text('${widget.pairing.name} · $_relPath',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.home_outlined, color: Colors.white70),
                  onPressed: () => _load('.'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.white70)))
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (_, i) {
                          final e = _entries[i];
                          final isDir = e['isDir'] as bool? ?? false;
                          final path = e['path'] as String? ?? '';
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isDir ? Icons.folder : Icons.description_outlined,
                              color: isDir
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFF38BDF8),
                            ),
                            title: Text(e['name'] as String? ?? '',
                                style: const TextStyle(color: Colors.white)),
                            onTap: () => isDir ? _load(path) : _editFile(path),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
