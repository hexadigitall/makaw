import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers/service_providers.dart';
import '../../domain/activity_entry.dart';

/// Embedded live control for a media activity entry.
///
/// For [ActivityKind.mediaMusic], binds to the global [MusicPlayerService] and
/// renders live play/pause + seek when this entry's track is the current one.
/// For videos (whose live state lives in the player page), we render a compact
/// "open" affordance instead.
class ActivityMediaControl extends ConsumerWidget {
  final ActivityEntry entry;

  const ActivityMediaControl({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(musicPlayerServiceProvider);
    if (music != null && entry.kind == ActivityKind.media && entry.subtype == ActivityKind.mediaMusic) {
      final currentSongId = music.currentSong?.id;
      final refId = entry.payload['ref']?.toString();
      if (currentSongId != null && refId == currentSongId.toString()) {
        return _LiveMusicControl(music: music);
      }
    }
    return const Icon(Icons.play_circle_outline, color: Color(0xFF94A3B8), size: 22);
  }
}

class _LiveMusicControl extends StatelessWidget {
  final dynamic music;
  const _LiveMusicControl({required this.music});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => music.togglePlayPause(),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF334155)),
            child: Icon(
              music.isPlaying ? Icons.pause : Icons.play_arrow,
              color: const Color(0xFFF472B6),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.skip_next, color: Color(0xFF94A3B8), size: 18),
          onPressed: () => music.nextSong(),
        ),
      ],
    );
  }
}
