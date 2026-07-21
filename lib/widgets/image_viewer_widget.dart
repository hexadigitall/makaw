import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/image_viewer_service.dart';

class ImageViewerWidget extends StatefulWidget {
  final ImageViewerService service;
  const ImageViewerWidget({super.key, required this.service});

  @override
  State<ImageViewerWidget> createState() => _ImageViewerWidgetState();
}

class _ImageViewerWidgetState extends State<ImageViewerWidget> {
  String _page = 'photos';
  String? _selectedFolder;
  ImageFileInfo? _viewerImage;
  final _kDark = const Color(0xFF0F0F1A);
  final _kAccent = const Color(0xFF818CF8);
  final _kMuted = const Color(0xFF666680);
  final _kCard = const Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);
    if (widget.service.allImages.isEmpty && !widget.service.isScanning) {
      // scan disabled — see main.dart
    }
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: _page == 'viewer' ? null : _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isPhotos = _page == 'photos';
    final isFolders = _page == 'folders' && _selectedFolder == null;
    final isFav = _page == 'favorites';
    final isTrash = _page == 'trash';

    String title;
    if (isFav) title = 'Favourites';
    else if (isTrash) title = 'Trash';
    else if (_selectedFolder != null) title = _selectedFolder!;
    else title = 'Makaw Photos';

    return AppBar(
      backgroundColor: _kDark,
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      leading: _selectedFolder != null
          ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => setState(() => _page = 'folders'))
          : null,
      actions: [
        if (isTrash)
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent), tooltip: 'Empty Trash',
            onPressed: () {
              widget.service.emptyTrash();
              setState(() => _page = 'folders');
            },
          ),
        if (isPhotos || isFolders)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) {
              if (v == 'select') {}
              else if (v == 'settings') {}
              else if (v == 'trash') setState(() => _page = 'trash');
              else if (v == 'favorites') setState(() => _page = 'favorites');
            },
            itemBuilder: (_) => [
              //const PopupMenuItem(value: 'select', child: ListTile(leading: Icon(Icons.checklist), title: Text('Select items'))),
              //const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings), title: Text('Settings'))),
              const PopupMenuItem(value: 'trash', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Trash'))),
              const PopupMenuItem(value: 'favorites', child: ListTile(leading: Icon(Icons.star_border), title: Text('Favourites'))),
            ],
          ),
        if (isFav || isTrash)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => setState(() => _page = 'photos'),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_page == 'viewer' && _viewerImage != null) return _buildViewer();
    if (_page == 'favorites') return _buildFavoritesPage();
    if (_page == 'trash') return _buildTrashPage();
    if (_selectedFolder != null) return _buildFolderContents();
    return Column(
      children: [
        // Tabs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _tabBtn('Photos', _page == 'photos'),
              const SizedBox(width: 12),
              _tabBtn('Folders', _page == 'folders'),
            ],
          ),
        ),
        Expanded(
          child: _page == 'photos'
              ? RefreshIndicator(
                  onRefresh: () => widget.service.scanAllImages(),
                  color: const Color(0xFF818CF8),
                  child: _buildPhotosPage(),
                )
              : _buildFoldersPage(),
        ),
      ],
    );
  }

  Widget _tabBtn(String label, bool active) {
    return GestureDetector(
      onTap: () => setState(() => _page = label.toLowerCase()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _kAccent : _kCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ─── Photos Page ──────────────────────────────────────────────────────────
  Widget _buildPhotosPage() {
    if (widget.service.allImages.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: 400,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_library, color: Color(0xFF666680), size: 48),
                const SizedBox(height: 12),
                Text(widget.service.isScanning ? 'Scanning...' : 'No images found',
                    style: const TextStyle(color: Color(0xFF666680))),
              ],
            ),
          ),
        ),
      );
    }
    final byDate = widget.service.byDate;
    final years = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: years.length,
      itemBuilder: (_, yi) {
        final year = years[yi];
        final months = byDate[year]!;
        final monthKeys = months.keys.toList()..sort((a, b) => b.compareTo(a));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(year, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...monthKeys.map((month) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(month, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                _buildImageGrid(months[month]!),
              ],
            )),
          ],
        );
      },
    );
  }

  Widget _buildImageGrid(List<ImageFileInfo> images) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3,
        ),
        itemCount: images.length,
        itemBuilder: (_, i) => _imageThumb(images[i]),
      ),
    );
  }

  Widget _imageThumb(ImageFileInfo img) {
    return GestureDetector(
      onTap: () => setState(() { _viewerImage = img; _page = 'viewer'; }),
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(File(img.filePath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Color(0xFF666680))),
        ),
      ),
    );
  }

  // ─── Folders Page ─────────────────────────────────────────────────────────
  Widget _buildFoldersPage() {
    if (widget.service.folders.isEmpty) {
      return const Center(child: Text('No folders found', style: TextStyle(color: Color(0xFF666680))));
    }
    final folders = widget.service.folders.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: folders.length,
      itemBuilder: (_, i) {
        final entry = folders[i];
        final thumb = entry.value.first;
        return GestureDetector(
          onTap: () => setState(() { _selectedFolder = entry.key; _page = 'folders'; }),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                  child: Image.file(File(thumb.filePath), width: 72, height: 72, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 72, height: 72, color: _kDark, child: const Icon(Icons.folder, color: Color(0xFF818CF8)))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.key, style: const TextStyle(color: Colors.white, fontSize: 15), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('${entry.value.length} ${entry.value.length == 1 ? 'photo' : 'photos'}',
                          style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.chevron_right, color: Color(0xFF666680)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderContents() {
    if (_selectedFolder == null) return const SizedBox();
    final images = widget.service.folders[_selectedFolder] ?? [];
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3,
      ),
      itemCount: images.length,
      itemBuilder: (_, i) => _imageThumb(images[i]),
    );
  }

  // ─── Image Viewer ─────────────────────────────────────────────────────────
  Widget _buildViewer() {
    final img = _viewerImage!;
    final isFav = widget.service.isFavorite(img.id);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => _page = 'photos'),
        ),
        title: Text(img.fileName, style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? _kAccent : Colors.white),
            onPressed: () { widget.service.toggleFavorite(img.id); setState(() {}); },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1.0, maxScale: 5.0,
          child: Image.file(File(img.filePath), fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64)),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.black87,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _iconBtn(Icons.share, 'Share', () => _shareSheet(img)),
            _iconBtn(Icons.auto_fix_high, 'Auto', () => _autoSheet(img)),
            _iconBtn(Icons.edit, 'Edit', () => _editPage(img)),
            _iconBtn(Icons.delete_outline, 'Trash', () => _trashDialog(img)),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  // ─── Share Sheet ──────────────────────────────────────────────────────────
  void _shareSheet(ImageFileInfo img) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kDark,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5, maxChildSize: 0.85, minChildSize: 0.3,
        builder: (_, scrollCtrl) => CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: _kMuted, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(img.filePath), width: 80, height: 80, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Color(0xFF666680))),
                  ),
                  const SizedBox(height: 8),
                  Text(img.fileName, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                _shareTile(Icons.bluetooth, 'Bluetooth', img),
                _shareTile(Icons.message, 'Messages', img),
                _shareTile(Icons.email, 'Gmail', img),
                _shareTile(Icons.share, 'More', img, isMore: true),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareTile(IconData icon, String label, ImageFileInfo img, {bool isMore = false}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: isMore ? const Icon(Icons.chevron_right, color: Color(0xFF666680)) : null,
      onTap: () {
        Navigator.pop(context);
        if (isMore) {
          Share.shareXFiles([XFile(img.filePath)]);
        } else {
          Share.shareXFiles([XFile(img.filePath)], subject: label);
        }
      },
    );
  }

  // ─── Auto-edit Sheet ──────────────────────────────────────────────────────
  void _autoSheet(ImageFileInfo img) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (_, scrollCtrl) => CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.55,
                    child: Center(
                      child: InteractiveViewer(
                        minScale: 1.0, maxScale: 3.0,
                        child: Image.file(File(img.filePath), fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64)),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                        child: const Text('Press & hold to compare', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                color: _kDark,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    ),
                    ElevatedButton(
                      onPressed: () => _confirmReplace(img),
                      style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
                      child: const Text('Replace', style: TextStyle(color: Colors.black)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmReplace(ImageFileInfo img) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Allow Makaw Image Viewer to modify this photo?', style: TextStyle(color: Colors.white, fontSize: 15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Deny', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showSaving();
            },
            child: const Text('Allow', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  void _showSaving() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF1A1A2E),
        content: Row(children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8))),
          SizedBox(width: 16),
          Text('Saving changes', style: TextStyle(color: Colors.white)),
        ]),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ─── Edit Page ────────────────────────────────────────────────────────────
  void _editPage(ImageFileInfo img) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black87,
          leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          title: const Text('Edit', style: TextStyle(color: Colors.white)),
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  minScale: 1.0, maxScale: 5.0,
                  child: Image.file(File(img.filePath), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64)),
                ),
              ),
            ),
            // Edit tools
            Container(
              color: _kDark,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _editTool(Icons.rotate_right, 'Rotate'),
                  _editTool(Icons.crop, 'Crop'),
                ],
              ),
            ),
            // Presets
            Container(
              color: _kCard,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _presetChip('None', true),
                    _presetChip('Auto', false),
                    _presetChip('Bright', false),
                    _presetChip('Contrast', false),
                    _presetChip('Vivid', false),
                    _presetChip('Warm', false),
                    _presetChip('Cool', false),
                    _presetChip('Mono', false),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          color: _kDark,
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
              ElevatedButton(
                onPressed: () { _showSaving(); Future.delayed(const Duration(seconds: 2), () { if (mounted) Navigator.pop(context); }); },
                style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
                child: const Text('Save copy', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _editTool(IconData icon, String label) {
    return GestureDetector(
      onTap: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _presetChip(String label, bool active) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: active ? _kAccent : _kDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 13)),
    );
  }

  // ─── Trash Dialog ─────────────────────────────────────────────────────────
  void _trashDialog(ImageFileInfo img) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Allow Makaw Image Viewer to move this photo to Trash?', style: TextStyle(color: Colors.white, fontSize: 15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Deny', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.service.addTrashEntry(img);
              widget.service.moveToTrash(img);
              setState(() => _page = 'photos');
            },
            child: const Text('Allow', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  // ─── Favourites Page ──────────────────────────────────────────────────────
  Widget _buildFavoritesPage() {
    final favs = widget.service.favorites;
    if (favs.isEmpty) {
      return const Center(child: Text('No favourites yet', style: TextStyle(color: Color(0xFF666680))));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3,
      ),
      itemCount: favs.length,
      itemBuilder: (_, i) => _imageThumb(favs[i]),
    );
  }

  // ─── Trash Page ───────────────────────────────────────────────────────────
  Widget _buildTrashPage() {
    final items = widget.service.trashImages;
    if (items.isEmpty) {
      return const Center(child: Text('Trash is empty', style: TextStyle(color: Color(0xFF666680))));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return Stack(
          children: [
            _imageThumb(item),
            Positioned(
              bottom: 4, right: 4,
              child: GestureDetector(
                onTap: () {
                  widget.service.restoreFromTrash(item);
                  widget.service.removeTrashEntry(item.id);
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF818CF8)),
                  child: const Icon(Icons.restore, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
