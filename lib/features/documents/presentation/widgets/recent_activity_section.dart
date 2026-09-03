import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/document_service.dart';
import '../../../../app/providers/service_providers.dart';

/// Recent Activity section for a Documents ecosystem hub — lists recently
/// opened document files (from the file-recents store, intersected with the
/// scanned document list) so the user can jump straight back into a file.
/// Tapping a file reopens it; supported readers auto-restore the reading
/// position.
class RecentActivitySection extends ConsumerStatefulWidget {
  final void Function(DocumentFileInfo doc) onOpen;
  const RecentActivitySection({super.key, required this.onOpen});

  @override
  ConsumerState<RecentActivitySection> createState() => _RecentActivitySectionState();
}

class _RecentActivitySectionState extends ConsumerState<RecentActivitySection> {
  List<DocumentFileInfo>? _recents;
  final _kCard = const Color(0xFF1E293B);

  static const _icons = <String, IconData>{
    'pdf': Icons.picture_as_pdf,
    'epub': Icons.menu_book,
    'doc': Icons.description,
    'txt': Icons.text_fields,
    'html': Icons.language,
    'xls': Icons.grid_on,
    'code': Icons.code,
  };

  static const _colors = <String, Color>{
    'pdf': Color(0xFFEF4444),
    'epub': Color(0xFF8B5CF6),
    'doc': Color(0xFF3B82F6),
    'txt': Color(0xFF94A3B8),
    'html': Color(0xFFF59E0B),
    'xls': Color(0xFF10B981),
    'code': Color(0xFF14B8A6),
  };

  DocumentService get _service => ref.read(documentServiceProvider) ?? DocumentService();

  @override
  void initState() {
    super.initState();
    _load();
    final service = ref.read(documentServiceProvider);
    service?.addListener(_onServiceChanged);
  }

  void _onServiceChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    final service = ref.read(documentServiceProvider);
    service?.removeListener(_onServiceChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final recents = await _service.recentDocuments();
    if (mounted) setState(() => _recents = recents);
  }

  String _ext(String path) => path.split('.').last.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final recents = _recents;
    if (recents == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8))),
      );
    }
    if (recents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            const Icon(Icons.history, color: Color(0xFF475569), size: 32),
            const SizedBox(height: 8),
            const Text('No recent documents yet',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            const SizedBox(height: 4),
            Text('Documents you open will appear here.',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history, color: Color(0xFF818CF8), size: 18),
            const SizedBox(width: 6),
            const Text('Recent Activity',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        for (final doc in recents) _buildTile(doc),
      ],
    );
  }

  Widget _buildTile(DocumentFileInfo doc) {
    final ext = _ext(doc.filePath);
    final color = _colors[ext] ?? const Color(0xFF94A3B8);
    final icon = _icons[ext] ?? Icons.insert_drive_file;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(doc.fileName,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis),
        subtitle: Text('${ext.toUpperCase()} · ${DocumentService.folderDisplayName(doc.folder)}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.play_arrow_rounded, color: Color(0xFF94A3B8), size: 20),
        onTap: () => widget.onOpen(doc),
      ),
    );
  }
}
