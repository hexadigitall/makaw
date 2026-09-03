import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/highlight_core.dart';
import 'package:xterm/xterm.dart';

import '../../data/code_studio_service.dart';
import '../../data/studio_project.dart';
import '../../data/terminal_engine.dart';

/// Defines the active mobile view (editor / terminal / preview / git).
enum MobileIdeView { editor, terminal, preview, git }

/// Adaptive Makaw Code Studio IDE.
///
/// The same state (active file, open tabs, terminal session) seamlessly
/// morphs between a multi-pane desktop grid and a stacked, gesture-driven
/// mobile interface:
///  - Desktop (>= 900px): file explorer | editor+terminal | live preview grid.
///  - Mobile: gesture-driven workspace with a bottom nav, a collapsible
///    terminal pill, and a glassmorphic file-explorer drawer.
class MakawIdeWorkspace extends StatefulWidget {
  final StudioProject project;

  const MakawIdeWorkspace({Key? key, required this.project}) : super(key: key);

  @override
  State<MakawIdeWorkspace> createState() => _MakawIdeWorkspaceState();
}

class _MakawIdeWorkspaceState extends State<MakawIdeWorkspace> {
  // State Controllers
  late CodeController _codeController;
  final MakawTerminalEngine _terminalEngine = MakawTerminalEngine();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Workspace Data
  List<File> _projectFiles = [];
  List<File> _openTabs = [];
  File? _activeFile;
  final Set<String> _dirtyPaths = {};
  bool _saving = false;

  // Layout Toggles
  bool _showDesktopTerminal = true;
  bool _showDesktopPreview = true;
  MobileIdeView _currentMobileView = MobileIdeView.editor;
  bool _isPreviewRunning = false;

  // General (non-npm) file preview buffer.
  String _filePreviewHtml = '';

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(text: '');
    _codeController.addListener(_onCodeChanged);
    _initializeWorkspace();
  }

  void _onCodeChanged() {
    final file = _activeFile;
    if (file == null) return;
    final text = _codeController.text;
    if (!_dirtyPaths.contains(file.path)) {
      setState(() => _dirtyPaths.add(file.path));
    } else if (text == (file.existsSync() ? file.readAsStringSync() : '')) {
      if (mounted) setState(() => _dirtyPaths.remove(file.path));
    }
  }

  /// Writes the current editor buffer back to [_activeFile] on disk.
  Future<void> _saveActiveFile() async {
    final file = _activeFile;
    if (file == null) return;
    if (_saving) return;
    _saving = true;
    try {
      await file.writeAsString(_codeController.text, flush: true);
      setState(() => _dirtyPaths.remove(file.path));
    } finally {
      _saving = false;
    }
  }

  /// Saves any dirty open tabs then pops the workspace.
  Future<void> _saveAllAndPop() async {
    for (final f in List<File>.from(_openTabs)) {
      if (!_dirtyPaths.contains(f.path)) continue;
      try {
        await f.writeAsString(_codeController.text, flush: true);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _terminalEngine.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _initializeWorkspace() async {
    // Scaffold a default React/TS/Tailwind environment if the project is empty.
    final files = CodeStudioService.listFiles(widget.project.directory);
    if (files.isEmpty) {
      await CodeStudioService.createFolder(widget.project.directory, 'src/components');
      await CodeStudioService.createFile(widget.project.directory, 'src/App.jsx',
          content:
              'import React, { useState } from "react";\n\nexport default function App() {\n  const [count, setCount] = useState(0);\n  return (\n    <div className="container">\n      <h1>Makaw Studio</h1>\n      <p>Count: {count}</p>\n      <button onClick={() => setCount(count + 1)}>Increment</button>\n    </div>\n  );\n}');
      await CodeStudioService.createFile(widget.project.directory, 'src/index.jsx',
          content:
              'import React from "react";\nimport ReactDOM from "react-dom/client";\nimport App from "./App";\nimport "./styles.css";\n\nReactDOM.createRoot(document.getElementById("root")).render(<App />);');
      await CodeStudioService.createFile(widget.project.directory, 'src/styles.css',
          content: 'body { background: #0F172A; color: white; }');
      await CodeStudioService.createFile(widget.project.directory, 'package.json',
          content: '{\n  "name": "makaw-project",\n  "version": "1.0.0"\n}');
    }
    _loadProjectFiles();
    _terminalEngine.startSession(workingDirectory: widget.project.directory.path);
  }

  void _loadProjectFiles() {
    final files = CodeStudioService.listFiles(widget.project.directory);
    if (!mounted) return;
    setState(() {
      _projectFiles = files;
      if (_openTabs.isEmpty && files.isNotEmpty) {
        _openFileInTab(files.firstWhere(
          (f) => f.path.endsWith('App.jsx'),
          orElse: () => files.first,
        ));
      }
    });
  }

  Future<void> _openFileInTab(File file) async {
    if (!_openTabs.any((f) => f.path == file.path)) {
      _openTabs.add(file);
    }
    await _selectFile(file);
  }

  Future<void> _selectFile(File file) async {
    if (_activeFile?.path == file.path) return;
    // Persist any pending edits to the current tab before switching.
    final current = _activeFile;
    if (current != null && _dirtyPaths.contains(current.path)) {
      try {
        await current.writeAsString(_codeController.text, flush: true);
      } catch (_) {}
    }
    _activeFile = file;
    final content = file.existsSync() ? file.readAsStringSync() : '';
    _codeController.text = content;
    _codeController.language = _resolveLanguage(file.path);
    if (mounted) setState(() => _dirtyPaths.remove(file.path));
  }

  Future<void> _closeTab(File file) async {
    // Persist unsaved edits before closing the tab.
    if (_dirtyPaths.contains(file.path)) {
      try {
        await file.writeAsString(_codeController.text, flush: true);
      } catch (_) {}
    }
    setState(() {
      _dirtyPaths.remove(file.path);
      _openTabs.removeWhere((f) => f.path == file.path);
      if (_activeFile?.path == file.path) {
        if (_openTabs.isNotEmpty) {
          _selectFile(_openTabs.last);
        } else {
          _activeFile = null;
          _codeController.text = '';
        }
      }
    });
  }

  Mode? _resolveLanguage(String path) {
    if (path.endsWith('.jsx') || path.endsWith('.js')) return javascript;
    if (path.endsWith('.tsx') || path.endsWith('.ts')) return typescript;
    if (path.endsWith('.html')) return xml;
    if (path.endsWith('.css')) return css;
    if (path.endsWith('.json')) return javascript;
    if (path.endsWith('.md') || path.endsWith('.txt')) return null;
    return javascript;
  }

  /// Detects the extension from a file name ('' if none).
  String _extOf(String name) {
    final idx = name.lastIndexOf('.');
    if (idx <= 0) return '';
    return name.substring(idx + 1).toLowerCase();
  }

  /// Returns a starter template for a newly-created file based on its extension.
  String _boilerplateFor(String name) {
    final ext = _extOf(name);
    switch (ext) {
      case 'js':
      case 'jsx':
        return '// $name\nfunction main() {\n  console.log("Hello from Makaw Studio!");\n}\n\nmain();\n';
      case 'ts':
      case 'tsx':
        return '// $name\nfunction main(): void {\n  console.log("Hello from Makaw Studio!");\n}\n\nmain();\n';
      case 'dart':
        return '// $name\nvoid main() {\n  print("Hello from Makaw Studio!");\n}\n';
      case 'py':
        return '# $name\ndef main():\n    print("Hello from Makaw Studio!")\n\nif __name__ == "__main__":\n    main()\n';
      case 'css':
        return '/* $name */\nbody {\n  background: #0F172A;\n  color: #E2E8F0;\n}\n';
      case 'html':
        return '<!DOCTYPE html>\n<html>\n<head>\n  <meta charset="utf-8" />\n  <title>$name</title>\n</head>\n<body>\n  <h1>Hello Makaw Studio!</h1>\n</body>\n</html>\n';
      case 'json':
        return '{\n  "name": "$name",\n  "version": "1.0.0"\n}\n';
      case 'md':
        return '# $name\n\n';
      default:
        return '';
    }
  }

  Future<void> _handleCrudAction(String action, FileSystemEntity? entity) async {
    if (action == 'new_file') {
      final name = await _promptInput('New File Name', 'e.g., Component.jsx');
      if (name != null && name.trim().isNotEmpty) {
        final clean = name.trim();
        final boilerplate = _boilerplateFor(clean);
        final newFile = await CodeStudioService.createFile(widget.project.directory, clean, content: boilerplate);
        _loadProjectFiles();
        await _openFileInTab(newFile);
      }
    } else if (action == 'new_folder') {
      final name = await _promptInput('New Folder Name', 'e.g., components');
      if (name != null && name.trim().isNotEmpty) {
        await CodeStudioService.createFolder(widget.project.directory, name.trim());
        _loadProjectFiles();
      }
    } else if (action == 'delete' && entity != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Delete file?', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(
            CodeStudioService.baseName(entity.path),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await CodeStudioService.deleteEntity(entity);
        _openTabs.removeWhere((f) => f.path == entity.path);
        _loadProjectFiles();
      }
    }
  }

  Future<String?> _promptInput(String title, String hint) {
    final controller = TextEditingController();
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
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
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

  bool get _hasPackageJson =>
      File(CodeStudioService.fileIn(widget.project.directory, 'package.json').path)
          .existsSync();

  /// Renders the active plain file (HTML/JS/CSS) into a self-contained HTML
  /// document that can be displayed without a dev server.
  void _buildPlainPreview() {
    final file = _activeFile;
    if (file == null) return;
    final lower = file.path.toLowerCase();
    final content = file.existsSync() ? file.readAsStringSync() : '';
    String html;
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      html = content;
    } else if (lower.endsWith('.css')) {
      html = '<!DOCTYPE html><html><head><meta charset="utf-8"><style>$content</style></head>'
          '<body><h1>CSS Preview</h1><p>Your stylesheet is applied to this page.</p></body></html>';
    } else if (lower.endsWith('.js') || lower.endsWith('.mjs') || lower.endsWith('.jsx') ||
        lower.endsWith('.ts') || lower.endsWith('.tsx')) {
      html = '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>'
          '<div id="root"></div><script>$content</script></body></html>';
    } else {
      // Fallback: show the raw content.
      final esc = content.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
      html = '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>'
          '<pre style="font-family:monospace;white-space:pre-wrap">$esc</pre></body></html>';
    }
    _filePreviewHtml = html;
  }

  void _togglePreviewServer() {
    setState(() {
      _isPreviewRunning = !_isPreviewRunning;
      if (_isPreviewRunning) {
        if (_hasPackageJson) {
          // Real dev server for npm projects.
          _terminalEngine.writeCommand('npm run dev\n');
        } else {
          // Plain files: render an in-memory HTML snapshot.
          _buildPlainPreview();
        }
      } else {
        if (_hasPackageJson) {
          _terminalEngine.writeRaw('\x03'); // Ctrl+C
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _saveAllAndPop();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFF0B1121),
        drawer: isDesktop ? null : _buildMobileGlassExplorer(),
        body: SafeArea(
          child: Column(
            children: [
              _buildGlobalHeader(isDesktop),
              Expanded(
                child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: isDesktop ? null : _buildMobileBottomNav(),
      ),
    );
  }

  // --- 1. GLOBAL HEADER ---
  Widget _buildGlobalHeader(bool isDesktop) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.8),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(8)),
            child: const Center(child: Text('M', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))),
          ),
          const SizedBox(width: 12),
          const Text('Makaw', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          const Text('Code Studio Hub', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 14)),
          const Spacer(),
          if (isDesktop) ...[
            Container(
              width: 300,
              height: 36,
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(18)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: const [
                  Icon(Icons.search, color: Colors.white54, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Search files or commands...', style: TextStyle(color: Colors.white38, fontSize: 13))),
                  Text('⌘K', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Row(
              children: const [
                Icon(Icons.share, color: Color(0xFF8B5CF6), size: 18),
                SizedBox(width: 6),
                Text('main', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(width: 24),
            const Icon(Icons.notifications_none, color: Colors.white),
            const SizedBox(width: 16),
            const CircleAvatar(backgroundColor: Color(0xFF8B5CF6), radius: 16, child: Text('SF', style: TextStyle(color: Colors.white, fontSize: 12))),
          ] else ...[
            const CircleAvatar(backgroundColor: Color(0xFF8B5CF6), radius: 16, child: Icon(Icons.person, color: Colors.white, size: 18)),
          ]
        ],
      ),
    );
  }

  // --- 2. DESKTOP LAYOUT (3-Pane Grid) ---
  Widget _buildDesktopLayout() {
    return Column(
      children: [
        // Desktop Toolbar
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDesktopToolbarButton('Editor', Icons.code, true, () {}),
              _buildDesktopToolbarButton('Terminal', Icons.terminal, _showDesktopTerminal, () => setState(() => _showDesktopTerminal = !_showDesktopTerminal)),
              _buildDesktopToolbarButton('Git', Icons.share, false, () {}),
              _buildDesktopToolbarButton('Preview', Icons.visibility, _showDesktopPreview, () => setState(() => _showDesktopPreview = !_showDesktopPreview)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Explorer
              SizedBox(width: 260, child: _buildFileExplorer()),
              // Middle: Editor & Terminal
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Expanded(flex: 7, child: _buildEditorCanvas()),
                    if (_showDesktopTerminal)
                      Expanded(flex: 3, child: _buildTerminalPane()),
                  ],
                ),
              ),
              // Right: Live Preview
              if (_showDesktopPreview)
                Expanded(flex: 4, child: _buildPreviewPane()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopToolbarButton(String title, IconData icon, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF3B82F6) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // --- 3. MOBILE LAYOUT (Stacked & Gesture Driven) ---
  Widget _buildMobileLayout() {
    return Stack(
      children: [
        // Base Layer: Editor Canvas
        Column(
          children: [
            _buildEditorTabs(),
            Expanded(child: _buildEditorCanvas()),
          ],
        ),

        // Overlay Layer 1: Collapsed Terminal Pill (if not actively in terminal view)
        if (_currentMobileView != MobileIdeView.terminal)
          Positioned(
            bottom: 80,
            left: 16,
            right: 16,
            child: GestureDetector(
              onTap: () => setState(() => _currentMobileView = MobileIdeView.terminal),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: const [
                    Icon(Icons.terminal, color: Color(0xFF60A5FA), size: 18),
                    SizedBox(width: 12),
                    Text('Terminal • zsh — collapsed', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Spacer(),
                    Icon(Icons.keyboard_arrow_up, color: Colors.white54),
                  ],
                ),
              ),
            ),
          ),

        // Overlay Layer 2: Full Screen Terminal / Preview
        if (_currentMobileView == MobileIdeView.terminal)
          Positioned.fill(
            child: Container(color: const Color(0xFF0F172A), child: _buildTerminalPane()),
          ),
        if (_currentMobileView == MobileIdeView.preview)
          Positioned.fill(
            child: Container(color: const Color(0xFF0F172A), child: _buildPreviewPane()),
          ),
      ],
    );
  }

  Widget _buildMobileBottomNav() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMobileNavIcon(MobileIdeView.editor, Icons.code, 'Editor'),
          _buildMobileNavIcon(MobileIdeView.terminal, Icons.terminal, 'Terminal'),
          _buildMobileNavIcon(MobileIdeView.preview, Icons.visibility, 'Preview'),
          _buildMobileNavIcon(MobileIdeView.git, Icons.share, 'Git'),
        ],
      ),
    );
  }

  Widget _buildMobileNavIcon(MobileIdeView view, IconData icon, String label) {
    final isActive = _currentMobileView == view;
    return InkWell(
      onTap: () => setState(() => _currentMobileView = view),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: isActive ? const Color(0xFF8B5CF6) : Colors.white54, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- 4. FILE EXPLORER (Shared, but Glassmorphic on Mobile) ---
  Widget _buildFileExplorer() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('EXPLORER', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    InkWell(onTap: () => _handleCrudAction('new_file', null), child: const Icon(Icons.note_add_outlined, size: 16, color: Colors.white70)),
                    const SizedBox(width: 12),
                    InkWell(onTap: () => _handleCrudAction('new_folder', null), child: const Icon(Icons.create_new_folder_outlined, size: 16, color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _projectFiles.isEmpty
                ? const Center(
                    child: Text('No files yet', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  )
                : ListView.builder(
                    itemCount: _projectFiles.length,
                    itemBuilder: (context, index) {
                      final file = _projectFiles[index];
                      final name = file.path.split(Platform.pathSeparator).last;
                      final isSelected = _activeFile?.path == file.path;

                      return InkWell(
                        onTap: () => _openFileInTab(file),
                        onLongPress: () => _handleCrudAction('delete', file),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          color: isSelected ? const Color(0xFF3B82F6).withOpacity(0.2) : Colors.transparent,
                          child: Row(
                            children: [
                              Icon(_getFileIcon(name), size: 14, color: isSelected ? const Color(0xFF60A5FA) : Colors.white70),
                              const SizedBox(width: 8),
                              Expanded(child: Text(name, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileGlassExplorer() {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.7),
            border: Border(right: BorderSide(color: Colors.white.withOpacity(0.1))),
          ),
          child: SafeArea(child: _buildFileExplorer()),
        ),
      ),
    );
  }

  // --- 5. EDITOR CANVAS & TABS ---
  Widget _buildEditorTabs() {
    return Container(
      height: 44,
      color: const Color(0xFF0B1121),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _openTabs.length,
              itemBuilder: (context, index) {
                final file = _openTabs[index];
                final name = file.path.split(Platform.pathSeparator).last;
                final isSelected = _activeFile?.path == file.path;
                final isDirty = _dirtyPaths.contains(file.path);

                return GestureDetector(
                  onTap: () => _selectFile(file),
                  child: Container(
                    margin: const EdgeInsets.only(top: 6, right: 4, left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF1E293B),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: Row(
                      children: [
                        if (isDirty) ...[
                          const Icon(Icons.circle, size: 8, color: Color(0xFFFBBF24)),
                          const SizedBox(width: 6),
                        ],
                        Text(name, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _closeTab(file),
                          child: const Icon(Icons.close, size: 14, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Save active file
          IconButton(
            icon: Icon(
              _dirtyPaths.contains(_activeFile?.path)
                  ? Icons.save_rounded
                  : Icons.save_outlined,
              color: _dirtyPaths.contains(_activeFile?.path) ? const Color(0xFFFBBF24) : Colors.white54,
              size: 18,
            ),
            tooltip: 'Save (Ctrl+S)',
            onPressed: _saveActiveFile,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white54, size: 18),
            onPressed: () => _handleCrudAction('new_file', null),
            tooltip: 'New file',
          ),
        ],
      ),
    );
  }

  Widget _buildEditorCanvas() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          if (MediaQuery.of(context).size.width >= 900) _buildEditorTabs(),
          Expanded(
            child: CodeTheme(
              data: CodeThemeData(styles: monokaiSublimeTheme),
              child: SingleChildScrollView(
                child: CodeField(
                  controller: _codeController,
                  gutterStyle: const GutterStyle(showLineNumbers: true, textStyle: TextStyle(color: Colors.white38, fontSize: 13), margin: 16),
                  textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.5),
                ),
              ),
            ),
          ),
          // Bottom Status Bar
          Container(
            height: 24,
            color: const Color(0xFF3B82F6),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Icon(Icons.check, size: 12, color: Colors.white),
                SizedBox(width: 4),
                Text('HTML | UTF-8 | spaces:2 | CRLF | Prettier', style: TextStyle(color: Colors.white, fontSize: 10)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- 6. TERMINAL PANE ---
  Widget _buildTerminalPane() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: const Color(0xFF1E293B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TERMINAL  zsh — npm run dev', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                if (_currentMobileView == MobileIdeView.terminal)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                    onPressed: () => setState(() => _currentMobileView = MobileIdeView.editor),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TerminalView(_terminalEngine.terminal, autofocus: false, backgroundOpacity: 0.0),
          ),
        ],
      ),
    );
  }

  // --- 7. PREVIEW PANE ---
  Widget _buildPreviewPane() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      margin: const EdgeInsets.all(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Browser Header
          Container(
            height: 44,
            color: const Color(0xFF1E293B),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Icon(Icons.arrow_back, color: Colors.white54, size: 16),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, color: Colors.white24, size: 16),
                const SizedBox(width: 8),
                const Icon(Icons.refresh, color: Colors.white54, size: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock, size: 12, color: Colors.white54),
                        const SizedBox(width: 6),
                        Text(
                          _isPreviewRunning && !_hasPackageJson
                              ? 'Streaming Preview — ${_activeFile?.path.split(Platform.pathSeparator).last ?? ''}'
                              : 'localhost:5173',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(_isPreviewRunning ? Icons.stop : Icons.play_arrow, color: _isPreviewRunning ? Colors.redAccent : Colors.greenAccent, size: 18),
                  onPressed: _togglePreviewServer,
                ),
              ],
            ),
          ),
          // Web Viewport
          Expanded(
            child: _isPreviewRunning
                ? InAppWebView(
                    initialUrlRequest: _hasPackageJson
                        ? URLRequest(url: WebUri('http://localhost:5173'))
                        : null,
                    initialData: !_hasPackageJson
                        ? InAppWebViewInitialData(data: _filePreviewHtml, mimeType: 'text/html')
                        : null,
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.web, size: 48, color: Colors.black26),
                        const SizedBox(height: 12),
                        const Text('Preview Server Offline', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                        TextButton(onPressed: _togglePreviewServer, child: const Text('Start preview')),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String name) {
    if (name.endsWith('.jsx') || name.endsWith('.js')) return Icons.javascript;
    if (name.endsWith('.tsx') || name.endsWith('.ts')) return Icons.code;
    if (name.endsWith('.css')) return Icons.css;
    if (name.endsWith('.json')) return Icons.data_object;
    if (name.endsWith('.md')) return Icons.description;
    return Icons.insert_drive_file_outlined;
  }
}
