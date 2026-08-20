import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../../data/services/makaw_audio_handler.dart';
import 'dart:io';

class MakawMiniPlayer extends StatelessWidget {
  final MakawAudioHandler audioHandler;
  final VoidCallback onExpand;

  const MakawMiniPlayer({
    super.key,
    required this.audioHandler,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: audioHandler.playbackState,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data;
            final isPlaying = state?.playing ?? false;
            final position = state?.position ?? Duration.zero;
            final duration = item.duration ?? Duration.zero;

            return GestureDetector(
              onTap: onExpand,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: duration.inMilliseconds > 0
                          ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0,
                      minHeight: 2.5,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF818CF8)),
                    ),
                    ListTile(
                      dense: true,
                      leading: _buildArtwork(item),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      subtitle: Text(
                        item.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous, color: Colors.white70, size: 20),
                            onPressed: audioHandler.skipToPrevious,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: const Color(0xFF818CF8),
                              size: 36,
                            ),
                            onPressed: isPlaying ? audioHandler.pause : audioHandler.play,
                            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next, color: Colors.white70, size: 20),
                            onPressed: audioHandler.skipToNext,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildArtwork(MediaItem item) {
    final filePath = item.extras?['filePath'] as String?;
    if (filePath != null && File(filePath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Image.file(
            File(filePath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallbackIcon(),
          ),
        ),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.music_note, color: Colors.white70, size: 20),
    );
  }
}
