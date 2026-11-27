import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../../core/platform/platform_paths.dart';
import '../../../../core/utils/natural_sort.dart';
import '../../../media/data/services/media_thumbnail_service.dart';
import '../../data/services/archive_service.dart';
import '../../data/services/device_file_browser.dart';

/// Full-device File Explorer for the Files / Documents ecosystem.
///
/// Includes fast background recursive search, category filtering, multi-select,
/// sort controls, breadcrumb navigation, and full Zip/RAR/Tar/Gz archive
/// creation, inspection, and extraction.
class FoldersPage extends StatefulWidget {
  final void Function(String filePath) openFile;
  final String? initialPath;

  const FoldersPage({
    super.key,
    required this.openFile,
    this.initialPath,
  });

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  final List<String> _pathStack = [];
  List<DeviceEntry> _entries = [];
  bool _loading = false;
  String? _error;
  bool _permissionGranted = true;

  // Search & Filter state
  bool _searchMode = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _searchCategory = 'all';
  bool _searching = false;
  List<DeviceEntry> _searchResults = [];
  Timer? _searchDebounce;
  int _searchTicket = 0;

  // Sort & Multi-select state
  String _sortBy = 'name'; // name | name_desc | date | size | type
  bool _selectMode = false;
  final Set<String> _selectedPaths = {};

  bool get _isHome => _pathStack.isEmpty;
  String get _currentPath => _isHome ? '/' : _pathStack.last;

  static const _kDark = Color(0xFF0A0F1A);
  static const _kAccent = Color(0xFF818CF8);
  static const _kCard = Color(0xFF141C2E);
  static const _kBorder = Color(0xFF1E293B);

  @override
  void initState() {
    super.initState();
    final init = widget.initialPath;
    if (init != null && init.isNotEmpty && Directory(init).existsSync()) {
      _pathStack.add(init);
    }
    _ensurePermission();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensurePermission() async {
    final ok = await DeviceFileBrowser.ensureManageStoragePermission();
    if (mounted) setState(() => _permissionGranted = ok);
    if (ok && !_isHome) _load(_currentPath);
  }

  void _go(String path) {
    setState(() {
      _searchMode = false;
      _searchCtrl.clear();
      _searchQuery = '';
      _selectMode = false;
      _selectedPaths.clear();
      _pathStack.add(path);
    });
    _load(path);
  }

  void _jumpToPath(String path) {
    setState(() {
      _selectMode = false;
      _selectedPaths.clear();
      _pathStack
        ..clear()
        ..add(path);
    });
    _load(path);
  }

  void _back() {
    if (_selectMode) {
      setState(() {
        _selectMode = false;
        _selectedPaths.clear();
      });
      return;
    }
    if (_searchMode) {
      setState(() {
        _searchMode = false;
        _searchCtrl.clear();
        _searchQuery = '';
        _searchResults = [];
      });
      return;
    }
    if (_pathStack.isEmpty) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    setState(() => _pathStack.removeLast());
    if (!_isHome) _load(_currentPath);
  }

  void _load(String path) {
    setState(() {
      _loading = true;
      _error = null;
    });
    Future.microtask(() {
      List<DeviceEntry> entries;
      try {
        entries = DeviceFileBrowser.listDirectory(path);
        _applySort(entries);
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Cannot read $path';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    });
  }

  void _applySort(List<DeviceEntry> list) {
    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (_sortBy) {
        case 'name_desc':
          return naturalCompare(b.name, a.name);
        case 'date':
          return b.modified.compareTo(a.modified);
        case 'size':
          return b.size.compareTo(a.size);
        case 'type':
          final ec = a.ext.compareTo(b.ext);
          return ec != 0 ? ec : naturalCompare(a.name, b.name);
        case 'name':
        default:
          return naturalCompare(a.name, b.name);
      }
    });
  }

  void _triggerSearch(String value) {
    _searchDebounce?.cancel();
    setState(() => _searchQuery = value);
    final q = value.trim();
    if (q.isEmpty && _searchCategory == 'all') {
      setState(() {
        _searching = false;
        _searchResults = [];
      });
      return;
    }
    final ticket = ++_searchTicket;
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 200), () async {
      final root = _isHome ? PlatformPaths.storageRoot() : _currentPath;
      final hits = await DeviceFileBrowser.searchRecursive(
        rootPath: root,
        query: q,
        category: _searchCategory,
      );
      if (!mounted || ticket != _searchTicket) return;
      setState(() {
        _searchResults = hits;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: _kDark,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            if (_searchMode) _buildSearchFilterChips(),
            if (!_searchMode && !_isHome) _buildBreadcrumbBar(),
            if (_selectMode) _buildSelectionBar(),
            Expanded(
              child: _searchMode
                  ? _buildSearchResultsBody()
                  : (_isHome ? _buildHome() : _buildDirectory()),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_searchMode) {
      return AppBar(
        backgroundColor: _kCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: _back,
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: _isHome
                ? 'Fast search across device storage...'
                : 'Search in ${_displayName(_currentPath)}...',
            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
            border: InputBorder.none,
          ),
          onChanged: _triggerSearch,
        ),
        actions: [
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded, color: Colors.white70),
              onPressed: () {
                _searchCtrl.clear();
                _triggerSearch('');
              },
            ),
        ],
      );
    }

    return AppBar(
      backgroundColor: _kDark,
      elevation: 0,
      title: Text(
        _isHome ? 'File Explorer' : _displayName(_currentPath),
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        overflow: TextOverflow.ellipsis,
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: _back,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded, color: _kAccent),
          tooltip: 'Fast Search',
          onPressed: () => setState(() => _searchMode = true),
        ),
        if (!_isHome) ...[
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, color: Colors.white70, size: 22),
            tooltip: 'New Folder',
            onPressed: _createFolderDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded, color: Colors.white70, size: 22),
            color: _kCard,
            tooltip: 'Sort',
            onSelected: (v) {
              setState(() {
                _sortBy = v;
                _applySort(_entries);
              });
            },
            itemBuilder: (_) => [
              _sortOption('name', 'Name (A-Z)'),
              _sortOption('name_desc', 'Name (Z-A)'),
              _sortOption('date', 'Newest Modified'),
              _sortOption('size', 'Largest Size'),
              _sortOption('type', 'File Type'),
            ],
          ),
        ],
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          tooltip: 'Refresh',
          onPressed: () => _isHome ? _ensurePermission() : _load(_currentPath),
        ),
      ],
    );
  }

  PopupMenuItem<String> _sortOption(String value, String label) {
    final selected = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 16,
            color: selected ? _kAccent : Colors.white38,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: selected ? _kAccent : Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildSearchFilterChips() {
    const cats = [
      ('all', 'All', Icons.apps_rounded),
      ('folders', 'Folders', Icons.folder_rounded),
      ('docs', 'Docs', Icons.description_rounded),
      ('media', 'Media', Icons.perm_media_rounded),
      ('archives', 'Zip / RAR', Icons.folder_zip_rounded),
      ('code', 'Code', Icons.code_rounded),
    ];
    return Container(
      height: 44,
      color: _kCard,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: FilterChip(
                selected: _searchCategory == c.$1,
                avatar: Icon(c.$3, size: 14, color: _searchCategory == c.$1 ? Colors.white : _kAccent),
                label: Text(c.$2, style: TextStyle(fontSize: 11.5, color: _searchCategory == c.$1 ? Colors.white : Colors.white70)),
                backgroundColor: _kDark,
                selectedColor: const Color(0xFF6366F1),
                side: BorderSide(color: _searchCategory == c.$1 ? _kAccent : _kBorder),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  setState(() => _searchCategory = c.$1);
                  _triggerSearch(_searchCtrl.text);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbBar() {
    final parts = _currentPath.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
    return Container(
      height: 36,
      color: const Color(0xFF0E1525),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: parts.length + 1,
        separatorBuilder: (_, __) => const Icon(Icons.chevron_right_rounded, size: 15, color: Color(0xFF64748B)),
        itemBuilder: (_, idx) {
          if (idx == 0) {
            return InkWell(
              onTap: () => setState(() => _pathStack.clear()),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Center(child: Icon(Icons.home_rounded, size: 16, color: _kAccent)),
              ),
            );
          }
          final targetParts = parts.sublist(0, idx);
          final targetPath = Platform.isWindows
              ? '${targetParts.first}\\${targetParts.skip(1).join('\\')}'
              : '/${targetParts.join('/')}';
          final isLast = idx == parts.length;
          return InkWell(
            onTap: isLast ? null : () => _jumpToPath(targetPath),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  parts[idx - 1],
                  style: TextStyle(
                    color: isLast ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
              _selectMode = false;
              _selectedPaths.clear();
            }),
          ),
          Text('${_selectedPaths.length} selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.select_all_rounded, color: Colors.white70, size: 20),
            tooltip: 'Select All',
            onPressed: () {
              final src = _searchMode ? _searchResults : _entries;
              setState(() => _selectedPaths.addAll(src.map((e) => e.path)));
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_zip_rounded, color: Color(0xFFFB923C), size: 21),
            tooltip: 'Compress to .zip',
            onPressed: _selectedPaths.isEmpty ? null : () => _compressDialog(_selectedPaths.toList()),
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: _kAccent, size: 20),
            tooltip: 'Share',
            onPressed: _selectedPaths.isEmpty
                ? null
                : () {
                    final files = _selectedPaths.where((p) => File(p).existsSync()).map((p) => XFile(p)).toList();
                    if (files.isEmpty) {
                      _toast('Select files (not folders) to share');
                    } else {
                      Share.shareXFiles(files);
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 21),
            tooltip: 'Delete',
            onPressed: _selectedPaths.isEmpty ? null : () => _deletePathsDialog(_selectedPaths.toList()),
          ),
        ],
      ),
    );
  }

  // ─── Quick-access home ────────────────────────────────────────────────────

  Widget _buildHome() {
    if (!_permissionGranted) return _buildPermissionBanner();
    final roots = DeviceFileBrowser.quickAccessRoots();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Hero Fast Search Banner
        InkWell(
          onTap: () => setState(() => _searchMode = true),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
            ),
            child: const Row(
              children: [
                Icon(Icons.search_rounded, color: _kAccent, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search any file, folder, .zip or .rar across device...',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ),
                Icon(Icons.bolt_rounded, color: Color(0xFFFBBF24), size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Row(
          children: [
            Icon(Icons.storage_rounded, color: _kAccent, size: 18),
            SizedBox(width: 8),
            Text('Quick access', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        for (final r in roots) _buildRootTile(r),
        const SizedBox(height: 12),
        const Divider(color: Color(0xFF1E293B)),
        const SizedBox(height: 4),
        const Text(
          'Long-press any files or folders to compress (.zip / .tar.gz). Tap any .zip or .rar to inspect and extract.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildPermissionBanner() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off, size: 56, color: Color(0xFF64748B)),
            const SizedBox(height: 16),
            const Text('Full file access required',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Enable "All files access" to browse, search, zip & extract files.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _ensurePermission,
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              icon: const Icon(Icons.shield),
              label: const Text('Grant access'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRootTile(QuickAccessRoot r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => _go(r.path),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _rootColor(r.kind).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(_rootIcon(r.kind), color: _rootColor(r.kind), size: 24),
          ),
          title: Text(r.label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(r.path, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11), overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
        ),
      ),
    );
  }

  IconData _rootIcon(IconKind k) {
    switch (k) {
      case IconKind.home: return Icons.home_rounded;
      case IconKind.download: return Icons.download_rounded;
      case IconKind.doc: return Icons.description_rounded;
      case IconKind.picture: return Icons.photo_rounded;
      case IconKind.music: return Icons.music_note_rounded;
      case IconKind.video: return Icons.movie_rounded;
      case IconKind.android: return Icons.android_rounded;
      case IconKind.root: return Icons.storage_rounded;
    }
  }

  Color _rootColor(IconKind k) {
    switch (k) {
      case IconKind.home: return const Color(0xFF38BDF8);
      case IconKind.download: return const Color(0xFFFB923C);
      case IconKind.doc: return const Color(0xFFFBBF24);
      case IconKind.picture: return const Color(0xFF38BDF8);
      case IconKind.music: return const Color(0xFFF472B6);
      case IconKind.video: return const Color(0xFFF87171);
      case IconKind.android: return const Color(0xFF22D3EE);
      case IconKind.root: return const Color(0xFF34D399);
    }
  }

  // ─── Search Results ───────────────────────────────────────────────────────

  Widget _buildSearchResultsBody() {
    if (_searching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _kAccent),
            SizedBox(height: 12),
            Text('Searching storage...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          ],
        ),
      );
    }
    if (_searchQuery.trim().isEmpty && _searchCategory == 'all') {
      return const Center(
        child: Text('Type a filename or tap a category chip above',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
      );
    }
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('No matching files or folders found',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      itemBuilder: (_, i) => _buildEntry(_searchResults[i], showParentPath: true),
    );
  }

  // ─── Directory listing ────────────────────────────────────────────────────

  Widget _buildDirectory() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _kAccent));
    if (_error != null) return _buildError(_error!);
    if (_entries.isEmpty) {
      return const Center(child: Text('Folder is empty', style: TextStyle(color: Color(0xFF64748B))));
    }
    return RefreshIndicator(
      color: _kAccent,
      backgroundColor: _kCard,
      onRefresh: () async => _load(_currentPath),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _entries.length,
        itemBuilder: (_, i) => _buildEntry(_entries[i]),
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 48),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          const SizedBox(height: 8),
          const Text('You may need all-files access to read this location.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _ensurePermission, style: FilledButton.styleFrom(backgroundColor: _kAccent), child: const Text('Grant access')),
        ],
      ),
    );
  }

  static const _videoExts = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', '3gp', 'm4v'};
  static const _audioExts = {'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma', 'opus'};
  static const _imgExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

  Widget _buildLeading(DeviceEntry e) {
    final ext = e.ext.toLowerCase();
    if (_imgExts.contains(ext)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(e.path),
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          cacheWidth: 100,
          cacheHeight: 100,
          errorBuilder: (_, __, ___) => _defaultLeading(e),
        ),
      );
    }
    if (_audioExts.contains(ext) || _videoExts.contains(ext)) {
      return MediaArtworkWidget(
        filePath: e.path,
        isVideo: _videoExts.contains(ext),
        width: 42,
        height: 42,
        borderRadius: BorderRadius.circular(8),
        fallback: _defaultLeading(e),
      );
    }
    return _defaultLeading(e);
  }

  Widget _defaultLeading(DeviceEntry e) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _fileColor(e.ext).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Icon(_fileIcon(e.ext), color: _fileColor(e.ext), size: 21)),
    );
  }

  Widget _buildEntry(DeviceEntry e, {bool showParentPath = false}) {
    final selected = _selectedPaths.contains(e.path);
    final isArchive = !e.isDirectory && ArchiveService.isArchivePath(e.path);

    void handleTap() {
      if (_selectMode) {
        setState(() {
          if (selected) {
            _selectedPaths.remove(e.path);
            if (_selectedPaths.isEmpty) _selectMode = false;
          } else {
            _selectedPaths.add(e.path);
          }
        });
        return;
      }
      if (e.isDirectory) {
        _go(e.path);
      } else if (isArchive) {
        _openArchiveSheet(e);
      } else {
        widget.openFile(e.path);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? const Color(0xFF232F4D) : _kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: selected ? _kAccent : _kBorder, width: selected ? 1.2 : 0.6),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: handleTap,
          onLongPress: () => setState(() {
            _selectMode = true;
            _selectedPaths.add(e.path);
          }),
          leading: e.isDirectory
              ? Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.folder_rounded, color: _kAccent, size: 24),
                )
              : _buildLeading(e),
          title: Text(e.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
          subtitle: Text(
            showParentPath
                ? '${e.isDirectory ? 'Folder' : e.sizeLabel}  \u2022  ${p.dirname(e.path)}'
                : (e.isDirectory ? 'Folder' : '${e.sizeLabel}  \u2022  ${_fmtDate(e.modified)}'),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _selectMode
              ? Checkbox(
                  value: selected,
                  activeColor: _kAccent,
                  onChanged: (_) => handleTap(),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 19),
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF334155))),
                  onSelected: (v) {
                    if (v == 'open') handleTap();
                    else if (v == 'extract') _extractArchive(e.path, createSubfolder: true);
                    else if (v == 'extract_here') _extractArchive(e.path, createSubfolder: false);
                    else if (v == 'zip') _compressDialog([e.path]);
                    else if (v == 'targz') _compressDialog([e.path], format: 'tar.gz');
                    else if (v == 'rename') _renameDialog(e);
                    else if (v == 'share' && !e.isDirectory) Share.shareXFiles([XFile(e.path)]);
                    else if (v == 'info') _showPropertiesDialog(e);
                    else if (v == 'delete') _deletePathsDialog([e.path]);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'open', child: Text(e.isDirectory ? 'Open Folder' : (isArchive ? 'Inspect Archive' : 'Open'), style: const TextStyle(color: Colors.white))),
                    if (isArchive) ...[
                      const PopupMenuItem(value: 'extract', child: Text('Extract to Folder', style: TextStyle(color: Color(0xFFFB923C), fontWeight: FontWeight.w600))),
                      const PopupMenuItem(value: 'extract_here', child: Text('Extract Here', style: TextStyle(color: Colors.white))),
                    ],
                    const PopupMenuItem(value: 'zip', child: Text('Compress (.zip)', style: TextStyle(color: Color(0xFF38BDF8)))),
                    const PopupMenuItem(value: 'targz', child: Text('Compress (.tar.gz)', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white))),
                    if (!e.isDirectory)
                      const PopupMenuItem(value: 'share', child: Text('Share', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'info', child: Text('Properties', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
        ),
      ),
    );
  }

  // ─── Archive Operations (Zip / RAR / Tar.gz) ──────────────────────────────

  Future<void> _openArchiveSheet(DeviceEntry archiveEntry) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => FutureBuilder<List<ArchiveEntryInfo>>(
          future: ArchiveService.inspectArchive(archiveEntry.path),
          builder: (_, snap) {
            final entries = snap.data ?? const [];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFB923C).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.folder_zip_rounded, color: Color(0xFFFB923C), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(archiveEntry.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            Text(
                              snap.connectionState == ConnectionState.waiting
                                  ? 'Inspecting archive...'
                                  : '${entries.length} items  \u2022  ${archiveEntry.sizeLabel}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFB923C),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.unarchive_rounded, size: 18),
                          label: const Text('Extract to Folder', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _extractArchive(archiveEntry.path, createSubfolder: true);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF334155)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.drive_folder_upload_rounded, size: 18),
                          label: const Text('Extract Here'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _extractArchive(archiveEntry.path, createSubfolder: false);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: _kBorder),
                Expanded(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFFB923C)))
                      : entries.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Archive preview unavailable for this format — tap Extract to attempt extraction.',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: sc,
                              itemCount: entries.length,
                              itemBuilder: (_, i) {
                                final item = entries[i];
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    item.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                                    color: item.isDirectory ? _kAccent : const Color(0xFF94A3B8),
                                    size: 19,
                                  ),
                                  title: Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                                  trailing: item.isDirectory
                                      ? null
                                      : Text(_fmtBytes(item.size), style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _extractArchive(String archivePath, {required bool createSubfolder}) async {
    final parent = p.dirname(archivePath);
    final stem = p.basenameWithoutExtension(archivePath).replaceAll(RegExp(r'\.tar$', caseSensitive: false), '');
    final destDir = createSubfolder ? ArchiveService.uniquePath(p.join(parent, stem)) : parent;

    _showProgressDialog('Extracting ${p.basename(archivePath)}...');
    final res = await ArchiveService.extractArchive(archivePath: archivePath, destinationDir: destDir);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close progress dialog

    if (res.success) {
      if (!_isHome) _load(_currentPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          content: Text(res.message, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
          action: SnackBarAction(
            label: 'Open Folder',
            textColor: Colors.black,
            onPressed: () => _go(res.outputPath),
          ),
        ),
      );
    } else if (res.canTryExternalFallback) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _kCard,
          title: const Text('Archive Notice', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(res.message, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Colors.white60))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFB923C), foregroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(ctx);
                OpenFilex.open(archivePath);
              },
              child: const Text('Open Externally'),
            ),
          ],
        ),
      );
    } else {
      _toast(res.message);
    }
  }

  Future<void> _compressDialog(List<String> sourcePaths, {String format = 'zip'}) async {
    if (sourcePaths.isEmpty) return;
    final defaultBase = sourcePaths.length == 1
        ? p.basenameWithoutExtension(sourcePaths.first)
        : 'Makaw_Archive_${DateTime.now().millisecondsSinceEpoch}';
    final ctrl = TextEditingController(text: defaultBase);
    final ext = format == 'tar.gz' ? 'tar.gz' : 'zip';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: Text('Compress to .$ext', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${sourcePaths.length} ${sourcePaths.length == 1 ? 'item' : 'items'} selected',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Archive Name',
                suffixText: '.$ext',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
            icon: const Icon(Icons.folder_zip_rounded, size: 17),
            label: const Text('Compress'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final rawName = ctrl.text.trim().isEmpty ? defaultBase : ctrl.text.trim();
    final parent = _isHome ? p.dirname(sourcePaths.first) : _currentPath;
    final cleanName = rawName.endsWith('.$ext') ? rawName : '$rawName.$ext';
    final outPath = ArchiveService.uniquePath(p.join(parent, p.basename(cleanName)));

    _showProgressDialog('Compressing to ${p.basename(outPath)}...');
    final res = format == 'tar.gz'
        ? await ArchiveService.createTarGz(sourcePaths: sourcePaths, outputPath: outPath)
        : await ArchiveService.createZip(sourcePaths: sourcePaths, outputZipPath: outPath);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    setState(() {
      _selectMode = false;
      _selectedPaths.clear();
    });
    if (!_isHome) _load(_currentPath);
    _toast(res.message);
  }

  void _showProgressDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        content: Row(
          children: [
            const CircularProgressIndicator(color: Color(0xFFFB923C)),
            const SizedBox(width: 16),
            Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13))),
          ],
        ),
      ),
    );
  }

  // ─── Folder / File Operations ─────────────────────────────────────────────

  Future<void> _createFolderDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('New Folder', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Folder name', hintStyle: TextStyle(color: Color(0xFF64748B))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create', style: TextStyle(color: _kAccent))),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      try {
        await Directory(p.join(_currentPath, ctrl.text.trim())).create(recursive: true);
        _load(_currentPath);
      } catch (e) {
        _toast('Failed to create folder: $e');
      }
    }
  }

  Future<void> _renameDialog(DeviceEntry entry) async {
    final ctrl = TextEditingController(text: entry.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Rename', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rename', style: TextStyle(color: _kAccent))),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty && ctrl.text.trim() != entry.name) {
      final newPath = p.join(p.dirname(entry.path), ctrl.text.trim());
      try {
        if (entry.isDirectory) {
          await Directory(entry.path).rename(newPath);
        } else {
          await File(entry.path).rename(newPath);
        }
        if (!_isHome) _load(_currentPath);
        if (_searchMode) _triggerSearch(_searchCtrl.text);
      } catch (e) {
        _toast('Rename failed: $e');
      }
    }
  }

  Future<void> _deletePathsDialog(List<String> paths) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: Text('Delete ${paths.length} ${paths.length == 1 ? 'item' : 'items'}?',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('Deleted files cannot be recovered.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final path in paths) {
      try {
        if (Directory(path).existsSync()) {
          Directory(path).deleteSync(recursive: true);
        } else if (File(path).existsSync()) {
          File(path).deleteSync();
        }
      } catch (_) {}
    }
    setState(() {
      _selectMode = false;
      _selectedPaths.clear();
    });
    if (!_isHome) _load(_currentPath);
    if (_searchMode) _triggerSearch(_searchCtrl.text);
  }

  void _showPropertiesDialog(DeviceEntry e) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: Text(e.name, style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Path: ${e.path}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            const SizedBox(height: 6),
            Text('Type: ${e.isDirectory ? 'Folder' : '${e.ext.toUpperCase()} File'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (!e.isDirectory) Text('Size: ${e.sizeLabel} (${e.size} B)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('Modified: ${e.modified.toLocal().toString().split('.').first}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: _kAccent))),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  IconData _fileIcon(String ext) {
    const video = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', '3gp', 'm4v'};
    const audio = {'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma', 'opus'};
    const img = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'};
    const docs = {'pdf', 'epub', 'doc', 'docx', 'odt', 'rtf', 'pages'};
    const code = {'dart', 'js', 'ts', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'go', 'rs', 'json', 'xml', 'yaml', 'yml', 'ini', 'cfg', 'html', 'htm', 'css', 'sh', 'sql', 'lrc', 'srt'};
    if (video.contains(ext)) return Icons.movie_rounded;
    if (audio.contains(ext)) return Icons.music_note_rounded;
    if (img.contains(ext)) return Icons.image_rounded;
    if (docs.contains(ext)) return Icons.description_rounded;
    if (code.contains(ext)) return Icons.code_rounded;
    if (ext == 'apk') return Icons.android_rounded;
    if (ArchiveService.supportedArchiveExts.contains(ext)) return Icons.folder_zip_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _fileColor(String ext) {
    const video = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', '3gp', 'm4v'};
    const audio = {'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma', 'opus'};
    const img = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'};
    const docs = {'pdf', 'epub', 'doc', 'docx', 'odt', 'rtf', 'pages'};
    const code = {'dart', 'js', 'ts', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'go', 'rs', 'json', 'xml', 'yaml', 'yml', 'ini', 'cfg', 'html', 'htm', 'css', 'sh', 'sql', 'lrc', 'srt'};
    if (video.contains(ext)) return const Color(0xFFF87171);
    if (audio.contains(ext)) return const Color(0xFFF472B6);
    if (img.contains(ext)) return const Color(0xFF38BDF8);
    if (docs.contains(ext)) return const Color(0xFFFBBF24);
    if (code.contains(ext)) return const Color(0xFF22D3EE);
    if (ext == 'apk') return const Color(0xFF34D399);
    if (ArchiveService.supportedArchiveExts.contains(ext)) return const Color(0xFFFB923C);
    return const Color(0xFF94A3B8);
  }

  String _displayName(String path) {
    if (path == '/' || path == r'\') return 'Device root';
    final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.last : path;
  }
}
