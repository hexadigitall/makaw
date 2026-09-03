import 'package:flutter/material.dart';
import '../../../../core/storage/lyric_service.dart';

class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  List<_SongGroup> _groups = [];
  bool _isLoading = true;
  String _query = '';
  final _searchController = TextEditingController();
  Lyric? _selected;
  List<Lyric> _selectedLines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final q = _query.trim();
    final search = q.isNotEmpty ? await LyricService.search(q) : await LyricService.listSongs();
    final grouped = <String, List<Lyric>>{};
    for (final l in search) {
      grouped.putIfAbsent(l.songId, () => []);
      grouped[l.songId]!.add(l);
    }
    final groups = grouped.entries
        .map((e) => _SongGroup(e.key, e.value.first.songTitle, e.value.first.artist, e.value))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (mounted) setState(() {
      _groups = groups;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Search lyrics',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: Colors.white38, size: 22),
            prefixIconConstraints: BoxConstraints(minWidth: 40),
          ),
          onChanged: (v) {
            _query = v.trim();
            _load();
          },
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                _query = '';
                _load();
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF472B6)))
          : _selected != null
              ? _buildDetail()
              : _groups.isEmpty
                  ? _buildEmptyState()
                  : _buildList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lyrics_outlined, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            _query.isNotEmpty ? 'No results' : 'No saved lyrics',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text('Lyrics you save from the Music player appear here',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _groups.length,
      itemBuilder: (_, i) {
        final g = _groups[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF1E293B),
            child: const Icon(Icons.music_note, color: Color(0xFFF472B6)),
          ),
          title: Text(g.title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(g.artist ?? '', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () async {
            final lines = g.items.any((l) => l.startMs != null)
                ? await LyricService.linesForSong(g.songId)
                : g.items;
            setState(() {
              _selected = g.items.first;
              _selectedLines = lines;
            });
          },
        );
      },
    );
  }

  Widget _buildDetail() {
    final s = _selected!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => setState(() {
                  _selected = null;
                  _selectedLines = [];
                }),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.songTitle,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (s.artist != null)
                      Text(s.artist!,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171)),
                onPressed: () async {
                  await LyricService.deleteSong(s.songId);
                  setState(() {
                    _selected = null;
                    _selectedLines = [];
                  });
                  await _load();
                },
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF1E293B)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _selectedLines.isEmpty
                ? Text(s.text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.7))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _selectedLines.map((l) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _fmtTime(l.startMs ?? 0),
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(l.text,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                              ),
                            ],
                          ),
                        )).toList(),
                  ),
          ),
        ),
      ],
    );
  }

  String _fmtTime(int ms) {
    final s = (ms / 1000).floor();
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _SongGroup {
  final String songId;
  final String title;
  final String? artist;
  final List<Lyric> items;
  _SongGroup(this.songId, this.title, this.artist, this.items);
}
