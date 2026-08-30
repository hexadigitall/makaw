import 'package:flutter/material.dart';
import '../../../../core/storage/subtitle_service.dart';

class SubtitlesPage extends StatefulWidget {
  const SubtitlesPage({super.key});

  @override
  State<SubtitlesPage> createState() => _SubtitlesPageState();
}

class _SubtitlesPageState extends State<SubtitlesPage> {
  List<_MediaGroup> _groups = [];
  bool _isLoading = true;
  String _query = '';
  final _searchController = TextEditingController();
  String? _selectedMedia;
  List<SubtitleCue> _selectedCues = [];

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
    var cues = q.isNotEmpty ? await SubtitleService.search(q) : await _allMedia();
    final grouped = <String, List<SubtitleCue>>{};
    for (final c in cues) {
      grouped.putIfAbsent(c.mediaId, () => []);
      grouped[c.mediaId]!.add(c);
    }
    final groups = grouped.entries
        .map((e) => _MediaGroup(e.key, e.value.first.mediaTitle, e.value))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (mounted) setState(() {
      _groups = groups;
      _isLoading = false;
    });
  }

  Future<List<SubtitleCue>> _allMedia() async {
    // Gather distinct media via search on empty text is not ideal; instead
    // union cue sets by querying one representative per media_id.
    try {
      final rows = await SubtitleService.search('', limit: 10000);
      final mediaIds = <String>{};
      final result = <SubtitleCue>[];
      for (final c in rows) {
        if (mediaIds.add(c.mediaId)) result.add(c);
      }
      return result;
    } catch (_) {
      return const [];
    }
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
            hintText: 'Search subtitles',
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
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00897B)))
          : _selectedMedia != null
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
          const Icon(Icons.subtitles_outlined, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            _query.isNotEmpty ? 'No results' : 'No saved subtitles',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text('Subtitles saved from the video player appear here',
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
            child: const Icon(Icons.closed_caption, color: Color(0xFFF87171)),
          ),
          title: Text(g.title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text('${g.cues.length} cues', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () async {
            final cues = await SubtitleService.cuesForMedia(g.mediaId);
            setState(() {
              _selectedMedia = g.mediaId;
              _selectedCues = cues;
            });
          },
        );
      },
    );
  }

  Widget _buildDetail() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => setState(() {
                  _selectedMedia = null;
                  _selectedCues = [];
                }),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _groups.isEmpty ? '' : (_groups.firstWhere((g) => g.mediaId == _selectedMedia).title),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171)),
                onPressed: () async {
                  await SubtitleService.deleteMedia(_selectedMedia!);
                  setState(() {
                    _selectedMedia = null;
                    _selectedCues = [];
                  });
                  await _load();
                },
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF1E293B)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _selectedCues.length,
            itemBuilder: (_, i) {
              final c = _selectedCues[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_fmtTime(c.startMs)} → ${_fmtTime(c.endMs)}',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(c.text,
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                    ),
                  ],
                ),
              );
            },
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

class _MediaGroup {
  final String mediaId;
  final String title;
  final List<SubtitleCue> cues;
  _MediaGroup(this.mediaId, this.title, this.cues);
}
