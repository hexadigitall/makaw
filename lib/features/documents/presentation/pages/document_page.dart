import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/services/document_service.dart';
import '../../../../app/providers/service_providers.dart';

class DocumentWidget extends ConsumerStatefulWidget {
  final void Function(String filePath) openFile;
  const DocumentWidget({super.key, required this.openFile});
  @override
  ConsumerState<DocumentWidget> createState() => _DocumentWidgetState();
}

class _DocumentWidgetState extends ConsumerState<DocumentWidget> {
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

  DocumentService get _service => ref.read(documentServiceProvider) ?? DocumentService();

  @override
  void initState() {
    super.initState();
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
    'docx': Icons.description,
    'txt': Icons.text_fields,
  };

  static const _categoryColors = <String, Color>{
    'pdf': Color(0xFFEF4444),
    'epub': Color(0xFF8B5CF6),
    'doc': Color(0xFF3B82F6),
    'docx': Color(0xFF3B82F6),
    'txt': Color(0xFF94A3B8),
  };

  String _ext(String path) => path.split('.').last.toLowerCase();
  IconData _icon(String path) => _categoryIcons[_ext(path)] ?? Icons.insert_drive_file;
  Color _color(String path) => _categoryColors[_ext(path)] ?? const Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: _page == 'viewer' ? null : _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _kDark,
      title: Text(_appBarTitle(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      leading: _selectedFolder != null
          ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => setState(() => _page = 'home'))
          : null,
      actions: [
        if (_page == 'home')
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => setState(() { _page = 'search'; _searchCtrl.text = _searchQuery; }),
          ),
      ],
    );
  }

  String _appBarTitle() {
    if (_page == 'search') return 'Search';
    if (_selectedFolder != null) return _selectedFolder!;
    return 'Documents';
  }

  Widget _buildBody() {
    if (_page == 'search') return _buildSearchPage();
    if (_selectedFolder != null) return _buildFolderContents();
    return Column(
      children: [
        _buildHomeTabs(),
        Expanded(child: _buildHomeContent()),
      ],
    );
  }

  Widget _buildHomeTabs() {
    final tabs = ['all', 'pdf', 'epub', 'txt'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: tabs.map((t) {
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
              child: Text(t == 'all' ? 'All' : t.toUpperCase(),
                  style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHomeContent() {
    final docs = _service.allDocuments;
    final filtered = _homeTab == 'all' ? docs : docs.where((d) => _ext(d.filePath) == _homeTab).toList();
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, color: Color(0xFF666680), size: 48),
            const SizedBox(height: 12),
            Text(_service.isScanning ? 'Scanning...' : 'No documents found', style: const TextStyle(color: Color(0xFF666680))),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (_, i) => _buildDocItem(filtered[i]),
    );
  }

  Widget _buildDocItem(DocumentFileInfo doc) {
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
          subtitle: Text(_ext(doc.filePath).toUpperCase(), style: const TextStyle(color: Color(0xFF666680), fontSize: 11)),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF666680), size: 20),
            onSelected: (v) {
              if (v == 'share') Share.shareXFiles([XFile(doc.filePath)]);
              if (v == 'fav') { _service.toggleFavorite(doc.id); setState(() {}); }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share, color: Colors.white70), title: Text('Share', style: TextStyle(color: Colors.white)))),
              PopupMenuItem(value: 'fav', child: ListTile(
                leading: Icon(_service.isFavorite(doc.id) ? Icons.star : Icons.star_border, color: Colors.white70),
                title: Text(_service.isFavorite(doc.id) ? 'Unfavourite' : 'Favourite', style: const TextStyle(color: Colors.white)),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderContents() {
    if (_selectedFolder == null) return const SizedBox();
    final docs = _service.folders[_selectedFolder] ?? [];
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      itemBuilder: (_, i) => _buildDocItem(docs[i]),
    );
  }

  Widget _buildSearchPage() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search documents...',
              hintStyle: const TextStyle(color: Color(0xFF666680)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF666680)),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, color: Color(0xFF666680)), onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); })
                  : null,
              filled: true,
              fillColor: _kCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
        ),
        Expanded(child: _buildSearchResults()),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) return const SizedBox();
    final results = _service.allDocuments.where((d) => d.fileName.toLowerCase().contains(_searchQuery)).toList();
    if (results.isEmpty) {
      return const Center(child: Text('No results', style: TextStyle(color: Color(0xFF666680))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      itemBuilder: (_, i) => _buildDocItem(results[i]),
    );
  }
}
