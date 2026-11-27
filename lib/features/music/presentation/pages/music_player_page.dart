import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../data/services/music_player_service.dart';
import '../../../media/data/services/media_thumbnail_service.dart';
import '../../../../app/providers/service_providers.dart';
import 'music_playlist_page.dart';
import 'lyrics_creator_page.dart';
import '../../../../core/storage/lrc_storage_service.dart';
import '../../../../core/services/global_player_state.dart';
import '../../../documents/presentation/pages/folders_page.dart';
import '../widgets/music_visualizer_bars.dart';
import '../widgets/synced_lyrics_view.dart';

class MusicPlayerWidget extends ConsumerStatefulWidget {
  final VoidCallback? onOpenVideos;
  final VoidCallback? onOpenSettings;

  const MusicPlayerWidget({
    super.key,
    this.onOpenVideos,
    this.onOpenSettings,
  });

  @override
  ConsumerState<MusicPlayerWidget> createState() => _MusicPlayerWidgetState();
}

class _MusicPlayerWidgetState extends ConsumerState<MusicPlayerWidget> {
  MusicPlayerService get _service => ref.read(musicPlayerServiceProvider) ?? MusicPlayerService();
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<int> _selectedIds = {};
  bool _selectMode = false;
  bool _isSearchPage = false;
  bool _showLyrics = false;
  String _lyricsText = '';
  bool _lyricsLoading = false;
  List<LrcLine> _lrcLines = [];
  String _lyricsSource = '';
  int _lyricsOffsetMs = 0;
  bool get _hasLrc => _lrcLines.isNotEmpty;

  // Dynamic color palette from album art
  Color _dominantColor = const Color(0xFF0F0F1A);
  Color _accentColor = const Color(0xFF818CF8);
  bool _paletteLoading = false;
  int _prevSongId = -1;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
    // Defer the scan past the first build pass — scanAllSongs() fires
    // notifyListeners synchronously, which would setState on the parent
    // (MakawHome) while MusicPlayerWidget's route is still mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _service.scanAllSongs(force: false);
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) {
      if (_service.currentSong != null && _service.currentSong!.id != _prevSongId) {
        _lyricsText = '';
        _lrcLines = [];
        _lyricsSource = '';
        _lyricsOffsetMs = 0;
        _updateDominantColor();
        if (_showLyrics) {
          _fetchLyrics(forceOnline: true);
        }
      }
      setState(() {});
    }
  }

  String fmtDur(Duration d) {
    if (d.inSeconds >= 3600) {
      return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String fmtMs(int ms) => fmtDur(Duration(milliseconds: ms));

  // ─── Palette Extraction ─────────────────────────────────────────────────────
  Future<void> _updateDominantColor() async {
    final song = _service.currentSong;
    if (song == null || song.id == _prevSongId || _paletteLoading) return;
    _prevSongId = song.id;
    _paletteLoading = true;
    try {
      final bytes = await MediaThumbnailService.instance.getThumbnail(song.filePath, isVideo: false);
      if (bytes != null && bytes.isNotEmpty) {
        final provider = MemoryImage(bytes);
        final palette = await PaletteGenerator.fromImageProvider(
          provider,
          maximumColorCount: 16,
        ).timeout(const Duration(seconds: 3));
        if (palette.dominantColor != null) {
          final c = palette.dominantColor!.color;
          final hsl = HSLColor.fromColor(c);
          final dark = hsl.withLightness((hsl.lightness * 0.35).clamp(0.0, 1.0)).toColor();
          final accent = hsl.withSaturation((hsl.saturation * 1.2).clamp(0.0, 1.0)).toColor();
          if (mounted) setState(() { _dominantColor = dark; _accentColor = accent; });
        }
      }
    } catch (_) {}
    _paletteLoading = false;
  }

  // ─── Lyrics ────────────────────────────────────────────────────────────────
  Future<void> _fetchLyrics({bool forceOnline = false}) async {
    final song = _service.currentSong;
    if (song == null) return;
    setState(() {
      _lyricsLoading = true;
      _lyricsText = '';
      _lrcLines = [];
      _lyricsSource = '';
    });

    final resolved = await LrcStorageService.resolveLyrics(
      songPath: song.filePath,
      title: song.displayTitle,
      artist: song.displayArtist,
      album: song.displayAlbum,
      allowOnline: forceOnline || _service.autoFetchLyrics,
    );
    if (!mounted) return;
    setState(() {
      _lrcLines = resolved.syncedLines;
      _lyricsText = resolved.plainText;
      _lyricsSource = resolved.sourceLabel;
      _lyricsLoading = false;
    });
  }

  Future<void> _openLyricsCreator() async {
    final song = _service.currentSong;
    if (song == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LyricsCreatorPage(
          service: _service,
          song: song,
          initialLines: _lrcLines,
          initialPlainText: _lyricsText,
        ),
      ),
    );
    if (mounted) {
      await _fetchLyrics(forceOnline: false);
    }
  }

  Future<void> _importLrcFile() async {
    final song = _service.currentSong;
    if (song == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc', 'txt'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final raw = await File(path).readAsString();
      final parsed = LrcStorageService.parseLrc(raw);
      final saved = await LrcStorageService.saveLyricsForSong(
        songPath: song.filePath,
        title: song.displayTitle,
        artist: song.displayArtist,
        album: song.displayAlbum,
        syncedLines: parsed,
        plainText: parsed.isEmpty ? raw : '',
      );
      if (!mounted) return;
      setState(() {
        _lrcLines = parsed;
        _lyricsText = parsed.isEmpty ? raw : '';
        _lyricsSource = 'Imported .lrc';
      });
      _toast('Saved to MakawLyrics (${p.basename(saved)})');
    } catch (e) {
      _toast('Import failed: $e');
    }
  }

  Future<void> _pasteLyricsFromClipboard() async {
    final song = _service.currentSong;
    if (song == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      _toast('Clipboard is empty');
      return;
    }
    final parsed = LrcStorageService.parseLrc(raw);
    await LrcStorageService.saveLyricsForSong(
      songPath: song.filePath,
      title: song.displayTitle,
      artist: song.displayArtist,
      album: song.displayAlbum,
      syncedLines: parsed,
      plainText: parsed.isEmpty ? raw : '',
    );
    if (!mounted) return;
    setState(() {
      _lrcLines = parsed;
      _lyricsText = parsed.isEmpty ? raw : '';
      _lyricsSource = parsed.isNotEmpty ? 'Pasted .lrc' : 'Pasted text';
    });
    _toast(parsed.isNotEmpty
        ? 'Imported ${parsed.length} timed lines to MakawLyrics'
        : 'Pasted lyrics — open Studio to add timers');
  }

  Future<void> _openMakawLyricsFolder() async {
    final folder = await LrcStorageService.lyricsFolderPath();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FoldersPage(
          initialPath: folder,
          openFile: (path) async => OpenFilex.open(path),
        ),
      ),
    );
  }

  void _expandLyricsFullscreen() {
    final song = _service.currentSong;
    if (song == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0F1A),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AnimatedBuilder(
          animation: _service,
          builder: (_, __) => SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.92,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                song.displayArtist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy .lrc',
                          icon: const Icon(Icons.copy_all_rounded, color: Colors.white70, size: 20),
                          onPressed: () async {
                            final out = _hasLrc
                                ? LrcStorageService.formatLrc(
                                    lines: _lrcLines,
                                    title: song.displayTitle,
                                    artist: song.displayArtist,
                                    album: song.displayAlbum,
                                  )
                                : _lyricsText;
                            await Clipboard.setData(ClipboardData(text: out));
                            _toast('Copied lyrics to clipboard');
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SyncedLyricsView(
                      syncedLines: _lrcLines,
                      plainText: _lyricsText,
                      sourceLabel: _lyricsSource,
                      position: _service.position,
                      accentColor: _accentColor,
                      isLoading: _lyricsLoading,
                      offsetMs: _lyricsOffsetMs,
                      onOffsetChanged: (o) {
                        setState(() => _lyricsOffsetMs = o);
                        setModalState(() {});
                      },
                      onSeekToLine: (d) => _service.seek(d),
                      onOpenCreator: () {
                        Navigator.pop(ctx);
                        _openLyricsCreator();
                      },
                      onSearchOnline: () => _fetchLyrics(forceOnline: true),
                      onImportFile: _importLrcFile,
                      onPasteClipboard: _pasteLyricsFromClipboard,
                      onOpenLyricsFolder: _openMakawLyricsFolder,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── LRC-aware now-playing body ────────────────────────────────────────────
  Widget _buildLyricsView() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SyncedLyricsView(
        syncedLines: _lrcLines,
        plainText: _lyricsText,
        sourceLabel: _lyricsSource,
        position: _service.position,
        accentColor: _accentColor,
        isLoading: _lyricsLoading,
        offsetMs: _lyricsOffsetMs,
        onOffsetChanged: (o) => setState(() => _lyricsOffsetMs = o),
        onSeekToLine: (d) => _service.seek(d),
        onOpenCreator: _openLyricsCreator,
        onSearchOnline: () => _fetchLyrics(forceOnline: true),
        onImportFile: _importLrcFile,
        onPasteClipboard: _pasteLyricsFromClipboard,
        onOpenLyricsFolder: _openMakawLyricsFolder,
        onExpandFullscreen: _expandLyricsFullscreen,
      ),
    );
  }

  // ─── End lyrics ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_service.showNowPlaying) {
          _service.setShowNowPlaying(false);
          return;
        }
        if (_isSearchPage) {
          setState(() {
            _isSearchPage = false;
            _searchCtrl.clear();
          });
          return;
        }
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        body: _service.showNowPlaying && _service.currentSong != null
            ? _buildNowPlaying()
            : _isSearchPage
                ? _buildSearchPage()
                : Column(
                    children: [
                      _buildHeader(),
                      Expanded(child: _buildTabs()),
                      if (_service.hasQueue || _service.currentSong != null) _buildMiniPlayer(),
                      _buildFooter(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 6, left: 6, right: 8, bottom: 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                onPressed: () {
                  if (_service.showNowPlaying) {
                    _service.setShowNowPlaying(false);
                    return;
                  }
                  if (_isSearchPage) {
                    setState(() {
                      _isSearchPage = false;
                      _searchCtrl.clear();
                    });
                    return;
                  }
                  Navigator.of(context).pop();
                },
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Makaw Music',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (isLandscape)
                SizedBox(
                  width: 220,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextField(
                      controller: _searchCtrl,
                      readOnly: true,
                      onTap: () => setState(() => _isSearchPage = true),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search songs, albums...',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 19),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Color(0xFF94A3B8), size: 18),
                                onPressed: () { _searchCtrl.clear(); setState(() {}); })
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF131B2E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF818CF8), size: 21),
                tooltip: 'Rescan media',
                onPressed: () => _service.scanAllSongs(force: true),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF818CF8), size: 21),
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF334155))),
                onSelected: (v) {
                  if (v == 'scan') _service.scanAllSongs(force: true);
                  else if (v == 'settings') _openMusicSettings();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'scan', child: ListTile(title: Text('Refresh Library', style: TextStyle(color: Colors.white, fontSize: 13)), leading: Icon(Icons.refresh_rounded, color: Color(0xFF818CF8)))),
                  const PopupMenuItem(value: 'settings', child: ListTile(title: Text('Music Settings', style: TextStyle(color: Colors.white, fontSize: 13)), leading: Icon(Icons.settings_rounded, color: Color(0xFF818CF8)))),
                ],
              ),
            ],
          ),
          if (!isLandscape)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: TextField(
                controller: _searchCtrl,
                readOnly: true,
                onTap: () => setState(() => _isSearchPage = true),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search songs, playlists, artists...',
                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF818CF8), size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Color(0xFF94A3B8), size: 18),
                          onPressed: () { _searchCtrl.clear(); setState(() {}); })
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF131B2E).withValues(alpha: 0.8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchPage() {
    final query = _searchCtrl.text.toLowerCase();
    final results = _service.allSongs.where((s) =>
        s.displayTitle.toLowerCase().contains(query) ||
        s.displayArtist.toLowerCase().contains(query)).toList();
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () { _searchCtrl.clear(); setState(() => _isSearchPage = false); },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists, albums...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF818CF8), size: 20),
                      filled: true,
                      fillColor: const Color(0xFF131B2E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? const Center(child: Text('Type to search your music library', style: TextStyle(color: Color(0xFF64748B))))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (_, i) => _songItem(results[i], i, results),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final search = _searchCtrl.text.toLowerCase();
    return DefaultTabController(
      length: 5,
      initialIndex: ['Songs', 'Playlists', 'Folders', 'Albums', 'Artists'].indexOf(_service.selectedTab).clamp(0, 4),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF131B2E).withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF1E293B), width: 1),
            ),
            child: TabBar(
              onTap: (i) => _service.setSelectedTab(['Songs', 'Playlists', 'Folders', 'Albums', 'Artists'][i]),
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF94A3B8),
              labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.all(3),
              labelPadding: const EdgeInsets.symmetric(horizontal: 15),
              tabs: const [
                Tab(text: 'Songs'), Tab(text: 'Playlists'), Tab(text: 'Folders'),
                Tab(text: 'Albums'), Tab(text: 'Artists'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _songsTab(search), _playlistsTab(search), _groupTab(search, 'folders'),
                _groupTab(search, 'albums'), _groupTab(search, 'artists'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Songs Tab ----------
  Widget _songsTab(String search) {
    final songs = search.isEmpty
        ? _service.allSongs
        : _service.allSongs.where((s) =>
            s.displayTitle.toLowerCase().contains(search) ||
            s.displayArtist.toLowerCase().contains(search)).toList();

    if (_service.isScanning) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)));
    }
    if (songs.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF818CF8),
        backgroundColor: const Color(0xFF1E293B),
        onRefresh: () async => await _service.scanAllSongs(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.music_note, color: Color(0xFF666680), size: 48),
                    const SizedBox(height: 12),
                    Text(_service.scanError.isNotEmpty ? _service.scanError : 'No songs found',
                        style: const TextStyle(color: Color(0xFF666680))),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final listView = Expanded(
      child: RefreshIndicator(
        color: const Color(0xFF818CF8),
        backgroundColor: const Color(0xFF1E293B),
        onRefresh: () async => await _service.scanAllSongs(force: true),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: songs.length,
          itemBuilder: (_, i) => _songItem(songs[i], i, songs),
        ),
      ),
    );

    if (isLandscape) {
      final navBottom = MediaQuery.of(context).padding.bottom;
      return Stack(
        children: [
          Column(
            children: [
              if (_selectMode) _selectBar(songs),
              listView,
            ],
          ),
          if (!_selectMode)
            Positioned(
              bottom: 16 + navBottom, right: 80,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'play_land',
                    onPressed: songs.isEmpty ? null : () => _service.playSong(0, fromList: songs),
                    backgroundColor: const Color(0xFF818CF8),
                    child: const Icon(Icons.play_arrow, color: Colors.black),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    heroTag: 'shuffle_land',
                    onPressed: songs.isEmpty ? null : () => _service.playShuffled(songs),
                    backgroundColor: const Color(0xFF2A2A4E),
                    child: Icon(Icons.shuffle, color: const Color(0xFF818CF8)),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Column(
      children: [
        if (_selectMode) _selectBar(songs),
        _toolBar(songs),
        listView,
      ],
    );
  }

  Widget _toolBar(List<SongInfo> songs) {
    int totalMs = 0;
    for (final s in songs) {
      totalMs += s.duration;
    }
    final totalDurStr = fmtMs(totalMs);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.music_note_rounded, color: Color(0xFF818CF8), size: 15),
              ),
              const SizedBox(width: 8),
              Text(
                '${songs.length} Tracks',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              if (songs.isNotEmpty) ...[
                Text(
                  '  \u2022  $totalDurStr',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
              const Spacer(),
              _sortBtn(),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: songs.isEmpty ? null : () => _service.playSong(0, fromList: songs),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
                      label: const Text('Play All', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: songs.isEmpty ? null : () => _service.playShuffled(songs),
                    icon: const Icon(Icons.shuffle_rounded, size: 18, color: Color(0xFF818CF8)),
                    label: const Text('Shuffle', style: TextStyle(color: Color(0xFF818CF8), fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2E3A52), width: 1),
                      backgroundColor: const Color(0xFF161F33).withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sortBtn() {
    String label;
    switch (_service.sortMode) {
      case 'name': label = 'A-Z'; break;
      case 'name_desc': label = 'Z-A'; break;
      case 'date': label = 'Date'; break;
      case 'duration': label = 'Length'; break;
      case 'size': label = 'Size'; break;
      default: label = 'A-Z';
    }
    return PopupMenuButton<String>(
      onSelected: (v) => _service.setSortMode(v),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF334155))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2338),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2B374E), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, color: Color(0xFF818CF8), size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'name', child: Text('Name (A-Z)', style: TextStyle(color: Colors.white, fontSize: 13))),
        const PopupMenuItem(value: 'name_desc', child: Text('Name (Z-A)', style: TextStyle(color: Colors.white, fontSize: 13))),
        const PopupMenuItem(value: 'date', child: Text('Date Added', style: TextStyle(color: Colors.white, fontSize: 13))),
        const PopupMenuItem(value: 'duration', child: Text('Length', style: TextStyle(color: Colors.white, fontSize: 13))),
        const PopupMenuItem(value: 'size', child: Text('Size', style: TextStyle(color: Colors.white, fontSize: 13))),
      ],
    );
  }

  Widget _selectBar(List<SongInfo> songs) {
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () { setState(() { _selectMode = false; _selectedIds.clear(); }); },
          ),
          Text('${_selectedIds.length} Selected', style: const TextStyle(color: Colors.white, fontSize: 14)),
          const Spacer(),
          if (_selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              onPressed: () => _deleteSelected(songs),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF818CF8), size: 20),
            onSelected: (v) => _selectAction(v, songs),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'select_all', child: Text('Select All')),
              const PopupMenuItem(value: 'play_next', child: Text('Play Next')),
              const PopupMenuItem(value: 'add_queue', child: Text('Add to Queue')),
              const PopupMenuItem(value: 'add_playlist', child: Text('Add to Playlist')),
            ],
          ),
        ],
      ),
    );
  }

  void _selectAction(String v, List<SongInfo> songs) {
    final sel = songs.where((s) => _selectedIds.contains(s.id)).toList();
    if (v == 'select_all') {
      setState(() { _selectedIds.addAll(songs.map((s) => s.id)); });
    } else if (v == 'play_next') {
      for (final s in sel.reversed) _service.playNext(s);
      setState(() { _selectMode = false; _selectedIds.clear(); });
    } else if (v == 'add_queue') {
      for (final s in sel) _service.addToQueue(s);
      setState(() { _selectMode = false; _selectedIds.clear(); });
    } else if (v == 'add_playlist') {
      if (sel.isNotEmpty) _addToPlaylistSheet(sel.first.id);
      setState(() { _selectMode = false; _selectedIds.clear(); });
    }
  }

  void _deleteSelected(List<SongInfo> songs) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete selected files?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              for (final s in songs.where((s) => _selectedIds.contains(s.id))) {
                try { File(s.filePath).deleteSync(); } catch (_) {}
              }
              _service.scanAllSongs();
              setState(() { _selectedIds.clear(); _selectMode = false; });
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  bool _isNewSong(SongInfo song) {
    try {
      final f = File(song.filePath);
      if (!f.existsSync()) return false;
      final modified = f.statSync().modified;
      if (DateTime.now().difference(modified).inHours < 72) return true;
      final p = song.filePath.toLowerCase();
      if (p.contains('download') || p.contains('downloads')) {
        return DateTime.now().difference(modified).inDays < 7;
      }
    } catch (_) {}
    return false;
  }

  Widget _songItem(SongInfo song, int index, List<SongInfo>? list) {
    final isCurrent = _service.currentSong?.id == song.id;
    final isPlaying = isCurrent && _service.isPlaying;
    final isFav = _service.isFavorite(song.id);
    final isSel = _selectedIds.contains(song.id);
    final isNew = _isNewSong(song);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
      decoration: BoxDecoration(
        color: isSel
            ? const Color(0xFF232D46)
            : (isCurrent
                ? const Color(0xFF162036)
                : const Color(0xFF0F1626).withValues(alpha: 0.5)),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFF6366F1).withValues(alpha: 0.65)
              : (isSel ? const Color(0xFF818CF8) : const Color(0xFF1E293B).withValues(alpha: 0.6)),
          width: isCurrent ? 1.2 : 0.8,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (_selectMode) {
              setState(() {
                if (_selectedIds.contains(song.id)) { _selectedIds.remove(song.id); if (_selectedIds.isEmpty) _selectMode = false; }
                else { _selectedIds.add(song.id); }
              });
            } else {
              _service.playSong(index, fromList: list);
            }
          },
          onLongPress: () => setState(() { _selectMode = true; _selectedIds.add(song.id); }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    _thumb(song.filePath),
                    if (isCurrent)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: MusicVisualizerBars(
                            isPlaying: isPlaying,
                            height: 16,
                            barWidth: 2.5,
                            color: const Color(0xFF818CF8),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              song.displayTitle,
                              style: TextStyle(
                                color: isCurrent ? const Color(0xFF818CF8) : Colors.white,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                fontSize: 13.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (song.formatBadge.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: song.isLossless
                                    ? const Color(0xFF06B6D4).withValues(alpha: 0.18)
                                    : (_service.hasMultipleFormats(song)
                                        ? const Color(0xFFF59E0B).withValues(alpha: 0.22)
                                        : const Color(0xFF6366F1).withValues(alpha: 0.14)),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: song.isLossless
                                      ? const Color(0xFF06B6D4)
                                      : (_service.hasMultipleFormats(song)
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFF6366F1).withValues(alpha: 0.6)),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                song.formatBadge,
                                style: TextStyle(
                                  color: song.isLossless
                                      ? const Color(0xFF06B6D4)
                                      : (_service.hasMultipleFormats(song)
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFF818CF8)),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                          if (isNew) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                              ),
                              child: const Text('NEW', style: TextStyle(color: Color(0xFF10B981), fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${song.displayArtist}  \u2022  ${fmtMs(song.duration)}',
                        style: TextStyle(
                          color: isCurrent ? const Color(0xFF818CF8).withValues(alpha: 0.85) : const Color(0xFF94A3B8),
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                    color: isFav ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                    size: 19,
                  ),
                  onPressed: () {
                    _service.toggleFavorite(song.id);
                    _toast(isFav ? 'Removed from Favourites' : 'Added to Favourites');
                  },
                ),
                _songMenu(song, list),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb([String? filePath]) {
    if (filePath != null && filePath.isNotEmpty) {
      return MediaArtworkWidget(
        filePath: filePath,
        isVideo: false,
        width: 44,
        height: 44,
        borderRadius: BorderRadius.circular(8),
        fallbackColor: const Color(0xFF1E293B),
        iconColor: const Color(0xFF818CF8),
      );
    }
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.music_note_rounded, color: Color(0xFF818CF8), size: 22),
    );
  }

  Widget _songMenu(SongInfo song, List<SongInfo>? list) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Color(0xFF666680), size: 18),
      onSelected: (v) {
        if (v == 'play') _service.playSongInfo(song);
        else if (v == 'play_next') _service.playNext(song);
        else if (v == 'add_queue') _service.addToQueue(song);
        else if (v == 'add_playlist') _addToPlaylistSheet(song.id);
        else if (v == 'share') _toast('Share coming soon');
        else if (v == 'delete') _deleteSong(song);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'play', child: Text('Play')),
        const PopupMenuItem(value: 'play_next', child: Text('Play Next')),
        const PopupMenuItem(value: 'add_queue', child: Text('Add to Queue')),
        const PopupMenuItem(value: 'add_playlist', child: Text('Add to Playlist')),
        const PopupMenuItem(value: 'share', child: Text('Share')),
        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
      ],
    );
  }

  void _deleteSong(SongInfo song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete this song?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              try { File(song.filePath).deleteSync(); } catch (_) {}
              _service.scanAllSongs();
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ---------- Playlists Tab ----------
  Widget _playlistsTab(String search) {
    final lists = search.isEmpty
        ? _service.playlists
        : _service.playlists.where((p) => p.name.toLowerCase().contains(search)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Text(
                '${lists.length + 1} Playlists',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _newPlaylistDialog,
                icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                label: const Text('New Playlist', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2E).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E293B), width: 0.8),
                ),
                child: ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEC4899).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
                  ),
                  title: const Text('Favourites', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text('${_service.favorites.length} tracks', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 18),
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF334155))),
                    onSelected: (v) {
                      if (v == 'open') {
                        GlobalPlayerState.instance.pushToolRoute('playlist');
                        Navigator.push(context, MaterialPageRoute(builder: (_) => MusicPlaylistPage(
                          service: _service, playlistName: 'Favourites',
                        ))).then((_) {
                          GlobalPlayerState.instance.popToolRoute('playlist');
                        });
                      } else if (v == 'play' && _service.favorites.isNotEmpty) {
                        _service.playSong(0, fromList: _service.favorites);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'open', child: Text('Open', style: TextStyle(color: Colors.white))),
                      const PopupMenuItem(value: 'play', child: Text('Play', style: TextStyle(color: Colors.white))),
                    ],
                  ),
                  onTap: () {
                    GlobalPlayerState.instance.pushToolRoute('playlist');
                    Navigator.push(context, MaterialPageRoute(builder: (_) => MusicPlaylistPage(
                      service: _service, playlistName: 'Favourites',
                    ))).then((_) {
                      GlobalPlayerState.instance.popToolRoute('playlist');
                    });
                  },
                ),
              ),
              ...lists.map((pl) {
                final s = _service.getPlaylistSongs(pl.name);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2E).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E293B), width: 0.8),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 24),
                    ),
                    title: Text(pl.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: Text('${s.length} tracks', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 18),
                      color: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF334155))),
                      onSelected: (v) {
                        if (v == 'open') {
                          GlobalPlayerState.instance.pushToolRoute('playlist');
                          Navigator.push(context, MaterialPageRoute(builder: (_) => MusicPlaylistPage(
                            service: _service, playlistName: pl.name,
                          ))).then((_) {
                            GlobalPlayerState.instance.popToolRoute('playlist');
                          });
                        } else if (v == 'play' && s.isNotEmpty) _service.playSong(0, fromList: s);
                        else if (v == 'rename') _renamePlaylistDialog(pl.name);
                        else if (v == 'export') _exportPlaylistM3u8(pl.name, s);
                        else if (v == 'delete') _service.deletePlaylist(pl.name);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'open', child: Text('Open', style: TextStyle(color: Colors.white))),
                        const PopupMenuItem(value: 'play', child: Text('Play', style: TextStyle(color: Colors.white))),
                        const PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white))),
                        const PopupMenuItem(value: 'export', child: Text('Export .m3u8', style: TextStyle(color: Colors.white))),
                        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                    onTap: () {
                      GlobalPlayerState.instance.pushToolRoute('playlist');
                      Navigator.push(context, MaterialPageRoute(builder: (_) => MusicPlaylistPage(
                        service: _service, playlistName: pl.name,
                      ))).then((_) {
                        GlobalPlayerState.instance.popToolRoute('playlist');
                      });
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  void _newPlaylistDialog({int? songId}) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Color(0xFF666680)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4E))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                if (songId != null && songId > 0) {
                  _service.addToPlaylist(name, songId);
                  _toast('Created "$name" and added song');
                } else {
                  _service.addToPlaylist(name, -1);
                  _toast('Created playlist "$name"');
                }
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  void _renamePlaylistDialog(String oldName) {
    final ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'New name',
            hintStyle: TextStyle(color: Color(0xFF666680)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4E))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                final ok = _service.renamePlaylist(oldName, newName);
                if (!ok) {
                  _toast('A playlist with that name already exists');
                  return;
                }
                _toast('Renamed to "$newName"');
              }
              Navigator.pop(ctx);
            },
            child: const Text('Rename', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  void _exportPlaylistM3u8(String playlistName, List<SongInfo> songs) async {
    if (songs.isEmpty) { _toast('Playlist is empty'); return; }
    final content = StringBuffer('#EXTM3U\n');
    for (final s in songs) {
      final dur = (s.duration / 1000).round();
      content.writeln('#EXTINF:$dur,${s.displayArtist} - ${s.displayTitle}');
      content.writeln(s.filePath);
    }
    try {
      final dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$playlistName.m3u8');
      await file.writeAsString(content.toString());
      _toast('Exported to Download/$playlistName.m3u8');
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  // ---------- Grouped Tabs ----------
  Widget _groupTab(String search, String type) {
    Map<String, List<SongInfo>> map;
    IconData icon;
    List<Color> gradientColors;
    switch (type) {
      case 'folders':
        map = _service.folders;
        icon = Icons.folder_rounded;
        gradientColors = const [Color(0xFFF59E0B), Color(0xFFF97316)];
        break;
      case 'albums':
        map = _service.albums;
        icon = Icons.album_rounded;
        gradientColors = const [Color(0xFF8B5CF6), Color(0xFF6366F1)];
        break;
      default:
        map = _service.artists;
        icon = Icons.person_rounded;
        gradientColors = const [Color(0xFF06B6D4), Color(0xFF0EA5E9)];
        break;
    }
    var keys = map.keys.toList();
    if (search.isNotEmpty) keys = keys.where((k) => k.toLowerCase().contains(search)).toList();
    keys.sort();

    if (keys.isEmpty) {
      return Center(child: Text(
        type == 'folders' ? 'No folders found' : type == 'albums' ? 'No albums found' : 'No artists found',
        style: const TextStyle(color: Color(0xFF64748B))));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: keys.map((k) {
        final count = map[k]!.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E293B), width: 0.8),
          ),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors.first.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            title: Text(
              k.split(Platform.pathSeparator).last,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '$count ${count == 1 ? "track" : "tracks"}',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 20),
            onTap: () => _openGroup(k, map[k]!),
          ),
        );
      }).toList(),
    );
  }

  void _openGroup(String title, List<SongInfo> songs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F1A),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (_, scrollCtrl) => CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                    TextButton.icon(
                      onPressed: () { _service.playSong(0, fromList: songs); Navigator.pop(context); },
                      icon: const Icon(Icons.play_arrow, size: 18, color: Color(0xFF818CF8)),
                      label: const Text('Play All', style: TextStyle(color: Color(0xFF818CF8))),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _songItem(songs[i], i, songs),
                childCount: songs.length,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Mini Player ----------
  Widget _buildMiniPlayer() {
    final s = _service.currentSong;
    if (s == null) return const SizedBox.shrink();
    final isFav = _service.isFavorite(s.id);
    final progress = _service.duration > Duration.zero
        ? (_service.position.inMilliseconds / _service.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: GestureDetector(
        onTap: () => _service.setShowNowPlaying(true),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF131C2E).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _accentColor.withValues(alpha: 0.45),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      _thumbSmall(s.filePath),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.displayTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 2.5),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.displayArtist,
                                    style: TextStyle(
                                      color: _accentColor.withValues(alpha: 0.9),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                MusicVisualizerBars(
                                  isPlaying: _service.isPlaying,
                                  height: 11,
                                  barWidth: 2,
                                  spacing: 1.5,
                                  color: _accentColor,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                          color: isFav ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                          size: 20,
                        ),
                        onPressed: () {
                          _service.toggleFavorite(s.id);
                          _toast(isFav ? 'Removed from Favourites' : 'Added to Favourites');
                        },
                      ),
                      GestureDetector(
                        onTap: () => _service.togglePlayPause(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_accentColor, _accentColor.withValues(alpha: 0.85)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _accentColor.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            _service.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 24),
                        onPressed: () => _service.nextSong(),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(_accentColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbSmall([String? filePath]) {
    if (filePath != null && filePath.isNotEmpty) {
      return MediaArtworkWidget(
        filePath: filePath,
        isVideo: false,
        width: 40,
        height: 40,
        borderRadius: BorderRadius.circular(8),
        fallbackColor: const Color(0xFF1E293B),
        iconColor: const Color(0xFF818CF8),
      );
    }
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.music_note_rounded, color: Color(0xFF818CF8), size: 20),
    );
  }

  // ---------- Footer ----------
  Widget _buildFooter() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1322),
        border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 2, top: 4),
      child: Row(
        children: [
          _navItem(Icons.library_music_rounded, 'My Music', true, null),
          _navItem(Icons.smart_display_rounded, 'Videos', false, widget.onOpenVideos),
          _navItem(Icons.settings_rounded, 'Settings', false, widget.onOpenSettings ?? _openMusicSettings),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool selected, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? const Color(0xFF818CF8) : const Color(0xFF64748B), size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFF818CF8) : const Color(0xFF64748B),
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              if (selected)
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFF818CF8),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Now Playing ──────────────────────────────────────────────────────────────
  Widget _buildNowPlaying() {
    final song = _service.currentSong!;
    final isFav = _service.isFavorite(song.id);
    final pct = _service.duration > Duration.zero
        ? (_service.position.inMilliseconds / _service.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final artSize = isLandscape ? 180.0 : 280.0;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _dominantColor,
              _dominantColor.withValues(alpha: 0.85),
              const Color(0xFF0F0F1A),
            ],
          ),
        ),
        child: SafeArea(
          child: isLandscape
              ? _npLandscape(song, isFav, artSize, pct)
              : _npPortrait(song, isFav, artSize, pct),
        ),
      ),
    );
  }

  Widget _npPortrait(SongInfo song, bool isFav, double artSize, double pct) {
    return Column(
      children: [
        // ── Header: down arrow + title + queue ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 26),
                  onPressed: () => _service.setShowNowPlaying(false),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MusicVisualizerBars(
                    isPlaying: _service.isPlaying,
                    height: 12,
                    barWidth: 2,
                    spacing: 1.5,
                    color: _accentColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 20),
                  onPressed: _queueSheet,
                ),
              ),
            ],
          ),
        ),

        // ── Album Art ──
        Expanded(
          flex: 4,
          child: Center(
            child: Hero(
              tag: 'album_art_${song.id}',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: artSize,
                height: artSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: _accentColor.withValues(alpha: 0.38), blurRadius: 42, spreadRadius: 4),
                  ],
                  color: _dominantColor.withValues(alpha: 0.6),
                ),
                child: _showLyrics
                    ? ClipRRect(borderRadius: BorderRadius.circular(24), child: _buildLyricsView())
                    : MediaArtworkWidget(
                        filePath: song.filePath,
                        isVideo: false,
                        width: artSize,
                        height: artSize,
                        borderRadius: BorderRadius.circular(24),
                        fit: BoxFit.cover,
                        fallbackColor: _dominantColor.withValues(alpha: 0.6),
                        iconColor: const Color(0xFF818CF8),
                      ),
              ),
            ),
          ),
        ),

        if (song.formatBadge.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
            decoration: BoxDecoration(
              color: song.isLossless
                  ? const Color(0xFF06B6D4).withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: song.isLossless
                    ? const Color(0xFF06B6D4)
                    : Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  song.isLossless ? Icons.auto_awesome : Icons.graphic_eq_rounded,
                  size: 13,
                  color: song.isLossless ? const Color(0xFF06B6D4) : _accentColor,
                ),
                const SizedBox(width: 5),
                Text(
                  song.isLossless
                      ? 'LOSSLESS AUDIO \u2022 ${song.formatBadge}'
                      : 'AUDIO \u2022 ${song.formatBadge}',
                  style: TextStyle(
                    color: song.isLossless ? const Color(0xFF06B6D4) : Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // ── Song Info ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(
                song.displayTitle,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                song.displayArtist,
                style: TextStyle(color: _accentColor, fontSize: 15, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
              if (song.displayAlbum.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  song.displayAlbum,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Action Row ──
        _buildActionRow(song, isFav),

        const SizedBox(height: 8),

        // ── Progress Bar ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: _accentColor,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  thumbColor: Colors.white,
                  overlayColor: _accentColor.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: pct,
                  onChanged: (v) => _service.seek(Duration(milliseconds: (v * _service.duration.inMilliseconds).round())),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(fmtDur(_service.position), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                    Text(fmtDur(_service.duration), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Playback Controls ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: _service.isShuffled ? _accentColor : Colors.white.withValues(alpha: 0.4),
                  size: 22,
                ),
                onPressed: () => _service.toggleShuffle(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 34),
                onPressed: () => _service.previousSong(),
              ),
              GestureDetector(
                onTap: () => _service.togglePlayPause(),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_accentColor, _accentColor.withValues(alpha: 0.85)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.45),
                        blurRadius: 22,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _service.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 34),
                onPressed: () => _service.nextSong(),
              ),
              IconButton(
                icon: Icon(
                  _service.loopMode == LoopMode.off ? Icons.repeat_rounded :
                  _service.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  color: _service.loopMode != LoopMode.off ? _accentColor : Colors.white.withValues(alpha: 0.4),
                  size: 22,
                ),
                onPressed: () => _service.cycleLoopMode(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
      ],
    );
  }

  Widget _npLandscape(SongInfo song, bool isFav, double artSize, double pct) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
                    onPressed: () => _service.setShowNowPlaying(false),
                  ),
                  const Spacer(),
                  Text('Now Playing', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.queue_music, color: Colors.white70, size: 22),
                    onPressed: _queueSheet,
                  ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Hero(
                  tag: 'album_art_${song.id}',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    width: artSize, height: artSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 30)],
                      color: _dominantColor.withValues(alpha: 0.6),
                    ),
                    child: _showLyrics
                        ? ClipRRect(borderRadius: BorderRadius.circular(16), child: _buildLyricsView())
                        : MediaArtworkWidget(
                            filePath: song.filePath,
                            isVideo: false,
                            width: artSize,
                            height: artSize,
                            borderRadius: BorderRadius.circular(16),
                            fit: BoxFit.cover,
                            fallbackColor: _dominantColor.withValues(alpha: 0.6),
                            iconColor: const Color(0xFF818CF8),
                          ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.displayTitle, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis, maxLines: 2),
                      const SizedBox(height: 4),
                      Text(song.displayArtist, style: TextStyle(color: _accentColor, fontSize: 14)),
                      const SizedBox(height: 12),
                      _buildActionRow(song, isFav),
                      const SizedBox(height: 12),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          activeTrackColor: _accentColor, inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: pct,
                          onChanged: (v) => _service.seek(Duration(milliseconds: (v * _service.duration.inMilliseconds).round())),
                        ),
                      ),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(fmtDur(_service.position), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                        Text(fmtDur(_service.duration), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(Icons.shuffle, color: _service.isShuffled ? _accentColor : Colors.white.withValues(alpha: 0.4), size: 22),
                    onPressed: () => _service.toggleShuffle(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 30),
                    onPressed: () => _service.previousSong(),
                  ),
                  GestureDetector(
                    onTap: () => _service.togglePlayPause(),
                    child: Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _accentColor),
                      child: Icon(_service.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white, size: 34),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 30),
                    onPressed: () => _service.nextSong(),
                  ),
                  IconButton(
                    icon: Icon(
                      _service.loopMode == LoopMode.off ? Icons.repeat_rounded :
                      _service.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                      color: _service.loopMode != LoopMode.off ? _accentColor : Colors.white.withValues(alpha: 0.4), size: 22,
                    ),
                    onPressed: () => _service.cycleLoopMode(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(SongInfo song, bool isFav) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _actionChip(Icons.favorite, isFav ? 'Favourited' : 'Favourite', isFav, () {
          _service.toggleFavorite(song.id);
          _toast(isFav ? 'Removed from Favourites' : 'Added to Favourites');
        }),
        const SizedBox(width: 12),
        _actionChip(Icons.timer_outlined, _service.hasTimer ? '${_service.timerMinutes}m' : 'Timer', _service.hasTimer, () => _timerSheet()),
        const SizedBox(width: 12),
        _actionChip(Icons.lyrics, 'Lyrics', _showLyrics, () {
          setState(() => _showLyrics = !_showLyrics);
          if (_showLyrics && _lrcLines.isEmpty && _lyricsText.isEmpty) {
            _fetchLyrics(forceOnline: true);
          }
        }),
        const SizedBox(width: 12),
        _actionChip(Icons.speed, '${_service.player.speed}x', _service.player.speed != 1.0, () => _speedSheet()),
        const SizedBox(width: 12),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.6), size: 22),
          onSelected: (v) => _npMenu(v, song),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'add_playlist', child: ListTile(title: Text('Add to Playlist'), leading: Icon(Icons.playlist_add))),
            const PopupMenuItem(value: 'tag_editor', child: ListTile(title: Text('Edit Tags'), leading: Icon(Icons.edit))),
            const PopupMenuItem(value: 'edit_lyrics', child: ListTile(title: Text('Lyrics Creator / Studio'), leading: Icon(Icons.edit_note))),
            const PopupMenuItem(value: 'lyrics_folder', child: ListTile(title: Text('Open MakawLyrics Folder'), leading: Icon(Icons.folder_open))),
            const PopupMenuItem(value: 'rename', child: ListTile(title: Text('Rename File'), leading: Icon(Icons.drive_file_rename_outline))),
            const PopupMenuItem(value: 'share', child: ListTile(title: Text('Share'), leading: Icon(Icons.share))),
            const PopupMenuItem(value: 'delete', child: ListTile(title: Text('Delete', style: TextStyle(color: Colors.redAccent)), leading: Icon(Icons.delete, color: Colors.redAccent))),
          ],
        ),
      ],
    );
  }

  Widget _actionChip(IconData icon, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: active ? _accentColor.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? _accentColor.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: active ? (icon == Icons.favorite || icon == Icons.favorite_rounded ? const Color(0xFFEF4444) : _accentColor) : Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: active ? _accentColor : Colors.white54,
              fontSize: 10.5,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _npMenu(String v, SongInfo song) {
    if (v == 'add_playlist') _addToPlaylistSheet(song.id);
    else if (v == 'tag_editor') _tagEditorDialog(song);
    else if (v == 'edit_lyrics') _openLyricsCreator();
    else if (v == 'lyrics_folder') _openMakawLyricsFolder();
    else if (v == 'rename') _renameDialog(song);
    else if (v == 'share') {
      if (File(song.filePath).existsSync()) {
        Share.shareXFiles([XFile(song.filePath)]);
      } else {
        _toast('Audio file not found');
      }
    }
    else if (v == 'delete') _deleteSong(song);
  }

  void _renameDialog(SongInfo song) {
    final ctrl = TextEditingController(text: song.fileName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Rename', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl, autofocus: true, style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'New name', hintStyle: TextStyle(color: Color(0xFF666680)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4E))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                try {
                  final dir = song.filePath.substring(0, song.filePath.lastIndexOf(Platform.pathSeparator));
                  final ext = song.filePath.split('.').last;
                  File(song.filePath).renameSync('$dir${Platform.pathSeparator}${ctrl.text}.$ext');
                  _service.scanAllSongs();
                } catch (_) {}
                Navigator.pop(ctx);
              }
            },
            child: const Text('Rename', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  void _addToPlaylistSheet(int songId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5, maxChildSize: 0.8, minChildSize: 0.3,
        builder: (_, scrollCtrl) => CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(padding: const EdgeInsets.all(16),
                  child: Text('Add to Playlist', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
            ),
            if (_service.favorites.every((s) => s.id != songId))
              SliverToBoxAdapter(
                child: ListTile(
                  leading: const Icon(Icons.favorite, color: Color(0xFF818CF8)),
                  title: const Text('Favourites', style: TextStyle(color: Colors.white)),
                  onTap: () { _service.toggleFavorite(songId); Navigator.pop(context); _toast('Added to Favourites'); },
                ),
              ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final pl = _service.playlists[i];
                  return ListTile(
                    leading: const Icon(Icons.playlist_play, color: Color(0xFF818CF8)),
                    title: Text(pl.name, style: const TextStyle(color: Colors.white)),
                    onTap: () { _service.addToPlaylist(pl.name, songId); Navigator.pop(context); _toast('Added to ${pl.name}'); },
                  );
                },
                childCount: _service.playlists.length,
              ),
            ),
            SliverToBoxAdapter(
              child: ListTile(
                leading: const Icon(Icons.add, color: Color(0xFF818CF8)),
                title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
                onTap: () { Navigator.pop(context); _newPlaylistDialog(songId: songId); },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }

  // ─── ID3 Tag Editor ─────────────────────────────────────────────────────────
  void _tagEditorDialog(SongInfo song) {
    final titleCtrl = TextEditingController(text: song.displayTitle);
    final artistCtrl = TextEditingController(text: song.displayArtist);
    final albumCtrl = TextEditingController(text: song.displayAlbum);
    final yearCtrl = TextEditingController();
    final genreCtrl = TextEditingController();
    final trackCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Edit Tags', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tagField('Title', titleCtrl),
                _tagField('Artist', artistCtrl),
                _tagField('Album', albumCtrl),
                _tagField('Year', yearCtrl),
                _tagField('Genre', genreCtrl),
                _tagField('Track #', trackCtrl),
                const SizedBox(height: 8),
                Text('Tags are saved to the audio file via platform channel.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _toast('Saving tags...');
              try {
                await _metadataChannel.invokeMethod('writeMetadata', {
                  'path': song.filePath,
                  'title': titleCtrl.text.trim(),
                  'artist': artistCtrl.text.trim(),
                  'album': albumCtrl.text.trim(),
                  'year': yearCtrl.text.trim(),
                  'genre': genreCtrl.text.trim(),
                  'track': trackCtrl.text.trim(),
                });
                await _service.scanAllSongs();
                _toast('Tags saved');
              } catch (e) {
                _toast('Failed to save tags: $e');
              }
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  static const _metadataChannel = MethodChannel('com.hexadigitall.makaw/metadata');

  Widget _tagField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF666680)),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4E))),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
        ),
      ),
    );
  }

  void _queueSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MusicQueueSheet(service: _service),
    );
  }

  void _timerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5, maxChildSize: 0.7, minChildSize: 0.3,
        builder: (_, scrollCtrl) => CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(padding: const EdgeInsets.all(16),
                  child: Text('Sleep Timer', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                _timerOpt('Off', 0), _timerOpt('5 minutes', 5), _timerOpt('10 minutes', 10),
                _timerOpt('15 minutes', 15), _timerOpt('30 minutes', 30), _timerOpt('1 hour', 60),
                _timerOpt('90 minutes', 90), _timerOpt('2 hours', 120),
              ]),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }

  Widget _timerOpt(String label, int mins) {
    return ListTile(
      title: Text(label, style: TextStyle(color: _service.timerMinutes == mins ? const Color(0xFF818CF8) : Colors.white)),
      trailing: _service.timerMinutes == mins ? const Icon(Icons.check, color: Color(0xFF818CF8), size: 20) : null,
      onTap: () { _service.setTimer(mins); Navigator.pop(context); },
    );
  }

  void _speedSheet() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final cur = _service.player.speed;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5, maxChildSize: 0.7, minChildSize: 0.3,
        builder: (_, scrollCtrl) => CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(padding: const EdgeInsets.all(16),
                  child: Text('Playback Speed', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
            ),
            SliverList(
              delegate: SliverChildListDelegate(
                speeds.map((s) => ListTile(
                  title: Text('${s}x', style: TextStyle(color: cur == s ? const Color(0xFF818CF8) : Colors.white)),
                  trailing: cur == s ? const Icon(Icons.check, color: Color(0xFF818CF8), size: 20) : null,
                  onTap: () { _service.setPlaybackSpeed(s); Navigator.pop(context); },
                )).toList(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: const Color(0xFF1A1A2E),
      behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2),
    ));
  }

  // ─── Settings ──────────────────────────────────────────────────────────────
  void _openMusicSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => DraggableScrollableSheet(
          initialChildSize: 0.78,
          maxChildSize: 0.94,
          minChildSize: 0.45,
          expand: false,
          builder: (_, sc) => CustomScrollView(
            controller: sc,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                  child: Column(
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
                      Row(
                        children: [
                          const Text(
                            'Music Settings',
                            style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              _service.scanAllSongs(force: true);
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF818CF8)),
                            label: const Text('Scan', style: TextStyle(color: Color(0xFF818CF8))),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _settingsSectionHeader('Audio & Equalizer'),
              SliverToBoxAdapter(
                child: ListTile(
                  leading: const Icon(Icons.equalizer_rounded, color: Color(0xFF818CF8)),
                  title: const Text('Equalizer & Bass Boost', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    _service.eqEnabled
                        ? 'Active: ${_service.eqPreset}${_service.bassBoost > 0 ? " + Bass ${(_service.bassBoost * 100).round()}%" : ""}'
                        : 'Off (Tap to tune 5-band EQ)',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: Switch(
                    value: _service.eqEnabled,
                    activeColor: const Color(0xFF818CF8),
                    onChanged: (v) async {
                      await _service.setEqEnabled(v);
                      setDlg(() {});
                    },
                  ),
                  onTap: () => _openEqualizerSheet(ctx, setDlg),
                ),
              ),
              SliverToBoxAdapter(
                child: SwitchListTile(
                  secondary: const Icon(Icons.compare_arrows_rounded, color: Color(0xFF818CF8)),
                  title: const Text('Crossfade Transitions', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    _service.crossfadeEnabled
                        ? 'Smooth fade out (${_service.crossfadeSec}s before end)'
                        : 'Gapless direct transitions',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: _service.crossfadeEnabled,
                  activeColor: const Color(0xFF818CF8),
                  onChanged: (v) {
                    _service.setCrossfade(v);
                    setDlg(() {});
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: _settingsTile(
                  Icons.speed_rounded,
                  'Playback speed: ${_service.player.speed}x',
                  () => _speedSheet(),
                ),
              ),
              SliverToBoxAdapter(
                child: _settingsTile(
                  Icons.tune_rounded,
                  'Audio buffer: ${_service.bufferMs}ms',
                  () => _showBufferPicker(ctx, setDlg),
                ),
              ),
              SliverToBoxAdapter(
                child: _settingsTile(
                  Icons.bedtime_outlined,
                  _service.hasTimer ? 'Sleep timer: ${_service.timerMinutes}m remaining' : 'Sleep timer: Off',
                  () => _timerSheet(),
                ),
              ),
              _settingsSectionHeader('Library & Scanner'),
              SliverToBoxAdapter(
                child: _settingsTile(
                  Icons.sort_rounded,
                  'Default sort: ${_sortLabel(_service.sortMode)}',
                  () => _showSortPicker(ctx, setDlg),
                ),
              ),
              SliverToBoxAdapter(
                child: SwitchListTile(
                  secondary: const Icon(Icons.filter_alt_outlined, color: Color(0xFF818CF8)),
                  title: const Text('Skip short clips (< 30s)', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text(
                    'Hide ringtones, notifications, and voice notes during scan',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: _service.skipShortAudio,
                  activeColor: const Color(0xFF818CF8),
                  onChanged: (v) {
                    _service.setSkipShortAudio(v);
                    _service.scanAllSongs(force: true);
                    setDlg(() {});
                  },
                ),
              ),
              _settingsSectionHeader('Lyrics & Studio'),
              SliverToBoxAdapter(
                child: SwitchListTile(
                  secondary: const Icon(Icons.cloud_download_outlined, color: Color(0xFF818CF8)),
                  title: const Text('Auto-search online synced lyrics', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text(
                    'Queries lrclib.net / lyrics.ovh when offline .lrc is missing',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: _service.autoFetchLyrics,
                  activeColor: const Color(0xFF818CF8),
                  onChanged: (v) {
                    _service.setAutoFetchLyrics(v);
                    setDlg(() {});
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: SwitchListTile(
                  secondary: const Icon(Icons.save_alt_rounded, color: Color(0xFF818CF8)),
                  title: const Text('Save fetched lyrics to MakawLyrics folder', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text(
                    'Caches downloaded .lrc files locally for offline use & sharing',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: _service.saveLrcToFolder,
                  activeColor: const Color(0xFF818CF8),
                  onChanged: (v) {
                    _service.setSaveLrcToFolder(v);
                    setDlg(() {});
                  },
                ),
              ),
              if (_service.currentSong != null)
                SliverToBoxAdapter(
                  child: _settingsTile(
                    Icons.timer_outlined,
                    'Open Lyrics Creator for current song',
                    () {
                      Navigator.pop(ctx);
                      _openLyricsCreator();
                    },
                  ),
                ),
              SliverToBoxAdapter(
                child: _settingsTile(
                  Icons.folder_open_rounded,
                  'Browse MakawLyrics (.lrc) folder',
                  () {
                    Navigator.pop(ctx);
                    _openMakawLyricsFolder();
                  },
                ),
              ),
              _settingsSectionHeader('System & Info'),
              SliverToBoxAdapter(
                child: _settingsTile(
                  Icons.notifications_none_rounded,
                  'Media Notification: ${_service.notificationStatus}',
                  () => _showAbout(ctx),
                ),
              ),
              SliverToBoxAdapter(
                child: _settingsTile(Icons.info_outline_rounded, 'About Makaw Music', () => _showAbout(ctx)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 36)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsSectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF818CF8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  void _openEqualizerSheet(BuildContext parentCtx, void Function(void Function()) parentSetDlg) {
    showModalBottomSheet(
      context: parentCtx,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEqState) {
          final bands = _service.eqBandDb;
          final freqs = _service.eqFreqsHz;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.equalizer_rounded, color: Color(0xFF818CF8)),
                      const SizedBox(width: 8),
                      const Text(
                        'Equalizer & Tone',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Switch(
                        value: _service.eqEnabled,
                        activeColor: const Color(0xFF818CF8),
                        onChanged: (v) async {
                          await _service.setEqEnabled(v);
                          setEqState(() {});
                          parentSetDlg(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: MusicPlayerService.eqPresets.keys.map((preset) {
                      final active = _service.eqPreset == preset;
                      return ChoiceChip(
                        label: Text(preset),
                        selected: active,
                        selectedColor: const Color(0xFF818CF8),
                        backgroundColor: const Color(0xFF1E293B),
                        labelStyle: TextStyle(
                          color: active ? Colors.black : Colors.white70,
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        ),
                        onSelected: (_) async {
                          await _service.applyEqPreset(preset);
                          setEqState(() {});
                          parentSetDlg(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Bass Boost', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('${(_service.bassBoost * 100).round()}%', style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Slider(
                    value: _service.bassBoost,
                    min: 0.0,
                    max: 1.0,
                    activeColor: const Color(0xFF818CF8),
                    inactiveColor: Colors.white12,
                    onChanged: (v) async {
                      await _service.setBassBoost(v);
                      setEqState(() {});
                      parentSetDlg(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 185,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(bands.length, (i) {
                        final hz = i < freqs.length ? freqs[i] : 1000;
                        final label = hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k' : '${hz}Hz';
                        final db = bands[i].clamp(-12.0, 12.0);
                        return Expanded(
                          child: Column(
                            children: [
                              Text('${db >= 0 ? '+' : ''}${db.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: -1,
                                  child: Slider(
                                    value: db,
                                    min: -12.0,
                                    max: 12.0,
                                    activeColor: _service.eqEnabled ? const Color(0xFF818CF8) : Colors.white24,
                                    inactiveColor: Colors.white12,
                                    onChanged: (val) async {
                                      await _service.setEqBandDb(i, val);
                                      setEqState(() {});
                                      parentSetDlg(() {});
                                    },
                                  ),
                                ),
                              ),
                              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                            ],
                          ),
                        );
                      }),
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

  String _sortLabel(String mode) {
    switch (mode) {
      case 'name': return 'A-Z';
      case 'name_desc': return 'Z-A';
      case 'date': return 'Newest first';
      case 'duration': return 'Longest first';
      case 'size': return 'Largest first';
      default: return 'A-Z';
    }
  }

  void _showSortPicker(BuildContext ctx, void Function(void Function()) setDlg) {
    final modes = ['name', 'name_desc', 'date', 'duration', 'size'];
    final labels = ['A-Z', 'Z-A', 'Newest first', 'Longest first', 'Largest first'];
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Sort Order', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: List.generate(modes.length, (i) =>
          RadioListTile<String>(
            title: Text(labels[i], style: const TextStyle(color: Colors.white, fontSize: 14)),
            value: modes[i], groupValue: _service.sortMode,
            activeColor: const Color(0xFF818CF8),
            onChanged: (v) { _service.setSortMode(v!); Navigator.pop(dCtx); setDlg(() {}); },
          ),
        )),
      ),
    );
  }

  void _showBufferPicker(BuildContext ctx, void Function(void Function()) setDlg) {
    final values = [500, 1000, 2000, 3000, 5000];
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Audio Buffer', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: values.map((v) =>
          RadioListTile<int>(
            title: Text('${v}ms', style: const TextStyle(color: Colors.white, fontSize: 14)),
            value: v, groupValue: _service.bufferMs,
            activeColor: const Color(0xFF818CF8),
            onChanged: (val) { _service.setBufferMs(val!); Navigator.pop(dCtx); setDlg(() {}); },
          ),
        ).toList()),
      ),
    );
  }

  void _showAbout(BuildContext ctx) {
    Navigator.pop(ctx);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Makaw Music', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Version 1.0', style: TextStyle(color: Colors.white54, fontSize: 13)),
          SizedBox(height: 8),
          Text('Music player for local audio files. Supports shuffle, lyrics (LRC/plain), playlists, and more.', style: TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Color(0xFF818CF8))))],
      ),
    );
  }

  Widget _settingsTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF818CF8), size: 22),
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF666680), size: 20),
      onTap: onTap,
    );
  }
}

class MusicQueueSheet extends StatefulWidget {
  final MusicPlayerService service;
  final VoidCallback? onOpenPlayer;
  const MusicQueueSheet({super.key, required this.service, this.onOpenPlayer});

  @override
  State<MusicQueueSheet> createState() => _MusicQueueSheetState();
}

class _MusicQueueSheetState extends State<MusicQueueSheet> {
  MusicPlayerService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _fmtDurMs(int ms) {
    if (ms <= 0) return '';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = _service;
    final cur = s.currentSong;
    final upNext = s.currentIndex >= 0 && s.currentIndex + 1 < s.queue.length
        ? s.queue.sublist(s.currentIndex + 1)
        : <SongInfo>[];

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      maxChildSize: 0.94,
      minChildSize: 0.45,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: Color(0xFF283148), width: 1)),
        ),
        child: Column(
          children: [
            // ── Drag Handle ──
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  const Text(
                    'Playing Queue',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF818CF8).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${s.queue.length} tracks',
                      style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  if (widget.onOpenPlayer != null)
                    TextButton.icon(
                      onPressed: widget.onOpenPlayer,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF818CF8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      icon: const Icon(Icons.open_in_full_rounded, size: 15),
                      label: const Text('Player', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  if (s.queue.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.playlist_add_check_rounded, color: Colors.white.withValues(alpha: 0.6), size: 22),
                      onPressed: () => _saveQueueAsPlaylist(s),
                      tooltip: 'Save as Playlist',
                    ),
                  if (s.queue.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: Colors.white.withValues(alpha: 0.5), size: 20),
                      onPressed: () {
                        s.clearQueue();
                        Navigator.pop(context);
                      },
                      tooltip: 'Clear Queue',
                    ),
                ],
              ),
            ),

            // ── Scrollable Content ──
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 24),
                children: [
                  // ── NOW PLAYING Section ──
                  if (cur != null) ...[
                    _sectionHeader('NOW PLAYING'),
                    _queueItem(cur, s.currentIndex, isPlaying: true),
                  ],

                  // ── UP NEXT Section ──
                  if (upNext.isNotEmpty) ...[
                    _sectionHeader('UP NEXT (${upNext.length})'),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: upNext.length,
                      onReorder: (oldIdx, newIdx) => _reorderQueue(
                        s,
                        oldIdx + s.currentIndex + 1,
                        newIdx + s.currentIndex + 1,
                      ),
                      itemBuilder: (_, i) {
                        final realIdx = i + s.currentIndex + 1;
                        return _queueItem(upNext[i], realIdx, key: ValueKey('${upNext[i].id}_$realIdx'));
                      },
                    ),
                  ],

                  // ── AUTO-PLAY & PLAYBACK MODES Section ──
                  _sectionHeader('PLAYBACK MODE'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: s.cycleLoopMode,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: s.loopMode != LoopMode.off
                                    ? const Color(0xFF818CF8).withValues(alpha: 0.14)
                                    : const Color(0xFF161D30),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: s.loopMode != LoopMode.off
                                      ? const Color(0xFF818CF8).withValues(alpha: 0.4)
                                      : Colors.white10,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    s.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                    color: s.loopMode != LoopMode.off ? const Color(0xFF818CF8) : Colors.white54,
                                    size: 17,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    s.loopMode == LoopMode.one
                                        ? 'Repeat One'
                                        : s.loopMode == LoopMode.all
                                            ? 'Repeat All'
                                            : 'Repeat Off',
                                    style: TextStyle(
                                      color: s.loopMode != LoopMode.off ? Colors.white : Colors.white60,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: s.toggleShuffle,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: s.isShuffled
                                    ? const Color(0xFF818CF8).withValues(alpha: 0.14)
                                    : const Color(0xFF161D30),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: s.isShuffled
                                      ? const Color(0xFF818CF8).withValues(alpha: 0.4)
                                      : Colors.white10,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shuffle_rounded,
                                    color: s.isShuffled ? const Color(0xFF818CF8) : Colors.white54,
                                    size: 17,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    s.isShuffled ? 'Shuffled' : 'In Order',
                                    style: TextStyle(
                                      color: s.isShuffled ? Colors.white : Colors.white60,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (s.queue.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.queue_music, color: Colors.white.withValues(alpha: 0.15), size: 48),
                            const SizedBox(height: 12),
                            Text('Queue is empty', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
                            const SizedBox(height: 4),
                            Text('Play a song to start', style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _queueItem(SongInfo song, int index, {bool isPlaying = false, Key? key}) {
    final durStr = _fmtDurMs(song.duration);
    final reorderIndex = isPlaying ? index : (index - (_service.currentIndex + 1));

    return ReorderableDelayedDragStartListener(
      key: key ?? ValueKey('${song.id}_$index'),
      index: reorderIndex.clamp(0, _service.queue.length),
      enabled: !isPlaying,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: isPlaying ? const Color(0xFF818CF8).withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isPlaying)
                ReorderableDragStartListener(
                  index: reorderIndex.clamp(0, _service.queue.length),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.drag_handle_rounded, color: Colors.white.withValues(alpha: 0.28), size: 20),
                  ),
                ),
              Stack(
                alignment: Alignment.center,
                children: [
                  MediaArtworkWidget(
                    filePath: song.filePath,
                    isVideo: false,
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.circular(10),
                    fallbackColor: const Color(0xFF1E293B),
                    iconColor: const Color(0xFF818CF8),
                  ),
                  if (isPlaying)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.48),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: MusicVisualizerBars(
                          isPlaying: _service.isPlaying,
                          color: const Color(0xFF818CF8),
                          height: 14,
                          barWidth: 2.5,
                          spacing: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          title: Text(
            song.displayTitle,
            style: TextStyle(
              color: isPlaying ? const Color(0xFFA5B4FC) : Colors.white,
              fontSize: 14,
              fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          subtitle: Text(
            '${song.displayArtist}${song.formatBadge.isNotEmpty ? " · ${song.formatBadge}" : ""}${durStr.isNotEmpty ? " · $durStr" : ""}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11.5),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          trailing: isPlaying
              ? IconButton(
                  icon: Icon(
                    _service.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: const Color(0xFF818CF8),
                    size: 24,
                  ),
                  onPressed: _service.togglePlayPause,
                )
              : IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.35), size: 18),
                  onPressed: () => _service.removeFromQueue(index),
                  tooltip: 'Remove from Queue',
                ),
          onTap: () => _service.playFromQueue(index),
        ),
      ),
    );
  }

  void _reorderQueue(MusicPlayerService s, int oldIdx, int newIdx) {
    s.reorderQueue(oldIdx, newIdx);
  }

  void _saveQueueAsPlaylist(MusicPlayerService s) {
    final ctrl = TextEditingController(text: 'Queue ${DateTime.now().month}/${DateTime.now().day}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Save Queue as Playlist', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Color(0xFF666680)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4E))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                final ids = s.queue.map((sq) => sq.id).toList();
                for (final id in ids) {
                  s.addToPlaylist(ctrl.text, id);
                }
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Saved ${ids.length} tracks to "${ctrl.text}"'),
                  backgroundColor: const Color(0xFF1A1A2E),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }
}
