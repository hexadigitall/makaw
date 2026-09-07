import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'pdf_organizer_page.dart';
import 'pdf_merger_page.dart';
import '../../../../core/services/text_action_service.dart';

class _SearchResult {
  final int page;
  final int start;
  final int end;
  const _SearchResult({required this.page, required this.start, required this.end});
}

class MakawPdfViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const MakawPdfViewerPage({super.key, required this.filePath, this.title = '', this.onClose});

  @override
  State<MakawPdfViewerPage> createState() => _MakawPdfViewerPageState();
}

class _MakawPdfViewerPageState extends State<MakawPdfViewerPage> with SingleTickerProviderStateMixin {
  PdfViewerController? _controller;
  PdfDocument? _document;
  bool _isLoading = true;
  int _currentPage = 0;
  int _totalPages = 0;
  double _zoom = 1.0;

  bool _showChrome = true;
  late AnimationController _chromeAnim;
  late Animation<double> _chromeFade;

  bool _isSearchActive = false;
  final _searchCtrl = TextEditingController();
  List<_SearchResult> _searchResults = [];
  int _currentSearchIndex = -1;
  bool _isSearching = false;

  bool _showSidebar = false;
  int _sidebarTab = 0;

  List<int> _bookmarks = [];

  // Non-destructive text selection (Stack overlay, never a modal route).
  String _selectionText = '';
  Rect? _menuTargetRect; // screen rect anchor for the floating context menu
  bool _showSelectionMenu = false;
  double _canvasTopInset = 0;

  // Persistent TTS HUD.
  bool _showTtsHud = false;
  String _hudText = '';
  String _hudSource = '';
  Timer? _ttsPoller;

  static const _kDark = Color(0xFF0F0F1A);
  static const _kCard = Color(0xFF1A1A2E);
  static const _kAccent = Color(0xFF818CF8);
  static const _kMuted = Color(0xFF666680);
  static const _kBarHeight = 48.0;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
    _chromeAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _chromeFade = CurvedAnimation(parent: _chromeAnim, curve: Curves.easeOut);
    _chromeAnim.forward();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: _kDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _ttsPoller?.cancel();
    _searchCtrl.dispose();
    _chromeAnim.dispose();
    SystemChrome.restoreSystemUIOverlays();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF0B1119),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) {
      _chromeAnim.forward();
    } else {
      _chromeAnim.reverse();
    }
  }

  void _onDocumentChanged(PdfDocument? document) {
    if (document == null) return;
    _document = document;
    _totalPages = document.pages.length;
    setState(() { _isLoading = false; _currentPage = 0; });
    _restorePosition();
  }

  Future<void> _restorePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('pdf_pos_${widget.filePath.hashCode}');
      if (data != null) {
        final map = jsonDecode(data) as Map<String, dynamic>;
        final page = map['page'] as int? ?? 0;
        if (page > 0 && page < _totalPages) {
          _controller?.goToPage(pageNumber: page + 1);
        }
      }
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    if (_currentPage <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pdf_pos_${widget.filePath.hashCode}', jsonEncode({
        'page': _currentPage,
        'zoom': _zoom,
        'ts': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  void _toggleBookmark() {
    setState(() {
      if (_bookmarks.contains(_currentPage)) {
        _bookmarks.remove(_currentPage);
      } else {
        _bookmarks.add(_currentPage);
      }
      _bookmarks.sort();
    });
    _saveBookmarks();
  }

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pdf_bm_${widget.filePath.hashCode}', jsonEncode(_bookmarks));
  }

  Future<void> _loadBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('pdf_bm_${widget.filePath.hashCode}');
      if (data != null) {
        setState(() => _bookmarks = (jsonDecode(data) as List).cast<int>());
      }
    } catch (_) {}
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty || _document == null) {
      setState(() { _searchResults = []; _currentSearchIndex = -1; });
      return;
    }
    setState(() { _isSearching = true; _searchResults = []; });
    try {
      final results = <_SearchResult>[];
      final doc = _document!;
      for (var i = 0; i < doc.pages.length; i += 20) {
        final end = math.min(i + 20, doc.pages.length);
        for (var p = i; p < end; p++) {
          try {
            final pageText = await doc.pages[p].loadText();
            final text = pageText.fullText;
            if (text.isNotEmpty) {
              final lower = text.toLowerCase();
              final qLower = query.toLowerCase();
              var idx = 0;
              while ((idx = lower.indexOf(qLower, idx)) != -1) {
                results.add(_SearchResult(page: p, start: idx, end: idx + qLower.length));
                idx += qLower.length;
              }
            }
          } catch (_) {}
        }
        if (i + 20 < doc.pages.length) {
          await Future.delayed(Duration.zero);
          if (!mounted) return;
          setState(() => _searchResults = List.from(results));
        }
      }
      setState(() {
        _searchResults = results;
        _currentSearchIndex = results.isNotEmpty ? 0 : -1;
        _isSearching = false;
      });
      if (results.isNotEmpty) _jumpToSearchResult(0);
    } catch (_) {
      setState(() => _isSearching = false);
    }
  }

  void _jumpToSearchResult(int index) {
    if (index < 0 || index >= _searchResults.length) return;
    final result = _searchResults[index];
    setState(() => _currentSearchIndex = index);
    _controller?.goToPage(pageNumber: result.page + 1);
  }

  void _onTextSelectionChange(List<PdfTextRanges> selections) {
    if (!mounted) return;
    final nonEmpty = selections.where((s) => s.ranges.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      if (_showSelectionMenu) {
        _clearSelectionAndMenu();
      }
      return;
    }
    final buffer = StringBuffer();
    for (final s in nonEmpty) {
      for (final r in s.ranges) {
        final full = s.pageText.fullText;
        final start = r.start < full.length ? r.start : full.length;
        final end = r.end <= full.length ? r.end : full.length;
        if (end > start) buffer.write(full.substring(start, end));
      }
    }
    final selected = buffer.toString().trim();
    if (selected.isEmpty) return;
    setState(() {
      _selectionText = selected;
      _menuTargetRect = _screenRectForSelection(nonEmpty.first);
      _showSelectionMenu = true;
    });
  }

  /// The selection menu is a Stack overlay (not a modal route) so pdfrx never
  /// loses focus and the highlight/handles survive until an explicit action or
  /// a tap-away on the canvas.

  // Map a document-space point to the viewer's local (viewport) coordinates
  // using the controller's transform matrix (the same math pdfrx uses for its
  // own text-selection overlay).
  Offset _docToViewport(Offset doc) {
    final s = _controller!.value.storage;
    final w = doc.dx * s[3] + doc.dy * s[7] + s[15];
    final px = (doc.dx * s[0] + doc.dy * s[4] + s[12]) / w;
    final py = (doc.dx * s[1] + doc.dy * s[5] + s[13]) / w;
    return Offset(px, py);
  }

  // Screen-space rect (in the outer Stack) of a selection's bounding box.
  Rect? _screenRectForSelection(PdfTextRanges sel) {
    if (_controller == null) return null;
    final page = sel.pageNumber;
    final docRect = _controller!.calcRectForRectInsidePage(pageNumber: page, rect: sel.bounds);
    final tl = _docToViewport(docRect.topLeft).translate(0, _canvasTopInset);
    final br = _docToViewport(docRect.bottomRight).translate(0, _canvasTopInset);
    return Rect.fromPoints(tl, br);
  }

  void _clearSelectionAndMenu() {
    setState(() {
      _showSelectionMenu = false;
      _selectionText = '';
      _menuTargetRect = null;
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearchActive = !_isSearchActive;
      if (!_isSearchActive) {
        _searchResults = [];
        _currentSearchIndex = -1;
        _searchCtrl.clear();
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      return Scaffold(
        backgroundColor: _kDark,
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontSize: 14)),
          backgroundColor: _kCard,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onClose ?? () => Navigator.pop(context)),
        ),
        body: const Center(child: Text('File not found', style: TextStyle(color: Colors.white54))),
      );
    }

    return Scaffold(
      backgroundColor: _kDark,
      body: Builder(
        builder: (context) {
          ErrorWidget.builder = (FlutterErrorDetails details) {
            debugPrint('=== PDF VIEWER ERROR ===');
            debugPrint('${details.exception}');
            debugPrint('${details.stack}');
            return Container(
              color: _kDark,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                  const SizedBox(height: 16),
                  const Text('PDF Viewer Error', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${details.exception}', style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
                ],
              ),
            );
          };
          // Chrome is an overlay. To keep the first page's header (and every
          // page's top) visible below the top bar instead of hidden behind it,
          // the canvas is inset below the top chrome rather than overlapped.
          final chromeInsetTop = _showChrome
              ? MediaQuery.of(context).padding.top + _kBarHeight + (_isSearchActive ? 48.0 : 0.0)
              : 0.0;
          _canvasTopInset = chromeInsetTop;
          return Stack(
            children: [
              // Canvas — full screen (or inset below top chrome), tap to toggle chrome
              Positioned(
                top: chromeInsetTop,
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_showSelectionMenu) {
                      _clearSelectionAndMenu();
                      return;
                    }
                    if (_showSidebar) {
                      setState(() => _showSidebar = false);
                    } else {
                      _toggleChrome();
                    }
                  },
                  child: PdfViewer.file(
                    widget.filePath,
                    params: PdfViewerParams(
                      enableTextSelection: true,
                      boundaryMargin: const EdgeInsets.all(50),
                      minScale: 0.5,
                      maxScale: 5.0,
                      backgroundColor: _kDark,
                      pageAnchor: PdfPageAnchor.top,
                      // Render slightly above fit-to-screen for readable text,
                      // but cap it well below the raw devicePixelRatio so a
                      // high-dpi device doesn't rasterize every page at 3x —
                      // that stalls pan/scroll. Offscreen pages get re-rendered
                      // sharper by pdfrx as the user zooms.
                      getPageRenderingScale: (context, page, controller, estimatedScale) {
                        final base = estimatedScale <= 0 ? 1.0 : estimatedScale;
                        final target = base * 1.5;
                        return target > 3.0 ? 3.0 : target;
                      },
                      onDocumentChanged: _onDocumentChanged,
                      onPageChanged: (pageNumber) {
                        if (pageNumber != null) {
                          setState(() => _currentPage = pageNumber - 1);
                          _savePosition();
                        }
                      },
                      onTextSelectionChange: _onTextSelectionChange,
                      onViewerReady: (doc, ctrl) {
                        _controller = ctrl;
                        _totalPages = doc.pages.length;
                        _document = doc;
                        if (mounted) setState(() => _isLoading = false);
                      },
                    ),
                  ),
                ),
              ),

              // Sidebar drawer (slides from left)
              if (_showSidebar) _buildSidebar(),

              // Chrome overlay — fades in/out
              if (_showChrome) ...[
                _buildTopBar(),
                _buildBottomBar(),
              ],

              // Loading
              if (_isLoading)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _kCard.withOpacity(0.8), borderRadius: BorderRadius.circular(12)),
                    child: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent)),
                  ),
                ),

                // Floating text-selection context menu (Stack overlay — non-modal).
                if (_showSelectionMenu && _menuTargetRect != null)
                  _buildFloatingSelectionMenu(),

                // Persistent TTS HUD (mounted by header & context Read Aloud).
                if (_showTtsHud) _buildTtsHud(),
            ],
          );
        },
      ),
    );
  }

  // ── Top Bar ────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0, left: 0, right: 0,
      child: AnimatedBuilder(
        animation: _chromeFade,
        builder: (_, __) => Opacity(
          opacity: _chromeFade.value,
          child: Container(
            padding: EdgeInsets.only(top: topPad),
            color: _kDark,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Primary row: back | title | actions
                SizedBox(
                  height: _kBarHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                        onPressed: widget.onClose ?? () => Navigator.pop(context),
                        splashRadius: 20,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.title.isNotEmpty ? widget.title : widget.filePath.split('\\').last.split('/').last,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _bookmarks.contains(_currentPage) ? Icons.bookmark : Icons.bookmark_border,
                          color: _bookmarks.contains(_currentPage) ? _kAccent : Colors.white70,
                          size: 20,
                        ),
                        onPressed: _toggleBookmark,
                        splashRadius: 18,
                      ),
                      IconButton(
                        icon: const Icon(Icons.search_rounded, color: Colors.white70, size: 20),
                        onPressed: _toggleSearch,
                        splashRadius: 18,
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 20),
                        onPressed: _showMenuSheet,
                        splashRadius: 18,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),

                // Search bar (slides in below)
                if (_isSearchActive) _buildSearchBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Search Bar ─────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search in document...',
                hintStyle: const TextStyle(color: _kMuted, fontSize: 13),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 8, right: 4),
                  child: Icon(Icons.search, color: _kMuted, size: 18),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchCtrl.clear(); _performSearch(''); },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.close, color: _kMuted, size: 16),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: _kCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                isDense: true,
              ),
              onSubmitted: _performSearch,
              onChanged: (v) {
                if (v.length >= 3) _performSearch(v);
              },
            ),
          ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              '${_currentSearchIndex + 1}/${_searchResults.length}',
              style: const TextStyle(color: _kMuted, fontSize: 12),
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: 36, height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70),
                onPressed: _currentSearchIndex > 0 ? () => _jumpToSearchResult(_currentSearchIndex - 1) : null,
              ),
            ),
            SizedBox(
              width: 36, height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                onPressed: _currentSearchIndex < _searchResults.length - 1 ? () => _jumpToSearchResult(_currentSearchIndex + 1) : null,
              ),
            ),
          ] else if (_isSearching) ...[
            const SizedBox(width: 12),
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: _kAccent)),
          ],
        ],
      ),
    );
  }

  // ── Bottom Bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: AnimatedBuilder(
        animation: _chromeFade,
        builder: (_, __) => Opacity(
          opacity: _chromeFade.value,
          child: Container(
            padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
            color: _kDark,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Page scrubber
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 1.5,
                    activeTrackColor: _kAccent,
                    inactiveTrackColor: _kAccent.withOpacity(0.2),
                    thumbColor: _kAccent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    overlayColor: _kAccent.withOpacity(0.15),
                  ),
                  child: Slider(
                    value: _currentPage.toDouble(),
                    min: 0,
                    max: _totalPages > 1 ? (_totalPages - 1).toDouble() : 1,
                    onChanged: (v) => _controller?.goToPage(pageNumber: v.round() + 1),
                  ),
                ),
                // Page label: centered
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_currentPage + 1} / $_totalPages',
                    style: const TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom Sheet Menu ──────────────────────────────────────────────────

  void _showMenuSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 32, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),

            // Zoom info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.zoom_out_map, color: _kMuted, size: 18),
                  const SizedBox(width: 12),
                  const Text('Zoom', style: TextStyle(color: _kMuted, fontSize: 13)),
                  const Spacer(),
                  // Zoom buttons
                  _menuZoomBtn(Icons.remove, () => _controller?.setZoom(_controller?.centerPosition ?? Offset.zero, _zoom / 1.2)),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: _kDark, borderRadius: BorderRadius.circular(4)),
                    child: Text('${(_zoom * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                  _menuZoomBtn(Icons.add, () => _controller?.setZoom(_controller?.centerPosition ?? Offset.zero, _zoom * 1.2)),
                ],
              ),
            ),

            const SizedBox(height: 4),
            const Divider(color: Color(0xFF2D3748), height: 1),
            const SizedBox(height: 4),

            _menuTile(Icons.grid_view_rounded, 'Organize Pages', () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => PdfOrganizerPage(filePath: widget.filePath)));
            }),
            _menuTile(Icons.merge_type_rounded, 'Merge PDFs', () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfMergerPage()));
            }),
            _menuTile(Icons.record_voice_over_rounded, 'Read Aloud', () {
              Navigator.pop(ctx);
              _mountTtsHud();
            }),
            _menuTile(Icons.info_outline_rounded, 'Document Info', () {
              Navigator.pop(ctx);
              _showDocumentInfo();
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuZoomBtn(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 36, height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(icon, color: Colors.white70),
        onPressed: onPressed,
      ),
    );
  }

  Widget _menuTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: _kMuted, size: 20),
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      dense: true,
      onTap: onTap,
    );
  }

  // ── Sidebar ────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top,
      left: 0, bottom: 0,
      width: 260,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          decoration: const BoxDecoration(
            color: _kCard,
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(4, 0))],
          ),
          child: Column(
            children: [
              // Tabs
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    _sidebarTabBtn(0, Icons.grid_view_rounded, 'Pages'),
                    _sidebarTabBtn(1, Icons.toc_rounded, 'Outline'),
                    _sidebarTabBtn(2, Icons.bookmark_rounded, 'Marks'),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2D3748), height: 1),
              Expanded(child: _buildSidebarContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebarTabBtn(int idx, IconData icon, String label) {
    final active = _sidebarTab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _sidebarTab = idx),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: active ? _kAccent : Colors.transparent, width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? _kAccent : _kMuted, size: 14),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: active ? _kAccent : _kMuted, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarContent() {
    switch (_sidebarTab) {
      case 0: return _buildThumbnailsList();
      case 1: return _buildOutlinesList();
      case 2: return _buildBookmarksList();
      default: return const SizedBox();
    }
  }

  Widget _buildThumbnailsList() {
    if (_document == null) return const Center(child: CircularProgressIndicator(color: _kAccent, strokeWidth: 1.5));
    final pages = _document!.pages;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: pages.length,
      itemBuilder: (_, i) {
        final isActive = i == _currentPage;
        return GestureDetector(
          onTap: () {
            _controller?.goToPage(pageNumber: i + 1);
            setState(() => _showSidebar = false);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isActive ? _kAccent.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isActive ? _kAccent : const Color(0xFF2D3748), width: 1),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 100,
                    child: PdfPageView(
                      document: _document!,
                      pageNumber: i + 1,
                      alignment: Alignment.center,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: isActive ? _kAccent : _kMuted,
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOutlinesList() {
    if (_document == null) return const Center(child: CircularProgressIndicator(color: _kAccent, strokeWidth: 1.5));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _document!.pages.length,
      itemBuilder: (_, i) {
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          leading: Text('${i + 1}', style: const TextStyle(color: _kMuted, fontSize: 12)),
          title: Text('Page ${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 13)),
          onTap: () {
            _controller?.goToPage(pageNumber: i + 1);
            setState(() => _showSidebar = false);
          },
        );
      },
    );
  }

  Widget _buildBookmarksList() {
    if (_bookmarks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border_rounded, color: _kMuted, size: 32),
            SizedBox(height: 8),
            Text('No bookmarks', style: TextStyle(color: _kMuted, fontSize: 13)),
            SizedBox(height: 2),
            Text('Tap bookmark icon to save pages', style: TextStyle(color: _kMuted, fontSize: 11)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _bookmarks.length,
      itemBuilder: (_, i) {
        final page = _bookmarks[i];
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          leading: const Icon(Icons.bookmark_rounded, color: _kAccent, size: 16),
          title: Text('Page ${page + 1}', style: const TextStyle(color: Colors.white, fontSize: 13)),
          trailing: GestureDetector(
            onTap: () {
              setState(() => _bookmarks.remove(page));
              _saveBookmarks();
            },
            child: const Icon(Icons.close_rounded, color: _kMuted, size: 16),
          ),
          onTap: () {
            _controller?.goToPage(pageNumber: page + 1);
            setState(() => _showSidebar = false);
          },
        );
      },
    );
  }

  // ── Document Info ──────────────────────────────────────────────────────

  void _showDocumentInfo() {
    final file = File(widget.filePath);
    final size = file.lengthSync();
    final sizeStr = size > 1024 * 1024
        ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(size / 1024).toStringAsFixed(1)} KB';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Document Info', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoRow('File', widget.filePath.split('\\').last.split('/').last),
            _infoRow('Pages', '$_totalPages'),
            _infoRow('Size', sizeStr),
            _infoRow('Zoom', '${(_zoom * 100).round()}%'),
            _infoRow('Bookmarks', '${_bookmarks.length}'),
            if (_searchResults.isNotEmpty) _infoRow('Search matches', '${_searchResults.length}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _kMuted, fontSize: 13)),
          const SizedBox(width: 16),
          Flexible(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  // ── Read Aloud ─────────────────────────────────────────────────────────

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<String> _pageText(int pageIndex) async {
    if (_document == null) return '';
    try {
      final pt = await _document!.pages[pageIndex].loadText();
      return pt.fullText.trim();
    } catch (_) {
      return '';
    }
  }

  void _setupTtsPolling() {
    _ttsPoller?.cancel();
    _ttsPoller = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  // -- Persistent TTS HUD ------------------------------------------------

  void _mountTtsHud() {
    setState(() => _showTtsHud = true);
    _setupTtsPolling();
  }

  Future<void> _dismissTtsHud() async {
    _ttsPoller?.cancel();
    await TextActionService.stopSpeaking();
    if (!mounted) return;
    setState(() {
      _showTtsHud = false;
      _hudText = '';
      _hudSource = '';
      if (_showSelectionMenu) {
        _clearSelectionAndMenu();
      }
    });
  }

  Future<void> _playHudTarget(String text, String source) async {
    if (text.trim().isEmpty) {
      _showToast('No selectable text on this page');
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      _showTtsHud = true;
      _hudText = text;
      _hudSource = source;
    });
    await TextActionService.playFromBeginning(text);
    _setupTtsPolling();
    if (mounted) setState(() {});
  }

  Future<void> _playPageInHud() async {
    final text = await _pageText(_currentPage);
    await _playHudTarget(text, 'Page ${_currentPage + 1}');
  }

  Future<void> _playSelectionInHud() async {
    if (_selectionText.isEmpty) return;
    await _playHudTarget(_selectionText, 'Selection');
  }

  // Context-menu Read Aloud: read the selection if present, else the page in
  // the viewport. Keeps the HUD mounted and the selection intact so the HUD's
  // Read Selection stays available.
  Future<void> _readContextAloud() async {
    final text = _selectionText.isNotEmpty ? _selectionText : await _pageText(_currentPage);
    await _playHudTarget(text, _selectionText.isNotEmpty ? 'Selection' : 'Page ${_currentPage + 1}');
  }

  // -- Floating selection context menu -----------------------------------

  bool get _isSingleWord => _selectionText.split(RegExp(r'\s+')).length == 1;

  Widget _buildFloatingSelectionMenu() {
    final target = _menuTargetRect!;
    final screen = MediaQuery.of(context).size;
    const menuHeight = 48.0;
    // Place the menu above or below the selection so it never occludes it.
    final placeAbove = target.top - menuHeight - 12 >= 0;
    final top = placeAbove ? target.top - menuHeight - 12 : target.bottom + 12;
    var left = target.left - 8;
    if (left < 0) left = 0;
    if (left > screen.width - 300) left = screen.width - 300;

    return Positioned(
      top: top,
      left: left,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF1E293B),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _selectionMenuItem(Icons.content_copy_rounded, 'Copy', () {
              TextActionService.copyToClipboard(_selectionText);
              _clearSelectionAndMenu();
              _showToast('Copied to clipboard');
            }),
            _selectionMenuItem(Icons.record_voice_over_rounded, 'Read Aloud', _readContextAloud),
            if (_isSingleWord)
              _selectionMenuItem(Icons.volume_up_rounded, 'Pronounce', () {
                _clearSelectionAndMenu();
                TextActionService.pronounce(_selectionText);
              }),
          ],
        ),
      ),
    );
  }

  Widget _selectionMenuItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _hudBtn(IconData icon, String label, VoidCallback? onTap) {
    final color = onTap == null ? const Color(0xFF475569) : const Color(0xFF22D3EE);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildTtsHud() {
    final speaking = TextActionService.isSpeaking;
    final paused = TextActionService.isPaused;
    final hasSelection = _selectionText.isNotEmpty;
    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + 16,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF1E293B),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.record_voice_over_rounded, color: Color(0xFFF472B6), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _hudSource.isEmpty ? 'Reading' : _hudSource,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    onPressed: _dismissTtsHud,
                    splashRadius: 16,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (_hudText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  _hudText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.3),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _hudBtn(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    paused ? 'Continue' : (speaking ? 'Pause' : 'Play'),
                    () async {
                      if (TextActionService.isPaused) {
                        await TextActionService.resumeSpeaking();
                      } else if (TextActionService.isSpeaking) {
                        await TextActionService.pauseSpeaking();
                      } else {
                        final text = _hudText.isNotEmpty ? _hudText : await _pageText(_currentPage);
                        final src = _hudSource.isNotEmpty ? _hudSource : 'Page ${_currentPage + 1}';
                        await _playHudTarget(text, src);
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                  _hudBtn(Icons.menu_book_rounded, 'Read Page', _playPageInHud),
                  _hudBtn(Icons.highlight_rounded, 'Read Sel', hasSelection ? _playSelectionInHud : null),
                  _hudBtn(Icons.stop_rounded, 'Stop', TextActionService.stopSpeaking),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
