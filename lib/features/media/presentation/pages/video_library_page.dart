import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/services/cross_platform_video_scanner.dart';
import '../../data/services/video_db_service.dart';
import 'video_player_page.dart';

class MakawVideoLibraryPage extends StatefulWidget {
  const MakawVideoLibraryPage({super.key});

  @override
  State<MakawVideoLibraryPage> createState() => _MakawVideoLibraryPageState();
}

class _MakawVideoLibraryPageState extends State<MakawVideoLibraryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<VideoItem> _allVideos = [];
  List<VideoItem> _filteredVideos = [];
  List<VideoPlaybackRecord> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshLibrary();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshLibrary() async {
    setState(() => _isLoading = true);
    final videos = await CrossPlatformVideoScanner.scanVideos();
    final history = await MakawVideoDbService.getRecentHistory();
    setState(() {
      _allVideos = videos;
      _filteredVideos = videos;
      _history = history;
      _isLoading = false;
    });
  }

  void _filterSearch(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredVideos = _allVideos.where((v) => v.title.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _deleteVideo(VideoItem video) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Delete Video?', style: TextStyle(color: Colors.white)),
        content: Text('Permanently delete "${video.title}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final file = File(video.path);
      if (await file.exists()) { await file.delete(); _refreshLibrary(); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Video & Media', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(text: 'All Videos'),
            Tab(text: 'Folders'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabController, children: [
              _buildAllVideosTab(),
              _buildFoldersTab(),
              _buildHistoryTab(),
            ]),
    );
  }

  Widget _buildAllVideosTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          onChanged: _filterSearch,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Search ${_allVideos.length} videos...',
            prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(child: _filteredVideos.isEmpty
          ? Center(child: Text('No videos found', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))))
          : ListView.builder(
              itemCount: _filteredVideos.length,
              itemBuilder: (context, index) {
                final video = _filteredVideos[index];
                return ListTile(
                  leading: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(6)),
                    child: Icon(Icons.movie, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: Text(video.title, maxLines: 1, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                  subtitle: Text('${video.folderName} • ${video.sizeFormatted}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontSize: 12)),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                    onPressed: () => _deleteVideo(video),
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => MakawVideoPlayerScreen(videoPath: video.path, videoTitle: video.title),
                  )).then((_) => _refreshLibrary()),
                );
              },
            )),
    ]);
  }

  Widget _buildFoldersTab() {
    final Map<String, List<VideoItem>> folders = {};
    for (var v in _allVideos) {
      folders.putIfAbsent(v.folderName, () => []).add(v);
    }
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: folders.entries.map((entry) => Card(
        color: cs.surface,
        child: ExpansionTile(
          leading: Icon(Icons.folder, color: Colors.amberAccent),
          title: Text(entry.key, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
          subtitle: Text('${entry.value.length} videos', style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
          children: entry.value.map((vid) => ListTile(
            leading: Icon(Icons.play_arrow, size: 16, color: cs.onSurface.withOpacity(0.5)),
            title: Text(vid.title, maxLines: 1, style: TextStyle(color: cs.onSurface, fontSize: 13)),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => MakawVideoPlayerScreen(videoPath: vid.path, videoTitle: vid.title),
            )).then((_) => _refreshLibrary()),
          )).toList(),
        ),
      )).toList(),
    );
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return Center(child: Text('No watch history yet.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))));
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final record = _history[index];
        return ListTile(
          leading: Icon(Icons.history, color: cs.primary),
          title: Text(record.title, maxLines: 1, style: TextStyle(color: cs.onSurface)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              LinearProgressIndicator(value: record.progress, color: cs.primary, backgroundColor: cs.surfaceContainerHighest),
              const SizedBox(height: 4),
              Text(record.isCompleted ? 'Completed' : '${(record.progress * 100).toInt()}% watched',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 11)),
            ],
          ),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => MakawVideoPlayerScreen(videoPath: record.path, videoTitle: record.title),
          )).then((_) => _refreshLibrary()),
        );
      },
    );
  }
}
