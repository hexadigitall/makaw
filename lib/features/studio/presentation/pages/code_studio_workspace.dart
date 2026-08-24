import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/bash.dart';
import 'package:xterm/xterm.dart';
import '../../data/code_studio_service.dart';
import '../../data/terminal_engine.dart';

class MakawStudioWorkspacePage extends StatefulWidget {
  final StudioProject project;
  const MakawStudioWorkspacePage({super.key, required this.project});

  @override
  State<MakawStudioWorkspacePage> createState() => _MakawStudioWorkspacePageState();
}

class _MakawStudioWorkspacePageState extends State<MakawStudioWorkspacePage> {
  late final CodeController _codeController;
  final MakawTerminalEngine _terminalEngine = MakawTerminalEngine();

  List<File> _projectFiles = [];
  File? _activeFile;
  bool _showConsole = false;
  bool _showFileTree = true;

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(text: '');
    _loadProjectFiles();
    _terminalEngine.startSession(workingDirectory: widget.project.directory.path);
  }

  void _loadProjectFiles() {
    final files = widget.project.directory.listSync(recursive: true).whereType<File>().toList();
    setState(() {
      _projectFiles = files;
      if (_projectFiles.isNotEmpty && _activeFile == null) _selectFile(_projectFiles.first);
    });
  }

  void _selectFile(File file) {
    _activeFile = file;
    _codeController.text = file.readAsStringSync();
    _codeController.language = _resolveLanguage(file.path);
    setState(() {});
  }

  dynamic _resolveLanguage(String path) {
    if (path.endsWith('.dart')) return dart;
    if (path.endsWith('.py')) return python;
    if (path.endsWith('.html') || path.endsWith('.xml')) return xml;
    if (path.endsWith('.sh')) return bash;
    return javascript;
  }

  Future<void> _saveCurrentFile() async {
    if (_activeFile != null) {
      await _activeFile!.writeAsString(_codeController.text, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${_activeFile!.path.split(Platform.pathSeparator).last}'), duration: const Duration(seconds: 1)),
        );
      }
    }
  }

  void _runInTerminal() {
    if (_activeFile == null) return;
    _saveCurrentFile();
    setState(() => _showConsole = true);
    final relativePath = _activeFile!.path.replaceFirst('${widget.project.directory.path}${Platform.pathSeparator}', '');
    if (_activeFile!.path.endsWith('.py')) {
      _terminalEngine.writeCommand('python "$relativePath"');
    } else if (_activeFile!.path.endsWith('.js')) {
      _terminalEngine.writeCommand('node "$relativePath"');
    } else if (_activeFile!.path.endsWith('.dart')) {
      _terminalEngine.writeCommand('dart run "$relativePath"');
    } else if (_activeFile!.path.endsWith('.sh')) {
      _terminalEngine.writeCommand('sh "$relativePath"');
    }
  }

  @override
  void dispose() {
    _terminalEngine.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('${widget.project.name} • ${_activeFile?.path.split(Platform.pathSeparator).last ?? ""}',
            style: TextStyle(color: cs.onSurface, fontSize: 15)),
        actions: [
          IconButton(icon: Icon(Icons.account_tree_outlined, color: cs.onSurface.withOpacity(0.6)),
            onPressed: () => setState(() => _showFileTree = !_showFileTree)),
          IconButton(icon: Icon(Icons.save_outlined, color: cs.onSurface.withOpacity(0.6)),
            onPressed: _saveCurrentFile),
          IconButton(icon: Icon(Icons.terminal, color: cs.onSurface.withOpacity(0.6)),
            onPressed: () => setState(() => _showConsole = !_showConsole)),
          IconButton(
            icon: Icon(Icons.play_arrow, color: Colors.greenAccent),
            onPressed: _runInTerminal,
          ),
        ],
      ),
      body: Row(children: [
        if (_showFileTree)
          Container(
            width: isDesktop ? 220 : 160,
            color: cs.surface,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: cs.surfaceContainerHighest,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('EXPLORER', style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: Icon(Icons.add, size: 16, color: cs.onSurface.withOpacity(0.7)),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    onPressed: () async {
                      final nameController = TextEditingController();
                      final newName = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: cs.surface,
                          title: Text('Add File', style: TextStyle(color: cs.onSurface)),
                          content: TextField(controller: nameController, autofocus: true,
                            style: TextStyle(color: cs.onSurface)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            ElevatedButton(onPressed: () => Navigator.pop(ctx, nameController.text.trim()), child: const Text('Create')),
                          ],
                        ),
                      );
                      if (newName != null && newName.isNotEmpty) {
                        await CodeStudioService.createFile(widget.project.directory, newName);
                        _loadProjectFiles();
                      }
                    },
                  ),
                ]),
              ),
              Expanded(child: ListView.builder(
                itemCount: _projectFiles.length,
                itemBuilder: (context, index) {
                  final file = _projectFiles[index];
                  final name = file.path.split(Platform.pathSeparator).last;
                  final isSelected = _activeFile?.path == file.path;
                  return ListTile(
                    dense: true, selected: isSelected,
                    selectedTileColor: cs.primary.withOpacity(0.1),
                    leading: Icon(_getFileIcon(name), size: 16, color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.5)),
                    title: Text(name, style: TextStyle(
                      color: isSelected ? cs.onSurface : cs.onSurface.withOpacity(0.7), fontSize: 13)),
                    onTap: () => _selectFile(file),
                  );
                },
              )),
            ]),
          ),
        Expanded(child: Column(children: [
          Expanded(flex: 3, child: CodeTheme(
            data: CodeThemeData(styles: monokaiSublimeTheme),
            child: SingleChildScrollView(
              child: CodeField(
                controller: _codeController,
                gutterStyle: const GutterStyle(showLineNumbers: true,
                  textStyle: TextStyle(color: Colors.white24, fontSize: 12)),
                textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          )),
          if (_showConsole)
            Expanded(flex: 2, child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: Column(children: [
                Container(
                  height: 28, padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: cs.surface,
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('TERMINAL', style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: Icon(Icons.close, size: 14, color: cs.onSurface.withOpacity(0.5)),
                      padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _showConsole = false),
                    ),
                  ]),
                ),
                Expanded(child: TerminalView(
                  _terminalEngine.terminal,
                  autofocus: false,
                  backgroundOpacity: 1.0,
                )),
              ]),
            )),
        ])),
      ]),
    );
  }

  IconData _getFileIcon(String name) {
    if (name.endsWith('.dart')) return Icons.flutter_dash;
    if (name.endsWith('.py')) return Icons.code;
    if (name.endsWith('.html')) return Icons.html;
    if (name.endsWith('.css')) return Icons.css;
    return Icons.insert_drive_file_outlined;
  }
}
