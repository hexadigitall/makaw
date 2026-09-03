import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/service_providers.dart';
import '../../../core/services/terminal_sessions_store.dart';

/// "Recent Sessions" section for the Terminal hub. Lists created terminal
/// sessions (most recent first). Tapping opens the Terminal tool focused on
/// that session; a "New Session" tile creates one.
class RecentTerminalSessionsSection extends ConsumerStatefulWidget {
  final void Function(int sessionId) onOpenSession;
  final VoidCallback onNewSession;
  const RecentTerminalSessionsSection({
    super.key,
    required this.onOpenSession,
    required this.onNewSession,
  });

  @override
  ConsumerState<RecentTerminalSessionsSection> createState() => _RecentTerminalSessionsSectionState();
}

class _RecentTerminalSessionsSectionState extends ConsumerState<RecentTerminalSessionsSection> {
  List<TerminalSessionMeta>? _sessions;

  TerminalSessionsStore get _store => ref.read(terminalSessionsStoreProvider) ?? TerminalSessionsStore();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final s = await _store.load();
    if (mounted) setState(() => _sessions = s);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.post_add, color: Color(0xFF22D3EE), size: 18),
            const SizedBox(width: 6),
            const Text('Recent Sessions',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        if (sessions == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF22D3EE))),
          )
        else if (sessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
            child: const Text('No terminal sessions yet — create one to queue it here.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          )
        else
          for (final s in sessions)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22D3EE).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.terminal, color: Color(0xFF22D3EE), size: 20),
                ),
                title: Text(s.name,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
                subtitle: Text('Opened ${_ago(s.createdAt)}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                trailing: const Icon(Icons.play_arrow_rounded, color: Color(0xFF94A3B8), size: 20),
                onTap: () => widget.onOpenSession(s.id),
              ),
            ),
        const SizedBox(height: 4),
        Material(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onNewSession,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: Color(0xFF22D3EE), size: 18),
                  SizedBox(width: 6),
                  Text('New Terminal Session',
                      style: TextStyle(color: Color(0xFF22D3EE), fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
