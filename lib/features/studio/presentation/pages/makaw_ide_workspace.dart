import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../data/github_service.dart';
import '../../data/ide_settings.dart';
import '../../data/integration_helpers.dart';
import '../../data/studio_project.dart';
import '../../data/terminal_engine.dart';
import '../../data/git_service.dart';
import '../widgets/project_tree_view.dart';
import '../widgets/source_control_panel.dart';
import '../../../../core/widgets/widgets.dart';

/// Defines the active mobile view (editor / terminal / preview).
enum MobileIdeView { editor, terminal, preview }

/// Desktop left-panel mode.
enum _LeftPanelMode { explorer, sourceControl }

/// Divider marker used in pane-header menu action lists.
class _PaneDivider {
  const _PaneDivider();
}

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
  late StudioProject _project;
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

  // Desktop left-panel mode (Explorer / Source Control).
  _LeftPanelMode _leftPanelMode = _LeftPanelMode.explorer;
  final GlobalKey<ProjectTreeViewState> _treeKey = GlobalKey<ProjectTreeViewState>();
  final GlobalKey<SourceControlPanelState> _sourceControlKey = GlobalKey<SourceControlPanelState>();

  // VS Code-style status-bar git info.
  String _branch = '';
  String _aheadBehind = '';

  // General (non-npm) file preview buffer.
  String _filePreviewHtml = '';
  InAppWebViewController? _webController;

  // Persisted IDE settings + panel geometry.
  IdeSettings _settings = IdeSettings();
  double _leftPanelWidth = 260;
  double _terminalHeightFraction = 0.3;
  double _previewWidth = 360;
  bool _showLeftPanel = true;

  // Movable panel placement (VS Code style): terminal + preview can live on
  // the side or at the bottom; the bottom area can hold the terminal,
  // the preview, or both (stacked via a shared split).
  bool _terminalOnBottom = true;
  bool _previewOnBottom = false;
  double _terminalSideWidth = 300;
  double _bottomAreaFraction = 0.3;
  double _bottomShareTerminal = 0.5;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _codeController = CodeController(text: '');
    _codeController.addListener(_onCodeChanged);
    _initializeWorkspace();
    _loadGitInfo();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await IdeSettingsStore.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _leftPanelWidth = s.leftPanelWidth;
      _terminalHeightFraction = s.terminalHeightFraction;
      _previewWidth = s.previewWidth;
      _showLeftPanel = s.showLeftPanel;
      _showDesktopTerminal = s.showTerminal;
      _showDesktopPreview = s.showPreview;
      _terminalOnBottom = s.terminalOnBottom;
      _previewOnBottom = s.previewOnBottom;
      _terminalSideWidth = s.terminalSideWidth;
      _bottomAreaFraction = s.bottomAreaFraction;
      _bottomShareTerminal = s.bottomShareTerminal;
    });
  }

  Future<void> _persistSettings() async {
    _settings
      ..leftPanelWidth = _leftPanelWidth
      ..terminalHeightFraction = _terminalHeightFraction
      ..previewWidth = _previewWidth
      ..showLeftPanel = _showLeftPanel
      ..showTerminal = _showDesktopTerminal
      ..showPreview = _showDesktopPreview
      ..terminalOnBottom = _terminalOnBottom
      ..previewOnBottom = _previewOnBottom
      ..terminalSideWidth = _terminalSideWidth
      ..bottomAreaFraction = _bottomAreaFraction
      ..bottomShareTerminal = _bottomShareTerminal;
    await IdeSettingsStore.save(_settings);
  }

  Future<void> _loadGitInfo() async {
    try {
      final git = GitService(_project.directory);
      if (!git.isRepo) return;
      final st = await git.status();
      if (!mounted) return;
      setState(() {
        _branch = st.branch;
        _aheadBehind = st.aheadBehind;
      });
    } catch (_) {}
  }

  void _onCodeChanged() {
    final file = _activeFile;
    if (file == null) return;
    final text = _codeController.text;
    if (!_dirtyPaths.contains(file.path)) {
      if (!_isBinaryFile(file.path)) setState(() => _dirtyPaths.add(file.path));
    } else if (text == _readFileSafe(file)) {
      if (mounted) setState(() => _dirtyPaths.remove(file.path));
    }
  }

  bool _isBinaryFile(String path) {
    final lower = path.toLowerCase();
    final idx = lower.lastIndexOf('.');
    if (idx < 0) return false;
    const binaryExts = {
      'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'svg', 'pdf',
      'zip', 'gz', '7z', 'rar', 'tar', 'exe', 'dll', 'so', 'bin', 'iso',
      'mp3', 'mp4', 'wav', 'ogg', 'mov', 'avi', 'mkv', 'woff', 'woff2',
      'ttf', 'otf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'pub',
      'epub', 'mobi', 'azw', 'azw3', 'kfx', 'fb2', 'apk', 'db', 'sqlite',
      'sqlite3', 'wasm', 'class', 'jar',
    };
    return binaryExts.contains(lower.substring(idx + 1));
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
    _webController = null;
    super.dispose();
  }

  Future<void> _initializeWorkspace() async {
    _loadProjectFiles();
    _terminalEngine.startSession(workingDirectory: _project.directory.path);
  }

  /// Switches the in-memory project to [dir] (Open Folder / Open Recent /
  /// freshly-cloned repo) and re-initializes all workspace state.
  Future<void> _switchProject(Directory dir) async {
    if (!dir.existsSync()) {
      _showIdeToast('Folder not found: ${dir.path}');
      return;
    }
    setState(() {
      _project = StudioProject(dir);
      _projectFiles = [];
      _openTabs = [];
      _activeFile = null;
      _dirtyPaths.clear();
      _codeController.text = '';
      _filePreviewHtml = '';
      _isPreviewRunning = false;
      _branch = '';
      _aheadBehind = '';
    });
    _settings.rememberFolder(dir.path);
    await _persistSettings();
    _terminalEngine.startSession(workingDirectory: dir.path);
    _loadGitInfo();
    _loadProjectFiles();
    _refreshAfterFsChanged();
    await IntegrationHelpers.applyGitIdentity(
        dir, _settings.gitName, _settings.gitEmail);
    _showIdeToast('Opened ${dir.path.split(Platform.pathSeparator).last}');
  }

  /// "Open Folder…" — native directory picker, then switches the workspace.
  Future<void> _openFolderFromPicker() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Open Folder in Code Studio');
      if (path == null || path.isEmpty) return;
      await _switchProject(Directory(path));
    } catch (e) {
      _showIdeToast('Could not open folder: $e');
    }
  }

  Future<void> _openRecentFolder(String path) async {
    if (path.isEmpty) return;
    await _switchProject(Directory(path));
  }

  void _refreshAfterFsChanged() {
    _treeKey.currentState?.refresh();
    _sourceControlKey.currentState?.refresh();
    _loadProjectFiles();
  }

  void _loadProjectFiles() {
    final files = CodeStudioService.listFiles(_project.directory);
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
    final content = _readFileSafe(file);
    _codeController.text = content;
    _codeController.language = _resolveLanguage(file.path);
    if (mounted) setState(() => _dirtyPaths.remove(file.path));
  }

  /// Reads [file] as UTF-8 text. Binary files (images, archives, etc.) fail
  /// to decode; in that case a short notice is returned so the editor does
  /// not crash and the file can still be opened in its native app.
  String _readFileSafe(File file) {
    if (!file.existsSync()) return '';
    if (_isBinaryFile(file.path)) {
      return '// ${file.path.split(Platform.pathSeparator).last} is a binary '
          'file and cannot be edited as text.\n\n'
          'Use Reveal in Explorer or open it in Makaw (reader / viewer / editor) '
          'instead.\n';
    }
    try {
      return file.readAsStringSync();
    } catch (_) {
      return '// ${file.path.split(Platform.pathSeparator).last} could not be '
          'read as text (binary or locked file).\n';
    }
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
        final newFile = await CodeStudioService.createFile(_project.directory, clean, content: boilerplate);
        _refreshAfterFsChanged();
        await _openFileInTab(newFile);
      }
    } else if (action == 'new_folder') {
      final name = await _promptInput('New Folder Name', 'e.g., components');
      if (name != null && name.trim().isNotEmpty) {
        await CodeStudioService.createFolder(_project.directory, name.trim());
        _refreshAfterFsChanged();
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
        _refreshAfterFsChanged();
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
      File(CodeStudioService.fileIn(_project.directory, 'package.json').path)
          .existsSync();

  /// Renders the active plain file (HTML/JS/CSS) into a self-contained HTML
  /// document that can be displayed without a dev server.
  void _buildPlainPreview() {
    final file = _activeFile;
    if (file == null) return;
    final lower = file.path.toLowerCase();
    final content = _readFileSafe(file);
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
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _saveActiveFile(),
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => _saveActiveFile(),
              const SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true): () => _showCommandPalette(goToFile: false),
              const SingleActivator(LogicalKeyboardKey.keyP, control: true): () => _showCommandPalette(goToFile: true),
              const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _closeActiveTab(),
              const SingleActivator(LogicalKeyboardKey.tab, control: true): () => _nextEditorTab(),
              const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () => _prevEditorTab(),
            },
            child: Column(
              children: [
                _buildGlobalHeader(isDesktop),
                if (isDesktop) _buildMenuBar(),
                Expanded(
                  child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
                ),
              ],
            ),
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
          if (isDesktop)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: 'Back',
              onPressed: _saveAllAndPop,
            )
          else
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
          if (isDesktop)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Open Folder',
                  child: InkWell(
                    onTap: _openFolderFromPicker,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.folder_open, color: Color(0xFF60A5FA), size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_project.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
        ],
      ),
    );
  }

  /// VS Code-style menu bar: File / View / Terminal / Integrations.
  Widget _buildMenuBar() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          _menuButton('File', [
            ('New File', Icons.note_add_outlined, () => _handleCrudAction('new_file', null)),
            ('New Folder', Icons.create_new_folder_outlined, () => _handleCrudAction('new_folder', null)),
            ('Open Folder…', Icons.folder_open, _openFolderFromPicker),
            ('Open Recent', Icons.history, _openRecentMenu),
            ('Save', Icons.save_outlined, _saveActiveFile),
            ('Save All & Close', Icons.save_alt, _saveAllAndPop),
          ]),
          _menuButton('View', [
            ('Toggle Explorer', Icons.folder_outlined, () => setState(() {
                  _showLeftPanel = !_showLeftPanel;
                  _persistSettings();
                })),
            ('Toggle Terminal', Icons.terminal, () => setState(() {
                  _showDesktopTerminal = !_showDesktopTerminal;
                  _persistSettings();
                })),
            ('Toggle Live Preview', Icons.visibility, () => setState(() {
                  _showDesktopPreview = !_showDesktopPreview;
                  _persistSettings();
                })),
            ('Command Palette…', Icons.search, () => _showCommandPalette(goToFile: false)),
          ]),
          _menuButton('Terminal', [
            ('New Terminal', Icons.terminal, _openNewTerminal),
            ('Restart Shell', Icons.restart_alt, _restartTerminal),
            ('Clear Terminal', Icons.delete_outline, _terminalEngine.clearDisplay),
            ('Interrupt (Ctrl+C)', Icons.stop, _terminalEngine.interrupt),
          ]),
          _menuButton('Integrations', [
            ('GitHub…', Icons.cloud, _showIntegrationsDialog),
            ('Clone Repository…', Icons.content_copy, _showGitHubCloneDialog),
            ('Settings…', Icons.settings_outlined, _showSettingsDialog),
          ]),
        ],
      ),
    );
  }

  Widget _menuButton(String label, List<(String, IconData, VoidCallback)> items) {
    return PopupMenuButton<String>(
      tooltip: label,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (v) {
        final idx = int.tryParse(v);
        if (idx != null && idx >= 0 && idx < items.length) items[idx].$3();
      },
      itemBuilder: (ctx) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<String>(
            value: '$i',
            child: Row(
              children: [
                Icon(items[i].$2, size: 16, color: Colors.white70),
                const SizedBox(width: 10),
                Text(items[i].$1, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
      ],
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ),
    );
  }

  /// Shows the recent-folders flyout (Open Recent) as a menu.
  void _openRecentMenu() {
    final ctx = context;
    final anchors = ctx.findRenderObject() as RenderBox?;
    if (anchors == null) return;
    if (_settings.recentFolders.isEmpty) {
      _showIdeToast('No recent folders');
      return;
    }
    showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(180, 96, 0, 0),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        for (final p in _settings.recentFolders)
          PopupMenuItem<String>(
            value: p,
            child: SizedBox(
              width: 320,
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 15, color: Colors.white54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.split(Platform.pathSeparator).last,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(p, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
          ),
      ],
    ).then((v) {
      if (v != null) _openRecentFolder(v);
    });
  }

  void _restartTerminal() {
    _terminalEngine.startSession(workingDirectory: _project.directory.path);
  }

  void _openNewTerminal() {
    _terminalEngine.startSession(workingDirectory: _project.directory.path);
    if (!_showDesktopTerminal) setState(() => _showDesktopTerminal = true);
    if (_currentMobileView == MobileIdeView.editor) {
      setState(() => _currentMobileView = MobileIdeView.terminal);
    }
  }

  /// A compact OverflowMenu-style control for a pane header.
  /// [actions] items are either `(String, IconData, VoidCallback)` records or
  /// a [_PaneDivider].
  Widget _buildPaneHeaderMenu({
    required IconData icon,
    required String tooltip,
    required List<Object> actions,
  }) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      icon: Icon(icon, size: 16, color: Colors.white54),
      padding: const EdgeInsets.all(4),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (v) {
        final idx = int.tryParse(v);
        if (idx == null || idx < 0 || idx >= actions.length) return;
        final entry = actions[idx];
        final rec = entry;
        if (rec is (String, IconData, VoidCallback)) rec.$3();
      },
      itemBuilder: (ctx) => [
        for (var i = 0; i < actions.length; i++)
          if (actions[i] is _PaneDivider)
            const PopupMenuDivider(height: 8)
          else
            PopupMenuItem<String>(
              value: '$i',
              child: Row(children: [
                Icon((actions[i] as (String, IconData, VoidCallback)).$2, size: 15, color: Colors.white70),
                const SizedBox(width: 10),
                Text((actions[i] as (String, IconData, VoidCallback)).$1,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ]),
            ),
      ],
    );
  }

  /// Lists installed WSL distros and starts a WSL shell in the terminal.
  Future<void> _openWslShellDialog() async {
    final distros = await IntegrationHelpers.wslDistros();
    if (distros.isEmpty) {
      _showIdeToast('No WSL distros found');
      return;
    }
    final distro = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose WSL distro', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF16263F),
        children: [
          for (final d in distros)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text(d, style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
    if (distro == null || distro.isEmpty) return;
    setState(() => _settings.wslDistro = distro);
    await _persistSettings();
    _terminalEngine.startSession(
      workingDirectory: _project.directory.path,
      executable: 'wsl.exe',
      arguments: ['-d', distro, '--', 'bash', '-i'],
    );
    if (!_showDesktopTerminal) setState(() => _showDesktopTerminal = true);
  }

  /// Connects the integrated terminal to a configured SSH remote.
  Future<void> _openSshShellDialog() async {
    if (_settings.remoteHosts.isEmpty) {
      _showIdeToast('No remote hosts configured — add one in Integrations');
      _showIntegrationsDialog();
      return;
    }
    final host = await showDialog<RemoteHost>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Connect to remote', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF16263F),
        children: [
          for (final h in _settings.remoteHosts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, h),
              child: Text('${h.user}@${h.host}:${h.port}',
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
    if (host == null) return;
    _terminalEngine.startSession(
      workingDirectory: _project.directory.path,
      executable: 'ssh',
      arguments: ['-tt', '-p', host.port, host.target],
    );
    if (!_showDesktopTerminal) setState(() => _showDesktopTerminal = true);
  }

  /// Attaches the integrated terminal to a running Docker container.
  Future<void> _openDockerAttachDialog() async {
    final containers = await IntegrationHelpers.dockerContainers();
    if (containers.isEmpty) {
      _showIdeToast('No running Docker containers found');
      return;
    }
    final selected = await showDialog<({String id, String name, String image})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Attach to container', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF16263F),
        children: [
          for (final c in containers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Text('${c.name} (${c.image})',
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
    if (selected == null) return;
    _terminalEngine.writeCommand('docker exec -it ${selected.id} sh\n');
    if (!_showDesktopTerminal) setState(() => _showDesktopTerminal = true);
  }

  /// Integrations dialog: Git identity, GitHub token, remote hosts, WSL,
  /// Docker — the "accounts & connections" surface for the IDE.
  Future<void> _showIntegrationsDialog() async {
    final nameCtrl = TextEditingController(text: _settings.gitName);
    final emailCtrl = TextEditingController(text: _settings.gitEmail);
    final tokenCtrl = TextEditingController(text: _settings.githubToken);
    String? login;
    if (_settings.githubToken.isNotEmpty) {
      login = await GitHubService(_settings.githubToken).verifyToken();
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> verifyToken() async {
            final svc = GitHubService(tokenCtrl.text.trim());
            final result = await svc.verifyToken();
            if (!ctx.mounted) return;
            setDialogState(() => login = result);
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF16263F),
            insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
            title: const Text('Integrations & Accounts',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogSection('Git Identity'),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _dialogInput('user.name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _dialogInput('user.email'),
                    ),
                    const SizedBox(height: 16),
                    _dialogSection('GitHub'),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: tokenCtrl,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: _dialogInput('Personal access token'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: verifyToken,
                        child: const Text('Verify', style: TextStyle(color: Color(0xFF60A5FA))),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      login != null
                          ? 'Authenticated as $login'
                          : (_settings.githubToken.isNotEmpty && login == null
                              ? 'Token could not be verified'
                              : 'Not signed in'),
                      style: TextStyle(
                          color: login != null ? const Color(0xFF4ADE80) : Colors.white38,
                          fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    _dialogSection('Remote Hosts'),
                    for (final h in _settings.remoteHosts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          const Icon(Icons.router, size: 14, color: Colors.white54),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${h.name} — ${h.user}@${h.host}:${h.port}',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                            tooltip: 'Remove',
                            onPressed: () => setDialogState(() {
                              _settings.remoteHosts.removeWhere((x) => x.name == h.name);
                            }),
                          ),
                        ]),
                      ),
                    TextButton.icon(
                      onPressed: () => _addRemoteHost(ctx,
                          onAdded: () => setDialogState(() {})),
                      icon: const Icon(Icons.add, size: 15, color: Color(0xFF60A5FA)),
                      label: const Text('Add remote host', style: TextStyle(color: Color(0xFF60A5FA))),
                    ),
                    const SizedBox(height: 16),
                    _dialogSection('Local Tooling'),
                    FutureBuilder<IntegrationAvailable>(
                      future: IntegrationHelpers.wslAvailable(),
                      builder: (ctx, snap) {
                        final ok = snap.data?.ok ?? false;
                        return _integrityRow('WSL', ok, snap.data?.detail);
                      },
                    ),
                    FutureBuilder<IntegrationAvailable>(
                      future: IntegrationHelpers.dockerAvailable(),
                      builder: (ctx, snap) {
                        final ok = snap.data?.ok ?? false;
                        return _integrityRow('Docker', ok, snap.data?.detail);
                      },
                    ),
                    FutureBuilder<IntegrationAvailable>(
                      future: IntegrationHelpers.sshAvailable(),
                      builder: (ctx, snap) {
                        final ok = snap.data?.ok ?? false;
                        return _integrityRow('SSH', ok, snap.data?.detail);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _settings.gitName = nameCtrl.text.trim();
                    _settings.gitEmail = emailCtrl.text.trim();
                    _settings.githubToken = tokenCtrl.text.trim();
                  });
                  Navigator.pop(ctx);
                  _persistSettings();
                  IntegrationHelpers.applyGitIdentity(
                      _project.directory, _settings.gitName, _settings.gitEmail);
                  _showIdeToast('Integrations saved');
                },
                child: const Text('Save', style: TextStyle(color: Color(0xFF60A5FA))),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogSection(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title,
            style: const TextStyle(
                color: Color(0xFF60A5FA),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6)),
      );

  InputDecoration _dialogInput(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );

  Widget _integrityRow(String name, bool ok, String? detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.error_outline, size: 15, color: ok ? const Color(0xFF4ADE80) : const Color(0xFFF87171)),
        const SizedBox(width: 8),
        Text(name, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(detail ?? (ok ? 'Ready' : 'Not available'),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
        if (name == 'Docker' && ok)
          InkWell(
            onTap: _openDockerAttachDialog,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Text('Attach', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12)),
            ),
          ),
      ]),
    );
  }

  void _addRemoteHost(BuildContext dialogCtx, {VoidCallback? onAdded}) {
    final nameCtrl = TextEditingController();
    final hostCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '22');
    showDialog<void>(
      context: dialogCtx,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16263F),
        title: const Text('Add remote host', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: _dialogInput('Name (e.g. prod-server)')),
              const SizedBox(height: 8),
              TextField(controller: hostCtrl, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: _dialogInput('Host (e.g. 192.168.1.10)')),
              const SizedBox(height: 8),
              TextField(controller: userCtrl, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: _dialogInput('User (e.g. ubuntu)')),
              const SizedBox(height: 8),
              TextField(controller: portCtrl, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: _dialogInput('Port (22)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              final h = RemoteHost(
                name: nameCtrl.text.trim(),
                host: hostCtrl.text.trim(),
                user: userCtrl.text.trim(),
                port: portCtrl.text.trim().isEmpty ? '22' : portCtrl.text.trim(),
              );
              if (h.name.isNotEmpty && h.host.isNotEmpty && h.user.isNotEmpty) {
                _settings.remoteHosts.removeWhere((x) => x.name == h.name);
                _settings.remoteHosts.add(h);
              }
              Navigator.pop(ctx);
              onAdded?.call();
              _persistSettings();
            },
            child: const Text('Add', style: TextStyle(color: Color(0xFF60A5FA))),
          ),
        ],
      ),
    );
  }

  /// GitHub clone flow: search the configured account, pick a repo and a
  /// destination folder, then `git clone` into it and open it.
  Future<void> _showGitHubCloneDialog() async {
    if (_settings.githubToken.isEmpty) {
      _showIdeToast('Add a GitHub token first in Integrations');
      _showIntegrationsDialog();
      return;
    }
    final svc = GitHubService(_settings.githubToken);
    final queryCtrl = TextEditingController();
    List<GitHubRepo> results = [];
    bool cloning = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> doSearch() async {
            if (queryCtrl.text.trim().isEmpty) return;
            final r = await svc.search(queryCtrl.text);
            setDialogState(() => results = r);
          }

          Future<void> doClone(GitHubRepo repo) async {
            final dest = await FilePicker.platform.getDirectoryPath(
                dialogTitle: 'Choose where to clone ${repo.owner}/${repo.name}');
            if (dest == null || dest.isEmpty) return;
            setDialogState(() => cloning = true);
            final target = '${dest}${Platform.pathSeparator}${repo.name}';
            final out = await Process.run(
              'git',
              ['clone', '--depth', '1', svc.cloneUrl(repo), target],
            );
            if (!ctx.mounted) return;
            setDialogState(() => cloning = false);
            Navigator.pop(ctx);
            if (out.exitCode == 0) {
              await _switchProject(Directory(target));
            } else {
              _showIdeToast('Clone failed: ${(out.stderr as String).trim()}');
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF16263F),
            insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
            title: const Text('Clone Repository', style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 520,
              height: 460,
              child: Column(
                children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: queryCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _dialogInput('Search GitHub repositories…'),
                        onSubmitted: (_) => doSearch(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(onPressed: doSearch, child: const Text('Search', style: TextStyle(color: Color(0xFF60A5FA)))),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: cloning
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF60A5FA)))
                        : results.isEmpty
                            ? const Center(child: Text('No repositories yet — search above',
                                style: TextStyle(color: Colors.white38, fontSize: 13)))
                            : ListView.builder(
                                itemCount: results.length,
                                itemBuilder: (ctx, i) {
                                  final r = results[i];
                                  return InkWell(
                                    onTap: () => doClone(r),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                      child: Row(children: [
                                        const Icon(Icons.storage, size: 15, color: Colors.white54),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text('${r.owner}/${r.name}',
                                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                            if (r.description != null)
                                              Text(r.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                          ]),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(Icons.cloud_download_outlined, size: 16, color: const Color(0xFF60A5FA)),
                                        const SizedBox(width: 8),
                                        Text('${r.stars}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Colors.white54))),
            ],
          );
        },
      ),
    );
  }

  /// Settings dialog — alias for the integrations surface for now.
  Future<void> _showSettingsDialog() async => _showIntegrationsDialog();

  // --- 2. DESKTOP LAYOUT (3-Pane Grid) ---
  Widget _buildDesktopLayout() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final totalW = constraints.maxWidth;
        final totalH = constraints.maxHeight;
        if (totalW <= 0 || totalH <= 0) return const SizedBox();

        // Left panel (collapsible + draggable width).
        final leftW =
            _showLeftPanel ? _clampW(_leftPanelWidth, 160, totalW * 0.45) : 0.0;

        // Terminal placement.
        final terminalOnSide = _showDesktopTerminal && !_terminalOnBottom;
        final terminalOnBottom = _showDesktopTerminal && _terminalOnBottom;
        final previewOnSide = _showDesktopPreview && !_previewOnBottom;
        final previewOnBottom = _showDesktopPreview && _previewOnBottom;

        // Side panels take fixed widths; bottom panels take a fraction of the
        // total height.
        final terminalSideW = terminalOnSide
            ? _clampW(_terminalSideWidth, 200, totalW * 0.35)
            : 0.0;
        final previewSideW =
            previewOnSide ? _clampW(_previewWidth, 240, totalW * 0.45) : 0.0;
        final bottomAreaH = (terminalOnBottom || previewOnBottom)
            ? _bottomAreaFraction.clamp(0.15, 0.6) * totalH
            : 0.0;

        final middle = Column(
          children: [
            Expanded(flex: 7, child: _buildEditorCanvas()),
            if (terminalOnBottom || previewOnBottom)
              _buildSplitter(
                horizontal: true,
                inset: 0,
                onDrag: (dy) => setState(
                    () => _bottomAreaFraction += dy / totalH),
                onDragEnd: _persistSettings,
              ),
            if (terminalOnBottom || previewOnBottom)
              SizedBox(
                height: bottomAreaH,
                child: _buildBottomPanels(terminalOnBottom, previewOnBottom),
              ),
          ],
        );

        return Row(
          children: [
            _buildActivityBar(),
            if (leftW > 0) ...[
              SizedBox(width: leftW, child: _buildDesktopLeftPanel()),
              _buildSplitter(
                horizontal: false,
                inset: 0,
                onDrag: (dx) => setState(() => _leftPanelWidth += dx),
                onDragEnd: _persistSettings,
              ),
            ],
            Expanded(
              child: Container(color: const Color(0xFF0F172A), child: middle),
            ),
            if (previewSideW > 0) ...[
              _buildSplitter(
                horizontal: false,
                inset: 0,
                onDrag: (dx) => setState(() => _previewWidth -= dx),
                onDragEnd: _persistSettings,
              ),
              SizedBox(width: previewSideW, child: _buildPreviewPane()),
            ],
            if (terminalSideW > 0) ...[
              _buildSplitter(
                horizontal: false,
                inset: 0,
                onDrag: (dx) => setState(() => _terminalSideWidth -= dx),
                onDragEnd: _persistSettings,
              ),
              SizedBox(width: terminalSideW, child: _buildTerminalPane()),
            ],
          ],
        );
      },
    );
  }

  /// A `clamp` that tolerates a [max] smaller than [min] (e.g. when the
  /// window is very narrow) by returning the largest sensible bound.
  double _clampW(double value, double min, double max) {
    final lo = min < max ? min : max;
    final hi = min < max ? max : min;
    return value.clamp(lo, hi);
  }

  /// Stacked bottom panels (terminal and/or preview). When both are present
  /// they share the bottom area, split by a draggable handle.
  Widget _buildBottomPanels(bool terminalOnBottom, bool previewOnBottom) {
    if (terminalOnBottom && previewOnBottom) {
      return LayoutBuilder(
        builder: (ctx, constraints) {
          final termH = _bottomShareTerminal.clamp(0.2, 0.8) * constraints.maxHeight;
          return Column(
            children: [
              SizedBox(height: termH, child: _buildTerminalPane()),
              _buildSplitter(
                horizontal: true,
                inset: 0,
                onDrag: (dy) =>
                    setState(() => _bottomShareTerminal += dy / constraints.maxHeight),
                onDragEnd: _persistSettings,
              ),
              Expanded(child: _buildPreviewPane()),
            ],
          );
        },
      );
    }
    if (terminalOnBottom) return _buildTerminalPane();
    return _buildPreviewPane();
  }

  /// A drag handle used to resize panels. When [horizontal] it drags
  /// vertically (adjusting height); otherwise it drags horizontally
  /// (adjusting width).
  Widget _buildSplitter({
    required bool horizontal,
    required double inset,
    required void Function(double delta) onDrag,
    VoidCallback? onDragEnd,
  }) {
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate:
            horizontal ? null : (d) => onDrag(d.delta.dx),
        onVerticalDragUpdate: horizontal ? (d) => onDrag(d.delta.dy) : null,
        onHorizontalDragEnd: horizontal ? null : (_) => onDragEnd?.call(),
        onVerticalDragEnd: horizontal ? (_) => onDragEnd?.call() : null,
        child: Container(
          width: horizontal ? double.infinity : inset + 5,
          height: horizontal ? inset + 5 : double.infinity,
          color: const Color(0xFF0F172A),
        ),
      ),
    );
  }

  /// Moves the terminal/preview pane between bottom and side placement and
  /// persists the choice.
  void _setPanePlacement(String paneName, bool bottom) {
    setState(() {
      if (paneName == 'Terminal') {
        _terminalOnBottom = bottom;
      } else {
        _previewOnBottom = bottom;
      }
    });
    _persistSettings();
  }

  /// VS Code activity bar: Explorer / Search / Source Control / Terminal /
  /// Preview / Settings, with the active item highlighted by the left accent.
  Widget _buildActivityBar() {
    return Container(
      width: 48,
      color: const Color(0xFF0B1121),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildActivityItem(Icons.folder_outlined, 'Explorer', _leftPanelMode == _LeftPanelMode.explorer, () => _toggleExplorer()),
          _buildActivityItem(Icons.search, 'Search', false, () => _showCommandPalette(goToFile: true)),
          _buildActivityItem(Icons.source_outlined, 'Source Control', _leftPanelMode == _LeftPanelMode.sourceControl, () => setState(() => _leftPanelMode = _LeftPanelMode.sourceControl)),
          _buildActivityItem(Icons.terminal, 'Terminal', _showDesktopTerminal, () => setState(() => _showDesktopTerminal = !_showDesktopTerminal)),
          _buildActivityItem(Icons.visibility, 'Live Preview', _showDesktopPreview, () => setState(() => _showDesktopPreview = !_showDesktopPreview)),
          _buildActivityItem(Icons.cloud_outlined, 'GitHub / Clone', false, _showGitHubCloneDialog),
          const Spacer(),
          _buildActivityItem(Icons.settings_outlined, 'Settings', false, _showSettingsDialog),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Activity-bar Explorer: switches mode, or collapses/expands the panel.
  void _toggleExplorer() {
    setState(() {
      if (_leftPanelMode != _LeftPanelMode.explorer) {
        _leftPanelMode = _LeftPanelMode.explorer;
        _showLeftPanel = true;
      } else {
        _showLeftPanel = !_showLeftPanel;
      }
    });
    _persistSettings();
  }

  Widget _buildActivityItem(IconData icon, String label, bool active, VoidCallback onTap) {
    return Tooltip(
      message: label,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                top: 9,
                bottom: 9,
                child: Container(width: 2, color: active ? Colors.white : Colors.transparent),
              ),
              Icon(icon, size: 22, color: active ? Colors.white : const Color(0xFF858585)),
            ],
          ),
        ),
      ),
    );
  }

  void _showIdeToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E293B),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _closeActiveTab() {
    if (_activeFile != null) _closeTab(_activeFile!);
  }

  void _nextEditorTab() {
    if (_openTabs.isEmpty) return;
    final idx = _openTabs.indexWhere((f) => f.path == _activeFile?.path);
    if (idx < 0) return;
    _selectFile(_openTabs[(idx + 1) % _openTabs.length]);
  }

  void _prevEditorTab() {
    if (_openTabs.isEmpty) return;
    final idx = _openTabs.indexWhere((f) => f.path == _activeFile?.path);
    if (idx < 0) return;
    _selectFile(_openTabs[(idx - 1 + _openTabs.length) % _openTabs.length]);
  }

  /// VS Code-style Command Palette. In [goToFile] mode the tree is searched by
  /// name; otherwise a static command list (VS Code familiar commands) is shown.
  void _showCommandPalette({bool goToFile = false}) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        List<Widget> results = [];
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final query = controller.text.trim().toLowerCase();
            if (goToFile) {
              results = _allProjectFiles()
                  .where((f) => query.isEmpty || f.path.toLowerCase().contains(query))
                      .take(50)
                      .map((f) => ListTile(
                            dense: true,
                            leading: Icon(_getFileIcon(f.path.split(Platform.pathSeparator).last), size: 15, color: Colors.white70),
                            title: Text(f.path.split(Platform.pathSeparator).last, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: Text(f.path, style: const TextStyle(color: Colors.white38, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () { Navigator.pop(ctx); _openFileInTab(f); },
                          ))
                  .toList();
            } else {
              final cmds = <(String, IconData, VoidCallback)>[
                ('Open Folder…', Icons.folder_open, () { Navigator.pop(ctx); _openFolderFromPicker(); }),
                ('Open Recent', Icons.history, () { Navigator.pop(ctx); _openRecentMenu(); }),
                ('Clone Repository…', Icons.content_copy, () { Navigator.pop(ctx); _showGitHubCloneDialog(); }),
                ('GitHub / Integrations…', Icons.cloud, () { Navigator.pop(ctx); _showIntegrationsDialog(); }),
                ('New File', Icons.note_add_outlined, () { Navigator.pop(ctx); _handleCrudAction('new_file', null); }),
                ('New Folder', Icons.create_new_folder_outlined, () { Navigator.pop(ctx); _handleCrudAction('new_folder', null); }),
                ('Save', Icons.save_outlined, () { Navigator.pop(ctx); _saveActiveFile(); }),
                ('Close Editor', Icons.close, () { Navigator.pop(ctx); _closeActiveTab(); }),
                ('Run and Debug', Icons.play_circle_outline, () { Navigator.pop(ctx); _showIdeToast('Run & Debug coming soon'); }),
                ('Toggle Terminal', Icons.terminal, () { Navigator.pop(ctx); setState(() => _showDesktopTerminal = !_showDesktopTerminal); }),
                ('Toggle Live Preview', Icons.visibility, () { Navigator.pop(ctx); setState(() => _showDesktopPreview = !_showDesktopPreview); }),
                ('Source Control', Icons.source_outlined, () { Navigator.pop(ctx); setState(() => _leftPanelMode = _LeftPanelMode.sourceControl); }),
                ('Explorer', Icons.folder_outlined, () { Navigator.pop(ctx); setState(() => _leftPanelMode = _LeftPanelMode.explorer); }),
              ];
              results = cmds
                  .where((c) => query.isEmpty || c.$1.toLowerCase().contains(query))
                  .map((c) => ListTile(
                        dense: true,
                        leading: Icon(c.$2, size: 15, color: Colors.white70),
                        title: Text(c.$1, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        onTap: c.$3,
                      ))
                  .toList();
            }
            return AlertDialog(
              backgroundColor: const Color(0xFF16263F),
              insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
              contentPadding: const EdgeInsets.all(0),
              content: SizedBox(
                width: 520,
                height: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: goToFile ? 'Search files by name...' : 'Type a command or search...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 15),
                          prefixIcon: const Icon(Icons.arrow_right, color: Colors.white54),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    Expanded(
                      child: results.isEmpty
                          ? const Center(child: Text('No matching commands', style: TextStyle(color: Colors.white38, fontSize: 13)))
                          : ListView(shrinkWrap: true, children: results),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<File> _allProjectFiles() {
    final files = <File>[];
    try {
      final root = _project.directory;
      if (!root.existsSync()) return files;
      final stack = <Directory>[root];
      const skip = {'.git', 'node_modules', 'build', '.dart_tool', '.idea', 'out'};
      while (stack.isNotEmpty) {
        final dir = stack.removeLast();
        try {
          for (final e in dir.listSync()) {
            if (e is Directory) {
              if (!skip.contains(e.path.split(Platform.pathSeparator).last)) stack.add(e);
            } else if (e is File) {
              files.add(e);
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return files;
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
                  children: [
                    Icon(Icons.terminal, color: const Color(0xFF60A5FA), size: 18),
                    const SizedBox(width: 12),
                    Text('Terminal • ${_terminalEngine.shellName} — collapsed', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const Spacer(),
                    const Icon(Icons.keyboard_arrow_up, color: Colors.white54),
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
  Widget _buildDesktopLeftPanel() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _buildPanelModeTab(_LeftPanelMode.explorer, Icons.folder_outlined, 'Explorer'),
                const SizedBox(width: 4),
                _buildPanelModeTab(_LeftPanelMode.sourceControl, Icons.source_outlined, 'Git'),
                const Spacer(),
                if (_leftPanelMode == _LeftPanelMode.explorer)
                  Tooltip(
                    message: 'New file',
                    child: InkWell(
                      onTap: () => _handleCrudAction('new_file', null),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.note_add_outlined, size: 17, color: Colors.white70),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: _leftPanelMode == _LeftPanelMode.explorer
                ? ProjectTreeView(
                    key: _treeKey,
                    root: _project.directory,
                    selectedPath: _activeFile?.path ?? '',
                    onOpenFile: _openFileInTab,
                    onChanged: _refreshAfterFsChanged,
                  )
                : SourceControlPanel(
                    key: _sourceControlKey,
                    projectDir: _project.directory,
                    onChanged: _refreshAfterFsChanged,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelModeTab(_LeftPanelMode mode, IconData icon, String label) {
    final active = _leftPanelMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _leftPanelMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3B82F6).withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: active ? const Color(0xFF60A5FA) : Colors.white54),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }

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
      height: 36,
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
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
                    child: Row(
                      children: [
                        Icon(_getFileIcon(name), size: 13, color: isSelected ? const Color(0xFF60A5FA) : Colors.white54),
                        const SizedBox(width: 6),
                        Text(name, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12)),
                        const SizedBox(width: 4),
                        TappableIcon(
                          icon: isDirty ? Icons.circle : Icons.close,
                          iconSize: isDirty ? 8 : 13,
                          color: isDirty ? const Color(0xFFFBBF24) : Colors.white38,
                          onTap: () => _closeTab(file),
                          tooltip: 'Close',
                          target: 26,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_split, color: Colors.white38, size: 15),
            tooltip: 'Split editor',
            onPressed: () => _showIdeToast('Split editor coming soon'),
          ),
          const SizedBox(width: 6),
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
          // Bottom Status Bar (VS Code style)
          Container(
            height: 24,
            color: const Color(0xFF3B82F6),
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              children: [
                if (_branch.isNotEmpty) ...[
                  const Icon(Icons.source_outlined, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(_branch, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  if (_aheadBehind.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(_aheadBehind, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                  const SizedBox(width: 10),
                  Container(width: 1, height: 14, color: Colors.white38),
                  const SizedBox(width: 10),
                ],
                Icon(Icons.error_outline, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text('0', style: const TextStyle(color: Colors.white, fontSize: 11)),
                const SizedBox(width: 6),
                Icon(Icons.warning_amber_outlined, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text('0', style: const TextStyle(color: Colors.white, fontSize: 11)),
                const Spacer(),
                if (_activeFile != null) ...[
                  Text(_langLabel(_activeFile!.path), style: const TextStyle(color: Colors.white, fontSize: 11)),
                  const SizedBox(width: 12),
                ],
                Text('Ln ${_lineCol.$1}, Col ${_lineCol.$2}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                const SizedBox(width: 12),
                const Text('UTF-8', style: TextStyle(color: Colors.white, fontSize: 11)),
                const SizedBox(width: 12),
                const Icon(Icons.notifications_none, size: 12, color: Colors.white),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('TERMINAL', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Text(_terminalEngine.shellName, style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    Text(_project.name, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_currentMobileView == MobileIdeView.terminal)
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                        onPressed: () => setState(() => _currentMobileView = MobileIdeView.editor),
                      ),
                    if (MediaQuery.of(context).size.width >= 900)
                      _buildPaneHeaderMenu(
                        icon: Icons.unfold_more,
                        tooltip: 'Move panel',
                        actions: [
                          ('Move to Bottom', Icons.south, () => _setPanePlacement('Terminal', true)),
                          ('Move to Side', Icons.east, () => _setPanePlacement('Terminal', false)),
                          const _PaneDivider(),
                          ('New Terminal', Icons.terminal, _openNewTerminal),
                          ('Restart Shell', Icons.restart_alt, _restartTerminal),
                          ('WSL Shell…', Icons.terminal, _openWslShellDialog),
                          ('SSH Remote…', Icons.router, _openSshShellDialog),
                          ('Docker Attach…', Icons.apps, _openDockerAttachDialog),
                          ('Clear', Icons.delete_outline, _terminalEngine.clearDisplay),
                          ('Interrupt', Icons.stop, _terminalEngine.interrupt),
                        ],
                      ),
                  ],
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
                IconButton(
                  icon: Icon(Icons.refresh, size: 16, color: _isPreviewRunning ? Colors.white54 : Colors.white24),
                  onPressed: _isPreviewRunning ? () => _webController?.reload() : null,
                ),
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
                        Flexible(
                          child: Text(
                            _previewUrlLabel(),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
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
                if (MediaQuery.of(context).size.width >= 900)
                  _buildPaneHeaderMenu(
                    icon: Icons.unfold_more,
                    tooltip: 'Move panel',
                    actions: [
                      ('Move to Bottom', Icons.south, () => _setPanePlacement('Preview', true)),
                      ('Move to Side', Icons.east, () => _setPanePlacement('Preview', false)),
                      const _PaneDivider(),
                      ('Start / Stop Preview', Icons.play_arrow, _togglePreviewServer),
                      ('Refresh', Icons.refresh,
                          () => _webController?.reload()),
                    ],
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
                    onWebViewCreated: (controller) => _webController = controller,
                  )
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
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

  /// Short language label (VS Code status-bar style).
  String _langLabel(String path) {
    final lang = _languageLabel(path.split(Platform.pathSeparator).last);
    if (lang == 'plain') return 'Plain Text';
    return lang;
  }

  /// Current cursor line/column from the code controller selection.
  (int, int) get _lineCol {
    final sel = _codeController.selection;
    if (sel.isValid) {
      try {
        final pos = _codeController.fullText
            .substring(0, sel.baseOffset < sel.extentOffset ? sel.baseOffset : sel.extentOffset);
        final lines = pos.split('\n');
        return (lines.length, lines.last.length + 1);
      } catch (_) {}
    }
    return (1, 1);
  }

  /// Human-readable language name for a file name, based on its extension.
  String _languageLabel(String name) {
    switch (_extOf(name)) {
      case 'js':
      case 'jsx':
        return 'JavaScript';
      case 'ts':
      case 'tsx':
        return 'TypeScript';
      case 'html':
      case 'htm':
        return 'HTML';
      case 'css':
        return 'CSS';
      case 'json':
        return 'JSON';
      case 'md':
        return 'Markdown';
      case 'dart':
        return 'Dart';
      case 'py':
        return 'Python';
      case '':
        return 'plain';
      default:
        return 'plain';
    }
  }

  /// Address text shown in the preview browser bar.
  String _previewUrlLabel() {
    if (!_isPreviewRunning) return 'Preview offline';
    if (!_hasPackageJson) {
      return 'Streaming Preview — ${_activeFile?.path.split(Platform.pathSeparator).last ?? ''}';
    }
    return 'http://localhost:5173';
  }
}
