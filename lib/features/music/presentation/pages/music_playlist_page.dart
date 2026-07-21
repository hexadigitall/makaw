import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/services/music_player_service.dart';

class MusicPlaylistPage extends StatefulWidget {
  final MusicPlayerService service;
  final String playlistName;

  const MusicPlaylistPage({super.key, required this.service, required this.playlistName});

  @override
  State<MusicPlaylistPage> createState() => _MusicPlaylistPageState();
}

class _MusicPlaylistPageState extends State<MusicPlaylistPage> {
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  MusicPlayerService get s => widget.service;
  String get pn => widget.playlistName;

  List<SongInfo> get _songs => s.getPlaylistSongs(pn);

  @override
  void initState() {
    super.initState();
    s.addListener(_onChange);
  }

  @override
  void dispose() {
    s.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() { if (mounted) setState(() {}); }

  String fmtMs(int ms) {
    final d = Duration(milliseconds: ms);
    if (d.inSeconds >= 3600) {
      return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void _exitSelectMode() {
    setState(() { _selectMode = false; _selectedIds.clear(); });
  }

  void _playAll() {
    final list = _songs;
    if (list.isNotEmpty) s.playSong(0, fromList: list);
  }

  void _shufflePlay() {
    final list = _songs;
    if (list.isEmpty) return;
    s.playShuffled(list);
  }

  void _deleteSelected() {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Remove selected songs?', style: TextStyle(color: Colors.white)),
        content: const Text('This removes them from the playlist.', style: TextStyle(color: Color(0xFF666680))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              s.removeSongsFromPlaylist(pn, ids);
              _exitSelectMode();
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _selectAction(String v) {
    final songs = _songs;
    final sel = songs.where((s) => _selectedIds.contains(s.id)).toList();
    if (v == 'select_all') {
      setState(() { _selectedIds.addAll(songs.map((s) => s.id)); });
    } else if (v == 'play_next') {
      for (final s in sel.reversed) widget.service.playNext(s);
      _exitSelectMode();
    } else if (v == 'add_queue') {
      for (final s in sel) widget.service.addToQueue(s);
      _exitSelectMode();
    } else if (v == 'add_playlist') {
      if (sel.isNotEmpty) _addToPlaylistSheet(sel.first.id);
      _exitSelectMode();
    } else if (v == 'share') {
      final paths = sel.map((s) => XFile(s.filePath)).toList();
      if (paths.isNotEmpty) Share.shareXFiles(paths);
      _exitSelectMode();
    } else if (v == 'delete') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Delete selected files?', style: TextStyle(color: Colors.white)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                for (final s in sel) {
                  try { File(s.filePath).deleteSync(); } catch (_) {}
                }
                s.scanAllSongs();
                _exitSelectMode();
                Navigator.pop(ctx);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
    } else if (v == 'properties') {
      _showProperties(sel);
    }
  }

  void _showProperties(List<SongInfo> songs) {
    if (songs.isEmpty) return;
    final song = songs.first;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(song.displayTitle, style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _propRow('Artist', song.displayArtist),
            _propRow('Album', song.displayAlbum),
            _propRow('Duration', fmtMs(song.duration)),
            _propRow('File', song.fileName),
            _propRow('Path', song.filePath),
            _propRow('Size', '${(song.size / 1024 / 1024).toStringAsFixed(1)} MB'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Color(0xFF818CF8)))),
        ],
      ),
    );
  }

  Widget _propRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text('$label:', style: const TextStyle(color: Color(0xFF666680), fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _addToPlaylistSheet(int songId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Add to Playlist', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          const Divider(color: Color(0xFF2A2A4E)),
          ...s.playlists.where((p) => p.name != pn).map((p) => ListTile(
            title: Text(p.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text('${p.songIds.length} songs', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
            onTap: () {
              s.addToPlaylist(p.name, songId);
              Navigator.pop(ctx);
            },
          )),
          ListTile(
            leading: const Icon(Icons.add, color: Color(0xFF818CF8)),
            title: const Text('New Playlist', style: TextStyle(color: Color(0xFF818CF8))),
            onTap: () {
              Navigator.pop(ctx);
              _newPlaylistDialog(songId);
            },
          ),
        ],
      ),
    );
  }

  void _newPlaylistDialog(int songId) {
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
              if (ctrl.text.isNotEmpty) { s.addToPlaylist(ctrl.text, songId); Navigator.pop(ctx); }
            },
            child: const Text('Create', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectBar() {
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: _exitSelectMode,
          ),
          Text('${_selectedIds.length} Selected', style: const TextStyle(color: Colors.white, fontSize: 14)),
          const Spacer(),
          if (_selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
              onPressed: _deleteSelected,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF818CF8), size: 20),
            onSelected: _selectAction,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'select_all', child: Text('Select All')),
              const PopupMenuItem(value: 'play_next', child: Text('Play Next')),
              const PopupMenuItem(value: 'add_queue', child: Text('Add to Queue')),
              const PopupMenuItem(value: 'add_playlist', child: Text('Add to Playlist')),
              const PopupMenuItem(value: 'share', child: Text('Share')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
              const PopupMenuItem(value: 'properties', child: Text('Properties')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF818CF8), size: 22),
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => MusicAddMusicPage(service: s, playlistName: pn)),
              );
              if (result == true && mounted) setState(() {});
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 22),
            onSelected: (v) {
              if (v == 'select') {
                setState(() { _selectMode = true; _selectedIds.clear(); });
              } else if (v == 'refresh') {
                if (_songs.isNotEmpty) s.playSong(0, fromList: _songs);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'select', child: Text('Select')),
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _songItem(SongInfo song, int index) {
    final isCurrent = s.currentSong?.id == song.id;
    final isSel = _selectedIds.contains(song.id);

    return GestureDetector(
      onLongPress: _selectMode ? null : () => setState(() { _selectMode = true; _selectedIds.add(song.id); }),
      child: Container(
        color: isSel ? const Color(0xFF2A2A4E) : (isCurrent ? const Color(0xFF1E1E3A) : Colors.transparent),
        child: ListTile(
          leading: _selectMode
              ? Checkbox(
                  value: isSel,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) { _selectedIds.add(song.id); }
                      else { _selectedIds.remove(song.id); if (_selectedIds.isEmpty) _selectMode = false; }
                    });
                  },
                  activeColor: const Color(0xFF818CF8),
                  checkColor: Colors.white,
                )
              : Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFF2A2A4E), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.music_note, color: Color(0xFF818CF8), size: 22),
                ),
          title: Text(song.displayTitle,
              style: TextStyle(color: isCurrent ? const Color(0xFF818CF8) : Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis),
          subtitle: Text('${song.displayArtist}  \u2022  ${fmtMs(song.duration)}',
              style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
          onTap: () {
            if (_selectMode) {
              setState(() {
                if (_selectedIds.contains(song.id)) { _selectedIds.remove(song.id); if (_selectedIds.isEmpty) _selectMode = false; }
                else { _selectedIds.add(song.id); }
              });
            } else {
              s.playSong(index, fromList: _songs);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = _songs;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Column(
          children: [
            if (_selectMode) _buildSelectBar(),
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pn,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('${songs.length} songs',
                    style: const TextStyle(color: Color(0xFF666680), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _actionBtn(Icons.play_arrow, 'Play', songs.isNotEmpty ? _playAll : null),
                      const SizedBox(width: 12),
                      _actionBtn(Icons.shuffle, 'Shuffle', songs.isNotEmpty ? _shufflePlay : null),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1A1A2E), height: 1),
            Expanded(
              child: songs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.playlist_play, color: Color(0xFF666680), size: 48),
                          const SizedBox(height: 12),
                          const Text('No songs in this playlist', style: TextStyle(color: Color(0xFF666680), fontSize: 14)),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () async {
                              final result = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(builder: (_) => MusicAddMusicPage(service: s, playlistName: pn)),
                              );
                              if (result == true && mounted) setState(() {});
                            },
                            icon: const Icon(Icons.add, size: 18, color: Color(0xFF818CF8)),
                            label: const Text('Add Music', style: TextStyle(color: Color(0xFF818CF8))),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: songs.length,
                      itemBuilder: (_, i) => _songItem(songs[i], i),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback? onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: const Color(0xFF818CF8)),
      label: Text(label, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 14)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        side: const BorderSide(color: Color(0xFF818CF8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class MusicAddMusicPage extends StatefulWidget {
  final MusicPlayerService service;
  final String playlistName;

  const MusicAddMusicPage({super.key, required this.service, required this.playlistName});

  @override
  State<MusicAddMusicPage> createState() => _MusicAddMusicPageState();
}

class _MusicAddMusicPageState extends State<MusicAddMusicPage> {
  final Set<int> _selectedIds = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  MusicPlayerService get s => widget.service;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SongInfo> get _allSongs {
    final songs = s.allSongs;
    if (_search.isEmpty) return songs;
    return songs.where((s) =>
      s.displayTitle.toLowerCase().contains(_search) ||
      s.displayArtist.toLowerCase().contains(_search)
    ).toList();
  }

  List<int> get _existingIds => s.getPlaylistSongIds(widget.playlistName);
  bool get _allSelected {
    final available = _allSongs.where((s) => !_existingIds.contains(s.id)).toList();
    return available.isNotEmpty && available.every((s) => _selectedIds.contains(s.id));
  }

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        final available = _allSongs.where((s) => !_existingIds.contains(s.id)).toList();
        _selectedIds.addAll(available.map((s) => s.id));
      }
    });
  }

  void _accept() {
    final ids = _selectedIds.where((id) => !_existingIds.contains(id)).toList();
    if (ids.isNotEmpty) {
      s.addSongsToPlaylist(widget.playlistName, ids);
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final songs = _allSongs;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 22),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                  Expanded(
                    child: Text('${_selectedIds.length} Selected',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search, color: Color(0xFF818CF8), size: 22),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1A2E),
                          content: TextField(
                            controller: _searchCtrl, autofocus: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Search songs...',
                              hintStyle: TextStyle(color: Color(0xFF666680)),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4E))),
                              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () { _searchCtrl.clear(); Navigator.pop(ctx); },
                              child: const Text('Clear', style: TextStyle(color: Color(0xFF666680))),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.check, color: Color(0xFF818CF8), size: 22),
                    onPressed: _selectedIds.isNotEmpty ? _accept : null,
                  ),
                ],
              ),
            ),
            if (_search.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text('Results for "$_search"',
                      style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
                    const Spacer(),
                    TextButton(
                      onPressed: () { _searchCtrl.clear(); },
                      child: const Text('Clear', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
                    ),
                  ],
                ),
              ),
            if (songs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text('${songs.length} songs',
                      style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _toggleSelectAll,
                      icon: Icon(
                        _allSelected ? Icons.deselect : Icons.select_all,
                        size: 18, color: const Color(0xFF818CF8),
                      ),
                      label: Text(_allSelected ? 'Deselect All' : 'Select All',
                        style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
                    ),
                  ],
                ),
              ),
            const Divider(color: Color(0xFF1A1A2E), height: 1),
            Expanded(
              child: songs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_search.isNotEmpty ? Icons.search_off : Icons.music_note,
                              color: const Color(0xFF666680), size: 48),
                          const SizedBox(height: 12),
                          Text(_search.isNotEmpty ? 'No songs match your search' : 'No songs found',
                              style: const TextStyle(color: Color(0xFF666680))),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: songs.length,
                      itemBuilder: (_, i) {
                        final song = songs[i];
                        final alreadyAdded = _existingIds.contains(song.id);
                        final isSel = _selectedIds.contains(song.id);

                        return Container(
                          color: isSel ? const Color(0xFF2A2A4E) : Colors.transparent,
                          child: ListTile(
                            leading: Checkbox(
                              value: isSel || alreadyAdded,
                              onChanged: alreadyAdded ? null : (v) {
                                setState(() {
                                  if (v == true) _selectedIds.add(song.id);
                                  else _selectedIds.remove(song.id);
                                });
                              },
                              activeColor: const Color(0xFF818CF8),
                              checkColor: Colors.white,
                            ),
                            title: Text(song.displayTitle,
                              style: TextStyle(
                                color: alreadyAdded ? const Color(0xFF666680) : Colors.white,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('${song.displayArtist}  \u2022  ${Duration(milliseconds: song.duration).inMinutes}:${(Duration(milliseconds: song.duration).inSeconds % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Color(0xFF666680), fontSize: 12),
                            ),
                            trailing: alreadyAdded
                                ? const Icon(Icons.check, color: Color(0xFF666680), size: 18)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
