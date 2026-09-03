import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/services/document_service.dart';
import '../../../../app/providers/service_providers.dart';

/// Standalone Folders tool for the Documents ecosystem — shows folders that
/// contain documents (folder level). Tapping a folder drills into its files.
/// Reachable from the "File Explorer" button on the Documents Hub.
class FoldersPage extends ConsumerStatefulWidget {
  final void Function(String filePath) openFile;
  const FoldersPage({super.key, required this.openFile});

  @override
  ConsumerState<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends ConsumerState<FoldersPage> {
  String? _selectedFolder;
  final _kDark = const Color(0xFF0F0F1A);
  final _kAccent = const Color(0xFF818CF8);
  final _kCard = const Color(0xFF1A1A2E);

  static const _categoryIcons = <String, IconData>{
    'pdf': Icons.picture_as_pdf,
    'epub': Icons.menu_book,
    'doc': Icons.description,
    'txt': Icons.text_fields,
    'html': Icons.language,
    'xls': Icons.grid_on,
    'code': Icons.code,
  };

  static const _categoryColors = <String, Color>{
    'pdf': Color(0xFFEF4444),
    'epub': Color(0xFF8B5CF6),
    'doc': Color(0xFF3B82F6),
    'txt': Color(0xFF94A3B8),
    'html': Color(0xFFF59E0B),
    'xls': Color(0xFF10B981),
    'code': Color(0xFF14B8A6),
  };

  DocumentService get _service => ref.read(documentServiceProvider) ?? DocumentService();

  String _ext(String path) => path.split('.').last.toLowerCase();
  IconData _icon(String path) => _categoryIcons[_ext(path)] ?? Icons.insert_drive_file;
  Color _color(String path) => _categoryColors[_ext(path)] ?? const Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        backgroundColor: _kDark,
        title: Text(
          _selectedFolder == null ? 'Folders' : DocumentService.folderDisplayName(_selectedFolder!),
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_selectedFolder != null) {
              setState(() => _selectedFolder = null);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: _selectedFolder == null ? _buildFolders() : _buildFolderContents(),
    );
  }

  Widget _buildFolders() {
    final all = _service.allDocuments;
    if (all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_outlined, color: Color(0xFF666680), size: 48),
            const SizedBox(height: 12),
            Text(_service.isScanning ? 'Scanning for documents...' : 'No folders found',
                style: const TextStyle(color: Color(0xFF666680))),
            if (_service.isScanning) ...[
              const SizedBox(height: 12),
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent)),
            ],
          ],
        ),
      );
    }
    final byFolder = <String, List<DocumentFileInfo>>{};
    for (final d in all) {
      byFolder.putIfAbsent(d.folder, () => []).add(d);
    }
    final entries = byFolder.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final entry = entries[i];
        final docs = entry.value;
        return GestureDetector(
          onTap: () => setState(() => _selectedFolder = entry.key),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _kAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.folder, color: Color(0xFF818CF8), size: 24),
              ),
              title: Text(DocumentService.folderDisplayName(entry.key),
                  style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
              subtitle: Text('${docs.length} file${docs.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Color(0xFF666680), fontSize: 11)),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF666680)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderContents() {
    final docs = _service.folders[_selectedFolder] ?? [];
    if (docs.isEmpty) {
      return const Center(child: Text('Folder is empty', style: TextStyle(color: Color(0xFF666680))));
    }
    final sorted = List<DocumentFileInfo>.from(docs)
      ..sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      itemBuilder: (_, i) => _buildDocItem(sorted[i]),
    );
  }

  Widget _buildDocItem(DocumentFileInfo doc) {
    return GestureDetector(
      onTap: () => widget.openFile(doc.filePath),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _color(doc.filePath).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(_icon(doc.filePath), color: _color(doc.filePath), size: 24),
          ),
          title: Text(doc.fileName, style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
          subtitle: Text(_ext(doc.filePath).toUpperCase(), style: const TextStyle(color: Color(0xFF666680), fontSize: 11)),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.share, color: Color(0xFF666680), size: 20),
            onSelected: (v) {
              if (v == 'share') Share.shareXFiles([XFile(doc.filePath)]);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share, color: Colors.white70), title: Text('Share', style: TextStyle(color: Colors.white)))),
            ],
          ),
        ),
      ),
    );
  }
}
