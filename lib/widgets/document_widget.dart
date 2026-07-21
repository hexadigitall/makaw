import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/document_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Document Browser Widget
// ─────────────────────────────────────────────────────────────────────────────
class DocumentWidget extends StatefulWidget {
  final DocumentService service;
  final void Function(String filePath) openFile;
  const DocumentWidget({super.key, required this.service, required this.openFile});
  @override
  State<DocumentWidget> createState() => _DocumentWidgetState();
}

class _DocumentWidgetState extends State<DocumentWidget> {
  String _page = 'home';
  String _homeTab = 'all';
  String _browseSection = 'favourites';
  String? _selectedFolder;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  final _kDark = const Color(0xFF0F0F1A);
  final _kAccent = const Color(0xFF818CF8);
  final _kCard = const Color(0xFF1A1A2E);
  final _kMuted = const Color(0xFF666680);

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);
    if (widget.service.allDocuments.isEmpty && !widget.service.isScanning) {
      // scan disabled — see main.dart
    }
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _categoryIcons = <String, IconData>{
    'pdf': Icons.picture_as_pdf,
    'epub': Icons.book,
    'doc': Icons.description,
    'text': Icons.text_snippet,
    'html': Icons.code,
    'code': Icons.terminal,
    'other': Icons.insert_drive_file,
  };

  static const _categoryLabels = <String, String>{
    'pdf': 'PDF', 'epub': 'EPUB', 'doc': 'Doxuments',
    'text': 'Text', 'html': 'HTML', 'code': 'Code',
  };

  @override
  Widget build(BuildContext context) {
    final isHome = _page == 'home';
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        backgroundColor: _kDark,
        title: _page == 'search'
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(hintText: 'Search documents...', hintStyle: TextStyle(color: Color(0xFF666680)), border: InputBorder.none),
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              )
            : Text(
                _page == 'browse' ? 'Browse' :
                _page == 'favorites_page' ? 'Favourites' :
                _page == 'folders_page' ? 'Folders' :
                'Makaw Doxuments',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
        leading: !isHome
            ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => setState(() => _page = 'home'))
            : null,
        actions: [
          if (isHome) ...[
            IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () => setState(() { _page = 'search'; _searchCtrl.clear(); _searchQuery = ''; })),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) {
                if (v == 'refresh') widget.service.scanAllDocuments();
                else if (v == 'fav') setState(() => _page = 'favorites_page');
                else if (v == 'folders') setState(() => _page = 'folders_page');
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'fav', child: ListTile(leading: Icon(Icons.favorite), title: Text('Favourites'))),
                PopupMenuItem(value: 'folders', child: ListTile(leading: Icon(Icons.folder), title: Text('Folders'))),
                PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh), title: Text('Refresh'))),
              ],
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_page == 'search') return _buildSearchPage();
    if (_page == 'browse') return _buildBrowsePage();
    if (_page == 'favorites_page') return _buildFavoritesPage();
    if (_page == 'folders_page') return _buildFoldersPage();
    return RefreshIndicator(
      onRefresh: () => widget.service.scanAllDocuments(),
      color: const Color(0xFF818CF8),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: _buildHomePage(),
      ),
    );
  }

  // ─── Home Page ─────────────────────────────────────────────────────────────
  Widget _buildHomePage() {
    return Column(
      children: [
        // Category tabs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tabBtn('All', _homeTab == 'all'),
                const SizedBox(width: 8),
                _tabBtn('PDF', _homeTab == 'pdf'),
                const SizedBox(width: 8),
                _tabBtn('EPUB', _homeTab == 'epub'),
                const SizedBox(width: 8),
                _tabBtn('Docs', _homeTab == 'doc'),
                const SizedBox(width: 8),
                _tabBtn('Text', _homeTab == 'text'),
                const SizedBox(width: 8),
                _tabBtn('HTML', _homeTab == 'html'),
                const SizedBox(width: 8),
                _tabBtn('Code', _homeTab == 'code'),
              ],
            ),
          ),
        ),
        Expanded(child: _buildCategoryTab()),
      ],
    );
  }

  Widget _tabBtn(String label, bool active) {
    return GestureDetector(
      onTap: () => setState(() => _homeTab = label.toLowerCase()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(color: active ? _kAccent : _kCard, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  List<DocumentFileInfo> _filteredDocs() {
    final docs = widget.service.allDocuments;
    if (_homeTab == 'all') return docs;
    return docs.where((d) => d.category == _homeTab).toList();
  }

  Widget _buildCategoryTab() {
    final docs = _filteredDocs();
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description, color: Color(0xFF666680), size: 48),
            const SizedBox(height: 12),
              Text(widget.service.isScanning ? 'Scanning...' : 'No documents found',
                style: const TextStyle(color: Color(0xFF666680))),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 1.2),
      itemCount: docs.length,
      itemBuilder: (_, i) => _docCard(docs[i]),
    );
  }

  // ─── Search Page ───────────────────────────────────────────────────────────
  Widget _buildSearchPage() {
    final results = widget.service.allDocuments.where((d) =>
        d.fileName.toLowerCase().contains(_searchQuery) ||
        d.folder.toLowerCase().contains(_searchQuery)).toList();
    if (_searchQuery.isEmpty) {
      return const Center(child: Text('Type to search', style: TextStyle(color: Color(0xFF666680))));
    }
    if (results.isEmpty) {
      return const Center(child: Text('No results', style: TextStyle(color: Color(0xFF666680))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: results.length,
      itemBuilder: (_, i) => _docListTile(results[i]),
    );
  }

  // ─── Browse Page ───────────────────────────────────────────────────────────
  Widget _buildBrowsePage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _browseTile(Icons.favorite, 'Favourites', () => setState(() => _page = 'favorites_page')),
        const SizedBox(height: 12),
        _browseTile(Icons.folder, 'Folders', () => setState(() => _page = 'folders_page')),
        const SizedBox(height: 12),
        _browseTile(Icons.refresh, 'Refresh', () => widget.service.scanAllDocuments()),
      ],
    );
  }

  Widget _browseTile(IconData icon, String label, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: _kAccent),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF666680)),
        onTap: onTap,
      ),
    );
  }

  // ─── Favorites Page ────────────────────────────────────────────────────────
  Widget _buildFavoritesPage() {
    final favs = widget.service.favorites;
    if (favs.isEmpty) {
      return const Center(child: Text('No favourites yet', style: TextStyle(color: Color(0xFF666680))));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 1.2),
      itemCount: favs.length,
      itemBuilder: (_, i) => _docCard(favs[i]),
    );
  }

  // ─── Folders Page ──────────────────────────────────────────────────────────
  Widget _buildFoldersPage() {
    final folders = widget.service.folders.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (folders.isEmpty) {
      return const Center(child: Text('No folders', style: TextStyle(color: Color(0xFF666680))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: folders.length,
      itemBuilder: (_, i) {
        final entry = folders[i];
        return GestureDetector(
          onTap: () {
            setState(() { _selectedFolder = entry.key; _page = 'browse'; });
            _showFolderDocsSheet(entry.key, entry.value);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Color(0xFF818CF8), size: 32),
                const SizedBox(width: 12),
                Expanded(child: Text(entry.key, style: const TextStyle(color: Colors.white, fontSize: 15))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: _kDark, borderRadius: BorderRadius.circular(10)),
                  child: Text('${entry.value.length}', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Color(0xFF666680)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFolderDocsSheet(String folder, List<DocumentFileInfo> docs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.folder, color: Color(0xFF818CF8)),
                  const SizedBox(width: 8),
                  Text(folder, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${docs.length}', style: const TextStyle(color: Color(0xFF666680))),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2A3E), height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(8),
                itemCount: docs.length,
                itemBuilder: (_, i) => _docListTile(docs[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Doc Card (grid) ───────────────────────────────────────────────────────
  Widget _docCard(DocumentFileInfo d) {
    final icon = _categoryIcons[d.category] ?? Icons.insert_drive_file;
    return GestureDetector(
      onTap: () => widget.openFile(d.filePath),
      child: Container(
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: _kAccent, size: 36),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(d.fileName, style: const TextStyle(color: Colors.white, fontSize: 10),
                      overflow: TextOverflow.ellipsis, maxLines: 1, textAlign: TextAlign.center),
                ),
                Text('${d.folder} · ${_sizeStr(d.fileSize)}',
                    style: const TextStyle(color: Color(0xFF666680), fontSize: 8)),
              ],
            ),
            Positioned(
              top: 2, right: 2,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white, size: 16),
                onSelected: (opt) => _docMenuAction(opt, d),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(
                    value: 'favorite',
                    child: Text(widget.service.isFavorite(d.id) ? 'Remove from favourites' : 'Add to favourites'),
                  ),
                  const PopupMenuItem(value: 'share', child: Text('Share')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
            if (widget.service.isFavorite(d.id))
              const Positioned(
                top: 2, left: 2,
                child: Icon(Icons.favorite, color: Color(0xFF818CF8), size: 14),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Doc List Tile (list) ──────────────────────────────────────────────────
  Widget _docListTile(DocumentFileInfo d) {
    final icon = _categoryIcons[d.category] ?? Icons.insert_drive_file;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: _kAccent, size: 28),
        title: Text(d.fileName, style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis),
        subtitle: Text('${d.folder} · ${_sizeStr(d.fileSize)}',
            style: const TextStyle(color: Color(0xFF666680), fontSize: 11)),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Color(0xFF666680), size: 18),
          onSelected: (opt) => _docMenuAction(opt, d),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: Text('Open')),
            PopupMenuItem(
              value: 'favorite',
              child: Text(widget.service.isFavorite(d.id) ? 'Remove from favourites' : 'Add to favourites'),
            ),
            const PopupMenuItem(value: 'share', child: Text('Share')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => widget.openFile(d.filePath),
      ),
    );
  }

  void _docMenuAction(String opt, DocumentFileInfo d) {
    if (opt == 'open') widget.openFile(d.filePath);
    else if (opt == 'favorite') {
      widget.service.toggleFavorite(d.id);
      _toast(widget.service.isFavorite(d.id) ? 'Added to favourites' : 'Removed from favourites');
    } else if (opt == 'share') Share.shareXFiles([XFile(d.filePath)]);
    else if (opt == 'delete') _deleteConfirm(d);
  }

  void _deleteConfirm(DocumentFileInfo d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDark,
        title: const Text('Delete document', style: TextStyle(color: Colors.white)),
        content: Text('Delete "${d.fileName}"?', style: const TextStyle(color: Color(0xFF666680))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              try { File(d.filePath).deleteSync(); } catch (_) {}
              widget.service.allDocuments.removeWhere((x) => x.id == d.id);
              widget.service.notifyListeners();
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: _kCard,
      duration: const Duration(seconds: 2),
    ));
  }

  String _sizeStr(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
