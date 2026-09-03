import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/download_manager_provider.dart';
import '../providers/download_service.dart';

class DownloadsWidget extends ConsumerStatefulWidget {
  final void Function(String url, String filename, String? savePath) onOpenDownload;

  const DownloadsWidget({
    super.key,
    required this.onOpenDownload,
  });

  @override
  ConsumerState<DownloadsWidget> createState() => _DownloadsWidgetState();
}

class _DownloadsWidgetState extends ConsumerState<DownloadsWidget> {
  DownloadService? _manager;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mgr = ref.read(downloadServiceProvider);
    if (mgr != null && mgr != _manager) {
      _manager?.removeListener(_onChanged);
      _manager = mgr;
      _manager!.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _manager?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  DownloadService? get _mgr => _manager;

  @override
  Widget build(BuildContext context) {
    final mgr = _mgr;
    if (mgr == null) {
      return const Center(
        child: Text('Download manager not available', style: TextStyle(color: Color(0xFF94A3B8))),
      );
    }

    final dl = mgr.downloads;
    return Column(
      children: [
        _buildHeader(context, mgr),
        Expanded(
          child: dl.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  children: [
                    if (mgr.activeDownloads.isNotEmpty) ...[
                      _buildSectionLabel('Active (${mgr.activeDownloads.length})'),
                      ...mgr.activeDownloads.map((d) => _buildDownloadItem(context, d, mgr)),
                    ],
                    if (mgr.completedDownloads.isNotEmpty) ...[
                      _buildSectionLabel('Completed (${mgr.completedDownloads.length})'),
                      ...mgr.completedDownloads.map((d) => _buildDownloadItem(context, d, mgr)),
                    ],
                    if (mgr.failedDownloads.isNotEmpty) ...[
                      _buildSectionLabel('Failed (${mgr.failedDownloads.length})'),
                      ...mgr.failedDownloads.map((d) => _buildDownloadItem(context, d, mgr)),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, DownloadService mgr) {
    final active = mgr.activeDownloads;
    final totalSpeed = active.fold<int>(0, (s, d) => s + d.speed.round());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFFB923C).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.download, color: Color(0xFFFB923C), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (active.isNotEmpty)
                  Text('${active.length} active${totalSpeed > 0 ? '  •  ${_fmtSpeed(totalSpeed)}' : ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))
                else
                  const Text('All downloads', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
          if (mgr.completedDownloads.isNotEmpty)
            TextButton(
              onPressed: mgr.clearCompleted,
              child: const Text('Clear', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 28)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_download_outlined, size: 56, color: Color(0xFF475569)),
          SizedBox(height: 14),
          Text('No downloads', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15)),
          SizedBox(height: 6),
          Text('Downloads appear here when you download files', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
      child: Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
    );
  }

  Widget _buildDownloadItem(BuildContext context, DownloadItem item, DownloadService mgr) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _buildStateIcon(item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.filename,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  if (item.state == DownloadState.downloading) ...[
                    Row(children: [
                      Text('${(item.progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Color(0xFFFB923C), fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      if (item.totalBytes > 0)
                        Text('${item.receivedStr} / ${item.sizeStr}',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                      if (item.speed > 0) ...[
                        const SizedBox(width: 8),
                        Text(item.speedStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                      ],
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        backgroundColor: const Color(0xFF334155),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFB923C)),
                        minHeight: 4,
                      ),
                    ),
                  ] else if (item.state == DownloadState.queued) ...[
                    const Text('Waiting...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  ] else if (item.state == DownloadState.paused) ...[
                    const Text('Paused', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
                  ] else if (item.state == DownloadState.completed) ...[
                    Row(children: [
                      Text(item.sizeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      if (item.completedAt != null) ...[
                        const SizedBox(width: 8),
                        Text(_formatDate(item.completedAt!), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      ],
                    ]),
                  ] else if (item.state == DownloadState.failed) ...[
                    Text(item.error ?? 'Failed', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildActionButton(context, item, mgr),
          ],
        ),
      ),
    );
  }

  Widget _buildStateIcon(DownloadItem item) {
    switch (item.state) {
      case DownloadState.downloading:
        return SizedBox(
          width: 40, height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(width: 40, height: 40,
                child: CircularProgressIndicator(
                  value: item.progress,
                  strokeWidth: 3,
                  backgroundColor: const Color(0xFF334155),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFB923C)),
                ),
              ),
              const Icon(Icons.cloud_download, color: Color(0xFFFB923C), size: 18),
            ],
          ),
        );
      case DownloadState.queued:
        return Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.hourglass_empty, color: Color(0xFF94A3B8), size: 20),
        );
      case DownloadState.paused:
        return Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.pause_circle_outline, color: Color(0xFFF59E0B), size: 20),
        );
      case DownloadState.completed:
        return Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: const Color(0xFF166534), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 22),
        );
      case DownloadState.failed:
        return Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: const Color(0xFF7F1D1D), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 20),
        );
    }
  }

  Widget _buildActionButton(BuildContext context, DownloadItem item, DownloadService mgr) {
    switch (item.state) {
      case DownloadState.downloading:
        return _smallBtn(Icons.pause, 'Pause', () => mgr.pause(item));
      case DownloadState.queued:
        return _smallBtn(Icons.close, 'Remove', () => mgr.remove(item));
      case DownloadState.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _smallBtn(Icons.play_arrow, 'Resume', () => mgr.resume(item)),
            const SizedBox(width: 4),
            _smallBtn(Icons.close, 'Remove', () => mgr.remove(item)),
          ],
        );
      case DownloadState.completed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.savePath != null)
              _smallBtn(Icons.folder_open, 'Open', () => widget.onOpenDownload(item.url, item.filename, item.savePath)),
            const SizedBox(width: 4),
            _smallBtn(Icons.delete_outline, 'Remove', () => mgr.remove(item)),
          ],
        );
      case DownloadState.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _smallBtn(Icons.refresh, 'Retry', () => mgr.retry(item)),
            const SizedBox(width: 4),
            _smallBtn(Icons.close, 'Remove', () => mgr.remove(item)),
          ],
        );
    }
  }

  Widget _smallBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 32, height: 32,
      child: IconButton(
        icon: Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1048576) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / 1048576).toStringAsFixed(1)} MB/s';
  }
}
