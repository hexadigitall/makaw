import 'package:flutter/material.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/activity_entry.dart';

/// Maps an [ActivityKind] to a representative Material icon + accent color,
/// shared across the hub recents and the Makaw Home feed so entries look
/// consistent everywhere.
class ActivityVisual {
  final IconData icon;
  final Color color;
  const ActivityVisual(this.icon, this.color);

  static ActivityVisual forKind(ActivityEntry e) {
    switch (e.kind) {
      case ActivityKind.browser:
        return const ActivityVisual(Icons.language_rounded, Color(0xFF00A7C2));
      case ActivityKind.document:
        return const ActivityVisual(Icons.insert_drive_file, Color(0xFFFBBF24));
      case ActivityKind.terminal:
        return const ActivityVisual(Icons.terminal_rounded, Color(0xFF22D3EE));
      case ActivityKind.project:
        return const ActivityVisual(Icons.code_rounded, Color(0xFF818CF8));
      case ActivityKind.file:
        return const ActivityVisual(Icons.folder_outlined, Color(0xFF34D399));
      case ActivityKind.download:
        return const ActivityVisual(Icons.download_rounded, Color(0xFFFB923C));
      case ActivityKind.media:
        return e.subtype == ActivityKind.mediaVideo
            ? const ActivityVisual(Icons.video_library_outlined, Color(0xFFF87171))
            : const ActivityVisual(Icons.music_note_rounded, Color(0xFFF472B6));
    }
    return const ActivityVisual(Icons.history, Color(0xFF94A3B8));
  }
}

/// A single resume-worthy activity card: icon, title/subtitle, an optional
/// embedded control widget (e.g. live music/video controls), a per-item close
/// (X) and a tap-to-resume behavior.
class ActivityTile extends StatelessWidget {
  final ActivityEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final Widget? control;
  final bool showSubtitle;

  const ActivityTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.onRemove,
    this.control,
    this.showSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final visual = ActivityVisual.forKind(entry);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: visual.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(visual.icon, color: visual.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    if (showSubtitle && entry.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              if (control != null) ...[
                const SizedBox(width: 8),
                control!,
              ],
              if (onRemove != null)
                TappableIcon(
                  icon: Icons.close,
                  iconSize: 16,
                  color: const Color(0xFF94A3B8),
                  onTap: onRemove,
                  tooltip: 'Remove',
                  target: 34,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
