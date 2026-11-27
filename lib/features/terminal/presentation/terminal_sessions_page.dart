import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../app/providers/service_providers.dart';
import '../../../core/services/terminal_sessions_store.dart';
import '../../../core/ui/makaw_toast.dart';
import '../../../core/widgets/widgets.dart';
import '../application/terminal_runtime_manager.dart';
import '../domain/terminal_models.dart';
import 'widgets/sftp_browser_sheet.dart';
import 'widgets/ssh_hosts_sheet.dart';
import 'widgets/terminal_soft_keyboard.dart';

/// Makaw Terminal 2.0 — persistent multi-session local (`pwsh`, `powershell`,
/// `cmd`, `Git Bash`, `Ubuntu / WSL`, `zsh`, `bash`, `makaw-sh`) & pure-Dart
/// `dartssh2` remote terminal workstation for Mobile, Tablet, and Desktop.
class TerminalSessionsPage extends ConsumerStatefulWidget {
  final int? initialSessionId;
  const TerminalSessionsPage({super.key, this.initialSessionId});

  @override
  ConsumerState<TerminalSessionsPage> createState() =>
      _TerminalSessionsPageState();
}

class _TerminalSessionsPageState extends ConsumerState<TerminalSessionsPage> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  bool _searchVisible = false;
  List<TerminalSearchMatch> _matches = const [];
  int _matchCursor = 0;
  final List<TerminalHighlight> _activeHighlights = [];

  TerminalRuntimeManager get _mgr => ref.read(terminalRuntimeManagerProvider);

  @override
  void initState() {
    super.initState();
    _mgr.onPromptPassword = _promptSecret;
    _mgr.onOpenSftp = _openSftpForHost;
    _mgr.addListener(_onManagerChanged);
    unawaited(_mgr.ensureInitialized(requestedSessionId: widget.initialSessionId));
  }

  @override
  void dispose() {
    _clearSearchHighlights();
    _mgr.onPromptPassword = null;
    _mgr.onOpenSftp = null;
    _mgr.removeListener(_onManagerChanged);
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
  }

  Future<String?> _promptSecret(String prompt) async {
    if (!mounted) return null;
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(prompt,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter secret...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Authenticate'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return res;
  }

  Future<void> _openNewShellPicker() async {
    await _mgr.refreshEnvironment();
    if (!mounted) return;
    final shells = _mgr.availableShells;
    final sshHosts = _mgr.sshVault.hosts;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Launch Shell or Remote Target',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                for (final sp in shells)
                  ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    leading: Icon(
                      sp.category == ShellCategory.wsl
                          ? Icons.dns_outlined
                          : (sp.isHybridBuiltIn
                              ? Icons.bolt_rounded
                              : Icons.terminal_rounded),
                      color: const Color(0xFF38BDF8),
                    ),
                    title: Text(sp.label,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13.5)),
                    subtitle: Text(sp.subtitle,
                        style: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 11)),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_mgr.createLocalSession(profile: sp));
                    },
                  ),
                if (sshHosts.isNotEmpty) ...[
                  const Divider(color: Colors.white12),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('SAVED SSH WORKSTATIONS & SERVERS',
                        style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  for (final h in sshHosts)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.router_outlined,
                          color: Color(0xFF34D399)),
                      title: Text(h.name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13.5)),
                      subtitle: Text(h.displayTarget,
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 11)),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        unawaited(_mgr.createSshSession(h));
                      },
                    ),
                ],
                const Divider(color: Colors.white12),
                ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.add_circle_outline, color: Color(0xFF818CF8)),
                  title: const Text('Configure SSH Hosts & Keys…',
                      style:
                          TextStyle(color: Color(0xFF818CF8), fontSize: 13.5)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openHostsSheet();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openHostsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SshHostsSheet(
        vault: _mgr.sshVault,
        onConnect: (host) => unawaited(_mgr.createSshSession(host)),
        onBrowseSftp: (host) => unawaited(_openSftpForHost(host)),
      ),
    );
  }

  Future<void> _openSftpForHost(SshHostProfile host) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF090D16),
      builder: (_) => SftpBrowserSheet(
        host: host,
        vault: _mgr.sshVault,
        onOpenInTerminal: (remoteDir) => unawaited(
          _mgr.createSshSession(host.copyWith(defaultRemoteDir: remoteDir)),
        ),
      ),
    );
  }

  void _openSftpForActiveOrVault() {
    final active = _mgr.activeSession;
    if (active?.targetType == 'ssh' && active?.hostId != null) {
      final host = _mgr.sshVault.findByIdOrName(active!.hostId!);
      if (host != null) {
        unawaited(_openSftpForHost(host));
        return;
      }
    }
    _openHostsSheet();
  }

  void _openAppearanceSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setModalState) {
          final prefs = _mgr.appearance;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Terminal Appearance',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Font Size (${prefs.fontSize.toStringAsFixed(1)}pt)',
                            style: const TextStyle(
                                color: Color(0xFFCBD5E1), fontSize: 12.5)),
                        Expanded(
                          child: Slider(
                            min: 10,
                            max: 24,
                            divisions: 14,
                            value: prefs.fontSize,
                            onChanged: (v) {
                              _mgr.updateAppearance(prefs.copyWith(fontSize: v));
                              setModalState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Cursor Style',
                        style:
                            TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final c in const [
                          ('block', 'Block'),
                          ('underline', 'Underline'),
                          ('bar', 'Bar'),
                        ])
                          ChoiceChip(
                            label: Text(c.$2),
                            selected: prefs.cursorStyle == c.$1,
                            onSelected: (_) {
                              _mgr.updateAppearance(
                                  prefs.copyWith(cursorStyle: c.$1));
                              setModalState(() {});
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Theme Palette',
                        style:
                            TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in MakawTerminalThemePreset.presets)
                          ChoiceChip(
                            avatar: CircleAvatar(
                              backgroundColor: preset.theme.background,
                              child: Icon(Icons.circle,
                                  size: 10, color: preset.theme.cyan),
                            ),
                            label: Text(preset.label),
                            selected: prefs.themeId == preset.id,
                            onSelected: (_) {
                              _mgr.updateAppearance(
                                  prefs.copyWith(themeId: preset.id));
                              setModalState(() {});
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: prefs.showSoftKeys,
                      onChanged: (v) {
                        _mgr.updateAppearance(prefs.copyWith(showSoftKeys: v));
                        setModalState(() {});
                      },
                      title: const Text('Show Touch Soft-Key Bar',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _renameSession(TerminalSessionRuntime rt) async {
    _nameCtrl.text = rt.name;
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Rename Tab',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: _nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_nameCtrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (next != null && next.isNotEmpty) {
      await _mgr.renameSession(rt.id, next);
    }
  }

  void _copySelectionOrScreen(TerminalSessionRuntime rt) {
    final sel = rt.controller.selection;
    final text = sel != null
        ? rt.terminal.buffer.getText(sel)
        : rt.terminal.buffer.getText();
    Clipboard.setData(ClipboardData(text: text.trimRight()));
    MakawToast.success(
      context,
      sel != null ? 'Selection copied' : 'Terminal buffer copied',
    );
  }

  Future<void> _pasteClipboard(TerminalSessionRuntime rt) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) {
      if (mounted) MakawToast.info(context, 'Clipboard is empty');
      return;
    }
    rt.terminal.paste(text);
  }

  void _clearSearchHighlights() {
    for (final h in _activeHighlights) {
      h.dispose();
    }
    _activeHighlights.clear();
  }

  void _runSearch(String query) {
    _clearSearchHighlights();
    final active = _mgr.activeSession;
    if (active == null || query.trim().isEmpty) {
      setState(() {
        _matches = const [];
        _matchCursor = 0;
      });
      return;
    }
    final hits = TerminalRuntimeManager.searchScrollback(active.terminal, query);
    final preset = MakawTerminalThemePreset.byId(_mgr.appearance.themeId);
    for (final m in hits) {
      if (m.lineIndex >= active.terminal.buffer.lines.length) continue;
      final line = active.terminal.buffer.lines[m.lineIndex];
      final a1 = line.createAnchor(m.startCol);
      final a2 = line.createAnchor(m.endCol);
      _activeHighlights.add(
        active.controller.highlight(
          p1: a1,
          p2: a2,
          color: preset.theme.searchHitBackground.withOpacity(0.55),
        ),
      );
    }
    setState(() {
      _matches = hits;
      _matchCursor = hits.isEmpty ? 0 : hits.length - 1;
    });
  }

  void _stepSearch(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _matchCursor = (_matchCursor + delta) % _matches.length;
      if (_matchCursor < 0) _matchCursor += _matches.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _mgr.activeSession;
    final appearance = _mgr.appearance;
    final preset = MakawTerminalThemePreset.byId(appearance.themeId);
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: preset.theme.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: active == null ? null : () => _renameSession(active),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _statusDot(active?.state ?? TerminalSessionState.idle),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      active?.name ?? 'Terminal',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                active == null
                    ? ''
                    : '${active.shellLabel} · ${active.cwd}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
              ),
            ],
          ),
        ),
        actions: [
          if (isWide) ...[
            IconButton(
              icon: const Icon(Icons.search_rounded, color: Colors.white70, size: 20),
              tooltip: 'Find in scrollback',
              onPressed: () {
                setState(() => _searchVisible = !_searchVisible);
                if (!_searchVisible) _clearSearchHighlights();
              },
            ),
            if (_mgr.order.length >= 2)
              IconButton(
                icon: Icon(
                  Icons.vertical_split_rounded,
                  color: _mgr.splitEnabled ? const Color(0xFF38BDF8) : Colors.white70,
                  size: 20,
                ),
                tooltip: 'Toggle split pane',
                onPressed: _mgr.toggleSplitPane,
              ),
            IconButton(
              icon: const Icon(Icons.palette_outlined, color: Colors.white70, size: 20),
              tooltip: 'Themes & typography',
              onPressed: _openAppearanceSheet,
            ),
          ],
          if (active?.targetType == 'ssh')
            IconButton(
              icon: const Icon(Icons.folder_shared_outlined,
                  color: Color(0xFF34D399), size: 20),
              tooltip: 'Browse Remote SFTP Files',
              onPressed: _openSftpForActiveOrVault,
            ),
          IconButton(
            icon: const Icon(Icons.dns_outlined, color: Color(0xFF38BDF8), size: 20),
            tooltip: 'SSH Hosts & Keys',
            onPressed: _openHostsSheet,
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined, color: Color(0xFF38BDF8), size: 21),
            tooltip: 'New shell / remote',
            onPressed: _openNewShellPicker,
          ),
          if (!isWide)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
              color: const Color(0xFF0F172A),
              onSelected: (v) {
                if (v == 'find') {
                  setState(() => _searchVisible = !_searchVisible);
                  if (!_searchVisible) _clearSearchHighlights();
                } else if (v == 'appearance') {
                  _openAppearanceSheet();
                } else if (v == 'clear' && active != null) {
                  active.clearDisplay();
                } else if (v == 'rename' && active != null) {
                  _renameSession(active);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'find', child: Text('Find in scrollback', style: TextStyle(color: Colors.white))),
                PopupMenuItem(value: 'appearance', child: Text('Themes & Font', style: TextStyle(color: Colors.white))),
                PopupMenuItem(value: 'clear', child: Text('Clear screen', style: TextStyle(color: Colors.white))),
                PopupMenuItem(value: 'rename', child: Text('Rename tab', style: TextStyle(color: Colors.white))),
              ],
            ),
        ],
      ),
      body: !_mgr.initialized
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
          : Column(
              children: [
                _buildSessionTabBar(active),
                if (_searchVisible) _buildSearchBar(),
                Expanded(
                  child: active == null
                      ? const Center(
                          child: Text('Tap + to launch a shell',
                              style: TextStyle(color: Colors.white54)))
                      : (isWide &&
                              _mgr.splitEnabled &&
                              _mgr.splitSecondarySession != null)
                          ? Row(
                              children: [
                                Expanded(
                                    child: _buildTerminalPane(
                                        active, preset, appearance,
                                        isPrimary: true)),
                                Container(width: 1, color: Colors.white12),
                                Expanded(
                                    child: _buildTerminalPane(
                                        _mgr.splitSecondarySession!,
                                        preset,
                                        appearance,
                                        isPrimary: false)),
                              ],
                            )
                          : _buildTerminalPane(active, preset, appearance,
                              isPrimary: true),
                ),
                if (active != null && appearance.showSoftKeys)
                  TerminalSoftKeyboard(
                    terminal: active.terminal,
                    controller: active.controller,
                    showRow2: appearance.showSoftKeyRow2,
                    onToggleRow2: (v) => _mgr.updateAppearance(
                        appearance.copyWith(showSoftKeyRow2: v)),
                    onCopySelection: () => _copySelectionOrScreen(active),
                    onPasteClipboard: () => _pasteClipboard(active),
                    onClear: active.clearDisplay,
                    onOpenHosts: _openHostsSheet,
                    onToggleFind: () {
                      setState(() => _searchVisible = !_searchVisible);
                      if (!_searchVisible) _clearSearchHighlights();
                    },
                  ),
              ],
            ),
    );
  }

  Widget _buildSessionTabBar(TerminalSessionRuntime? active) {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final id in _mgr.order) _buildTabPill(id),
                ],
              ),
            ),
          ),
          if (active != null && active.lastExitCode != null)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: active.lastExitCode == 0
                    ? const Color(0xFF10B981).withOpacity(0.16)
                    : const Color(0xFFF87171).withOpacity(0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                active.lastExitCode == 0
                    ? '✓ 0'
                    : '✗ ${active.lastExitCode}',
                style: TextStyle(
                  color: active.lastExitCode == 0
                      ? const Color(0xFF34D399)
                      : const Color(0xFFFCA5A5),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF38BDF8), size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: 'Quick new tab',
            onPressed: () => unawaited(_mgr.createLocalSession()),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(int id) {
    final rt = _mgr.sessionById(id);
    if (rt == null) return const SizedBox.shrink();
    final isActive = id == _mgr.activeId;
    final isSplit = _mgr.splitEnabled && id == _mgr.splitSecondaryId;
    return GestureDetector(
      onTap: () => unawaited(_mgr.activateSession(id)),
      onLongPress: () => _renameSession(rt),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.only(left: 10, right: 4),
        height: 32,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF38BDF8)
              : (isSplit
                  ? const Color(0xFF1D4ED8).withOpacity(0.45)
                  : const Color(0xFF1E293B)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusDot(rt.state,
                colorOverride: isActive ? const Color(0xFF090D16) : null),
            const SizedBox(width: 5),
            Text(
              rt.name,
              style: TextStyle(
                color: isActive ? const Color(0xFF090D16) : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            TappableIcon(
              icon: Icons.close,
              iconSize: 14,
              color: isActive ? Colors.black87 : Colors.white38,
              onTap: () => unawaited(_mgr.closeSession(id)),
              tooltip: 'Close tab',
              target: 26,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Find in terminal output…',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                isDense: true,
                border: InputBorder.none,
              ),
              onChanged: _runSearch,
            ),
          ),
          Text(
            _matches.isEmpty
                ? '0'
                : '${_matchCursor + 1}/${_matches.length}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => _stepSearch(-1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => _stepSearch(1),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() => _searchVisible = false);
              _clearSearchHighlights();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalPane(
    TerminalSessionRuntime rt,
    MakawTerminalThemePreset preset,
    TerminalAppearancePrefs appearance, {
    required bool isPrimary,
  }) {
    if (kIsWeb) {
      return const Center(
        child: Text('Terminal PTY is not available on web',
            style: TextStyle(color: Colors.white54)),
      );
    }
    return Stack(
      children: [
        TerminalView(
          rt.terminal,
          controller: rt.controller,
          theme: preset.theme,
          textStyle: TerminalStyle(fontSize: appearance.fontSize),
          cursorType: _mgr.cursorType,
          // visiblePassword disables Android IME predictive-text/composing
          // duplication while preserving full QWERTY & deleteDetection backspace.
          keyboardType: !kIsWeb && Platform.isAndroid
              ? TextInputType.visiblePassword
              : TextInputType.emailAddress,
          deleteDetection: !kIsWeb && (Platform.isAndroid || Platform.isIOS),
          autofocus: isPrimary,
        ),
        if (rt.state == TerminalSessionState.exited ||
            rt.state == TerminalSessionState.error)
          Positioned(
            right: 12,
            bottom: 12,
            child: FilledButton.icon(
              onPressed: () => unawaited(_mgr.restartSession(rt.id)),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reconnect / Restart',
                  style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: const Color(0xFF090D16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusDot(TerminalSessionState st, {Color? colorOverride}) {
    final c = colorOverride ??
        switch (st) {
          TerminalSessionState.running => const Color(0xFF34D399),
          TerminalSessionState.connecting => const Color(0xFFFBBF24),
          TerminalSessionState.error => const Color(0xFFF87171),
          _ => const Color(0xFF64748B),
        };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}
