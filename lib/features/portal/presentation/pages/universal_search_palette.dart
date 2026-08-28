import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

Future<String> getAppDocsDir() async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}

/// Result entry kinds surfaced in the universal search.
enum SearchResultKind { tool, file, folder, web }

/// A single universal-search result.
class UniversalSearchResult {
  final SearchResultKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final void Function() onTap;

  const UniversalSearchResult({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
}

/// Universal Search & Command Palette.
///
/// This is a *distinct* surface from the browser omnibox / NTP. It searches the
/// Makaw ecosystem (tools, files, folders). Only an explicit "Search on the
/// Web" action bridges into the browser result screen.
class UniversalSearchPalette extends StatefulWidget {
  final void Function(String view) onOpenTool;
  final void Function(String path) onOpenFile;
  final void Function(String term) onSearchWeb;

  const UniversalSearchPalette({
    super.key,
    required this.onOpenTool,
    required this.onOpenFile,
    required this.onSearchWeb,
  });

  @override
  State<UniversalSearchPalette> createState() => _UniversalSearchPaletteState();
}

class _UniversalSearchPaletteState extends State<UniversalSearchPalette> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _scanning = false;
  bool _scanned = false;
  final List<_FsEntry> _indexed = [];

  static const List<_ToolDef> _tools = [
    _ToolDef('Code Studio', 'Write, run & debug projects', Icons.code_rounded, Color(0xFF818CF8), 'studio'),
    _ToolDef('Projects', 'Manage your workspace projects', Icons.folder_rounded, Color(0xFFFBBF24), 'projects'),
    _ToolDef('Git', 'Version control & repositories', Icons.account_tree_rounded, Color(0xFFF472B6), 'git'),
    _ToolDef('Snippets', 'Reusable code & text snippets', Icons.content_paste_rounded, Color(0xFF34D399), 'snippets'),
    _ToolDef('Terminal', 'Command-line shell', Icons.terminal_rounded, Color(0xFF22D3EE), 'terminal'),
    _ToolDef('Documents', 'View & browse documents', Icons.edit_document, Color(0xFFFBBF24), 'documents'),
    _ToolDef('File Explorer', 'Browse files on device', Icons.folder_open_rounded, Color(0xFF34D399), 'files'),
    _ToolDef('Media Hub', 'Photos, audio & video', Icons.video_collection_outlined, Color(0xFFF87171), 'media'),
    _ToolDef('Music Player', 'Play your audio library', Icons.music_note_rounded, Color(0xFFF472B6), 'music'),
    _ToolDef('Images', 'Browse image gallery', Icons.image_rounded, Color(0xFF38BDF8), 'images'),
    _ToolDef('Media Sniffer', 'Discover media on network', Icons.wifi_tethering_rounded, Color(0xFF22D3EE), 'sniffer'),
    _ToolDef('Downloads', 'View downloaded files', Icons.download_rounded, Color(0xFFFB923C), 'downloads'),
    _ToolDef('Cloud Sync', 'Sync across devices', Icons.cloud_rounded, Color(0xFF60A5FA), 'cloud'),
    _ToolDef('History', 'Browse browsing history', Icons.history_rounded, Color(0xFF94A3B8), 'history'),
    _ToolDef('Browser', 'Open the web browser', Icons.language_rounded, Color(0xFF00A7C2), 'browser'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    // Focus + keyboard as soon as the palette opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _scanWorkspace() async {
    if (_scanned || _scanning) return;
    setState(() => _scanning = true);
    try {
      final doc = await getAppDocsDir();
      final base = Directory(doc);
      if (await base.exists()) {
        await for (final entity in base.list(recursive: true, followLinks: false)) {
          if (!mounted) return;
          final isDir = entity is Directory;
          final name = entity.path.split(Platform.pathSeparator).last;
          _indexed.add(_FsEntry(name: name, path: entity.path, isDir: isDir));
          if (_indexed.length >= 600) break;
        }
      }
    } catch (_) {
      // Workspace unavailable — tools-only search still works.
    }
    if (mounted) {
      setState(() {
        _scanning = false;
        _scanned = true;
      });
    }
  }

  List<UniversalSearchResult> _results(String query) {
    final q = query.trim().toLowerCase();
    final results = <UniversalSearchResult>[];

    // 1. Tools
    final tools = _tools
        .where((t) => q.isEmpty || t.title.toLowerCase().contains(q) || t.view.contains(q))
        .map((t) => UniversalSearchResult(
              kind: SearchResultKind.tool,
              title: t.title,
              subtitle: '${t.desc}  ·  Tool',
              icon: t.icon,
              accent: t.accent,
              onTap: () => widget.onOpenTool(t.view),
            ));
    results.addAll(tools);

    // 2. Files & folders (from the scanned workspace)
    if (q.isNotEmpty) {
      final fs = _indexed
          .where((e) => e.name.toLowerCase().contains(q))
          .take(30)
          .map((e) => UniversalSearchResult(
                kind: e.isDir ? SearchResultKind.folder : SearchResultKind.file,
                title: e.name,
                subtitle: e.path,
                icon: e.isDir ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                accent: e.isDir ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
                onTap: () => widget.onOpenFile(e.path),
              ));
      results.addAll(fs);
    }

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildSearchField(context),
            Expanded(
              child: _buildResultsList(context, query),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Text(
            'Universal Search & Command Palette',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 22),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
          IconButton(
            icon: const Icon(Icons.travel_explore, color: Colors.white38, size: 22),
            onPressed: _scanWorkspace,
            tooltip: 'Scan workspace',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.search, color: Colors.white54, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search tools, files, and folders...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (value) {
                  final v = value.trim();
                  if (v.isEmpty) return;
                  final results = _results(v).where((r) => r.kind == SearchResultKind.tool || r.kind == SearchResultKind.file || r.kind == SearchResultKind.folder);
                  if (results.isNotEmpty) {
                    results.first.onTap();
                  } else {
                    widget.onSearchWeb(v);
                  }
                },
              ),
            ),
            if (_controller.text.trim().isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _controller.clear,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(BuildContext context, String query) {
    final results = _results(query);

    // Kick off a background scan once for file/folder results.
    if (!_scanned && !_scanning) {
      _scanWorkspace();
    }

    final tools = results.where((r) => r.kind == SearchResultKind.tool);
    final folders = results.where((r) => r.kind == SearchResultKind.folder);
    final files = results.where((r) => r.kind == SearchResultKind.file);

    if (query.isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (tools.isNotEmpty) ...[
          _buildSectionLabel('Tools'),
          ...tools.map((r) => _buildResultTile(r)),
        ],
        if (folders.isNotEmpty) ...[
          _buildSectionLabel('Folders'),
          ...folders.map((r) => _buildResultTile(r)),
        ],
        if (files.isNotEmpty) ...[
          _buildSectionLabel('Files'),
          ...files.map((r) => _buildResultTile(r)),
        ],
        if (tools.isEmpty && folders.isEmpty && files.isEmpty) ...[
          const SizedBox(height: 16),
          _buildWebSuggestion(context, query),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 8),
        _buildSectionLabel('Tools'),
        ..._tools.map((t) => _buildResultTile(UniversalSearchResult(
              kind: SearchResultKind.tool,
              title: t.title,
              subtitle: t.desc,
              icon: t.icon,
              accent: t.accent,
              onTap: () => widget.onOpenTool(t.view),
            ))),
        const SizedBox(height: 12),
        _buildSectionLabel('Workspace'),
        if (_scanning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
              ),
            ),
          )
        else ...[
          if (_indexed.isNotEmpty)
            ..._indexed.take(30).map((e) => _buildResultTile(UniversalSearchResult(
                  kind: e.isDir ? SearchResultKind.folder : SearchResultKind.file,
                  title: e.name,
                  subtitle: e.path,
                  icon: e.isDir ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                  accent: e.isDir ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
                  onTap: () => widget.onOpenFile(e.path),
                )))
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Scan your workspace to index files & folders.',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.45),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildResultTile(UniversalSearchResult r) {
    return InkWell(
      onTap: r.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(r.icon, color: r.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildWebSuggestion(BuildContext context, String query) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Material(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => widget.onSearchWeb(query),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.language_rounded, color: Color(0xFF38BDF8), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Search “$query” on the Web',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'No tools or files match — open Google results in the browser',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new, color: Colors.white38, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolDef {
  final String title;
  final String desc;
  final IconData icon;
  final Color accent;
  final String view;
  const _ToolDef(this.title, this.desc, this.icon, this.accent, this.view);
}

class _FsEntry {
  final String name;
  final String path;
  final bool isDir;
  const _FsEntry({required this.name, required this.path, required this.isDir});
}
