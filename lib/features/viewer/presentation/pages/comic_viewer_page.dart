import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../documents/data/services/archive_service.dart';
import '../../../documents/data/services/document_state_service.dart';
import '../../../../core/utils/natural_sort.dart';

enum ComicReadDirection { ltr, rtl, vertical }

/// Native Comic & Manga Archive Reader (`CBZ`, `CBT`, `CB7`, `CBA`, `CBR`).
class ComicViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const ComicViewerPage({
    super.key,
    required this.filePath,
    this.title = '',
    this.onClose,
  });

  @override
  State<ComicViewerPage> createState() => _ComicViewerPageState();
}

class _ComicViewerPageState extends State<ComicViewerPage> {
  final List<_ComicPageEntry> _pages = [];
  bool _loading = true;
  String? _error;
  bool _isUnsupportedRar = false;
  int _currentPage = 0;
  bool _showChrome = true;
  ComicReadDirection _direction = ComicReadDirection.ltr;
  PageController? _pageCtrl;
  final ScrollController _verticalCtrl = ScrollController();

  static final _imageExtRe = RegExp(r'\.(jpe?g|png|webp|gif|bmp)$', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  @override
  void dispose() {
    _saveProgress();
    _pageCtrl?.dispose();
    _verticalCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProgress() async {
    if (_pages.isEmpty) return;
    await DocumentStateService.saveProgress(
      widget.filePath,
      title: widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath),
      currentPage: _currentPage + 1,
      totalPages: _pages.length,
      scrollProgress: ((_currentPage + 1) / _pages.length).clamp(0.0, 1.0),
    );
  }

  Future<void> _loadArchive() async {
    try {
      final file = File(widget.filePath);
      if (!file.existsSync()) {
        setState(() {
          _error = 'File not found';
          _loading = false;
        });
        return;
      }

      final ext = p.extension(widget.filePath).replaceAll('.', '').toLowerCase();
      final bytes = await file.readAsBytes();
      final loaded = <_ComicPageEntry>[];

      if (ext == 'cbt') {
        final archive = TarDecoder().decodeBytes(bytes);
        _collectFromArchive(archive, loaded);
      } else if (ext == 'cbz' || _looksLikeZip(bytes)) {
        final archive = ZipDecoder().decodeBytes(bytes);
        _collectFromArchive(archive, loaded);
      } else {
        // Fallback via ArchiveService into a temp cache folder (handles CBT/tar/gz/bz2/xz or OS tar.exe)
        final tmp = await getTemporaryDirectory();
        final outDir = Directory(p.join(tmp.path, 'makaw_comic_${widget.filePath.hashCode.toUnsigned(32)}'));
        if (!outDir.existsSync() || outDir.listSync().isEmpty) {
          final res = await ArchiveService.extractArchive(
            archivePath: widget.filePath,
            destinationDir: outDir.path,
          );
          if (!res.success && ext == 'cbr') {
            if (mounted) {
              setState(() {
                _isUnsupportedRar = true;
                _loading = false;
              });
            }
            return;
          }
        }
        if (outDir.existsSync()) {
          final files = outDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => _imageExtRe.hasMatch(f.path))
              .toList()
            ..sort((a, b) => naturalCompare(a.path, b.path));
          for (final f in files) {
            loaded.add(_ComicPageEntry(name: p.basename(f.path), file: f));
          }
        }
      }

      if (loaded.isEmpty && ext == 'cbr') {
        if (mounted) {
          setState(() {
            _isUnsupportedRar = true;
            _loading = false;
          });
        }
        return;
      }

      final saved = await DocumentStateService.getState(widget.filePath);
      final restoredIdx = saved != null && saved.currentPage > 0
          ? (saved.currentPage - 1).clamp(0, (loaded.length - 1).clamp(0, loaded.length))
          : 0;

      if (!mounted) return;
      _pageCtrl = PageController(initialPage: restoredIdx);
      setState(() {
        _pages.addAll(loaded);
        _currentPage = restoredIdx;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to open comic archive: $e';
          _loading = false;
        });
      }
    }
  }

  static bool _looksLikeZip(List<int> b) =>
      b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04;

  void _collectFromArchive(Archive archive, List<_ComicPageEntry> out) {
    final imgs = archive.files
        .where((f) => f.isFile && !f.name.contains('__MACOSX') && _imageExtRe.hasMatch(f.name))
        .toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));
    for (final f in imgs) {
      out.add(_ComicPageEntry(name: f.name, bytes: Uint8List.fromList(f.content as List<int>)));
    }
  }

  void _jumpToPage(int pageIdx) {
    if (_pages.isEmpty) return;
    final clamped = pageIdx.clamp(0, _pages.length - 1);
    setState(() => _currentPage = clamped);
    if (_direction != ComicReadDirection.vertical && _pageCtrl?.hasClients == true) {
      _pageCtrl?.jumpToPage(clamped);
    }
    _saveProgress();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.title.isNotEmpty ? widget.title : p.basename(widget.filePath);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildReaderBody()),
          if (_showChrome && !_loading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.black.withValues(alpha: 0.78),
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                              if (_pages.isNotEmpty)
                                Text(
                                  'Page ${_currentPage + 1} of ${_pages.length} · ${_direction.name.toUpperCase()}',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        PopupMenuButton<ComicReadDirection>(
                          icon: const Icon(Icons.menu_book_rounded, color: Colors.white),
                          tooltip: 'Reading Direction',
                          color: const Color(0xFF1A1A2E),
                          onSelected: (dir) {
                            setState(() => _direction = dir);
                            if (dir != ComicReadDirection.vertical) {
                              _pageCtrl?.dispose();
                              _pageCtrl = PageController(initialPage: _currentPage);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: ComicReadDirection.ltr, child: Text('Left to Right (Comic)', style: TextStyle(color: Colors.white))),
                            PopupMenuItem(value: ComicReadDirection.rtl, child: Text('Right to Left (Manga)', style: TextStyle(color: Colors.white))),
                            PopupMenuItem(value: ComicReadDirection.vertical, child: Text('Vertical Strip (Webtoon)', style: TextStyle(color: Colors.white))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showChrome && !_loading && _pages.length > 1 && _direction != ComicReadDirection.vertical)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF141826).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Text('${_currentPage + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    Expanded(
                      child: Slider(
                        value: _currentPage.toDouble(),
                        min: 0,
                        max: (_pages.length - 1).toDouble(),
                        activeColor: const Color(0xFFEC4899),
                        onChanged: (v) => _jumpToPage(v.round()),
                      ),
                    ),
                    Text('${_pages.length}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReaderBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFEC4899)));
    }
    if (_isUnsupportedRar) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.collections_bookmark_outlined, color: Color(0xFFEC4899), size: 52),
              const SizedBox(height: 12),
              const Text(
                'RAR-compressed .cbr archive',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'This archive uses proprietary RAR compression on this platform. Re-pack as CBZ or open externally.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => OpenFilex.open(widget.filePath),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open in External Reader'),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.white60)),
        ),
      );
    }
    if (_pages.isEmpty) {
      return const Center(child: Text('No comic pages found in archive', style: TextStyle(color: Colors.white54)));
    }
    if (_direction == ComicReadDirection.vertical) {
      return GestureDetector(
        onTap: () => setState(() => _showChrome = !_showChrome),
        child: ListView.builder(
          controller: _verticalCtrl,
          itemCount: _pages.length,
          itemBuilder: (_, idx) => _pages[idx].buildImage(fit: BoxFit.fitWidth),
        ),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _showChrome = !_showChrome),
      child: PageView.builder(
        controller: _pageCtrl,
        reverse: _direction == ComicReadDirection.rtl,
        itemCount: _pages.length,
        onPageChanged: (idx) {
          setState(() => _currentPage = idx);
          _saveProgress();
        },
        itemBuilder: (_, idx) => InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.5,
          child: Center(child: _pages[idx].buildImage(fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

class _ComicPageEntry {
  final String name;
  final Uint8List? bytes;
  final File? file;

  _ComicPageEntry({required this.name, this.bytes, this.file});

  Widget buildImage({required BoxFit fit}) {
    if (bytes != null) {
      return Image.memory(bytes!, fit: fit, gaplessPlayback: true);
    }
    return Image.file(file!, fit: fit, gaplessPlayback: true);
  }
}
