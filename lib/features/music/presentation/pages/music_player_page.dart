import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:palette_generator/palette_generator.dart';
import '../../data/services/music_player_service.dart';
import '../../../../app/providers/service_providers.dart';
import 'music_playlist_page.dart';

class _LrcLine {
  final Duration time;
  final String text;
  const _LrcLine(this.time, this.text);
}

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
  List<_LrcLine> _lrcLines = [];
  bool _hasLrc = false;

  // Dynamic color palette from album art
  Color _dominantColor = const Color(0xFF0F0F1A);
  Color _accentColor = const Color(0xFF818CF8);
  bool _paletteLoading = false;
  int _prevSongId = -1;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
    if (_service.allSongs.isEmpty && !_service.isScanning) {
      _service.scanAllSongs();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) {
      setState(() {});
      if (_service.currentSong != null && _service.currentSong!.id != _prevSongId) {
        _updateDominantColor();
      }
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
      final file = File(song.filePath);
      if (!await file.exists()) return;
      final provider = FileImage(file);
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
    } catch (_) {}
    _paletteLoading = false;
  }

  // ─── Lyrics ────────────────────────────────────────────────────────────────
  List<_LrcLine> _parseLrc(String text) {
    final lines = <_LrcLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})[\.:](\d{2,3})\](.*)');
    for (final line in text.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final ms = int.parse(match.group(3)!.padRight(3, '0').substring(0, 3));
        final lyric = match.group(4)?.trim() ?? '';
        if (lyric.isNotEmpty) {
          lines.add(_LrcLine(Duration(milliseconds: min * 60000 + sec * 1000 + ms), lyric));
        }
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  Future<void> _fetchLyrics() async {
    final song = _service.currentSong;
    if (song == null) return;
    setState(() { _lyricsLoading = true; _lyricsText = ''; _lrcLines = []; _hasLrc = false; });

    // 1. Check for .lrc file next to audio
    final lrcFile = File(song.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc'));
    if (await lrcFile.exists()) {
      final raw = await lrcFile.readAsString();
      final parsed = _parseLrc(raw);
      if (parsed.isNotEmpty) {
        setState(() { _lrcLines = parsed; _hasLrc = true; _lyricsLoading = false; });
        return;
      }
    }

    final artist = Uri.encodeComponent(song.displayArtist.replaceAll('Unknown Artist', ''));
    final title = Uri.encodeComponent(song.displayTitle);

    // 2. Try lrclib.net (returns synced LRC)
    try {
      final res = await http.get(
        Uri.parse('https://lrclib.net/api/get?artist_name=$artist&track_name=$title'),
        headers: {'User-Agent': 'Makaw/1.0'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final synced = data['syncedLyrics'] as String?;
        final plain = data['plainLyrics'] as String?;
        if (synced != null && synced.isNotEmpty) {
          final parsed = _parseLrc(synced);
          if (parsed.isNotEmpty) {
            setState(() { _lrcLines = parsed; _hasLrc = true; _lyricsLoading = false; });
            return;
          }
        }
        if (plain != null && plain.isNotEmpty) {
          setState(() { _lyricsText = plain; _lyricsLoading = false; });
          return;
        }
      }
    } catch (_) {}

    // 3. Fallback to lyrics.ovh
    try {
      final res = await http.get(Uri.parse('https://api.lyrics.ovh/v1/$artist/$title'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final lyrics = data['lyrics'] as String?;
        if (lyrics != null && lyrics.isNotEmpty) {
          setState(() { _lyricsText = lyrics; _lyricsLoading = false; });
          return;
        }
      }
    } catch (_) {}

    setState(() { _lyricsText = 'No lyrics found'; _lyricsLoading = false; });
  }

  void _editLyricsDialog() {
    final ctrl = TextEditingController(text: _hasLrc
        ? _lrcLines.map((l) => '[${l.time.inMinutes}:${(l.time.inSeconds % 60).toString().padLeft(2, '0')}.${(l.time.inMilliseconds % 1000).toString().padLeft(3, '0')}]${l.text}').join('\n')
        : _lyricsText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Edit Lyrics', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: TextField(
            controller: ctrl,
            maxLines: null,
            expands: true,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Paste lyrics or LRC format here...',
              hintStyle: TextStyle(color: Color(0xFF666680)),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              final parsed = _parseLrc(text);
              if (parsed.isNotEmpty) {
                setState(() { _lrcLines = parsed; _hasLrc = true; _lyricsText = ''; });
              } else {
                setState(() { _lyricsText = text; _lrcLines = []; _hasLrc = false; });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  // ─── LRC-aware now-playing body ────────────────────────────────────────────
  Widget _buildLyricsView() {
    if (_lyricsLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)));
    }
    if (_hasLrc) {
      final pos = _service.position;
      int activeIdx = 0;
      for (int i = 0; i < _lrcLines.length; i++) {
        if (_lrcLines[i].time <= pos) activeIdx = i;
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lrcLines.length,
        itemBuilder: (_, i) {
          final isActive = i == activeIdx;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _lrcLines[i].text,
              style: TextStyle(
                color: isActive ? const Color(0xFF818CF8) : Colors.white54,
                fontSize: isActive ? 16 : 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          );
        },
      );
    }
    if (_lyricsText.isNotEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(_lyricsText, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6)),
      );
    }
    return const Center(child: Text('Tap "Lyrics" to fetch', style: TextStyle(color: Colors.white38)));
  }

  // ─── End lyrics ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }

  Widget _buildHeader() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 4, right: 8, bottom: 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.maybePop(context)),
              Expanded(
                child: Text('Makaw Music',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (isLandscape) SizedBox(
                width: 220,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextField(
                    controller: _searchCtrl,
                    readOnly: true,
                    onTap: () => setState(() => _isSearchPage = true),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search songs, playlists, albums...',
                      hintStyle: const TextStyle(color: Color(0xFF666680)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF666680), size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Color(0xFF666680), size: 18),
                              onPressed: () { _searchCtrl.clear(); setState(() {}); })
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFF818CF8)),
                onSelected: (v) {
                  if (v == 'scan') _service.scanAllSongs();
                  else if (v == 'settings') _openMusicSettings();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'scan', child: ListTile(title: Text('Refresh'), leading: Icon(Icons.refresh))),
                  const PopupMenuItem(value: 'settings', child: ListTile(title: Text('Settings'), leading: Icon(Icons.settings))),
                ],
              ),
            ],
          ),
          if (!isLandscape)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: TextField(
                controller: _searchCtrl,
                readOnly: true,
                onTap: () => setState(() => _isSearchPage = true),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search songs, playlists, albums...',
                  hintStyle: const TextStyle(color: Color(0xFF666680)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF666680), size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Color(0xFF666680), size: 18),
                          onPressed: () { _searchCtrl.clear(); setState(() {}); })
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                      hintText: 'Search songs...',
                      hintStyle: const TextStyle(color: Color(0xFF666680)),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? const Center(child: Text('Type to search', style: TextStyle(color: Color(0xFF666680))))
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
          TabBar(
            onTap: (i) => _service.setSelectedTab(['Songs', 'Playlists', 'Folders', 'Albums', 'Artists'][i]),
            indicatorColor: const Color(0xFF818CF8),
            labelColor: const Color(0xFF818CF8),
            unselectedLabelColor: const Color(0xFF666680),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Songs'), Tab(text: 'Playlists'), Tab(text: 'Folders'),
              Tab(text: 'Albums'), Tab(text: 'Artists'),
            ],
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note, color: Color(0xFF666680), size: 48),
            const SizedBox(height: 12),
            Text(_service.scanError.isNotEmpty ? _service.scanError : 'No songs found',
                style: const TextStyle(color: Color(0xFF666680))),
          ],
        ),
      );
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final listView = Expanded(child: ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: songs.length,
      itemBuilder: (_, i) => _songItem(songs[i], i, songs),
    ));

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: songs.isEmpty ? null : () => _service.playSong(0, fromList: songs),
                  icon: const Icon(Icons.play_arrow, size: 20, color: Colors.black),
                  label: const Text('Play', style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF818CF8),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: TextButton.icon(
                  onPressed: songs.isEmpty ? null : () {
                    _service.playShuffled(songs);
                  },
                  icon: Icon(Icons.shuffle, size: 18, color: const Color(0xFF818CF8)),
                  label: Text('Shuffle', style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13)),
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text('${songs.length} songs', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
              const Spacer(),
              _sortBtn(),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sort, color: Color(0xFF818CF8), size: 16),
          const SizedBox(width: 2),
          Text(label, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
        ],
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'name', child: Text('A-Z')),
        const PopupMenuItem(value: 'name_desc', child: Text('Z-A')),
        const PopupMenuItem(value: 'date', child: Text('Date Added')),
        const PopupMenuItem(value: 'duration', child: Text('Length')),
        const PopupMenuItem(value: 'size', child: Text('Size')),
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

  Widget _songItem(SongInfo song, int index, List<SongInfo>? list) {
    final isCurrent = _service.currentSong?.id == song.id;
    final isFav = _service.isFavorite(song.id);
    final isSel = _selectedIds.contains(song.id);

    return GestureDetector(
      onLongPress: () => setState(() { _selectMode = true; _selectedIds.add(song.id); }),
      child: Container(
        color: isSel ? const Color(0xFF2A2A4E) : (isCurrent ? const Color(0xFF1E1E3A) : Colors.transparent),
        child: ListTile(
          leading: _thumb(),
          title: Text(song.displayTitle,
              style: TextStyle(color: isCurrent ? const Color(0xFF818CF8) : Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis),
          subtitle: Text('${song.displayArtist}  \u2022  ${fmtMs(song.duration)}',
              style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
          trailing: isFav ? const Icon(Icons.favorite, color: Color(0xFF818CF8), size: 18) : _songMenu(song, list),
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
        ),
      ),
    );
  }

  Widget _thumb() {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: const Color(0xFF2A2A4E), borderRadius: BorderRadius.circular(6)),
      child: const Icon(Icons.music_note, color: Color(0xFF818CF8), size: 20),
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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text('${lists.length} playlists', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
              const Spacer(),
              TextButton.icon(
                onPressed: _newPlaylistDialog,
                icon: const Icon(Icons.add, size: 18, color: Color(0xFF818CF8)),
                label: const Text('New Playlist', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(children: [
            ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0xFF2A2A4E), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.favorite, color: Color(0xFF818CF8), size: 22),
              ),
              title: const Text('Favourites', style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text('${_service.favorites.length} songs', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
              onTap: () {
                final f = _service.favorites;
                if (f.isNotEmpty) _service.playSong(0, fromList: f);
              },
            ),
            ...lists.map((pl) {
              final s = _service.getPlaylistSongs(pl.name);
              return ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFF2A2A4E), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.playlist_play, color: Color(0xFF818CF8), size: 22),
                ),
                title: Text(pl.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text('${s.length} songs', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Color(0xFF666680), size: 18),
                  onSelected: (v) {
                    if (v == 'open') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => MusicPlaylistPage(
                        service: _service, playlistName: pl.name,
                      )));
                    } else if (v == 'play' && s.isNotEmpty) _service.playSong(0, fromList: s);
                    else if (v == 'rename') _renamePlaylistDialog(pl.name);
                    else if (v == 'export') _exportPlaylistM3u8(pl.name, s);
                    else if (v == 'delete') _service.deletePlaylist(pl.name);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'open', child: Text('Open')),
                    const PopupMenuItem(value: 'play', child: Text('Play')),
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'export', child: Text('Export .m3u8')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => MusicPlaylistPage(
                    service: _service, playlistName: pl.name,
                  )));
                },
              );
            }),
          ]),
        ),
      ],
    );
  }

  void _newPlaylistDialog() {
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
              if (ctrl.text.isNotEmpty) { _service.addToPlaylist(ctrl.text, -1); Navigator.pop(ctx); }
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
    switch (type) {
      case 'folders': map = _service.folders; icon = Icons.folder; break;
      case 'albums': map = _service.albums; icon = Icons.album; break;
      default: map = _service.artists; icon = Icons.person; break;
    }
    var keys = map.keys.toList();
    if (search.isNotEmpty) keys = keys.where((k) => k.toLowerCase().contains(search)).toList();
    keys.sort();

    if (keys.isEmpty) {
      return Center(child: Text(
        type == 'folders' ? 'No folders found' : type == 'albums' ? 'No albums found' : 'No artists found',
        style: const TextStyle(color: Color(0xFF666680))));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: keys.map((k) => ListTile(
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: const Color(0xFF2A2A4E), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Color(0xFF818CF8), size: 22),
        ),
        title: Text(k.split(Platform.pathSeparator).last, style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text('${map[k]!.length} songs', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF666680), size: 20),
        onTap: () => _openGroup(k, map[k]!),
      )).toList(),
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

    return GestureDetector(
      onTap: () => _service.setShowNowPlaying(true),
      child: Container(
        color: const Color(0xFF1A1A2E),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            _thumbSmall(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.displayTitle, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1),
                  Row(
                    children: [
                      Text(fmtDur(_service.position), style: const TextStyle(color: Color(0xFF666680), fontSize: 10)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: _service.duration > Duration.zero
                              ? (_service.position.inMilliseconds / _service.duration.inMilliseconds).clamp(0.0, 1.0) : 0,
                          backgroundColor: const Color(0xFF2A2A4E),
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF818CF8)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(fmtDur(_service.duration), style: const TextStyle(color: Color(0xFF666680), fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(_service.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: const Color(0xFF818CF8), size: 32),
              onPressed: () => _service.togglePlayPause(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbSmall() {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: const Color(0xFF2A2A4E), borderRadius: BorderRadius.circular(6)),
      child: const Icon(Icons.music_note, color: Color(0xFF818CF8), size: 18),
    );
  }

  // ---------- Footer ----------
  Widget _buildFooter() {
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          _navItem(Icons.library_music, 'My Music', true, null),
          _navItem(Icons.videocam, 'Videos', false, widget.onOpenVideos),
          _navItem(Icons.settings, 'Settings', false, widget.onOpenSettings),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool selected, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? const Color(0xFF818CF8) : const Color(0xFF666680), size: 22),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: selected ? const Color(0xFF818CF8) : const Color(0xFF666680), fontSize: 10)),
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
        // ── Header: down arrow + title ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
                onPressed: () => _service.setShowNowPlaying(false),
              ),
              const Spacer(),
              Text('Now Playing', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.queue_music, color: Colors.white70, size: 22),
                onPressed: _queueSheet,
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
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: _accentColor.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 4),
                  ],
                  color: _dominantColor.withValues(alpha: 0.6),
                ),
                child: _showLyrics
                    ? ClipRRect(borderRadius: BorderRadius.circular(20), child: _buildLyricsView())
                    : const Center(child: Icon(Icons.music_note, color: Color(0xFF818CF8), size: 80)),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── Song Info ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(song.displayTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis, maxLines: 2, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(song.displayArtist,
                  style: TextStyle(color: _accentColor, fontSize: 15),
                  overflow: TextOverflow.ellipsis, maxLines: 1, textAlign: TextAlign.center),
              if (song.displayAlbum.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(song.displayAlbum,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                    overflow: TextOverflow.ellipsis, maxLines: 1, textAlign: TextAlign.center),
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
                  trackHeight: 3,
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
                icon: Icon(Icons.shuffle,
                    color: _service.isShuffled ? _accentColor : Colors.white.withValues(alpha: 0.4), size: 22),
                onPressed: () => _service.toggleShuffle(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 32),
                onPressed: () => _service.previousSong(),
              ),
              GestureDetector(
                onTap: () => _service.togglePlayPause(),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _accentColor),
                  child: Icon(_service.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white, size: 38),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 32),
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
                        : const Center(child: Icon(Icons.music_note, color: Color(0xFF818CF8), size: 64)),
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
          if (_showLyrics && _lyricsText.isEmpty) _fetchLyrics();
        }),
        const SizedBox(width: 12),
        _actionChip(Icons.speed, '${_service.player?.speed ?? 1.0}x', _service.player?.speed != 1.0 && _service.player?.speed != null, () => _speedSheet()),
        const SizedBox(width: 12),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.6), size: 22),
          onSelected: (v) => _npMenu(v, song),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'add_playlist', child: ListTile(title: Text('Add to Playlist'), leading: Icon(Icons.playlist_add))),
            const PopupMenuItem(value: 'tag_editor', child: ListTile(title: Text('Edit Tags'), leading: Icon(Icons.edit))),
            const PopupMenuItem(value: 'edit_lyrics', child: ListTile(title: Text('Edit Lyrics'), leading: Icon(Icons.edit_note))),
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
              color: active ? _accentColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: active ? _accentColor : Colors.white.withValues(alpha: 0.5), size: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: active ? _accentColor : Colors.white.withValues(alpha: 0.4), fontSize: 10)),
        ],
      ),
    );
  }

  void _npMenu(String v, SongInfo song) {
    if (v == 'add_playlist') _addToPlaylistSheet(song.id);
    else if (v == 'tag_editor') _tagEditorDialog(song);
    else if (v == 'edit_lyrics') _editLyricsDialog();
    else if (v == 'rename') _renameDialog(song);
    else if (v == 'share') _toast('Share coming soon');
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
                onTap: () { Navigator.pop(context); _newPlaylistDialog(); },
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
      backgroundColor: const Color(0xFF0F0F1A),
      isScrollControlled: true,
      builder: (_) => _QueueSheetContent(service: _service),
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
    final cur = _service.player?.speed ?? 1.0;
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
                  onTap: () { _service.player?.setSpeed(s); Navigator.pop(context); },
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
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => DraggableScrollableSheet(
          initialChildSize: 0.6, maxChildSize: 0.85, minChildSize: 0.4,
          builder: (_, sc) => CustomScrollView(controller: sc, slivers: [
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text('Music Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
            SliverToBoxAdapter(child: _settingsTile(Icons.refresh, 'Scan music folder', () { _service.scanAllSongs(); Navigator.pop(ctx); })),
            SliverToBoxAdapter(child: _settingsTile(Icons.sort, 'Sort: ${_sortLabel(_service.sortMode)}', () => _showSortPicker(ctx, setDlg))),
            SliverToBoxAdapter(child: _settingsTile(Icons.tune, 'Audio buffer: ${_service.bufferMs}ms', () => _showBufferPicker(ctx, setDlg))),
            SliverToBoxAdapter(child: _settingsTile(Icons.info, 'About Makaw Music', () => _showAbout(ctx))),
            SliverToBoxAdapter(child: _settingsTile(Icons.notifications, 'Notif: ${_service.notificationStatus}', () => _showAbout(ctx))),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]),
        ),
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

class _QueueSheetContent extends StatefulWidget {
  final MusicPlayerService service;
  const _QueueSheetContent({required this.service});

  @override
  State<_QueueSheetContent> createState() => _QueueSheetContentState();
}

class _QueueSheetContentState extends State<_QueueSheetContent> {
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

  void _onChange() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final s = _service;
    final cur = s.currentSong;
    final upNext = s.currentIndex >= 0
        ? s.queue.sublist(s.currentIndex + 1)
        : <SongInfo>[];

    return DraggableScrollableSheet(
      initialChildSize: 0.7, maxChildSize: 0.92, minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ── Drag Handle ──
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
            ),

            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text('Up Next', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('${upNext.length} tracks', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
                  const Spacer(),
                  if (s.queue.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.white.withValues(alpha: 0.4), size: 20),
                      onPressed: () { s.clearQueue(); Navigator.pop(context); },
                      tooltip: 'Clear Queue',
                    ),
                  if (s.queue.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.save_outlined, color: Colors.white.withValues(alpha: 0.4), size: 20),
                      onPressed: () => _saveQueueAsPlaylist(s),
                      tooltip: 'Save as Playlist',
                    ),
                ],
              ),
            ),

            // ── Scrollable Content ──
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // ── NOW PLAYING Section ──
                  if (cur != null) ...[
                    _sectionHeader('NOW PLAYING'),
                    _queueItem(cur, s.currentIndex, isPlaying: true),
                  ],

                  // ── UP NEXT Section ──
                  if (upNext.isNotEmpty) ...[
                    _sectionHeader('UP NEXT'),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: upNext.length,
                      onReorder: (oldIdx, newIdx) => _reorderQueue(s, oldIdx + s.currentIndex + 1, newIdx + s.currentIndex + 1),
                      itemBuilder: (_, i) {
                        final realIdx = i + s.currentIndex + 1;
                        return _queueItem(upNext[i], realIdx, key: ValueKey(upNext[i].id));
                      },
                    ),
                  ],

                  // ── AUTO-PLAY Section ──
                  if (s.loopMode != LoopMode.off || s.isShuffled) ...[
                    _sectionHeader('AUTO-PLAY'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(s.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                              color: s.loopMode != LoopMode.off ? const Color(0xFF818CF8) : Colors.white.withValues(alpha: 0.3), size: 18),
                          const SizedBox(width: 10),
                          Text(
                            s.loopMode == LoopMode.one ? 'Repeat this track' :
                            s.loopMode == LoopMode.all ? 'Repeat all tracks' : 'No repeat',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                          ),
                          const Spacer(),
                          Text(
                            s.isShuffled ? 'Shuffled' : 'In order',
                            style: TextStyle(
                              color: s.isShuffled ? const Color(0xFF818CF8) : Colors.white.withValues(alpha: 0.3),
                              fontSize: 12, fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
    );
  }

  Widget _queueItem(SongInfo song, int index, {bool isPlaying = false, Key? key}) {
    return ReorderableDelayedDragStartListener(
      key: key ?? ValueKey(song.id),
      index: index,
      child: Container(
        color: isPlaying ? const Color(0xFF818CF8).withValues(alpha: 0.08) : Colors.transparent,
        child: ListTile(
          leading: isPlaying
              ? const Icon(Icons.equalizer, color: Color(0xFF818CF8), size: 20)
              : ReorderableDragStartListener(
                  index: index,
                  child: Icon(Icons.drag_handle, color: Colors.white.withValues(alpha: 0.2), size: 20),
                ),
          title: Text(song.displayTitle,
              style: TextStyle(
                color: isPlaying ? const Color(0xFF818CF8) : Colors.white,
                fontSize: 14,
                fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis, maxLines: 1),
          subtitle: Text(song.displayArtist,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              overflow: TextOverflow.ellipsis),
          trailing: isPlaying
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.3), size: 18),
                  onPressed: () => _service.removeFromQueue(index),
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
