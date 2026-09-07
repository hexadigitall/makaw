import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

import '../../data/git_diff_service.dart';

/// VS Code-style side-by-side Git diff viewer.
///
/// Renders the committed (HEAD) version of a file on the left and the current
/// working-tree version on the right, with the two panes scrolling in lockstep
/// and added/removed/modified lines tinted for clarity.
class GitDiffViewer extends StatefulWidget {
  final SideBySideDiff diff;
  final dynamic language;

  const GitDiffViewer({super.key, required this.diff, this.language});

  @override
  State<GitDiffViewer> createState() => _GitDiffViewerState();
}

class _GitDiffViewerState extends State<GitDiffViewer> {
  late final CodeController _leftController;
  late final CodeController _rightController;
  final ScrollController _leftScroll = ScrollController();
  final ScrollController _rightScroll = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _leftController = CodeController(
      text: widget.diff.originalText,
      language: widget.language,
    );
    _rightController = CodeController(
      text: widget.diff.currentText,
      language: widget.language,
    );
    _leftScroll.addListener(_syncToRight);
    _rightScroll.addListener(_syncToLeft);
  }

  void _syncToRight() {
    if (_syncing) return;
    _syncing = true;
    if (_rightScroll.hasClients) {
      _rightScroll.jumpTo(_leftScroll.offset.clamp(0.0, _rightScroll.position.maxScrollExtent));
    }
    _syncing = false;
  }

  void _syncToLeft() {
    if (_syncing) return;
    _syncing = true;
    if (_leftScroll.hasClients) {
      _leftScroll.jumpTo(_rightScroll.offset.clamp(0.0, _leftScroll.position.maxScrollExtent));
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _leftController.dispose();
    _rightController.dispose();
    _leftScroll.dispose();
    _rightScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = widget.diff.hasChanges;
    return Container(
      color: const Color(0xFF0B1121),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryBar(hasChanges),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _pane(
                    controller: _leftController,
                    scrollController: _leftScroll,
                    readOnly: true,
                    accent: const Color(0xFFF87171),
                    header: 'Original (HEAD)',
                  ),
                ),
                _gutterDivider(hasChanges),
                Expanded(
                  child: _pane(
                    controller: _rightController,
                    scrollController: _rightScroll,
                    readOnly: false,
                    accent: const Color(0xFF34D399),
                    header: 'Current (Working Tree)',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(bool hasChanges) {
    final added = widget.diff.lines.where((l) => l.kind == DiffLineKind.added).length;
    final removed = widget.diff.lines.where((l) => l.kind == DiffLineKind.removed).length;
    final modified = widget.diff.lines.where((l) => l.kind == DiffLineKind.modified).length;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          Icon(hasChanges ? Icons.fork_right : Icons.check_circle_outline,
              size: 15, color: hasChanges ? const Color(0xFF60A5FA) : const Color(0xFF34D399)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasChanges
                  ? '+$added added · -$removed removed · ~$modified modified'
                  : 'No changes — working tree matches HEAD',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gutterDivider(bool hasChanges) {
    return Container(
      width: 2,
      color: hasChanges ? const Color(0xFF2D3748) : const Color(0xFF1E293B),
    );
  }

  Widget _pane({
    required CodeController controller,
    required ScrollController scrollController,
    required bool readOnly,
    required Color accent,
    required String header,
  }) {
    return Container(
      color: const Color(0xFF181818),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 28,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFF212121),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(header, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: CodeTheme(
              data: CodeThemeData(styles: monokaiSublimeTheme),
              child: SingleChildScrollView(
                controller: scrollController,
                child: CodeField(
                  controller: controller,
                  readOnly: readOnly,
                  gutterStyle: const GutterStyle(
                    showLineNumbers: true,
                    textStyle: TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                  textStyle: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5, height: 1.45),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
