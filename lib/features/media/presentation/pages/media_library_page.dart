import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../../core/widgets/adaptive_container.dart';
import '../../../music/data/services/music_player_service.dart';
import '../../data/services/video_player_service.dart';
import '../../data/services/image_viewer_service.dart';
import '../../data/services/media_thumbnail_service.dart';

enum MediaCategory { all, music, video, photos, needsAttention }

/// Unified Media Library Screen.
///
/// Implements PRD Section 4 & Milestone M3:
/// "Media Hub > Music + Video + Gallery + Sniffer + Lyrics + Subtitles -> One Library
/// One Library (Music | Video | Photos), one player system."
class MediaLibraryPage extends StatefulWidget {
  final MusicPlayerService musicService;
  final VideoPlayerService videoService;
  final ImageViewerService imageService;
  final void Function(SongInfo song, List<SongInfo> queue) onPlaySong;
  final void Function(VideoFileInfo video) onPlayVideo;
  final void Function(ImageFileInfo image) onOpenImage;
  final VoidCallback onHome;

  const MediaLibraryPage({
    super.key,
    required this.musicService,
    required this.videoService,
    required this.imageService,
    required this.onPlaySong,
    required this.onPlayVideo,
    required this.onOpenImage,
    required this.onHome,
  });

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  MediaCategory _selectedCategory = MediaCategory.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const _bg = Color(0xFF0F172A);
  static const _surface = Color(0xFF1E293B);
  static const _surfaceHigh = Color(0xFF334155);
  static const _accent = Color(0xFFF87171); // Media Red / Coral

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SongInfo> get _filteredSongs {
    final all = widget.musicService.allSongs;
    return all.where((s) {
      if (_selectedCategory == MediaCategory.needsAttention) {
        final missingArtist = s.artist.isEmpty || s.artist.toLowerCase() == 'unknown';
        final missingTitle = s.title.isEmpty || s.title.toLowerCase() == 'unknown';
        return missingArtist || missingTitle;
      }
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q);
    }).toList();
  }

  List<VideoFileInfo> get _filteredVideos {
    if (_selectedCategory == MediaCategory.needsAttention) return const [];
    final all = widget.videoService.allVideos;
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all.where((v) => v.fileName.toLowerCase().contains(q)).toList();
  }

  List<ImageFileInfo> get _filteredImages {
    if (_selectedCategory == MediaCategory.needsAttention) return const [];
    final all = widget.imageService.allImages;
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all.where((img) => img.fileName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1120),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: widget.onHome,
          tooltip: 'Back',
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.video_collection_outlined, color: _accent, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              'Media Library',
              style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: AdaptiveContainer(
          child: Column(
            children: [
              _buildTopControls(),
              Expanded(child: _buildContent(isDesktop)),
              // Reserve bottom clearance so the mini-player never covers content
              const SizedBox(height: 72),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: const Color(0xFF0B1120),
      child: Column(
        children: [
          // Search input
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Search songs, videos, or photos...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Category pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryPill('All Media', MediaCategory.all, Icons.dashboard_outlined),
                const SizedBox(width: 8),
                _buildCategoryPill('Music', MediaCategory.music, Icons.music_note_rounded),
                const SizedBox(width: 8),
                _buildCategoryPill('Videos', MediaCategory.video, Icons.play_circle_outline_rounded),
                const SizedBox(width: 8),
                _buildCategoryPill('Photos', MediaCategory.photos, Icons.photo_library_outlined),
                const SizedBox(width: 8),
                _buildCategoryPill('Needs Attention', MediaCategory.needsAttention, Icons.flag_outlined),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPill(String label, MediaCategory category, IconData icon) {
    final isSelected = _selectedCategory == category;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = category),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _accent : _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _accent : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDesktop) {
    switch (_selectedCategory) {
      case MediaCategory.all:
        return _buildAllUnified(isDesktop);
      case MediaCategory.music:
        return _buildMusicList();
      case MediaCategory.video:
        return _buildVideoGrid(isDesktop);
      case MediaCategory.photos:
        return _buildPhotoGrid(isDesktop);
      case MediaCategory.needsAttention:
        return _buildNeedsAttentionList();
    }
  }

  Widget _buildAllUnified(bool isDesktop) {
    final songs = _filteredSongs;
    final videos = _filteredVideos;
    final images = _filteredImages;

    if (songs.isEmpty && videos.isEmpty && images.isEmpty) {
      return _buildEmptyState('No media found', 'Scan your device or download media to get started.');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (videos.isNotEmpty) ...[
          _buildSectionHeader('Videos (${videos.length})', () => setState(() => _selectedCategory = MediaCategory.video)),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: videos.length.clamp(0, 8),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) => _buildVideoCard(videos[i], 160),
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (songs.isNotEmpty) ...[
          _buildSectionHeader('Music (${songs.length})', () => setState(() => _selectedCategory = MediaCategory.music)),
          const SizedBox(height: 8),
          ...songs.take(6).map((s) => _buildSongTile(s, songs)),
          const SizedBox(height: 24),
        ],
        if (images.isNotEmpty) ...[
          _buildSectionHeader('Photos (${images.length})', () => setState(() => _selectedCategory = MediaCategory.photos)),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length.clamp(0, 10),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) => _buildPhotoCard(images[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback onSeeAll) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
        ),
        TextButton(
          onPressed: onSeeAll,
          child: const Text('See all', style: TextStyle(color: _accent, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildMusicList() {
    final songs = _filteredSongs;
    if (songs.isEmpty) {
      return _buildEmptyState('No songs found', 'Add music to your device library to listen.');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: songs.length,
      itemBuilder: (ctx, i) => _buildSongTile(songs[i], songs),
    );
  }

  Widget _buildSongTile(SongInfo song, List<SongInfo> queue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: MediaArtworkWidget(
          filePath: song.filePath,
          isVideo: false,
          width: 44,
          height: 44,
          borderRadius: BorderRadius.circular(8),
        ),
        title: Text(
          song.title.isNotEmpty ? song.title : 'Unknown Title',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          song.artist.isNotEmpty ? song.artist : 'Unknown Artist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.play_arrow_rounded, color: _accent, size: 26),
          onPressed: () => widget.onPlaySong(song, queue),
          tooltip: 'Play',
        ),
        onTap: () => widget.onPlaySong(song, queue),
      ),
    );
  }

  Widget _buildVideoGrid(bool isDesktop) {
    final videos = _filteredVideos;
    if (videos.isEmpty) {
      return _buildEmptyState('No videos found', 'No video files detected in storage.');
    }
    final cols = isDesktop ? 4 : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
      ),
      itemCount: videos.length,
      itemBuilder: (ctx, i) => _buildVideoCard(videos[i], null),
    );
  }

  Widget _buildVideoCard(VideoFileInfo video, double? width) {
    final progress = widget.videoService.resumeProgress(video.filePath);
    return InkWell(
      onTap: () => widget.onPlayVideo(video),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaArtworkWidget(
                    filePath: video.filePath,
                    isVideo: true,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                  ),
                  if (progress > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        color: _accent,
                        backgroundColor: Colors.black26,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                video.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoGrid(bool isDesktop) {
    final images = _filteredImages;
    if (images.isEmpty) {
      return _buildEmptyState('No photos found', 'No photo files detected in storage.');
    }
    final cols = isDesktop ? 6 : 3;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: images.length,
      itemBuilder: (ctx, i) => _buildPhotoCard(images[i]),
    );
  }

  Widget _buildPhotoCard(ImageFileInfo image) {
    return InkWell(
      onTap: () => widget.onOpenImage(image),
      borderRadius: BorderRadius.circular(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 100,
          height: 100,
          color: _surfaceHigh,
          child: Image(
            image: ResizeImage(
              FileImage(File(image.filePath)),
              width: 300,
              height: 300,
            ),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.image_rounded, color: Colors.white24, size: 32),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNeedsAttentionList() {
    final songs = _filteredSongs;
    if (songs.isEmpty) {
      return _buildEmptyState(
        'Library in great shape!',
        'No tracks with missing artist or title metadata found.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These tracks are missing proper artist or album metadata.',
                  style: TextStyle(color: Colors.amber, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...songs.map((s) => _buildSongTile(s, songs)),
      ],
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.perm_media_outlined, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
