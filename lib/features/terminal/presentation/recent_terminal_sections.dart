import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/service_providers.dart';
import '../../../core/services/terminal_sessions_store.dart';

/// "Recent Sessions" section for the Terminal hub. Lists created/pinned
/// terminal sessions along with their shell/SSH target, saved CWD, and live
/// background status from [TerminalRuntimeManager].
class RecentTerminalSessionsSection extends ConsumerStatefulWidget {
  final void Function(int sessionId) onOpenSession;
  final VoidCallback onNewSession;
  const RecentTerminalSessionsSection({
    super.key,
    required this.onOpenSession,
    required this.onNewSession,
  });

  @override
  ConsumerState<RecentTerminalSessionsSection> createState() =>
      _RecentTerminalSessionsSectionState();
}

class _RecentTerminalSessionsSectionState
    extends ConsumerState<RecentTerminalSessionsSection> {
  List<TerminalSessionMeta>? _sessions;

  TerminalSessionsStore get _store =>
      ref.read(terminalSessionsStoreProvider) ?? TerminalSessionsStore();

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

  Future<void> _remove(int id) async {
    await ref.read(terminalRuntimeManagerProvider).closeSession(id);
    if (mounted) _load();
  }

  Future<void> _clear() async {
    await _store.clearAll();
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    final mgr = ref.watch(terminalRuntimeManagerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.terminal_rounded, color: Color(0xFF22D3EE), size: 18),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Recent & Live Sessions',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            if (sessions != null && sessions.isNotEmpty)
              InkWell(
                onTap: _clear,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_sweep, color: Color(0xFF94A3B8), size: 15),
                      SizedBox(width: 4),
                      Text('Clear',
                          style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (sessions == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF22D3EE))),
          )
        else if (sessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12)),
            child: const Text(
                'No terminal sessions yet — launch a local shell or SSH workstation.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          )
        else
          for (final s in sessions)
            _buildSessionTile(s, isLive: mgr.isSessionRunning(s.id)),
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
                      style: TextStyle(
                          color: Color(0xFF22D3EE),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionTile(TerminalSessionMeta s, {required bool isLive}) {
    final shellBadge = s.shellId.isNotEmpty ? s.shellId : s.targetType;
    final subParts = <String>[
      if (shellBadge.isNotEmpty) shellBadge,
      if (s.cwd.isNotEmpty) s.cwd,
      _ago(s.updatedAt),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (isLive ? const Color(0xFF10B981) : const Color(0xFF22D3EE))
                .withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            s.targetType == 'ssh' ? Icons.router_outlined : Icons.terminal,
            color: isLive ? const Color(0xFF34D399) : const Color(0xFF22D3EE),
            size: 20,
          ),
        ),
        title: Row(
          children: [
            if (isLive)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(
                    color: Color(0xFF34D399), shape: BoxShape.circle),
              ),
            Flexible(
              child: Text(s.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Text(subParts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _store.togglePin(s.id),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  s.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: s.isPinned
                      ? const Color(0xFFFBBF24)
                      : const Color(0xFF64748B),
                  size: 16,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _remove(s.id),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, color: Color(0xFF94A3B8), size: 16),
              ),
            ),
            const Icon(Icons.play_arrow_rounded,
                color: Color(0xFF94A3B8), size: 20),
          ],
        ),
        onTap: () => widget.onOpenSession(s.id),
      ),
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
