import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../../../app/providers/service_providers.dart';
import '../../../../core/utils/natural_sort.dart';
import '../../../../core/ui/makaw_toast.dart';
import '../../../../core/platform/platform_paths.dart';
import '../../../pdf/presentation/pages/pdf_merger_page.dart';
import '../../../pdf/presentation/pages/pdf_organizer_page.dart';
import '../../data/services/archive_service.dart';
import '../../data/services/document_service.dart';
import '../../data/services/document_state_service.dart';
import '../../data/services/document_thumbnail_service.dart';
import '../../domain/document_reader_contract.dart';

enum _DocSort { recent, name, progress, size, ext }

/// Redesigned Makaw Documents Library & Reading Workspace (`DocumentWidget`).
///
/// Distinct from File Explorer ([FoldersPage]): focuses on readable knowledge,
/// 7 semantic format families across ~145 extensions, cover thumbnails,
/// SQLite [DocumentReadingState] progress bars, collections, PDF utilities,
/// and a native 3-pane workspace on Desktop (>= 900px).
class DocumentWidget extends ConsumerStatefulWidget {
  final void Function(String filePath) openFile;
  final void Function(String filePath)? onRevealInExplorer;
  final String initialTab;
  final bool autoScan;

  const DocumentWidget({
    super.key,
    required this.openFile,
    this.onRevealInExplorer,
    this.initialTab = 'all',
    this.autoScan = true,
  });

  @override
  ConsumerState<DocumentWidget> createState() => _DocumentWidgetState();
}

class _DocumentWidgetState extends ConsumerState<DocumentWidget> {
  static const _kDark = Color(0xFF0A0F1A);
  static const _kSurface = Color(0xFF121826);
  static const _kCard = Color(0xFF171F33);
  static const _kBorder = Color(0xFF25304A);
  static const _kAccent = Color(0xFF818CF8);
  static const _kMuted = Color(0xFF94A3B8);

  late String _activeFilter;
  String? _activeExtChip;
  int? _activeCollectionId;
  String? _selectedFolder;
  bool _gridMode = false;
  bool _showSearch = false;
  bool _selectMode = false;
  final Set<String> _selectedPaths = {};
  String _searchQuery = '';
  _DocSort _sortBy = _DocSort.recent;
  DocumentFileInfo? _inspectedDoc;
  DocumentService? _boundService;
  final TextEditingController _searchCtrl = TextEditingController();

  DocumentService get _service => _boundService ?? ref.read(documentServiceProvider) ?? DocumentService();

  @override
  void initState() {
    super.initState();
    _initFilterFromTab(widget.initialTab);
    _boundService = ref.read(documentServiceProvider);
    _boundService?.addListener(_onServiceChanged);
    DocumentStateService.version.addListener(_onServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DocumentStateService.warmCache();
      if (widget.autoScan && _service.allDocuments.isEmpty && !_service.isScanning) {
        _service.scanAllDocuments();
      }
    });
  }

  void _initFilterFromTab(String raw) {
    final tab = raw.toLowerCase();
    switch (tab) {
      case 'pdf':
        _activeFilter = 'family:${DocumentFamily.booksComics.id}';
        _activeExtChip = 'pdf';
        break;
      case 'epub':
        _activeFilter = 'family:${DocumentFamily.booksComics.id}';
        _activeExtChip = 'epub';
        break;
      case 'comic':
        _activeFilter = 'family:${DocumentFamily.booksComics.id}';
        break;
      case 'doc':
        _activeFilter = 'family:${DocumentFamily.docsNotes.id}';
        break;
      case 'txt':
        _activeFilter = 'family:${DocumentFamily.docsNotes.id}';
        break;
      case 'xls':
      case 'sheets':
        _activeFilter = 'family:${DocumentFamily.sheetsData.id}';
        break;
      case 'html':
      case 'code':
      case 'markup':
        _activeFilter = 'family:${DocumentFamily.markupTech.id}';
        break;
      case 'slides':
        _activeFilter = 'family:${DocumentFamily.slides.id}';
        break;
      case 'pim':
        _activeFilter = 'family:${DocumentFamily.mailPim.id}';
        break;
      case 'vector':
        _activeFilter = 'family:${DocumentFamily.vectorCad.id}';
        break;
      case 'folders':
        _activeFilter = 'folders';
        break;
      default:
        _activeFilter = 'all';
    }
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _boundService?.removeListener(_onServiceChanged);
    DocumentStateService.version.removeListener(_onServiceChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filtering & Sorting ────────────────────────────────────────────────────

  List<DocumentFileInfo> _baseFilteredDocs() {
    var list = List<DocumentFileInfo>.from(_service.allDocuments);

    if (_activeCollectionId != null) {
      final paths = DocumentStateService.pathsInCollection(_activeCollectionId!);
      list = list.where((d) => paths.contains(d.filePath)).toList();
    } else if (_activeFilter == 'continue') {
      list = list.where((d) {
        final st = DocumentStateService.peekState(d.filePath);
        return st != null && (st.readingStatus == ReadingStatus.reading || st.normalizedProgress > 0.01);
      }).toList();
    } else if (_activeFilter == 'pinned') {
      list = list.where((d) {
        final st = DocumentStateService.peekState(d.filePath);
        return (st?.isPinned ?? false) || _service.isFavorite(d.id);
      }).toList();
    } else if (_activeFilter == 'unread') {
      list = list.where((d) {
        final st = DocumentStateService.peekState(d.filePath);
        return st == null || st.readingStatus == ReadingStatus.unread;
      }).toList();
    } else if (_activeFilter == 'finished') {
      list = list.where((d) {
        final st = DocumentStateService.peekState(d.filePath);
        return st?.readingStatus == ReadingStatus.finished;
      }).toList();
    } else if (_activeFilter.startsWith('family:')) {
      final famId = _activeFilter.substring('family:'.length);
      final family = DocumentFamily.values.firstWhere(
        (f) => f.id == famId,
        orElse: () => DocumentFamily.booksComics,
      );
      list = list.where((d) => DocumentFormatRegistry.familyFor(d.fileName) == family).toList();
    }

    if (_searchQuery.isNotEmpty) {
      list = list.where((d) {
        final q = _searchQuery;
        return d.fileName.toLowerCase().contains(q) ||
            DocumentService.folderDisplayName(d.folder).toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  Map<String, int> _extCounts(List<DocumentFileInfo> docs) {
    final counts = <String, int>{};
    for (final d in docs) {
      final ext = DocumentFormatRegistry.normalizeExtension(d.fileName).toUpperCase();
      if (ext.isEmpty) continue;
      counts[ext] = (counts[ext] ?? 0) + 1;
    }
    return counts;
  }

  List<DocumentFileInfo> _applyExtAndSort(List<DocumentFileInfo> docs) {
    var result = docs;
    if (_activeExtChip != null) {
      result = result
          .where((d) => DocumentFormatRegistry.normalizeExtension(d.fileName) == _activeExtChip)
          .toList();
    }
    result.sort((a, b) {
      switch (_sortBy) {
        case _DocSort.name:
          return naturalCompare(a.fileName, b.fileName);
        case _DocSort.size:
          return b.fileSize.compareTo(a.fileSize);
        case _DocSort.ext:
          final cmp = DocumentFormatRegistry.normalizeExtension(a.fileName)
              .compareTo(DocumentFormatRegistry.normalizeExtension(b.fileName));
          return cmp != 0 ? cmp : naturalCompare(a.fileName, b.fileName);
        case _DocSort.progress:
          final pa = DocumentStateService.peekState(a.filePath)?.normalizedProgress ?? 0.0;
          final pb = DocumentStateService.peekState(b.filePath)?.normalizedProgress ?? 0.0;
          final cmp = pb.compareTo(pa);
          return cmp != 0 ? cmp : naturalCompare(a.fileName, b.fileName);
        case _DocSort.recent:
          final la = DocumentStateService.peekState(a.filePath)?.lastRead ?? a.dateTime ?? DateTime(1970);
          final lb = DocumentStateService.peekState(b.filePath)?.lastRead ?? b.dateTime ?? DateTime(1970);
          return lb.compareTo(la);
      }
    });
    return result;
  }

  List<DocumentFileInfo> _continueDocs() {
    final all = _service.allDocuments;
    final withState = <(DocumentFileInfo, DocumentReadingState)>[];
    for (final d in all) {
      final st = DocumentStateService.peekState(d.filePath);
      if (st != null && (st.readingStatus == ReadingStatus.reading || st.normalizedProgress > 0.01)) {
        withState.add((d, st));
      }
    }
    withState.sort((a, b) => b.$2.lastRead.compareTo(a.$2.lastRead));
    return withState.map((e) => e.$1).take(10).toList();
  }

  bool _isNewDoc(DocumentFileInfo doc) {
    if (doc.dateTime != null && DateTime.now().difference(doc.dateTime!).inHours < 72) {
      return true;
    }
    final folder = doc.folder.toLowerCase();
    return folder.contains('download') || folder.contains('received');
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildDocSelectionBar(List<DocumentFileInfo> scope) {
    final selectedDocs = scope.where((d) => _selectedPaths.contains(d.filePath)).toList();
    final pdfPaths = selectedDocs
        .where((d) => DocumentFormatRegistry.normalizeExtension(d.fileName) == 'pdf')
        .map((d) => d.filePath)
        .toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1A2238),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => setState(() {
              _selectMode = false;
              _selectedPaths.clear();
            }),
          ),
          Text('${_selectedPaths.length} selected', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.select_all_rounded, color: Colors.white70, size: 20),
            tooltip: 'Select All',
            onPressed: () => setState(() => _selectedPaths.addAll(scope.map((d) => d.filePath))),
          ),
          if (pdfPaths.length >= 2)
            IconButton(
              icon: const Icon(Icons.merge_type_rounded, color: Color(0xFFEF4444), size: 20),
              tooltip: 'Open PDF Merger',
              onPressed: () {
                setState(() {
                  _selectMode = false;
                  _selectedPaths.clear();
                });
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PdfMergerPage()));
              },
            ),
          IconButton(
            icon: const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
            tooltip: 'Pin Selected',
            onPressed: _selectedPaths.isEmpty
                ? null
                : () async {
                    for (final d in selectedDocs) {
                      await DocumentStateService.saveProgress(d.filePath, title: d.fileName, isPinned: true);
                    }
                    if (mounted) {
                      setState(() {
                        _selectMode = false;
                        _selectedPaths.clear();
                      });
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.folder_zip_outlined, color: Color(0xFFFB923C), size: 20),
            tooltip: 'Archive Selected as ZIP',
            onPressed: _selectedPaths.isEmpty
                ? null
                : () async {
                    final outZip = p.join(
                      PlatformPaths.defaultDownloadsHint(),
                      'makaw_docs_${DateTime.now().millisecondsSinceEpoch}.zip',
                    );
                    final res = await ArchiveService.createZip(sourcePaths: _selectedPaths.toList(), outputZipPath: outZip);
                    if (!mounted) return;
                    setState(() {
                      _selectMode = false;
                      _selectedPaths.clear();
                    });
                    if (res.success) {
                      MakawToast.success(context, 'ZIP saved: ${p.basename(outZip)}');
                    } else {
                      MakawToast.error(context, res.message);
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFF38BDF8), size: 20),
            tooltip: 'Share Selected',
            onPressed: _selectedPaths.isEmpty
                ? null
                : () => Share.shareXFiles(_selectedPaths.map((e) => XFile(e)).toList()),
          ),
        ],
      ),
    );
  }

  // ── UI Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selectMode && _selectedFolder == null && !_showSearch,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectMode) {
          setState(() {
            _selectMode = false;
            _selectedPaths.clear();
          });
          return;
        }
        if (_showSearch) {
          setState(() {
            _showSearch = false;
            _searchCtrl.clear();
            _searchQuery = '';
          });
          return;
        }
        if (_selectedFolder != null) {
          setState(() => _selectedFolder = null);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          return Scaffold(
            backgroundColor: _kDark,
            appBar: _buildAppBar(isDesktop),
            body: isDesktop ? _buildDesktopBody() : _buildMobileBody(),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDesktop) {
    if (_selectedFolder != null) {
      return AppBar(
        backgroundColor: _kSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => setState(() => _selectedFolder = null),
        ),
        title: Text(
          DocumentService.folderDisplayName(_selectedFolder!),
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );
    }

    return AppBar(
      backgroundColor: _kSurface,
      elevation: 0,
      titleSpacing: 4,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        },
      ),
      title: _showSearch && !isDesktop
          ? TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Search books, docs, sheets, slides...',
                hintStyle: TextStyle(color: _kMuted, fontSize: 14),
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            )
          : Row(
              children: [
                const Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Documents',
                      maxLines: 1,
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_service.allDocuments.length}',
                    style: const TextStyle(color: _kAccent, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
      actions: [
        if (!isDesktop)
          IconButton(
            icon: Icon(_showSearch ? Icons.close_rounded : Icons.search_rounded, color: Colors.white),
            tooltip: _showSearch ? 'Close Search' : 'Search Documents',
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchCtrl.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
        if (isDesktop) ...[
          IconButton(
            icon: Icon(_gridMode ? Icons.view_list_rounded : Icons.grid_view_rounded, color: Colors.white),
            tooltip: _gridMode ? 'List View' : 'Cover Grid View',
            onPressed: () => setState(() => _gridMode = !_gridMode),
          ),
          PopupMenuButton<_DocSort>(
            icon: const Icon(Icons.sort_rounded, color: Colors.white),
            color: const Color(0xFF1A2238),
            tooltip: 'Sort Documents',
            onSelected: (s) => setState(() => _sortBy = s),
            itemBuilder: (_) => [
              _sortItem(_DocSort.recent, 'Recently Opened / Modified'),
              _sortItem(_DocSort.name, 'Name (0-9, A-Z)'),
              _sortItem(_DocSort.progress, 'Reading Progress'),
              _sortItem(_DocSort.size, 'Largest First'),
              _sortItem(_DocSort.ext, 'File Format'),
            ],
          ),
        ],
        IconButton(
          icon: const Icon(Icons.build_circle_outlined, color: _kAccent),
          tooltip: 'Document Tools & Folders',
          onPressed: _openToolsSheet,
        ),
      ],
    );
  }

  Widget _buildMobileControlStrip(int shownCount) {
    final sortLabel = switch (_sortBy) {
      _DocSort.recent => 'Recent',
      _DocSort.name => 'Name',
      _DocSort.progress => 'Progress',
      _DocSort.size => 'Size',
      _DocSort.ext => 'Format',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$shownCount ${shownCount == 1 ? 'document' : 'documents'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _kMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<_DocSort>(
            color: const Color(0xFF1A2238),
            onSelected: (s) => setState(() => _sortBy = s),
            itemBuilder: (_) => [
              _sortItem(_DocSort.recent, 'Recently Opened / Modified'),
              _sortItem(_DocSort.name, 'Name (0-9, A-Z)'),
              _sortItem(_DocSort.progress, 'Reading Progress'),
              _sortItem(_DocSort.size, 'Largest First'),
              _sortItem(_DocSort.ext, 'File Format'),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort_rounded, color: _kMuted, size: 14),
                  const SizedBox(width: 5),
                  Text(sortLabel, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _gridMode = !_gridMode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_gridMode ? Icons.view_list_rounded : Icons.grid_view_rounded, color: _kAccent, size: 14),
                  const SizedBox(width: 4),
                  Text(_gridMode ? 'List' : 'Grid', style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_DocSort> _sortItem(_DocSort sort, String label) {
    final active = _sortBy == sort;
    return PopupMenuItem(
      value: sort,
      child: Row(
        children: [
          Icon(active ? Icons.check_circle_rounded : Icons.circle_outlined, color: active ? _kAccent : _kMuted, size: 17),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  // ── Mobile Body ────────────────────────────────────────────────────────────

  Widget _buildMobileBody() {
    if (_selectedFolder != null) return _buildFolderContents();
    final base = _baseFilteredDocs();
    final extCounts = _extCounts(base);
    final docs = _applyExtAndSort(base);
    final continueItems = (_activeFilter == 'all' && _searchQuery.isEmpty) ? _continueDocs() : const <DocumentFileInfo>[];

    return Column(
      children: [
        if (_selectMode) _buildDocSelectionBar(docs),
        _buildFilterPillStrip(),
        if (_activeFilter != 'folders' && extCounts.length > 1) _buildDynamicExtChips(base.length, extCounts),
        if (_activeFilter != 'folders') _buildMobileControlStrip(docs.length),
        Expanded(
          child: RefreshIndicator(
            color: _kAccent,
            onRefresh: _service.scanAllDocuments,
            child: _activeFilter == 'folders'
                ? _buildFoldersView()
                : docs.isEmpty && continueItems.isEmpty
                    ? _buildEmptyState()
                    : CustomScrollView(
                        slivers: [
                          if (continueItems.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                                child: Row(
                                  children: [
                                    const Text('CONTINUE READING', style: TextStyle(color: _kMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                    const Spacer(),
                                    Text('${continueItems.length} active', style: const TextStyle(color: _kAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(child: _buildContinueCarousel(continueItems)),
                          ],
                          if (_gridMode)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                              sliver: SliverGrid(
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 175,
                                  childAspectRatio: 0.70,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 12,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => _buildGridCard(docs[i]),
                                  childCount: docs.length,
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => _buildDocRow(docs[i]),
                                  childCount: docs.length,
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }

  // ── Desktop 3-Pane Body ────────────────────────────────────────────────────

  Widget _buildDesktopBody() {
    if (_selectedFolder != null) return _buildFolderContents();
    final base = _baseFilteredDocs();
    final extCounts = _extCounts(base);
    final docs = _applyExtAndSort(base);
    final selected = _inspectedDoc != null && docs.any((d) => d.filePath == _inspectedDoc!.filePath)
        ? _inspectedDoc!
        : (docs.isNotEmpty ? docs.first : null);

    return Row(
      children: [
        // Left Rail: Shelves + 7 Families + Collections
        Container(
          width: 225,
          color: _kSurface,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            children: [
              _sidebarHeader('SHELVES'),
              _sidebarTile('all', Icons.auto_stories_rounded, 'All Documents', count: _service.allDocuments.length),
              _sidebarTile('continue', Icons.play_circle_outline_rounded, 'Continue Reading', count: _continueDocs().length),
              _sidebarTile('pinned', Icons.star_rounded, 'Pinned & Starred'),
              _sidebarTile('unread', Icons.markunread_mailbox_outlined, 'Unread'),
              _sidebarTile('finished', Icons.check_circle_outline_rounded, 'Finished'),
              _sidebarTile('folders', Icons.folder_copy_outlined, 'Library Folders', count: _service.folders.length),
              const SizedBox(height: 12),
              _sidebarHeader('FORMAT FAMILIES'),
              for (final fam in DocumentFamily.values)
                _sidebarTile(
                  'family:${fam.id}',
                  _familyIcon(fam),
                  fam.label,
                  count: (_service.byFamily[fam] ?? const []).length,
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _sidebarHeader('COLLECTIONS')),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: _kAccent, size: 18),
                    tooltip: 'New Collection',
                    visualDensity: VisualDensity.compact,
                    onPressed: _promptCreateCollection,
                  ),
                ],
              ),
              for (final col in DocumentStateService.cachedCollections)
                ListTile(
                  dense: true,
                  selected: _activeCollectionId == col.id,
                  selectedTileColor: _kAccent.withValues(alpha: 0.16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(Icons.bookmark_rounded, color: Color(col.colorHex), size: 18),
                  title: Text(col.name, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                  trailing: Text(
                    '${DocumentStateService.pathsInCollection(col.id).length}',
                    style: const TextStyle(color: _kMuted, fontSize: 11),
                  ),
                  onTap: () => setState(() {
                    _activeCollectionId = col.id;
                    _activeExtChip = null;
                  }),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: _kBorder),
        // Center Pane: Search + Chips + Grid/List
        Expanded(
          child: Column(
            children: [
              if (_selectMode) _buildDocSelectionBar(docs),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Filter by title, folder, or format...',
                    hintStyle: const TextStyle(color: _kMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: _kMuted, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: _kMuted, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: _kCard,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                ),
              ),
              if (_activeFilter != 'folders' && extCounts.length > 1) _buildDynamicExtChips(base.length, extCounts),
              Expanded(
                child: _activeFilter == 'folders'
                    ? _buildFoldersView()
                    : docs.isEmpty
                        ? _buildEmptyState()
                        : _gridMode
                            ? GridView.builder(
                                padding: const EdgeInsets.all(14),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 185,
                                  childAspectRatio: 0.72,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: docs.length,
                                itemBuilder: (_, i) => _buildGridCard(docs[i], selected: selected?.filePath == docs[i].filePath),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(14),
                                itemCount: docs.length,
                                itemBuilder: (_, i) => _buildDocRow(docs[i], selected: selected?.filePath == docs[i].filePath),
                              ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: _kBorder),
        // Right Inspector Pane
        Container(
          width: 295,
          color: _kSurface,
          child: selected == null
              ? const Center(child: Text('Select a document', style: TextStyle(color: _kMuted)))
              : _buildInspectorPane(selected),
        ),
      ],
    );
  }

  Widget _sidebarHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
    child: Text(label, style: const TextStyle(color: _kMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
  );

  Widget _sidebarTile(String filterKey, IconData icon, String title, {int? count}) {
    final active = _activeCollectionId == null && _activeFilter == filterKey;
    return ListTile(
      dense: true,
      selected: active,
      selectedTileColor: _kAccent.withValues(alpha: 0.16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, color: active ? _kAccent : _kMuted, size: 18),
      title: Text(title, style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500), overflow: TextOverflow.ellipsis),
      trailing: count != null
          ? Text('$count', style: TextStyle(color: active ? _kAccent : _kMuted, fontSize: 11))
          : null,
      onTap: () => setState(() {
        _activeCollectionId = null;
        _activeFilter = filterKey;
        _activeExtChip = null;
      }),
    );
  }

  Widget _buildInspectorPane(DocumentFileInfo doc) {
    final spec = DocumentFormatRegistry.specFor(doc.fileName);
    final ext = DocumentFormatRegistry.normalizeExtension(doc.fileName).toUpperCase();
    final state = DocumentStateService.peekState(doc.filePath);
    final pct = ((state?.normalizedProgress ?? 0.0) * 100).round();
    final isPdf = ext == 'PDF' || ext == 'AI';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              width: 150,
              height: 200,
              child: _DocCoverThumb(doc: doc, accent: Color(spec.accentHex), icon: _familyIcon(spec.family), ext: ext),
            ),
          ),
          const SizedBox(height: 14),
          Text(doc.fileName, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _badge(ext, Color(spec.accentHex)),
              _badge(spec.tier.label, const Color(0xFF64748B)),
              if (state?.isPinned == true) _badge('PINNED', const Color(0xFFF59E0B)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            state != null && state.normalizedProgress > 0
                ? 'Reading Progress: $pct% (${state.currentPage}/${state.totalPages})'
                : 'Not started yet',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state?.normalizedProgress ?? 0.0,
              minHeight: 5,
              backgroundColor: const Color(0xFF25304A),
              color: Color(spec.accentHex),
            ),
          ),
          const SizedBox(height: 14),
          _metaLine('Family', spec.family.label),
          _metaLine('Size', _formatSize(doc.fileSize)),
          _metaLine('Folder', DocumentService.folderDisplayName(doc.folder)),
          if (state != null && state.bookmarks.isNotEmpty)
            _metaLine('Bookmarks', '${state.bookmarks.length} saved'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.black),
              onPressed: () => widget.openFile(doc.filePath),
              icon: const Icon(Icons.menu_book_rounded, size: 18),
              label: Text(pct > 0 ? 'Resume Reading ($pct%)' : 'Open Document'),
            ),
          ),
          const SizedBox(height: 8),
          if (isPdf) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PdfOrganizerPage(filePath: doc.filePath)),
                ),
                icon: const Icon(Icons.reorder_rounded, size: 18),
                label: const Text('Organize PDF Pages'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.onRevealInExplorer != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => widget.onRevealInExplorer!(doc.filePath),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Show in File Explorer'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 78, child: Text(label, style: const TextStyle(color: _kMuted, fontSize: 12))),
        Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis)),
      ],
    ),
  );

  // ── Strips & Carousels ─────────────────────────────────────────────────────

  Widget _buildFilterPillStrip() {
    final entries = <(String, String)>[
      ('all', 'All'),
      ('continue', 'Continue'),
      ('pinned', 'Pinned'),
      for (final f in DocumentFamily.values) ('family:${f.id}', f.shortLabel),
      ('folders', 'Folders'),
    ];
    return SizedBox(
      height: 46,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        itemCount: entries.length + DocumentStateService.cachedCollections.length,
        itemBuilder: (_, idx) {
          if (idx < entries.length) {
            final (key, label) = entries[idx];
            final active = _activeCollectionId == null && _activeFilter == key;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() {
                  _activeCollectionId = null;
                  _activeFilter = key;
                  _activeExtChip = null;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? _kAccent : _kCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: active ? _kAccent : _kBorder),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            );
          }
          final col = DocumentStateService.cachedCollections[idx - entries.length];
          final active = _activeCollectionId == col.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _activeCollectionId = col.id;
                _activeExtChip = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? Color(col.colorHex) : _kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: active ? Color(col.colorHex) : _kBorder),
                ),
                child: Text(col.name, style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDynamicExtChips(int totalCount, Map<String, int> extCounts) {
    final sortedExts = extCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _subChip('All ($totalCount)', _activeExtChip == null, () => setState(() => _activeExtChip = null)),
          for (final e in sortedExts)
            _subChip(
              '${e.key} (${e.value})',
              _activeExtChip == e.key.toLowerCase(),
              () => setState(() => _activeExtChip = e.key.toLowerCase()),
            ),
        ],
      ),
    );
  }

  Widget _subChip(String label, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 6, bottom: 4),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF334155) : const Color(0xFF101624),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? _kAccent : _kBorder),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.white : _kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ),
  );

  Widget _buildContinueCarousel(List<DocumentFileInfo> items) {
    return SizedBox(
      height: 158,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final doc = items[i];
          final spec = DocumentFormatRegistry.specFor(doc.fileName);
          final ext = DocumentFormatRegistry.normalizeExtension(doc.fileName).toUpperCase();
          final st = DocumentStateService.peekState(doc.filePath);
          final progress = st?.normalizedProgress ?? 0.0;
          final pct = (progress * 100).round();
          return GestureDetector(
            onTap: () => widget.openFile(doc.filePath),
            child: Container(
              width: 152,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _DocCoverThumb(
                      doc: doc,
                      accent: Color(spec.accentHex),
                      icon: _familyIcon(spec.family),
                      ext: ext,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(doc.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('$ext · $pct%', style: TextStyle(color: Color(spec.accentHex), fontSize: 10, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (st != null && st.totalPages > 1)
                        Text('p.${st.currentPage}/${st.totalPages}', style: const TextStyle(color: _kMuted, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: _kBorder,
                      color: Color(spec.accentHex),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Grid & Row Cards ───────────────────────────────────────────────────────

  Widget _buildGridCard(DocumentFileInfo doc, {bool selected = false}) {
    final spec = DocumentFormatRegistry.specFor(doc.fileName);
    final ext = DocumentFormatRegistry.normalizeExtension(doc.fileName).toUpperCase();
    final st = DocumentStateService.peekState(doc.filePath);
    final progress = st?.normalizedProgress ?? 0.0;
    final pinned = (st?.isPinned ?? false) || _service.isFavorite(doc.id);
    final isMultiSelected = _selectMode && _selectedPaths.contains(doc.filePath);

    return GestureDetector(
      onSecondaryTapDown: (d) => _showContextMenu(doc, d.globalPosition),
      onLongPress: () => setState(() {
        _selectMode = true;
        _selectedPaths.add(doc.filePath);
      }),
      onTap: () {
        if (_selectMode) {
          setState(() {
            if (isMultiSelected) {
              _selectedPaths.remove(doc.filePath);
              if (_selectedPaths.isEmpty) _selectMode = false;
            } else {
              _selectedPaths.add(doc.filePath);
            }
          });
          return;
        }
        setState(() => _inspectedDoc = doc);
        widget.openFile(doc.filePath);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isMultiSelected ? _kAccent.withValues(alpha: 0.14) : _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (isMultiSelected || selected) ? _kAccent : _kBorder,
            width: (isMultiSelected || selected) ? 1.8 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _DocCoverThumb(doc: doc, accent: Color(spec.accentHex), icon: _familyIcon(spec.family), ext: ext),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _badge(ext, Color(spec.accentHex)),
                  ),
                  if (_selectMode)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(
                        isMultiSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: isMultiSelected ? _kAccent : Colors.white70,
                        size: 20,
                      ),
                    )
                  else if (pinned)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.star_rounded, color: Colors.amber, size: 17),
                    ),
                  if (progress > 0.01)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.black54,
                        color: Color(spec.accentHex),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatSize(doc.fileSize)} · ${DocumentService.folderDisplayName(doc.folder)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _kMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocRow(DocumentFileInfo doc, {bool selected = false}) {
    final spec = DocumentFormatRegistry.specFor(doc.fileName);
    final ext = DocumentFormatRegistry.normalizeExtension(doc.fileName).toUpperCase();
    final accent = Color(spec.accentHex);
    final st = DocumentStateService.peekState(doc.filePath);
    final progress = st?.normalizedProgress ?? 0.0;
    final pct = (progress * 100).round();
    final pinned = (st?.isPinned ?? false) || _service.isFavorite(doc.id);
    final isNew = _isNewDoc(doc);
    final isMultiSelected = _selectMode && _selectedPaths.contains(doc.filePath);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _showContextMenu(doc, d.globalPosition),
        child: Material(
          color: isMultiSelected
              ? _kAccent.withValues(alpha: 0.14)
              : (selected ? const Color(0xFF1F2B47) : _kCard),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(
              color: (isMultiSelected || selected) ? _kAccent : _kBorder,
              width: isMultiSelected ? 1.6 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (_selectMode) {
                setState(() {
                  if (isMultiSelected) {
                    _selectedPaths.remove(doc.filePath);
                    if (_selectedPaths.isEmpty) _selectMode = false;
                  } else {
                    _selectedPaths.add(doc.filePath);
                  }
                });
                return;
              }
              setState(() => _inspectedDoc = doc);
              widget.openFile(doc.filePath);
            },
            onLongPress: () => setState(() {
              _selectMode = true;
              _selectedPaths.add(doc.filePath);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 54,
                    child: _DocCoverThumb(doc: doc, accent: accent, icon: _familyIcon(spec.family), ext: ext, compact: true),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(doc.fileName, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                            ),
                            if (pinned) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.star_rounded, color: Colors.amber, size: 15)),
                            if (isNew) ...[
                              const SizedBox(width: 6),
                              _badge('NEW', const Color(0xFF10B981)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$ext · ${_formatSize(doc.fileSize)} · ${DocumentService.folderDisplayName(doc.folder)}',
                                style: const TextStyle(color: _kMuted, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (pct > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                st != null && st.totalPages > 1 ? 'p.${st.currentPage}/${st.totalPages} ($pct%)' : '$pct%',
                                style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ],
                        ),
                        if (progress > 0.01) ...[
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: _kBorder,
                              color: accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _selectMode
                          ? (isMultiSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded)
                          : Icons.more_vert_rounded,
                      color: isMultiSelected ? _kAccent : _kMuted,
                      size: 20,
                    ),
                    onPressed: _selectMode
                        ? () => setState(() {
                              if (isMultiSelected) {
                                _selectedPaths.remove(doc.filePath);
                                if (_selectedPaths.isEmpty) _selectMode = false;
                              } else {
                                _selectedPaths.add(doc.filePath);
                              }
                            })
                        : () => _showContextMenu(doc, null),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Folders & Empty States ─────────────────────────────────────────────────

  Widget _buildFoldersView() {
    final all = _service.allDocuments;
    if (all.isEmpty) return _buildEmptyState();
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: _kCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _kBorder)),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              onTap: () => setState(() => _selectedFolder = entry.key),
              leading: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: _kAccent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.folder_rounded, color: _kAccent, size: 22),
              ),
              title: Text(DocumentService.folderDisplayName(entry.key), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              subtitle: Text('${entry.value.length} document${entry.value.length == 1 ? '' : 's'}', style: const TextStyle(color: _kMuted, fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded, color: _kMuted),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderContents() {
    final docs = _applyExtAndSort(_service.folders[_selectedFolder] ?? const []);
    if (docs.isEmpty) return const Center(child: Text('Folder is empty', style: TextStyle(color: _kMuted)));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      itemBuilder: (_, i) => _buildDocRow(docs[i]),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 110),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_outlined, color: _kMuted, size: 50),
              const SizedBox(height: 12),
              Text(
                _service.isScanning ? 'Indexing documents...' : 'No documents matched this view',
                style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Scan custom folders or adjust active family filters.',
                style: TextStyle(color: _kMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (_service.isScanning)
                const CircularProgressIndicator(strokeWidth: 2, color: _kAccent)
              else
                OutlinedButton.icon(
                  onPressed: _service.scanAllDocuments,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Scan Library'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Actions & Sheets ───────────────────────────────────────────────────────

  Future<void> _showContextMenu(DocumentFileInfo doc, Offset? pos) async {
    final st = DocumentStateService.peekState(doc.filePath);
    final pinned = (st?.isPinned ?? false) || _service.isFavorite(doc.id);
    final ext = DocumentFormatRegistry.normalizeExtension(doc.fileName).toLowerCase();

    void handle(String action) async {
      switch (action) {
        case 'open':
          widget.openFile(doc.filePath);
          break;
        case 'pin':
          await DocumentStateService.togglePin(doc.filePath, title: doc.fileName);
          _service.toggleFavorite(doc.id);
          break;
        case 'finish':
          await DocumentStateService.saveProgress(
            doc.filePath,
            title: doc.fileName,
            scrollProgress: 1.0,
            readingStatus: ReadingStatus.finished,
          );
          break;
        case 'collect':
          _showAddToCollectionSheet(doc);
          break;
        case 'organize':
          if (mounted) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfOrganizerPage(filePath: doc.filePath)));
          }
          break;
        case 'reveal':
          widget.onRevealInExplorer?.call(doc.filePath);
          break;
        case 'share':
          await Share.shareXFiles([XFile(doc.filePath)]);
          break;
      }
    }

    if (pos != null) {
      final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      final picked = await showMenu<String>(
        context: context,
        color: const Color(0xFF1A2238),
        position: RelativeRect.fromRect(Rect.fromLTWH(pos.dx, pos.dy, 1, 1), Offset.zero & overlay.size),
        items: _menuItems(pinned, ext),
      );
      if (picked != null) handle(picked);
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF141B2D),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(doc.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: Text('${ext.toUpperCase()} · ${_formatSize(doc.fileSize)}', style: const TextStyle(color: _kMuted, fontSize: 12)),
              ),
              const Divider(color: _kBorder, height: 1),
              for (final item in _menuItems(pinned, ext))
                ListTile(
                  dense: true,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    handle(item.value!);
                  },
                  title: item.child,
                ),
            ],
          ),
        ),
      );
    }
  }

  List<PopupMenuItem<String>> _menuItems(bool pinned, String ext) => [
    const PopupMenuItem(value: 'open', child: Text('Open / Resume', style: TextStyle(color: Colors.white))),
    PopupMenuItem(value: 'pin', child: Text(pinned ? 'Unpin Document' : 'Pin Document', style: const TextStyle(color: Colors.white))),
    const PopupMenuItem(value: 'finish', child: Text('Mark as Finished', style: TextStyle(color: Colors.white))),
    const PopupMenuItem(value: 'collect', child: Text('Add to Collection', style: TextStyle(color: Colors.white))),
    if (ext == 'pdf' || ext == 'ai')
      const PopupMenuItem(value: 'organize', child: Text('Organize PDF Pages', style: TextStyle(color: Colors.white))),
    if (widget.onRevealInExplorer != null)
      const PopupMenuItem(value: 'reveal', child: Text('Show in File Explorer', style: TextStyle(color: Colors.white))),
    const PopupMenuItem(value: 'share', child: Text('Share File', style: TextStyle(color: Colors.white))),
  ];

  void _openToolsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141B2D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Document Tools & Library', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF4444)),
                title: const Text('Merge PDFs', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Combine multiple PDF documents into one file', style: TextStyle(color: _kMuted, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PdfMergerPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined, color: _kAccent),
                title: const Text('Add Scan Folder', style: TextStyle(color: Colors.white)),
                subtitle: Text('${_service.customScanDirs.length} custom folder(s) added', style: const TextStyle(color: _kMuted, fontSize: 12)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final picked = await FilePicker.platform.getDirectoryPath();
                  if (picked != null && picked.isNotEmpty) {
                    await _service.addCustomScanDir(picked);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined, color: Color(0xFF34D399)),
                title: const Text('Create Collection', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Organize study, work, or reading shelves', style: TextStyle(color: _kMuted, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _promptCreateCollection();
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8)),
                title: const Text('Re-scan Document Library', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _service.scanAllDocuments();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptCreateCollection() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2238),
        title: const Text('New Collection', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'e.g. Research, Novels, Tax', hintStyle: TextStyle(color: _kMuted)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await DocumentStateService.createCollection(name);
    }
  }

  void _showAddToCollectionSheet(DocumentFileInfo doc) {
    final cols = DocumentStateService.cachedCollections;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141B2D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Add to Collection', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            if (cols.isEmpty)
              ListTile(
                leading: const Icon(Icons.add_rounded, color: _kAccent),
                title: const Text('Create first collection...', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _promptCreateCollection();
                },
              ),
            for (final c in cols)
              ListTile(
                leading: Icon(Icons.bookmark_rounded, color: Color(c.colorHex)),
                title: Text(c.name, style: const TextStyle(color: Colors.white)),
                trailing: DocumentStateService.pathsInCollection(c.id).contains(doc.filePath)
                    ? const Icon(Icons.check_rounded, color: Color(0xFF10B981))
                    : null,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final paths = DocumentStateService.pathsInCollection(c.id);
                  if (paths.contains(doc.filePath)) {
                    await DocumentStateService.removeFromCollection(c.id, doc.filePath);
                  } else {
                    await DocumentStateService.addToCollection(c.id, doc.filePath);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  static IconData _familyIcon(DocumentFamily fam) => switch (fam) {
    DocumentFamily.booksComics => Icons.menu_book_rounded,
    DocumentFamily.docsNotes => Icons.article_outlined,
    DocumentFamily.sheetsData => Icons.table_chart_outlined,
    DocumentFamily.slides => Icons.slideshow_rounded,
    DocumentFamily.markupTech => Icons.code_rounded,
    DocumentFamily.mailPim => Icons.mail_outline_rounded,
    DocumentFamily.vectorCad => Icons.architecture_rounded,
  };

  static Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.7), width: 0.8),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
  );
}

class _DocCoverThumb extends StatefulWidget {
  final DocumentFileInfo doc;
  final Color accent;
  final IconData icon;
  final String ext;
  final bool compact;

  const _DocCoverThumb({
    required this.doc,
    required this.accent,
    required this.icon,
    required this.ext,
    this.compact = false,
  });

  @override
  State<_DocCoverThumb> createState() => _DocCoverThumbState();
}

class _DocCoverThumbState extends State<_DocCoverThumb> {
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _thumbPath = DocumentThumbnailService.peekCachedPath(widget.doc.filePath);
    if (_thumbPath == null) _resolve();
  }

  @override
  void didUpdateWidget(covariant _DocCoverThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.filePath != widget.doc.filePath) {
      _thumbPath = DocumentThumbnailService.peekCachedPath(widget.doc.filePath);
      if (_thumbPath == null) _resolve();
    }
  }

  Future<void> _resolve() async {
    final path = await DocumentThumbnailService.getThumbnailPath(widget.doc.filePath);
    if (mounted && path != null) setState(() => _thumbPath = path);
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbPath != null && File(_thumbPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.compact ? 8 : 10),
        child: Image.file(File(_thumbPath!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallbackCard()),
      );
    }
    return _fallbackCard();
  }

  Widget _fallbackCard() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [widget.accent.withValues(alpha: 0.24), const Color(0xFF101624)],
      ),
      borderRadius: BorderRadius.circular(widget.compact ? 8 : 10),
      border: Border.all(color: widget.accent.withValues(alpha: 0.25)),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, color: widget.accent, size: widget.compact ? 22 : 34),
          if (!widget.compact) ...[
            const SizedBox(height: 6),
            Text(
              p.basenameWithoutExtension(widget.doc.fileName),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ],
      ),
    ),
  );
}
