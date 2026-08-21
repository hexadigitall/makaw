import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/highlight.dart' show Mode;
import 'package:highlight/languages/all.dart';
import '../data/code_studio_service.dart';

class CodeStudioWorkspacePage extends StatefulWidget {
  final CodeStudioProject project;
  const CodeStudioWorkspacePage({super.key, required this.project});
  @override
  State<CodeStudioWorkspacePage> createState() => _CodeStudioWorkspacePageState();
}

class _CodeStudioWorkspacePageState extends State<CodeStudioWorkspacePage> {
  late List<_OpenFile> _openFiles;
  int _activeIndex = 0;
  bool _isExecuting = false;
  String _consoleOutput = '';
  bool _consoleVisible = false;

  Mode? _resolveMode(String lang) => allLanguages[lang];

  @override
  void initState() {
    super.initState();
    _openFiles = widget.project.files.map((f) {
      return _OpenFile(
        file: f,
        language: CodeStudioService.detectLanguage(f.path),
      );
    }).toList();
    if (_openFiles.isEmpty) {
      _createInitialFile();
    } else {
      _initController(0);
    }
  }

  Future<void> _createInitialFile() async {
    final file = await CodeStudioService.createFile(widget.project.rootDir, 'main.js');
    setState(() {
      _openFiles.add(_OpenFile(file: file, language: 'javascript'));
      _initController(0);
    });
  }

  void _initController(int index) {
    if (index < 0 || index >= _openFiles.length) return;
    final f = _openFiles[index];
    final code = f.file.existsSync() ? f.file.readAsStringSync() : '';
    final mode = _resolveMode(f.language);
    f.controller = CodeController(
      text: code,
      language: mode,
    );
  }

  void _switchTab(int index) {
    if (index == _activeIndex || index >= _openFiles.length) return;
    _saveCurrent();
    setState(() {
      _activeIndex = index;
      if (_openFiles[index].controller == null) _initController(index);
    });
  }

  Future<void> _saveCurrent() async {
    if (_openFiles.isEmpty) return;
    final f = _openFiles[_activeIndex];
    if (f.controller == null) return;
    await f.file.writeAsString(f.controller!.text, flush: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved ${_fileName(f.file.path)}'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF1E293B),
      ));
    }
  }

  Future<void> _addNewFile() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('New File', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'filename.js',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Create', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final file = await CodeStudioService.createFile(widget.project.rootDir, name);
      setState(() {
        _openFiles.add(_OpenFile(file: file, language: CodeStudioService.detectLanguage(name)));
        _initController(_openFiles.length - 1);
        _activeIndex = _openFiles.length - 1;
      });
    }
  }

  Future<void> _deleteFile(int index) async {
    if (_openFiles.length <= 1) return;
    final f = _openFiles[index];
    await CodeStudioService.deleteFile(f.file);
    setState(() {
      _openFiles.removeAt(index);
      if (_activeIndex >= _openFiles.length) _activeIndex = _openFiles.length - 1;
    });
  }

  Future<void> _runCode() async {
    if (_openFiles.isEmpty) return;
    await _saveCurrent();
    final f = _openFiles[_activeIndex];
    setState(() {
      _isExecuting = true;
      _consoleVisible = true;
      _consoleOutput = 'Running ${_fileName(f.file.path)}...\n';
    });
    try {
      final result = await CodeStudioService.executeCode(f.file);
      setState(() {
        _isExecuting = false;
        _consoleOutput += result.stdout.toString();
        if (result.stderr.toString().isNotEmpty) {
          _consoleOutput += '\n[stderr]\n${result.stderr}';
        }
      });
    } catch (e) {
      setState(() {
        _isExecuting = false;
        _consoleOutput += '\nExecution failed: $e';
      });
    }
  }

  static String _fileName(String path) => path.split(Platform.pathSeparator).last;

  @override
  void dispose() {
    for (final f in _openFiles) {
      f.controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181825),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () {
            _saveCurrent();
            Navigator.of(context).pop();
          },
        ),
        title: Text(widget.project.name,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add_outlined, color: Colors.white54, size: 20),
            tooltip: 'New File',
            onPressed: _addNewFile,
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Colors.white54, size: 20),
            tooltip: 'Save',
            onPressed: _saveCurrent,
          ),
          const SizedBox(width: 4),
          _isExecuting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent)),
                )
              : IconButton(
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.greenAccent, size: 26),
                  tooltip: 'Run',
                  onPressed: _runCode,
                ),
        ],
      ),
      body: Column(
        children: [
          _buildFileTabs(),
          Expanded(
            child: _openFiles.isEmpty
                ? const Center(
                    child: Text('No files open', style: TextStyle(color: Colors.white38)))
                : _buildCodeEditor(),
          ),
          if (_consoleVisible) _buildConsole(),
        ],
      ),
    );
  }

  Widget _buildFileTabs() {
    return Container(
      height: 38,
      color: const Color(0xFF11111B),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _openFiles.length,
        itemBuilder: (ctx, i) {
          final f = _openFiles[i];
          final active = i == _activeIndex;
          final name = _fileName(f.file.path);
          return GestureDetector(
            onTap: () => _switchTab(i),
            onLongPress: () => _deleteFile(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF1E1E2E) : Colors.transparent,
                border: Border(
                  top: BorderSide(color: active ? const Color(0xFF818CF8) : Colors.transparent, width: 2),
                  right: const BorderSide(color: Color(0xFF313244), width: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconForLang(f.language), size: 14,
                    color: active ? const Color(0xFF818CF8) : Colors.white38),
                  const SizedBox(width: 6),
                  Text(name, style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: active ? Colors.white : Colors.white54,
                  )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCodeEditor() {
    final f = _openFiles[_activeIndex];
    if (f.controller == null) return const Center(child: CircularProgressIndicator());
    return CodeTheme(
      data: CodeThemeData(styles: monokaiSublimeTheme),
      child: CodeField(
        controller: f.controller!,
        gutterStyle: const GutterStyle(
          showLineNumbers: true,
          textStyle: TextStyle(color: Colors.white30, fontSize: 13, fontFamily: 'monospace'),
          width: 60,
          margin: 8,
        ),
        textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: Colors.white),
      ),
    );
  }

  Widget _buildConsole() {
    return Container(
      height: 160,
      color: const Color(0xFF11111B),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF181825),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                const Text('OUTPUT', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_isExecuting)
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.greenAccent)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _consoleVisible = false),
                  child: const Icon(Icons.close, size: 16, color: Colors.white38),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Text(_consoleOutput,
                style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForLang(String lang) {
    switch (lang) {
      case 'dart': return Icons.flutter_dash;
      case 'python': return Icons.science;
      case 'javascript': case 'typescript': return Icons.javascript;
      case 'html': case 'xml': return Icons.html;
      case 'css': return Icons.palette;
      case 'json': return Icons.data_object;
      case 'shell': return Icons.terminal;
      default: return Icons.code;
    }
  }
}

class _OpenFile {
  final File file;
  final String language;
  CodeController? controller;
  _OpenFile({required this.file, required this.language, this.controller});
}
