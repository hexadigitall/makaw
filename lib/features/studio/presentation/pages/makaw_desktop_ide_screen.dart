import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:xterm/xterm.dart';

import '../../data/code_studio_service.dart';
import '../../data/git_diff_service.dart';
import '../../data/git_service.dart';
import '../../data/ide_settings.dart';
import '../../data/studio_command_registry.dart';
import '../../data/studio_project.dart';
import '../../data/terminal_engine.dart';
import '../widgets/git_diff_viewer.dart';
import '../../../../core/widgets/widgets.dart';

/// The focused Windows desktop Code Studio: a full VS Code-style multi-pane
/// IDE in a single screen.
///
/// Layout: top command/title bar -> activity rail + explorer sidebar -> central
/// editor canvas (editor or side-by-side git diff) with an integrated terminal
/// drawer -> optional live web preview -> status bar. The Makaw logo in the
/// title bar routes strictly back to the Code Studio Hub (Level 1).
class MakawDesktopIdeScreen extends StatefulWidget {
  final StudioProject project;
  final VoidCallback onBackToStudioHub;

  const MakawDesktopIdeScreen({
    super.key,
    required this.project,
    required this.onBackToStudioHub,
  });

  @override
  State<MakawDesktopIdeScreen> createState() => _MakawDesktopIdeScreenState();
}

class _MakawDesktopIdeScreenState extends State<MakawDesktopIdeScreen> {
  // Engines
  late CodeController _codeController;
  final MakawTerminalEngine _terminalEngine = MakawTerminalEngine();

  // Files & tabs
  List<File> _projectFiles = [];
  List<File> _openTabs = [];
  File? _activeFile;
  final Set<String> _dirtyPaths = {};

  // Source control
  List<File> _changedFiles = [];
  String _branch = '';

  // Panels & views
  String _activeActivity = 'explorer';
  bool _isSideBarVisible = true;
  bool _isBottomPanelVisible = true;
  bool _isLivePreviewVisible = true;
  String _bottomTab = 'terminal';

  // Command palette
  bool _isCommandPaletteOpen = false;
  bool _isCommandMode = false;
  final TextEditingController _paletteInputController = TextEditingController();
  final FocusNode _paletteFocusNode = FocusNode();

  // Layout
  double _leftPanelWidth = 230;
  double _terminalHeight = 200;
  double _previewWidth = 380;

  // Live server
  bool _isLiveServerRunning = true;
  String _previewUrl = '';
  InAppWebViewController? _previewWebViewController;

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(text: '');
    _loadSettings();
    _loadProjectTree();
    _refreshGit();
    _terminalEngine.startSession(workingDirectory: widget.project.directory.path);
  }

  @override
  void dispose() {
    _terminalEngine.dispose();
    _codeController.dispose();
    _paletteInputController.dispose();
    _paletteFocusNode.dispose();
    super.dispose();
  }

  // ── Guards ──────────────────────────────────────────────────────────────

  static const List<String> _binaryExtensions = <String>[
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico', '.svg',
    '.pdf', '.zip', '.gz', '.tar', '.7z', '.rar',
    '.exe', '.dll', '.so', '.dylib', '.bin', '.dat',
    '.mp3', '.mp4', '.wav', '.flac', '.ogg', '.webm', '.mov', '.mkv',
    '.woff', '.woff2', '.ttf', '.otf', '.eot',
  ];

  bool _isBinaryFile(File file) {
    final ext = file.path.split('.').last.toLowerCase();
    return _binaryExtensions.contains('.$ext') || ext.contains(' ');
  }

  String _readFileSafe(File file) {
    if (_isBinaryFile(file)) {
      return '// Preview is not available for this binary file.\n';
    }
    try {
      return file.readAsStringSync();
    } catch (e) {
      return '// Could not read file: $e\n';
    }
  }

  // ── Project loading ─────────────────────────────────────────────────────

  Future<void> _loadProjectTree() async {
    final files = await CodeStudioService.listFilesAsync(widget.project.directory);
    if (!mounted) return;
    setState(() {
      _projectFiles = files;
      if (_openTabs.isEmpty && files.isNotEmpty) {
        final initial = files.firstWhere(
          (f) => f.path.endsWith('index.html') ||
              f.path.endsWith('main.dart') ||
              f.path.endsWith('.html'),
          orElse: () => files.first,
        );
        _openTab(initial);
      }
    });
  }

  
  void _openTab(File file) {
    if (!_openTabs.any((f) => f.path == file.path)) {
      setState(() => _openTabs.add(file));
    }
    _setActiveFile(file);
  }

  void _setActiveFile(File file) {
    setState(() {
      _activeFile = file;
      _codeController.text = _readFileSafe(file);
      _codeController.language = _resolveLanguage(file.path);
    });
  }

  void _closeTab(File file) {
    setState(() {
      _openTabs.removeWhere((f) => f.path == file.path);
      if (_activeFile?.path == file.path) {
        if (_openTabs.isNotEmpty) {
          final next = _openTabs.last;
          _activeFile = next;
          _codeController.text = _readFileSafe(next);
          _codeController.language = _resolveLanguage(next.path);
        } else {
          _activeFile = null;
          _codeController.text = '';
        }
      }
    });
  }

  Future<void> _saveCurrentFile({bool reloadPreview = true}) async {
    final active = _activeFile;
    if (active == null || _isBinaryFile(active)) return;
    try {
      await active.writeAsString(_codeController.text, flush: true);
      if (mounted) setState(() => _dirtyPaths.remove(active.path));
      if (reloadPreview) {
        try {
          await _previewWebViewController?.reload();
        } catch (_) {}
      }
    } catch (_) {}
  }

  dynamic _resolveLanguage(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.xml')) return xml;
    if (lower.endsWith('.css')) return css;
    if (lower.endsWith('.js') || lower.endsWith('.jsx')) return javascript;
    if (lower.endsWith('.ts') || lower.endsWith('.tsx')) return typescript;
    return xml;
  }

  // ── Git / Source control ────────────────────────────────────────────────

  Future<void> _refreshGit() async {
    final root = widget.project.directory;
    final status = await GitService(root).status();
    if (!mounted) return;
    setState(() {
      _branch = status.branch;
      _changedFiles = [
        for (final entry in status.entries) CodeStudioService.fileIn(root, entry.path),
      ];
    });
  }

  Future<void> _openSideBySideDiff(File file) async {
    final root = widget.project.directory;
    final rel = CodeStudioService.relativePath(root, file);
    final diff = await GitDiffService(root).loadDiff(rel);
    if (!mounted) return;
    setState(() {
      _activeDiff = diff;
      _diffPath = rel;
    });
  }

  SideBySideDiff? _activeDiff;
  String? _diffPath;

  String _basename(String path) => CodeStudioService.baseName(path);

  // ── Keyboard shortcuts ──────────────────────────────────────────────────

  void _handleKeyCombos(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    final isControl = event.isControlPressed || event.isMetaPressed;
    if (!isControl) return;
    if (event.logicalKey == LogicalKeyboardKey.keyP) {
      _openPalette(commandMode: event.isShiftPressed);
    } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
      _saveCurrentFile();
    } else if (event.logicalKey == LogicalKeyboardKey.keyB) {
      setState(() => _isSideBarVisible = !_isSideBarVisible);
    } else if (event.logicalKey == LogicalKeyboardKey.keyJ) {
      setState(() => _isBottomPanelVisible = !_isBottomPanelVisible);
    }
  }

  void _openPalette({required bool commandMode}) {
    if (_isCommandPaletteOpen) return;
    setState(() {
      _isCommandPaletteOpen = true;
      _isCommandMode = commandMode;
      _paletteInputController.text = commandMode ? '> ' : '';
    });
    Future.microtask(() => _paletteFocusNode.requestFocus());
  }

  void _closePalette() {
    setState(() => _isCommandPaletteOpen = false);
    _paletteInputController.clear();
  }

  // ── File CRUD / menus ───────────────────────────────────────────────────

  Future<void> _showNewFileDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('New File', style: TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'e.g. App.tsx, styles.css'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final newFile =
          await CodeStudioService.createFile(widget.project.directory, name);
      _loadProjectTree();
      _openTab(newFile);
    }
  }

  void _showRenameDialog(File file) async {
    final controller = TextEditingController(text: _basename(file.path));
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Rename File', style: TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(controller: controller, autofocus: true, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      final newPath =
          '${file.parent.path}${Platform.pathSeparator}$newName';
      await file.rename(newPath);
      _closeTab(file);
      _loadProjectTree();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: _handleKeyCombos,
      child: Scaffold(
        backgroundColor: const Color(0xFF181818),
        body: Stack(
          children: [
            Column(
              children: [
                _buildTopTitleBar(),
                Expanded(
                  child: Row(
                    children: [
                      _buildActivityBar(),
                      if (_isSideBarVisible) _buildPrimarySideBar(),
                      Expanded(
                        flex: 6,
                        child: Column(
                          children: [
                            _buildEditorTabBar(),
                            _buildBreadcrumbsBar(),
                            Expanded(child: _buildEditorCanvas()),
                            if (_isBottomPanelVisible) _buildBottomPanel(),
                          ],
                        ),
                      ),
                      if (_isLivePreviewVisible) _buildLivePreviewPane(),
                    ],
                  ),
                ),
                _buildStatusBar(),
              ],
            ),
            if (_isCommandPaletteOpen) _buildFloatingCommandPalette(),
          ],
        ),
      ),
    );
  }

  // ── Title bar ───────────────────────────────────────────────────────────

  Widget _buildTopTitleBar() {
    return Container(
      height: 40,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          InkWell(
            onTap: widget.onBackToStudioHub,
            borderRadius: BorderRadius.circular(4),
            child: const Tooltip(
              message: 'Back to Code Studio Hub',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: Image(
                        image: AssetImage('assets/makaw_logo_28.png'),
                        fit: BoxFit.cover,
                        errorBuilder: _logoError,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text('Makaw',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildMenuItem('File', _showFileMenu),
          _buildMenuItem('Edit', _showEditMenu),
          _buildMenuItem('Run', _runBuild),
          _buildMenuItem('Terminal',
              () => setState(() => _isBottomPanelVisible = !_isBottomPanelVisible)),
          const Spacer(),
          GestureDetector(
            onTap: () => _openPalette(commandMode: false),
            child: Container(
              height: 26,
              width: 320,
              decoration: BoxDecoration(
                color: const Color(0xFF252526),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: Colors.white54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.project.name,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(3)),
                    child: const Text('Ctrl+P', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(_isLivePreviewVisible ? Icons.splitscreen : Icons.square_outlined,
                size: 16, color: Colors.white54),
            tooltip: 'Toggle Live Preview',
            onPressed: () => setState(() => _isLivePreviewVisible = !_isLivePreviewVisible),
          ),
          IconButton(
            icon: Icon(_isBottomPanelVisible ? Icons.vertical_align_bottom : Icons.maximize,
                size: 16, color: Colors.white54),
            tooltip: 'Toggle Terminal Panel',
            onPressed: () => setState(() => _isBottomPanelVisible = !_isBottomPanelVisible),
          ),
        ],
      ),
    );
  }

  static Widget _logoError(BuildContext _, Object __, StackTrace? ___) {
    return const Icon(Icons.code, color: Colors.white, size: 22);
  }

  Widget _buildMenuItem(String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
    );
  }

  void _showFileMenu() {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(100, 40, 400, 400),
      color: const Color(0xFF252526),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem(height: 30, child: const Text('New File', style: TextStyle(color: Colors.white, fontSize: 12)), onTap: _showNewFileDialog),
        PopupMenuItem(height: 30, child: const Text('Open Folder…', style: TextStyle(color: Colors.white, fontSize: 12)), onTap: _openFolderPicker),
        const PopupMenuDivider(height: 4),
        PopupMenuItem(height: 30, child: const Text('Save (Ctrl+S)', style: TextStyle(color: Colors.white, fontSize: 12)), onTap: () => _saveCurrentFile()),
        const PopupMenuDivider(height: 4),
        PopupMenuItem(height: 30, child: const Text('Back to Code Studio Hub', style: TextStyle(color: Colors.white, fontSize: 12)), onTap: widget.onBackToStudioHub),
      ],
    );
  }

  void _showEditMenu() {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(150, 40, 400, 400),
      color: const Color(0xFF252526),
      items: const [
        PopupMenuItem(height: 30, child: Text('Undo', style: TextStyle(color: Colors.white, fontSize: 12))),
        PopupMenuItem(height: 30, child: Text('Redo', style: TextStyle(color: Colors.white, fontSize: 12))),
        PopupMenuItem(height: 30, child: Text('Find', style: TextStyle(color: Colors.white, fontSize: 12))),
      ],
    );
  }

  Future<void> _openFolderPicker() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;
    setState(() => _previewUrl = 'file://$dir');
  }

  void _runBuild() {
    _terminalEngine.writeCommand('echo Build started by Makaw Studio');
  }

  // ── Activity bar ────────────────────────────────────────────────────────

  Widget _buildActivityBar() {
    return Container(
      width: 48,
      color: const Color(0xFF333333),
      child: Column(
        children: [
          _buildActivityIcon('explorer', Icons.copy_rounded, 'Explorer (Ctrl+Shift+E)'),
          _buildActivityIcon('search', Icons.search_rounded, 'Search (Ctrl+Shift+F)'),
          _buildActivityIcon('git', Icons.fork_right_rounded, 'Source Control (Ctrl+Shift+G)'),
          _buildActivityIcon('debug', Icons.play_arrow_outlined, 'Run and Debug'),
          const Spacer(),
          _buildActivityIcon('settings', Icons.settings_outlined, 'Settings'),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildActivityIcon(String id, IconData icon, String tooltip) {
    final isSelected = _activeActivity == id && _isSideBarVisible;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_activeActivity == id) {
              _isSideBarVisible = !_isSideBarVisible;
            } else {
              _activeActivity = id;
              _isSideBarVisible = true;
            }
          });
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: isSelected ? Colors.white : Colors.transparent, width: 2),
            ),
          ),
          child: Icon(icon, color: isSelected ? Colors.white : Colors.white38, size: 22),
        ),
      ),
    );
  }

  // ── Primary sidebar ─────────────────────────────────────────────────────

  Widget _buildPrimarySideBar() {
    if (_activeActivity == 'git') {
      return _buildSourceControlSidebar();
    }
    return _buildExplorerSidebar();
  }

  Widget _buildSourceControlSidebar() {
    return Container(
      width: _leftPanelWidth,
      color: const Color(0xFF252526),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Expanded(
                  child: Text('SOURCE CONTROL',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Refresh',
                  onPressed: _refreshGit,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('Changes (${_changedFiles.length})',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: _changedFiles.isEmpty
                ? const Center(
                    child: Text('No working-tree changes',
                        style: TextStyle(color: Colors.white38, fontSize: 12)))
                : ListView.builder(
                    itemCount: _changedFiles.length,
                    itemBuilder: (context, index) {
                      final file = _changedFiles[index];
                      final name = _basename(file.path);
                      return InkWell(
                        onTap: () => _openSideBySideDiff(file),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                          color: _diffPath == file.path ? const Color(0xFF37373D) : Colors.transparent,
                          child: Row(
                            children: [
                              const Icon(Icons.mode_edit, size: 14, color: Color(0xFFFBBF24)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(name,
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    overflow: TextOverflow.ellipsis),
                              ),
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

  Widget _buildExplorerSidebar() {
    return Container(
      width: _leftPanelWidth,
      color: const Color(0xFF252526),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Expanded(
                  child: Text('EXPLORER',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                ),
                IconButton(
                  icon: const Icon(Icons.note_add_outlined, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'New File',
                  onPressed: _showNewFileDialog,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Refresh Explorer',
                  onPressed: _loadProjectTree,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: const Color(0xFF1E1E1E),
            child: Row(
              children: [
                const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white70),
                const SizedBox(width: 4),
                Text(widget.project.name.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _projectFiles.length,
              itemBuilder: (context, index) {
                final file = _projectFiles[index];
                final name = _basename(file.path);
                final isSelected = _activeFile?.path == file.path;
                final isDirty = _dirtyPaths.contains(file.path);
                return GestureDetector(
                  onSecondaryTapUp: (details) => _showFileContextMenu(details.globalPosition, file),
                  child: InkWell(
                    onTap: () => _openTab(file),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      color: isSelected ? const Color(0xFF37373D) : Colors.transparent,
                      child: Row(
                        children: [
                          Icon(_getFileIcon(name),
                              size: 16,
                              color: isSelected ? const Color(0xFF38BDF8) : Colors.white54),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isDirty ? '● $name' : name,
                              style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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

  void _showFileContextMenu(Offset position, File file) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF252526),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem(height: 28, child: const Text('Open to the Side', style: TextStyle(color: Colors.white, fontSize: 12)), onTap: () => setState(() => _isLivePreviewVisible = true)),
        const PopupMenuDivider(height: 4),
        PopupMenuItem(height: 28, child: const Text('Rename…', style: TextStyle(color: Colors.white, fontSize: 12)), onTap: () => _showRenameDialog(file)),
        PopupMenuItem(height: 28, child: const Text('Delete', style: TextStyle(color: Color(0xFFF87171), fontSize: 12)), onTap: () async {
          await file.delete();
          _closeTab(file);
          _loadProjectTree();
          _refreshGit();
        }),
      ],
    );
  }

  // ── Editor tabs / breadcrumbs ───────────────────────────────────────────

  Widget _buildEditorTabBar() {
    return Container(
      height: 36,
      color: const Color(0xFF252526),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _openTabs.length,
              itemBuilder: (context, index) {
                final file = _openTabs[index];
                final name = _basename(file.path);
                final isSelected = _activeFile?.path == file.path;
                final isDirty = _dirtyPaths.contains(file.path);
                return GestureDetector(
                  onTap: () => _setActiveFile(file),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1E1E1E) : const Color(0xFF2D2D2D),
                      border: Border(
                        right: const BorderSide(color: Color(0xFF181818), width: 1),
                        top: BorderSide(color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent, width: 2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getFileIcon(name),
                            size: 14,
                            color: isSelected ? const Color(0xFF38BDF8) : Colors.white38),
                        const SizedBox(width: 8),
                        Text(isDirty ? '● $name' : name,
                            style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 12)),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _closeTab(file),
                          child: const Icon(Icons.close, size: 14, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 16, color: Colors.white54),
            tooltip: 'More Actions…',
            onPressed: _showEditorOptionsMenu,
          ),
        ],
      ),
    );
  }

  void _showEditorOptionsMenu() {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(600, 40, 700, 300),
      color: const Color(0xFF252526),
      items: [
        PopupMenuItem(height: 28, child: const Text('Save All (Ctrl+S)', style: TextStyle(color: Colors.white, fontSize: 12)), onTap: () => _saveCurrentFile()),
        PopupMenuItem(height: 28, child: const Text('Close All', style: TextStyle(color: Colors.white, fontSize: 12)), onTap: () => setState(() => _openTabs.clear())),
      ],
    );
  }

  Widget _buildBreadcrumbsBar() {
    final fileName = _activeFile == null ? '' : _basename(_activeFile!.path);
    return Container(
      height: 22,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(widget.project.name, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const Text('  ›  ', style: TextStyle(color: Colors.white24, fontSize: 11)),
          Text(fileName, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  // ── Editor canvas (editor or diff) ──────────────────────────────────────

  Widget _buildEditorCanvas() {
    if (_activeDiff != null) {
      return Column(
        children: [
          _buildDiffBar(),
          Expanded(
            child: GitDiffViewer(
              diff: _activeDiff!,
              language: _resolveLanguage(_diffPath ?? ''),
            ),
          ),
        ],
      );
    }
    return Container(
      color: const Color(0xFF1E1E1E),
      child: CodeTheme(
        data: CodeThemeData(styles: monokaiSublimeTheme),
        child: SingleChildScrollView(
          child: CodeField(
            controller: _codeController,
            gutterStyle: const GutterStyle(
              showLineNumbers: true,
              textStyle: TextStyle(color: Colors.white24, fontSize: 13),
            ),
            textStyle: const TextStyle(fontFamily: 'Consolas', fontSize: 13, height: 1.45),
          ),
        ),
      ),
    );
  }

  Widget _buildDiffBar() {
    return Container(
      height: 36,
      color: const Color(0xFF252526),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.fork_right, size: 14, color: Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          Text('${_diffPath ?? ''} — changes',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white54),
            tooltip: 'Close diff',
            onPressed: () => setState(() {
              _activeDiff = null;
              _diffPath = null;
            }),
          ),
        ],
      ),
    );
  }

  // ── Bottom panel ────────────────────────────────────────────────────────

  Widget _buildBottomPanel() {
    return Container(
      height: _terminalHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        border: Border(top: BorderSide(color: Color(0xFF2B2B2B), width: 1)),
      ),
      child: Column(
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: const Color(0xFF1E1E1E),
            child: Row(
              children: [
                _buildPanelTab('PROBLEMS', 'problems'),
                _buildPanelTab('OUTPUT', 'output'),
                _buildPanelTab('TERMINAL', 'terminal'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 14, color: Colors.white54),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _terminalEngine.startSession(
                      workingDirectory: widget.project.directory.path),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 14, color: Colors.white54),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _isBottomPanelVisible = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _bottomTab == 'terminal'
                ? TerminalView(_terminalEngine.terminal,
                    autofocus: false, backgroundOpacity: 0.0)
                : const Center(
                    child: Text('No problems detected in workspace.',
                        style: TextStyle(color: Colors.white38, fontSize: 12))),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelTab(String label, String tabId) {
    final isSelected = _bottomTab == tabId;
    return InkWell(
      onTap: () => setState(() => _bottomTab = tabId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: isSelected ? Colors.white : Colors.transparent, width: 2),
          ),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // ── Live preview ────────────────────────────────────────────────────────

  Widget _buildLivePreviewPane() {
    return GestureDetector(
      onDoubleTap: () {},
      child: Container(
        width: _previewWidth,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: Color(0xFF2D2D2D), width: 1)),
        ),
        child: Column(
          children: [
            Container(
              height: 36,
              color: const Color(0xFF252526),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: Color(0xFF34D399)),
                  const SizedBox(width: 6),
                  const Text('PREVIEW — Live',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 14, color: Colors.white70),
                    tooltip: 'Reload',
                    onPressed: () => _previewWebViewController?.reload(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 14, color: Colors.white70),
                    tooltip: 'Close Preview',
                    onPressed: () => setState(() => _isLivePreviewVisible = false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLiveServerRunning
                  ? InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(_previewUrl.isEmpty
                            ? _derivePreviewUrl()
                            : _previewUrl),
                      ),
                      onWebViewCreated: (c) => _previewWebViewController = c,
                      onReceivedError: (c, r, e) {},
                    )
                  : const Center(
                      child: Text('Start a local server to preview your site.',
                          style: TextStyle(color: Colors.black54, fontSize: 12)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _derivePreviewUrl() {
    final active = _activeFile;
    if (active == null) return 'about:blank';
    return 'file://${active.path.replaceAll('\\', '/')}';
  }

  // ── Status bar ──────────────────────────────────────────────────────────

  Widget _buildStatusBar() {
    return Container(
      height: 22,
      color: const Color(0xFF007ACC),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.fork_right, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(_branch.isEmpty ? 'main*' : '$_branch*',
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          const SizedBox(width: 12),
          Text('${_changedFiles.length}',
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          const Spacer(),
          const Text('Spaces: 2', style: TextStyle(color: Colors.white, fontSize: 11)),
          const SizedBox(width: 12),
          const Text('UTF-8', style: TextStyle(color: Colors.white, fontSize: 11)),
          const SizedBox(width: 12),
          Text(_resolveLanguage(_activeFile?.path ?? '').name.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          const SizedBox(width: 16),
          InkWell(
            onTap: _runBuild,
            child: const Row(
              children: [
                Icon(Icons.wifi_tethering, size: 12, color: Colors.white),
                SizedBox(width: 4),
                Text('Go Live', style: TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Command palette ─────────────────────────────────────────────────────

  Widget _buildFloatingCommandPalette() {
    final raw = _paletteInputController.text;
    final query = raw.replaceFirst('>', '').trim().toLowerCase();

    final matchingFiles = query.isEmpty
        ? _projectFiles.take(30).toList()
        : _projectFiles.where((f) => f.path.toLowerCase().contains(query)).toList();

    final commandMatches = StudioCommandRegistry.commands(
      runBuild: _runBuild,
      openTerminal: () => _terminalEngine.startSession(
          workingDirectory: widget.project.directory.path),
      toggleTerminalPanel: () => setState(() => _isBottomPanelVisible = !_isBottomPanelVisible),
      togglePreview: () => setState(() => _isLivePreviewVisible = !_isLivePreviewVisible),
      newFile: _showNewFileDialog,
      saveFile: () => _saveCurrentFile(),
      backToHub: widget.onBackToStudioHub,
    ).where((c) =>
        c.label.toLowerCase().contains(query) ||
        (c.category?.toLowerCase().contains(query) ?? false));

    final commands = _isCommandMode ? commandMatches.toList() : const <IdeCommand>[];

    return Positioned(
      top: 40,
      left: MediaQuery.of(context).size.width * 0.2,
      right: MediaQuery.of(context).size.width * 0.2,
      child: MakawGlassSurface(
        blur: 18,
        opacity: 0.92,
        radius: 8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(_isCommandMode ? Icons.chevron_right : Icons.search,
                      size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _paletteInputController,
                      focusNode: _paletteFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _isCommandMode
                            ? 'Type a command to run…'
                            : 'Search files by name…',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                        border: InputBorder.none,
                      ),
                      onChanged: (val) => setState(() {}),
                      onSubmitted: (val) {
                        if (_isCommandMode) {
                          if (commands.isNotEmpty) {
                            commands.first.action();
                          }
                        } else if (matchingFiles.isNotEmpty) {
                          _openTab(matchingFiles.first);
                        }
                        _closePalette();
                      },
                    ),
                  ),
                  const ShadBadgeKBD(),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: _isCommandMode
                  ? ListView.builder(
                      shrinkWrap: true,
                      itemCount: commands.length,
                      itemBuilder: (context, index) {
                        final c = commands[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(c.icon, size: 16, color: Colors.white70),
                          title: Text(c.label,
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                          subtitle: c.category == null
                              ? null
                              : Text(c.category!,
                                  style: const TextStyle(color: Colors.white30, fontSize: 10)),
                          onTap: () {
                            c.action();
                            _closePalette();
                          },
                        );
                      },
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: matchingFiles.length,
                      itemBuilder: (context, index) {
                        final file = matchingFiles[index];
                        final name = _basename(file.path);
                        return ListTile(
                          dense: true,
                          leading: Icon(_getFileIcon(name),
                              size: 14, color: Colors.white70),
                          title: Text(name,
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                          subtitle: Text(file.path,
                              style: const TextStyle(color: Colors.white30, fontSize: 10)),
                          onTap: () {
                            _openTab(file);
                            _closePalette();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Settings persistence ────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final s = await IdeSettingsStore.load();
    if (mounted) {
      setState(() {
        _leftPanelWidth = s.leftPanelWidth;
        _terminalHeight = s.terminalHeightFraction;
        _previewWidth = s.previewWidth;
      });
    }
  }

  IconData _getFileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.html')) return Icons.html;
    if (lower.endsWith('.css')) return Icons.css;
    if (lower.endsWith('.js') || lower.endsWith('.jsx')) return Icons.javascript;
    if (lower.endsWith('.ts') || lower.endsWith('.tsx')) return Icons.code;
    if (lower.endsWith('.dart')) return Icons.flutter_dash;
    if (lower.endsWith('.json')) return Icons.data_object;
    return Icons.insert_drive_file_outlined;
  }
}

/// Small ⌘K / Ctrl+P-style key hint shown in the palette shell.
class ShadBadgeKBD extends StatelessWidget {
  const ShadBadgeKBD({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text('⌘K',
          style: TextStyle(color: Colors.white54, fontSize: 10)),
    );
  }
}