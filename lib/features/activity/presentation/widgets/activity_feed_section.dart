import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/activity_service.dart';
import '../../domain/activity_entry.dart';
import 'activity_tile.dart';
import 'activity_media_control.dart';

/// A resumable activity feed section used by the Makaw Home portal and reused
/// across hubs. Reads the unified [ActivityService], reacts to writes, and
/// renders one-tap-resume [ActivityTile]s with per-item remove and a clear-all.
class ActivityFeedSection extends ConsumerStatefulWidget {
  final String title;
  final void Function(ActivityEntry entry) onResume;
  final List<String>? kinds;
  final int limit;

  const ActivityFeedSection({
    super.key,
    required this.onResume,
    this.title = 'Recent Activity',
    this.kinds,
    this.limit = 20,
  });

  @override
  ConsumerState<ActivityFeedSection> createState() => _ActivityFeedSectionState();
}

class _ActivityFeedSectionState extends ConsumerState<ActivityFeedSection> {
  List<ActivityEntry>? _entries;

  @override
  void initState() {
    super.initState();
    ActivityService.revision.addListener(_onChange);
    _load();
  }

  @override
  void didUpdateWidget(ActivityFeedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kinds != widget.kinds || oldWidget.limit != widget.limit) _load();
  }

  @override
  void dispose() {
    ActivityService.revision.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => _load();

  Future<void> _load() async {
    var all = await ActivityService.getAll(limit: 1000);
    if (widget.kinds != null && widget.kinds!.isNotEmpty) {
      all = all.where((e) => widget.kinds!.contains(e.kind)).toList();
    }
    all = all.take(widget.limit).toList();
    if (mounted) setState(() => _entries = all);
  }

  Future<void> _clear() async {
    if (widget.kinds != null && widget.kinds!.isNotEmpty) {
      for (final k in widget.kinds!) {
        await ActivityService.clearByKind(k);
      }
    } else {
      await ActivityService.clearAll();
    }
    _load();
  }

  Future<void> _remove(ActivityEntry e) async {
    await ActivityService.remove(e.id!);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history, color: Color(0xFF818CF8), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(widget.title,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            if (entries.isNotEmpty)
              InkWell(
                onTap: _clear,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.delete_sweep, color: Color(0xFF94A3B8), size: 15),
                      const SizedBox(width: 4),
                      const Text('Clear',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
            child: const Text('No recent activity yet — actions from every ecosystem will appear here.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          )
        else
          for (final e in entries)
            ActivityTile(
              entry: e,
              onTap: () => widget.onResume(e),
              onRemove: e.id != null ? () => _remove(e) : null,
              control: e.kind == ActivityKind.media
                  ? ActivityMediaControl(entry: e)
                  : null,
            ),
      ],
    );
  }
}
