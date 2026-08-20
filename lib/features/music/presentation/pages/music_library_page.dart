import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/services/audio_scanner.dart';
import '../../data/services/makaw_audio_handler.dart';
import '../../domain/entities/entities.dart';

class MakawMusicLibraryView extends StatefulWidget {
  final MakawAudioHandler audioHandler;
  final VoidCallback? onExpandPlayer;

  const MakawMusicLibraryView({
    super.key,
    required this.audioHandler,
    this.onExpandPlayer,
  });

  @override
  State<MakawMusicLibraryView> createState() => _MakawMusicLibraryViewState();
}

class _MakawMusicLibraryViewState extends State<MakawMusicLibraryView> {
  final MakawAudioScanner _scanner = MakawAudioScanner();
  List<SongInfo> _allSongs = [];
  List<SongInfo> _filteredSongs = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedTab = 'Songs';
  String _sortMode = 'name';

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final songs = await _scanner.scanRealSongs();
    if (mounted) {
      setState(() {
        _allSongs = songs;
        _filteredSongs = songs;
        _isLoading = false;
      });
    }
  }

  void _filterSearch(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredSongs = _allSongs;
      } else {
        final q = query.toLowerCase();
        _filteredSongs = _allSongs.where((s) {
          final title = s.displayTitle.toLowerCase();
          final artist = s.displayArtist.toLowerCase();
          final album = s.displayAlbum.toLowerCase();
          return title.contains(q) || artist.contains(q) || album.contains(q);
        }).toList();
      }
    });
  }

  void _playAll({bool shuffle = false}) {
    if (_filteredSongs.isEmpty) return;
    widget.audioHandler.loadQueue(_filteredSongs, initialIndex: 0, shuffle: shuffle);
  }

  Map<String, List<SongInfo>> get _byAlbum {
    final map = <String, List<SongInfo>>{};
    for (final s in _filteredSongs) {
      map.putIfAbsent(s.displayAlbum, () => []).add(s);
    }
    return map;
  }

  Map<String, List<SongInfo>> get _byArtist {
    final map = <String, List<SongInfo>>{};
    for (final s in _filteredSongs) {
      map.putIfAbsent(s.displayArtist, () => []).add(s);
    }
    return map;
  }

  Map<String, List<SongInfo>> get _byFolder {
    final map = <String, List<SongInfo>>{};
    for (final s in _filteredSongs) {
      final folder = s.filePath.substring(0, s.filePath.lastIndexOf(Platform.pathSeparator));
      final folderName = folder.split(Platform.pathSeparator).last;
      map.putIfAbsent(folderName, () => []).add(s);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)));
    }

    return Column(
      children: [
        _buildSearchBar(),
        _buildTabBar(),
        _buildSortChips(),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        onChanged: _filterSearch,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search tracks, artists, albums...',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                  onPressed: () {
                    _filterSearch('');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF1E293B),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = ['Songs', 'Albums', 'Artists', 'Folders'];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tabs.length,
        itemBuilder: (_, i) {
          final tab = tabs[i];
          final active = _selectedTab == tab;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(tab),
              selected: active,
              onSelected: (_) => setState(() => _selectedTab = tab),
              selectedColor: const Color(0xFF818CF8),
              backgroundColor: const Color(0xFF1E293B),
              labelStyle: TextStyle(
                color: active ? Colors.white : Colors.white54,
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide.none,
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            '${_filteredSongs.length} tracks',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          const Spacer(),
          if (_selectedTab == 'Songs') ...[
            IconButton(
              icon: const Icon(Icons.shuffle, color: Color(0xFF818CF8), size: 18),
              onPressed: () => _playAll(shuffle: true),
              tooltip: 'Shuffle All',
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.sort, color: Colors.white.withValues(alpha: 0.4), size: 18),
              onSelected: (mode) {
                setState(() => _sortMode = mode);
                _applySort();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'name', child: Text('Name A-Z')),
                const PopupMenuItem(value: 'name_desc', child: Text('Name Z-A')),
                const PopupMenuItem(value: 'date', child: Text('Date Added')),
                const PopupMenuItem(value: 'duration', child: Text('Duration')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _applySort() {
    setState(() {
      switch (_sortMode) {
        case 'name':
          _filteredSongs.sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
          break;
        case 'name_desc':
          _filteredSongs.sort((a, b) => b.displayTitle.toLowerCase().compareTo(a.displayTitle.toLowerCase()));
          break;
        case 'date':
          _filteredSongs.sort((a, b) => b.id.compareTo(a.id));
          break;
        case 'duration':
          _filteredSongs.sort((a, b) => b.duration.compareTo(a.duration));
          break;
      }
    });
  }

  Widget _buildContent() {
    if (_filteredSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off, color: Colors.white.withValues(alpha: 0.2), size: 48),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No matches found' : 'No songs found',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
            ),
          ],
        ),
      );
    }

    switch (_selectedTab) {
      case 'Albums':
        return _buildAlbumView();
      case 'Artists':
        return _buildArtistView();
      case 'Folders':
        return _buildFolderView();
      default:
        return _buildSongList();
    }
  }

  Widget _buildSongList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _filteredSongs.length,
      itemBuilder: (_, index) {
        final song = _filteredSongs[index];
        return _buildSongTile(song, index);
      },
    );
  }

  Widget _buildSongTile(SongInfo song, int index) {
    return ListTile(
      leading: _buildSongArtwork(song),
      title: Text(
        song.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        '${song.displayArtist} · ${_formatDuration(song.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.3), size: 18),
        onSelected: (action) => _handleTrackAction(action, song),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'play_next', child: Text('Play Next')),
          const PopupMenuItem(value: 'queue', child: Text('Add to Queue')),
          const PopupMenuItem(value: 'info', child: Text('Track Info')),
        ],
      ),
      onTap: () {
        widget.audioHandler.loadQueue(_filteredSongs, initialIndex: index);
        widget.onExpandPlayer?.call();
      },
    );
  }

  Widget _buildSongArtwork(SongInfo song) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        color: const Color(0xFF1E293B),
        child: File(song.filePath).existsSync()
            ? Image.file(
                File(song.filePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultIcon(),
              )
            : _defaultIcon(),
      ),
    );
  }

  Widget _defaultIcon() {
    return const Center(
      child: Icon(Icons.music_note, color: Colors.white38, size: 22),
    );
  }

  Widget _buildAlbumView() {
    final albums = _byAlbum;
    final keys = albums.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final album = keys[i];
        final songs = albums[album]!;
        return ExpansionTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              color: const Color(0xFF1E293B),
              child: const Icon(Icons.album, color: Colors.white38, size: 22),
            ),
          ),
          title: Text(album, style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(
            '${songs.length} songs',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          iconColor: Colors.white38,
          collapsedIconColor: Colors.white38,
          children: songs.map((s) => _buildSongTile(s, _filteredSongs.indexOf(s))).toList(),
        );
      },
    );
  }

  Widget _buildArtistView() {
    final artists = _byArtist;
    final keys = artists.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final artist = keys[i];
        final songs = artists[artist]!;
        return ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF1E293B),
            child: Text(
              artist.isNotEmpty ? artist[0].toUpperCase() : '?',
              style: const TextStyle(color: Color(0xFF818CF8), fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(artist, style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(
            '${songs.length} songs',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          iconColor: Colors.white38,
          collapsedIconColor: Colors.white38,
          children: songs.map((s) => _buildSongTile(s, _filteredSongs.indexOf(s))).toList(),
        );
      },
    );
  }

  Widget _buildFolderView() {
    final folders = _byFolder;
    final keys = folders.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final folder = keys[i];
        final songs = folders[folder]!;
        return ExpansionTile(
          leading: const Icon(Icons.folder, color: Color(0xFFFFB020), size: 32),
          title: Text(folder, style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(
            '${songs.length} songs',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          iconColor: Colors.white38,
          collapsedIconColor: Colors.white38,
          children: songs.map((s) => _buildSongTile(s, _filteredSongs.indexOf(s))).toList(),
        );
      },
    );
  }

  void _handleTrackAction(String action, SongInfo song) {
    switch (action) {
      case 'play_next':
        widget.audioHandler.playNext(song);
        break;
      case 'queue':
        widget.audioHandler.addToQueue(song);
        break;
      case 'info':
        _showTrackInfo(song);
        break;
    }
  }

  void _showTrackInfo(SongInfo song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(song.displayTitle,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _infoRow('Artist', song.displayArtist),
            _infoRow('Album', song.displayAlbum),
            _infoRow('Duration', _formatDuration(song.duration)),
            _infoRow('File', song.fileName),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
