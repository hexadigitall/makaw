import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/services/document_service.dart';
import '../../../../app/providers/service_providers.dart';

/// The Documents ecosystems tool. Tabs:
///   Folders | All | PDF | EPUB | DOC | TXT | XLS | HTML
///
/// "All" and the per-type tabs list document files (file level) from every
/// folder together in alphabetical order, with search. "Folders" shows the
/// folders that contain documents (folder level); tapping a folder drills into
/// its files.
class DocumentWidget extends ConsumerStatefulWidget {
  final void Function(String filePath) openFile;
  final String initialTab;
  const DocumentWidget({super.key, required this.openFile, this.initialTab = 'all'});

  @override
  ConsumerState<DocumentWidget> createState() => _DocumentWidgetState();
}

class _DocumentWidgetState extends ConsumerState<DocumentWidget> {
  late String _homeTab = widget.initialTab;
  String? _selectedFolder;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  final _kDark = const Color(0xFF0F0F1A);
  final _kAccent = const Color(0xFF818CF8);
  final _kCard = const Color(0xFF1A1A2E);

  static const List<String> _tabs = ['folders', 'all', 'pdf', 'epub', 'doc', 'txt', 'xls', 'html'];

  /// Map tab id -> document category (as stored on DocumentFileInfo).
  static const Map<String, String?> _tabCategory = {
    'all': null,
    'pdf': 'pdf',
    'epub': 'epub',
    'doc': 'doc',
    'txt': 'text',
    'xls': 'xls',
    'html': 'html',
  };

  DocumentService get _service => ref.read(documentServiceProvider) ?? DocumentService();

  @override
  void initState() {
    super.initState();
    if (!_tabs.contains(_homeTab)) _homeTab = 'all';
    final service = ref.read(documentServiceProvider);
    service?.addListener(_onServiceChanged);
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final service = ref.read(documentServiceProvider);
    service?.removeListener(_onServiceChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _categoryIcons = <String, IconData>{
    'pdf': Icons.picture_as_pdf,
    'epub': Icons.menu_book,
    'doc': Icons.description,
    'txt': Icons.text_fields,
    'html': Icons.language,
    'xls': Icons.grid_on,
    'code': Icons.code,
  };

  static const _categoryColors = <String, Color>{
    'pdf': Color(0xFFEF4444),
    'epub': Color(0xFF8B5CF6),
    'doc': Color(0xFF3B82F6),
    'txt': Color(0xFF94A3B8),
    'html': Color(0xFFF59E0B),
    'xls': Color(0xFF10B981),
    'code': Color(0xFF14B8A6),
  };

  String _ext(String path) => path.split('.').last.toLowerCase();
  IconData _icon(String path) => _categoryIcons[_ext(path)] ?? Icons.insert_drive_file;
  Color _color(String path) => _categoryColors[_ext(path)] ?? const Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: _selectedFolder != null ? _buildFolderAppBar() : _buildAppBar(),
      body: _selectedFolder != null ? _buildFolderContents() : _buildBody(),
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    return AppBar(
      backgroundColor: _kDark,
      title: const Text('Documents', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  PreferredSizeWidget _buildFolderAppBar() {
    return AppBar(
      backgroundColor: _kDark,
      title: Text(DocumentService.folderDisplayName(_selectedFolder!),
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => setState(() => _selectedFolder = null),
      ),
    );
  }

  String _tabLabel(String t) {
    switch (t) {
      case 'folders': return 'Folders';
      case 'all': return 'All';
      case 'doc': return 'DOC';
      case 'html': return 'HTML';
      default: return t.toUpperCase();
    }
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildTabs(),
        if (_homeTab != 'folders') _buildSearchBar(),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _tabs.map((t) {
            final active = _homeTab == t;
            return GestureDetector(
              onTap: () => setState(() => _homeTab = t),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? _kAccent : _kCard,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(_tabLabel(t),
                    style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search documents...',
          hintStyle: const TextStyle(color: Color(0xFF666680)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF666680)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear, color: Color(0xFF666680)), onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); })
              : null,
          filled: true,
          fillColor: _kCard,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
      ),
    );
  }

  Widget _buildTabContent() {
    if (_homeTab == 'folders') return _buildFoldersView();
    final docs = _filteredDocs(_homeTab);
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, color: Color(0xFF666680), size: 48),
            const SizedBox(height: 12),
            Text(_service.isScanning ? 'Scanning for documents...' : 'No documents found',
                style: const TextStyle(color: Color(0xFF666680))),
            if (_service.isScanning) ...[
              const SizedBox(height: 12),
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent)),
            ],
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      itemBuilder: (_, i) => _buildDocItem(docs[i]),
    );
  }

  /// File-level list for a tab (All or a specific type), alphabetical by name,
  /// optionally filtered by the search query.
  List<DocumentFileInfo> _filteredDocs(String tab) {
    final category = _tabCategory[tab];
    var docs = category == null
        ? _service.allDocuments
        : _service.allDocuments.where((d) => d.category == category).toList();
    if (_searchQuery.isNotEmpty) {
      docs = docs.where((d) => d.fileName.toLowerCase().contains(_searchQuery)).toList();
    }
    docs.sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
    return docs;
  }

  /// Folder-level view: folders grouped, sorted by file count desc.
  Widget _buildFoldersView() {
    final all = _service.allDocuments;
    if (all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_outlined, color: Color(0xFF666680), size: 48),
            const SizedBox(height: 12),
            Text(_service.isScanning ? 'Scanning for documents...' : 'No folders found',
                style: const TextStyle(color: Color(0xFF666680))),
            if (_service.isScanning) ...[
              const SizedBox(height: 12),
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent)),
            ],
          ],
        ),
      );
    }
    final byFolder = <String, List<DocumentFileInfo>>{};
    for (final d in all) {
      byFolder.putIfAbsent(d.folder, () => []).add(d);
    }
    final folderEntries = byFolder.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: folderEntries.length,
      itemBuilder: (_, i) {
        final entry = folderEntries[i];
        final docs = entry.value;
        return GestureDetector(
          onTap: () => setState(() => _selectedFolder = entry.key),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _kAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.folder, color: Color(0xFF818CF8), size: 24),
              ),
              title: Text(DocumentService.folderDisplayName(entry.key),
                  style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
              subtitle: Text('${docs.length} file${docs.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Color(0xFF666680), fontSize: 11)),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF666680)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderContents() {
    final docs = _service.folders[_selectedFolder] ?? [];
    if (docs.isEmpty) {
      return const Center(child: Text('Folder is empty', style: TextStyle(color: Color(0xFF666680))));
    }
    final sorted = List<DocumentFileInfo>.from(docs)
      ..sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      itemBuilder: (_, i) => _buildDocItem(sorted[i]),
    );
  }

  Widget _buildDocItem(DocumentFileInfo doc) {
    final isFav = _service.isFavorite(doc.id);
    return GestureDetector(
      onTap: () => widget.openFile(doc.filePath),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _color(doc.filePath).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(_icon(doc.filePath), color: _color(doc.filePath), size: 24),
          ),
          title: Text(doc.fileName, style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
          subtitle: Text('${_ext(doc.filePath).toUpperCase()} · ${DocumentService.folderDisplayName(doc.folder)}',
              style: const TextStyle(color: Color(0xFF666680), fontSize: 11)),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF666680), size: 20),
            onSelected: (v) {
              if (v == 'share') Share.shareXFiles([XFile(doc.filePath)]);
              if (v == 'fav') _toggleFavoriteWithUndo(doc);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share, color: Colors.white70), title: Text('Share', style: TextStyle(color: Colors.white)))),
              PopupMenuItem(value: 'fav', child: ListTile(
                leading: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : Colors.white70),
                title: Text(isFav ? 'Unfavourite' : 'Favourite', style: const TextStyle(color: Colors.white)),
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleFavoriteWithUndo(DocumentFileInfo doc) {
    final wasFav = _service.isFavorite(doc.id);
    _service.toggleFavorite(doc.id);
    setState(() {});

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasFav ? 'Removed from favourites' : 'Added to favourites'),
        action: SnackBarAction(
          label: 'Undo',
          textColor: _kAccent,
          onPressed: () {
            _service.toggleFavorite(doc.id);
            setState(() {});
          },
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF1E293B),
      ),
    );
  }
}
