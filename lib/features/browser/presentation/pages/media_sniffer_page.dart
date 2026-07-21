import 'package:flutter/material.dart';
import '../../domain/entities/media_item.dart';

const _kAccentTeal = Color(0xFF00A7C2);

class MediaSnifferPage extends StatefulWidget {
  final List<MediaItem> items;
  final void Function(MediaItem) onDownload;
  final void Function(List<MediaItem>) onDownloadAll;
  final VoidCallback onClear;
  final void Function(MediaItem, String) onRename;
  final void Function(String) showToast;

  const MediaSnifferPage({
    super.key,
    required this.items,
    required this.onDownload,
    required this.onDownloadAll,
    required this.onClear,
    required this.onRename,
    required this.showToast,
  });

  @override
  State<MediaSnifferPage> createState() => _MediaSnifferPageState();
}

class _MediaSnifferPageState extends State<MediaSnifferPage> {
  bool _selectMode = false;
  late List<bool> _selected;
  late List<MediaItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    _selected = List.filled(_items.length, false);
  }

  int get _selectedCount => _selected.where((s) => s).length;

  List<MediaItem> _sections(String type) =>
      _items.where((m) => m.type == type).toList();

  IconData _typeIcon(String type) {
    switch (type) {
      case 'video': return Icons.videocam;
      case 'image': return Icons.image;
      case 'audio': return Icons.music_note;
      case 'document': return Icons.description;
      default: return Icons.insert_drive_file;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'video': return const Color(0xFF818CF8);
      case 'image': return const Color(0xFF34D399);
      case 'audio': return const Color(0xFFFBBF24);
      case 'document': return const Color(0xFFF87171);
      default: return const Color(0xFF94A3B8);
    }
  }

  String _sectionLabel(String type) {
    switch (type) {
      case 'video': return 'Videos';
      case 'image': return 'Images';
      case 'document': return 'Documents';
      case 'audio': return 'Audio';
      default: return 'Other';
    }
  }

  IconData _sectionIcon(String type) {
    switch (type) {
      case 'video': return Icons.videocam;
      case 'image': return Icons.image;
      case 'document': return Icons.description;
      case 'audio': return Icons.music_note;
      default: return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectionTypes = ['video', 'image', 'document', 'audio'];
    final availableTypes = sectionTypes.where((t) => _sections(t).isNotEmpty).toList();

    return Container(
      height: MediaQuery.of(context).size.height,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(4, MediaQuery.of(context).padding.top + 4, 4, 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Theme.of(context).cardColor, width: 0.5)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                if (_selectMode) ...[
                  Text('$_selectedCount Selected', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w600)),
                  Spacer(),
                  TextButton(
                    onPressed: _selectedCount == 0 ? null : () {
                      final toDelete = <MediaItem>[];
                      for (int i = _items.length - 1; i >= 0; i--) {
                        if (_selected[i]) toDelete.add(_items[i]);
                      }
                      widget.onDownloadAll(toDelete);
                      setState(() {
                        for (final item in toDelete) _items.remove(item);
                        _selected = List.filled(_items.length, false);
                        _selectMode = false;
                      });
                    },
                    child: Text('Delete', style: TextStyle(color: Colors.red, fontSize: 14)),
                  ),
                  SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onSurface),
                    onPressed: () {
                      setState(() {
                        _selected.fillRange(0, _selected.length, false);
                        _selectMode = false;
                      });
                    },
                    tooltip: 'Refresh',
                  ),
                ] else ...[
                  Text('Media Sniffer', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
                  Spacer(),
                  TextButton(
                    onPressed: () {
                      widget.onClear();
                      Navigator.of(context).pop();
                    },
                    child: Text('Clear', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14)),
                  ),
                  SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    onSelected: (v) {
                      if (v == 'select') setState(() => _selectMode = true);
                      if (v == 'select_all') {
                        setState(() {
                          _selectMode = true;
                          _selected.fillRange(0, _selected.length, true);
                        });
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'select', child: Text('Select', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                      PopupMenuItem(value: 'select_all', child: Text('Select All', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? Center(child: Text('No media found', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))))
                : ListView(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final type in availableTypes) ...[
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Row(
                            children: [
                              Icon(_sectionIcon(type), size: 16, color: _typeColor(type)),
                              SizedBox(width: 6),
                              Text(_sectionLabel(type), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
                              Spacer(),
                              Text('${_sections(type).length}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                            ],
                          ),
                        ),
                        for (final item in _sections(type))
                          _buildMediaItem(context, item),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaItem(BuildContext context, MediaItem item) {
    final idx = _items.indexOf(item);
    final name = item.title.isNotEmpty ? item.title : item.url.split('/').last.split('?').first;
    final displayName = name.length > 45 ? '${name.substring(0, 45)}...' : name;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: _selectMode
          ? CheckboxListTile(
              dense: true,
              value: idx >= 0 && idx < _selected.length ? _selected[idx] : false,
              activeColor: _kAccentTeal,
              checkColor: Colors.white,
              onChanged: (v) {
                if (idx < 0) return;
                setState(() => _selected[idx] = v ?? false);
              },
              secondary: Icon(_typeIcon(item.type), color: _typeColor(item.type), size: 22),
              title: Text(displayName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
              subtitle: Text(item.url, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          : Padding(
              padding: EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_typeIcon(item.type), color: _typeColor(item.type), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500)),
                            Text(item.url, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                        onPressed: () => _showRenameDialog(context, item),
                        constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.all(4),
                        tooltip: 'Rename',
                      ),
                      IconButton(
                        icon: Icon(Icons.download, size: 18, color: _kAccentTeal),
                        onPressed: () {
                          widget.onDownload(item);
                          widget.showToast('Added to downloads');
                        },
                        constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.all(4),
                        tooltip: 'Download',
                      ),
                    ],
                  ),
                  if (item.formats.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.formats.map((f) {
                        const selected = false;
                        return GestureDetector(
                          onTap: () {
                            widget.onDownload(MediaItem(url: f.url, type: item.type, title: item.title));
                            widget.showToast('Downloading ${f.label}');
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: selected ? _kAccentTeal.withValues(alpha: 0.3) : Color(0xFF374151),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: selected ? _kAccentTeal : Color(0xFF4B5563), width: 0.5),
                            ),
                            child: Text(f.label, style: TextStyle(fontSize: 11, color: selected ? _kAccentTeal : Color(0xFF93C5FD))),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  void _showRenameDialog(BuildContext context, MediaItem item) {
    final ctl = TextEditingController(text: item.title.isNotEmpty ? item.title : item.url.split('/').last.split('?').first);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Rename', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Enter new name',
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)))),
          TextButton(
            onPressed: () {
              final newName = ctl.text.trim();
              if (newName.isNotEmpty) {
                widget.onRename(item, newName);
                setState(() {
                  final idx = _items.indexOf(item);
                  if (idx >= 0) _items[idx] = MediaItem(url: item.url, type: item.type, title: newName, formats: item.formats);
                });
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Rename', style: TextStyle(color: _kAccentTeal)),
          ),
        ],
      ),
    );
  }
}
