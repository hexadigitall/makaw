import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../../../../core/platform/system_launcher.dart';
import '../../data/code_studio_service.dart';

/// Recursive project file tree with desktop-grade CRUD:
/// expand/collapse folders, open files, right-click / menu actions for
/// New file, New folder, Rename, Delete, Open in Terminal and Reveal in
/// Explorer.
class ProjectTreeView extends StatefulWidget {
  final Directory root;
  final String selectedPath;
  final void Function(File file) onOpenFile;
  final void Function() onChanged;

  const ProjectTreeView({
    super.key,
    required this.root,
    required this.selectedPath,
    required this.onOpenFile,
    required this.onChanged,
  });

  @override
  State<ProjectTreeView> createState() => ProjectTreeViewState();
}

class ProjectTreeViewState extends State<ProjectTreeView> {
  final Set<String> _collapsed = {};
  List<_Node> _roots = [];
  String _missingNote = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void didUpdateWidget(ProjectTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root.path != widget.root.path) {
      _collapsed.clear();
      _scan();
    }
  }

  /// Re-reads the folder tree from disk.
  void refresh() => _scan();

  /// Walks the folder tree on a background isolate so huge folders do not
  /// freeze the UI, then swaps the nodes into the tree in one setState.
  void _scan() {
    final root = widget.root;
    if (!root.existsSync()) {
      _roots = [];
      _missingNote = 'Folder not found';
      if (mounted) setState(() {});
      return;
    }
    final wasEmpty = _roots.isEmpty;
    if (mounted) {
      setState(() {
        _loading = true;
        if (wasEmpty) _missingNote = '';
      });
    }
    _buildNodesAsync(root).then((nodes) {
      if (!mounted) return;
      setState(() {
        _roots = nodes;
        _missingNote = nodes.isEmpty ? 'Empty folder' : '';
        _loading = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _missingNote = 'Could not read folder';
      });
    });
  }

  Future<List<_Node>> _buildNodesAsync(Directory dir) =>
      Isolate.run(() => _buildNodes(dir, ''));

  List<_Node> _buildNodes(Directory dir, String relPath) {
    final nodes = <_Node>[];
    try {
      final children = dir.listSync()
          .where((e) => !CodeStudioService.skippedDirs.contains(_nameOf(e)))
          .where((e) => !e.path.contains('${Platform.pathSeparator}.git'))
          .toList();
      children.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      for (final e in children) {
        final name = _nameOf(e);
        if (e is Directory) {
          nodes.add(_Node(
            name: name,
            relPath: relPath.isEmpty ? name : '$relPath/$name',
            isDir: true,
            children: _buildNodes(e, relPath.isEmpty ? name : '$relPath/$name'),
          ));
        } else {
          nodes.add(_Node(
            name: name,
            relPath: relPath.isEmpty ? name : '$relPath/$name',
            isDir: false,
            children: const [],
          ));
        }
      }
    } catch (_) {}
    return nodes;
  }

  static String _nameOf(FileSystemEntity e) =>
      e.path.split(Platform.pathSeparator).last;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      );
    }
    if (_missingNote.isNotEmpty) {
      return Center(
        child: Text(_missingNote, style: const TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [
        for (final node in _roots) _buildNode(node, 0),
      ],
    );
  }

  Widget _buildNode(_Node node, int depth) {
    final isSelected = !node.isDir &&
        CodeStudioService.fileIn(widget.root, node.relPath).path == widget.selectedPath;
    final isCollapsed = node.isDir && _collapsed.contains(node.relPath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRow(node, depth, isSelected, isCollapsed),
        if (node.isDir && !isCollapsed)
          for (final child in node.children) _buildNode(child, depth + 1),
      ],
    );
  }

  Widget _buildRow(_Node node, int depth, bool selected, bool collapsed) {
    final indent = depth * 12.0;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          if (node.isDir) {
            setState(() {
              if (collapsed) {
                _collapsed.remove(node.relPath);
              } else {
                _collapsed.add(node.relPath);
              }
            });
          } else {
            widget.onOpenFile(CodeStudioService.fileIn(widget.root, node.relPath));
          }
        },
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3B82F6).withOpacity(0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (node.isDir)
                Icon(
                  collapsed ? Icons.chevron_right : Icons.arrow_drop_down,
                  size: 16,
                  color: Colors.white38,
                )
              else
                const SizedBox(width: 16),
              Icon(
                node.isDir ? Icons.folder_rounded : _iconFor(node.name),
                size: 14,
                color: node.isDir ? const Color(0xFFFBBF24) : (selected ? const Color(0xFF60A5FA) : Colors.white70),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 12.5,
                    fontWeight: node.isDir ? FontWeight.w500 : FontWeight.normal,
                    fontFamily: node.isDir ? null : 'monospace',
                  ),
                ),
              ),
              _MenuButton(onAction: (action) => _handleMenu(node, action)),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dart')) return Icons.code;
    if (lower.endsWith('.ts') || lower.endsWith('.tsx') || lower.endsWith('.js') || lower.endsWith('.jsx') || lower.endsWith('.mjs'))
      return Icons.javascript;
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return Icons.html;
    if (lower.endsWith('.css') || lower.endsWith('.scss')) return Icons.css;
    if (lower.endsWith('.json')) return Icons.data_object;
    if (lower.endsWith('.md')) return Icons.notes;
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.svg'))
      return Icons.image;
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.py')) return Icons.code;
    if (lower.endsWith('.yml') || lower.endsWith('.yaml')) return Icons.settings;
    if (lower.endsWith('.lock')) return Icons.lock_outline;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _handleMenu(_Node node, String action) async {
    switch (action) {
      case 'open':
        if (!node.isDir) {
          widget.onOpenFile(CodeStudioService.fileIn(widget.root, node.relPath));
        }
        break;
      case 'new_file':
        final name = await _prompt('New File Name', 'e.g. api.dart');
        if (name != null && name.trim().isNotEmpty) {
          final base = node.isDir ? node.relPath : _parentOf(node.relPath);
          final target = (base.isEmpty ? '' : '$base/') + name.trim();
          await CodeStudioService.createFile(widget.root, target,
              content: _boilerplateFor(name.trim()));
          refresh();
          widget.onChanged();
        }
        break;
      case 'new_folder':
        final name = await _prompt('New Folder Name', 'e.g. components');
        if (name != null && name.trim().isNotEmpty) {
          final base = node.isDir ? node.relPath : _parentOf(node.relPath);
          final target = (base.isEmpty ? '' : '$base/') + name.trim();
          await CodeStudioService.createFolder(widget.root, target);
          refresh();
          widget.onChanged();
        }
        break;
      case 'rename':
        final current = node.name;
        final name = await _prompt('Rename', '', initial: current);
        if (name != null && name.trim().isNotEmpty && name.trim() != current) {
          try {
            final entity = node.isDir
                ? CodeStudioService.dirIn(widget.root, node.relPath)
                : CodeStudioService.fileIn(widget.root, node.relPath);
            final parentRel = _parentOf(node.relPath);
            final newRel = (parentRel.isEmpty ? '' : '$parentRel/') + name.trim();
            final target = node.isDir
                ? CodeStudioService.dirIn(widget.root, newRel)
                : CodeStudioService.fileIn(widget.root, newRel);
            if (await entity.exists()) await entity.rename(target.path);
            _collapsed
              ..remove(node.relPath)
              ..add(newRel);
            refresh();
            widget.onChanged();
          } catch (_) {}
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text('Delete?', style: TextStyle(color: Colors.white, fontSize: 16)),
            content: Text('$node.name (${node.isDir ? 'folder' : 'file'})',
                style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
            ],
          ),
        );
        if (confirmed == true) {
          final entity = node.isDir
              ? CodeStudioService.dirIn(widget.root, node.relPath)
              : CodeStudioService.fileIn(widget.root, node.relPath);
          await CodeStudioService.deleteEntity(entity);
          refresh();
          widget.onChanged();
        }
      case 'terminal':
        final dirRel = node.isDir ? node.relPath : _parentOf(node.relPath);
        final path = dirRel.isEmpty
            ? widget.root.path
            : CodeStudioService.dirIn(widget.root, dirRel).path;
        await SystemLauncher.openTerminalAt(path);
      case 'explorer':
        final path = node.isDir
            ? CodeStudioService.dirIn(widget.root, node.relPath).path
            : CodeStudioService.fileIn(widget.root, node.relPath).parent.path;
        await SystemLauncher.openExplorer(path);
    }
  }

  String _parentOf(String relPath) {
    final idx = relPath.lastIndexOf('/');
    return idx < 0 ? '' : relPath.substring(0, idx);
  }

  String _boilerplateFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dart')) return 'void main() {\n  print(\'Hello from $name\');\n}\n';
    if (lower.endsWith('.py')) return '#!/usr/bin/env python\n\nprint("Hello from $name")\n';
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) return "// $name\nconsole.log('Hello from $name');\n";
    if (lower.endsWith('.ts')) return "// $name\nexport {};\nconsole.log('Hello from $name');\n";
    if (lower.endsWith('.html')) return '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="utf-8">\n  <title>$name</title>\n</head>\n<body>\n  <h1>$name</h1>\n</body>\n</html>\n';
    if (lower.endsWith('.css')) return '/* $name */\n';
    if (lower.endsWith('.json')) return '{\n  "$name": true\n}\n';
    if (lower.endsWith('.md')) return '# $name\n\n\n';
    return '';
  }

  Future<String?> _prompt(String title, String hint, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF60A5FA))),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Confirm')),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final void Function(String) onAction;
  const _MenuButton({required this.onAction});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: const Icon(Icons.more_horiz, size: 14, color: Colors.white38),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: onAction,
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'open', child: _MenuLabel(Icons.open_in_new, 'Open')),
        const PopupMenuItem(value: 'new_file', child: _MenuLabel(Icons.note_add_outlined, 'New File')),
        const PopupMenuItem(value: 'new_folder', child: _MenuLabel(Icons.create_new_folder_outlined, 'New Folder')),
        const PopupMenuItem(value: 'rename', child: _MenuLabel(Icons.drive_file_rename_outline, 'Rename')),
        const PopupMenuItem(value: 'delete', child: _MenuLabel(Icons.delete_outline, 'Delete', danger: true)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'terminal', child: _MenuLabel(Icons.terminal, 'Open in Terminal')),
        const PopupMenuItem(value: 'explorer', child: _MenuLabel(Icons.folder_open, 'Reveal in Explorer')),
      ],
    );
  }
}

class _MenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const _MenuLabel(this.icon, this.label, {this.danger = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: danger ? Colors.redAccent : Colors.white70),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
              color: danger ? Colors.redAccent : Colors.white,
              fontSize: 13,
            )),
      ],
    );
  }
}

class _Node {
  final String name;
  final String relPath;
  final bool isDir;
  final List<_Node> children;

  const _Node({required this.name, required this.relPath, required this.isDir, required this.children});
}