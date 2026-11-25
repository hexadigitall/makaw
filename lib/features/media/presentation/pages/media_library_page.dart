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
  final VoidCallback? onOpenMusicPlayer;
  final VoidCallback? onOpenVideoPlayer;

  const MediaLibraryPage({
    super.key,
    required this.musicService,
    required this.videoService,
    required this.imageService,
    required this.onPlaySong,
    required this.onPlayVideo,
    required this.onOpenImage,
    required this.onHome,
    this.onOpenMusicPlayer,
    this.onOpenVideoPlayer,
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
  void initState() {
    super.initState();
    widget.musicService.addListener(_onServiceChanged);
    widget.videoService.addListener(_onServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.musicService.scanAllSongs(force: false);
      widget.videoService.scanAllVideos(force: false);
    });
  }

  @override
  void dispose() {
    widget.musicService.removeListener(_onServiceChanged);
    widget.videoService.removeListener(_onServiceChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
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
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_display_rounded, color: Color(0xFF38BDF8)),
            tooltip: 'Open Video Tool',
            onPressed: widget.onOpenVideoPlayer,
          ),
          IconButton(
            icon: const Icon(Icons.library_music_rounded, color: Color(0xFF818CF8)),
            tooltip: 'Open Music Tool',
            onPressed: widget.onOpenMusicPlayer,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: AdaptiveContainer(
          child: Column(
            children: [
              _buildTopControls(),
              Expanded(child: _buildContent(isDesktop)),
              if (widget.musicService.currentSong != null ||
                  widget.videoService.activeVideoPath != null ||
                  widget.videoService.lastInProgress != null)
                _buildMiniPlayer()
              else
                const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPlayer() {
    final song = widget.musicService.currentSong;
    if (song != null) {
      final progress = widget.musicService.duration.inMilliseconds > 0
          ? (widget.musicService.position.inMilliseconds / widget.musicService.duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
      return Container(
        color: const Color(0xFF1E293B),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF334155),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00A7C2)),
              minHeight: 2,
            ),
            InkWell(
              onTap: () {
                if (widget.onOpenMusicPlayer != null) {
                  widget.onOpenMusicPlayer!();
                } else {
                  widget.onPlaySong(song, widget.musicService.queue.isNotEmpty ? widget.musicService.queue : [song]);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    MediaArtworkWidget(
                      filePath: song.filePath,
                      isVideo: false,
                      width: 44,
                      height: 44,
                      borderRadius: BorderRadius.circular(8),
                      fallbackColor: const Color(0xFF334155),
                      iconColor: const Color(0xFF00A7C2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.displayArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70, size: 24),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      onPressed: () => widget.musicService.previousSong(),
                    ),
                    IconButton(
                      icon: Icon(
                        widget.musicService.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                        color: const Color(0xFF00A7C2),
                        size: 38,
                      ),
                      constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                      padding: EdgeInsets.zero,
                      onPressed: () => widget.musicService.togglePlayPause(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 24),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      onPressed: () => widget.musicService.nextSong(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final activeVideo = widget.videoService.activeVideoPath ?? widget.videoService.lastInProgress;
    if (activeVideo != null && activeVideo.isNotEmpty) {
      final title = activeVideo.split('\\').last.split('/').last;
      final progress = widget.videoService.resumeProgress(activeVideo);
      final isPlaying = widget.videoService.isVideoPlaying;

      return Container(
        color: const Color(0xFF1E293B),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF334155),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF818CF8)),
              minHeight: 2,
            ),
            InkWell(
              onTap: () {
                final video = widget.videoService.allVideos.firstWhere(
                  (v) => v.filePath == activeVideo,
                  orElse: () => VideoFileInfo(
                    id: 0,
                    filePath: activeVideo,
                    fileName: title,
                    folder: '',
                    fileSize: 0,
                  ),
                );
                widget.onPlayVideo(video);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    MediaArtworkWidget(
                      filePath: activeVideo,
                      isVideo: true,
                      width: 44,
                      height: 44,
                      borderRadius: BorderRadius.circular(8),
                      fallbackColor: const Color(0xFF334155),
                      iconColor: const Color(0xFF818CF8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPlaying ? 'Playing video' : 'Paused',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                        color: const Color(0xFF818CF8),
                        size: 38,
                      ),
                      constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                      padding: EdgeInsets.zero,
                      onPressed: () => widget.videoService.toggleActiveVideoPlayPause(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
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
    Widget content;
    switch (_selectedCategory) {
      case MediaCategory.all:
        content = _buildAllUnified(isDesktop);
        break;
      case MediaCategory.music:
        content = _buildMusicList();
        break;
      case MediaCategory.video:
        content = _buildVideoGrid(isDesktop);
        break;
      case MediaCategory.photos:
        content = _buildPhotoGrid(isDesktop);
        break;
      case MediaCategory.needsAttention:
        content = _buildNeedsAttentionList();
        break;
    }
    return RefreshIndicator(
      color: _accent,
      backgroundColor: _surface,
      onRefresh: () async {
        await Future.wait([
          widget.musicService.scanAllSongs(force: true),
          widget.videoService.scanAllVideos(force: true),
          widget.imageService.scanAllImages(),
        ]);
      },
      child: content,
    );
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
          _buildSectionHeader(
            'Videos (${videos.length})',
            widget.onOpenVideoPlayer ?? () => setState(() => _selectedCategory = MediaCategory.video),
            actionLabel: 'Video Tool',
            actionIcon: Icons.smart_display_rounded,
          ),
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
          _buildSectionHeader(
            'Music (${songs.length})',
            widget.onOpenMusicPlayer ?? () => setState(() => _selectedCategory = MediaCategory.music),
            actionLabel: 'Music Tool',
            actionIcon: Icons.library_music_rounded,
          ),
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

  Widget _buildSectionHeader(
    String title,
    VoidCallback onSeeAll, {
    String actionLabel = 'See all',
    IconData? actionIcon,
  }) {
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
        TextButton.icon(
          onPressed: onSeeAll,
          icon: Icon(
            actionIcon ?? (actionLabel == 'See all' ? Icons.chevron_right_rounded : Icons.open_in_new_rounded),
            size: 16,
            color: _accent,
          ),
          label: Text(actionLabel, style: const TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildMusicList() {
    final songs = _filteredSongs;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (widget.onOpenMusicPlayer != null)
          InkWell(
            onTap: widget.onOpenMusicPlayer,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF818CF8).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.library_music_rounded, color: Color(0xFF818CF8), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Open Makaw Music Tool',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Playlists \u2022 Albums \u2022 Folders \u2022 Artists \u2022 Queue',
                          style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF818CF8), size: 16),
                ],
              ),
            ),
          ),
        if (songs.isEmpty)
          _buildEmptyState('No songs found', 'Add music to your device library to listen.')
        else
          ...songs.map((s) => _buildSongTile(s, songs)),
      ],
    );
  }

  bool _isNewMedia(String filePath) {
    try {
      final f = File(filePath);
      if (!f.existsSync()) return false;
      final modified = f.statSync().modified;
      if (DateTime.now().difference(modified).inHours < 72) return true;
      final p = filePath.toLowerCase();
      if (p.contains('download') || p.contains('downloads')) {
        return DateTime.now().difference(modified).inDays < 7;
      }
    } catch (_) {}
    return false;
  }

  Widget _buildSongTile(SongInfo song, List<SongInfo> queue) {
    final isCurrent = widget.musicService.currentSong?.id == song.id;
    final isPlaying = isCurrent && widget.musicService.isPlaying;
    final isNew = _isNewMedia(song.filePath);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isCurrent ? _accent.withValues(alpha: 0.12) : _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent ? _accent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.04),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            MediaArtworkWidget(
              filePath: song.filePath,
              isVideo: false,
              width: 44,
              height: 44,
              borderRadius: BorderRadius.circular(8),
            ),
            if (isCurrent)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isPlaying ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                  color: _accent,
                  size: 24,
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                song.title.isNotEmpty ? song.title : 'Unknown Title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrent ? _accent : Colors.white,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            if (song.formatBadge.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: song.isLossless
                      ? const Color(0xFF06B6D4).withValues(alpha: 0.18)
                      : (widget.musicService.hasMultipleFormats(song)
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.22)
                          : const Color(0xFF6366F1).withValues(alpha: 0.14)),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: song.isLossless
                        ? const Color(0xFF06B6D4)
                        : (widget.musicService.hasMultipleFormats(song)
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
                        : (widget.musicService.hasMultipleFormats(song)
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF818CF8)),
                    fontSize: 9.5,
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
                child: const Text('NEW', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          song.artist.isNotEmpty ? song.artist : 'Unknown Artist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: isCurrent ? _accent.withValues(alpha: 0.8) : Colors.white54, fontSize: 12),
        ),
        trailing: IconButton(
          icon: Icon(
            isPlaying ? Icons.pause_circle_filled_rounded : (isCurrent ? Icons.play_circle_fill_rounded : Icons.play_arrow_rounded),
            color: _accent,
            size: 26,
          ),
          onPressed: () => widget.onPlaySong(song, queue),
          tooltip: isPlaying ? 'Pause' : 'Play',
        ),
        onTap: () => widget.onPlaySong(song, queue),
      ),
    );
  }

  Widget _buildVideoGrid(bool isDesktop) {
    final videos = _filteredVideos;
    final cols = isDesktop ? 4 : 2;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.onOpenVideoPlayer != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: widget.onOpenVideoPlayer,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.smart_display_rounded, color: Color(0xFF38BDF8), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Open Makaw Video Tool',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Playlists \u2022 Folders \u2022 Resume Watching \u2022 Video Browser',
                            style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF38BDF8), size: 16),
                  ],
                ),
              ),
            ),
          ),
        if (videos.isEmpty)
          _buildEmptyState('No videos found', 'No video files detected in storage.')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
            ),
            itemCount: videos.length,
            itemBuilder: (ctx, i) => _buildVideoCard(videos[i], null),
          ),
      ],
    );
  }

  Widget _buildVideoCard(VideoFileInfo video, double? width) {
    final progress = widget.videoService.resumeProgress(video.filePath);
    final isCurrent = widget.videoService.activeVideoPath == video.filePath;
    final isPlaying = isCurrent && widget.videoService.isVideoPlaying;
    final isNew = widget.videoService.isNewFile(video.filePath) || _isNewMedia(video.filePath);

    return InkWell(
      onTap: () => widget.onPlayVideo(video),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: isCurrent ? _accent.withValues(alpha: 0.12) : _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCurrent ? _accent.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.06),
            width: isCurrent ? 2 : 1,
          ),
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
                  if (isCurrent)
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isPlaying ? Icons.equalizer_rounded : Icons.pause_rounded, color: Colors.black, size: 14),
                            const SizedBox(width: 4),
                            Text(isPlaying ? 'PLAYING' : 'PAUSED', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  if (isNew)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2)],
                        ),
                        child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ),
                    ),
                  if (progress > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3.5,
                        color: _accent,
                        backgroundColor: Colors.black38,
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
                style: TextStyle(color: isCurrent ? _accent : Colors.white, fontSize: 12, fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500),
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
