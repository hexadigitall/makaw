import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/storage/lrc_storage_service.dart';

/// Professional karaoke-grade synced lyrics view with smooth auto-scroll,
/// multi-line wrapping, tap-to-seek, timing offset tuner, and Creator Studio launch.
class SyncedLyricsView extends StatefulWidget {
  final List<LrcLine> syncedLines;
  final String plainText;
  final String sourceLabel;
  final Duration position;
  final Color accentColor;
  final bool isLoading;
  final int offsetMs;
  final ValueChanged<int>? onOffsetChanged;
  final ValueChanged<Duration>? onSeekToLine;
  final VoidCallback onOpenCreator;
  final VoidCallback onSearchOnline;
  final VoidCallback onImportFile;
  final VoidCallback onPasteClipboard;
  final VoidCallback onOpenLyricsFolder;
  final VoidCallback? onExpandFullscreen;

  const SyncedLyricsView({
    super.key,
    required this.syncedLines,
    required this.plainText,
    required this.sourceLabel,
    required this.position,
    required this.accentColor,
    this.isLoading = false,
    this.offsetMs = 0,
    this.onOffsetChanged,
    this.onSeekToLine,
    required this.onOpenCreator,
    required this.onSearchOnline,
    required this.onImportFile,
    required this.onPasteClipboard,
    required this.onOpenLyricsFolder,
    this.onExpandFullscreen,
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final ScrollController _scrollCtrl = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int _lastActiveIdx = -1;
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  int _computeActiveIndex() {
    if (widget.syncedLines.isEmpty) return -1;
    final adjustedPos = widget.position + Duration(milliseconds: widget.offsetMs);
    int idx = -1;
    for (int i = 0; i < widget.syncedLines.length; i++) {
      if (widget.syncedLines[i].time <= adjustedPos) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  @override
  void didUpdateWidget(SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeIdx = _computeActiveIndex();
    if (activeIdx >= 0 && activeIdx != _lastActiveIdx) {
      _lastActiveIdx = activeIdx;
      final now = DateTime.now();
      // Give the user 3 seconds grace if they manually scrolled to read ahead/back
      if (now.difference(_userScrolledAt).inSeconds >= 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLine(activeIdx));
      }
    }
  }

  void _scrollToLine(int idx) {
    final key = _itemKeys[idx];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.42,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildTopToolbar(),
          Expanded(child: _buildBody()),
          if (widget.syncedLines.isNotEmpty && widget.onOffsetChanged != null)
            _buildOffsetBar(),
        ],
      ),
    );
  }

  Widget _buildTopToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: widget.accentColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.syncedLines.isNotEmpty
                    ? (widget.sourceLabel.isNotEmpty ? widget.sourceLabel : 'Synced LRC')
                    : (widget.plainText.isNotEmpty ? 'Plain Lyrics' : 'Lyrics'),
                style: TextStyle(color: widget.accentColor, fontSize: 10, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _miniToolBtn(Icons.edit_note_rounded, 'Creator Studio', widget.onOpenCreator),
          _miniToolBtn(Icons.copy_rounded, 'Copy LRC', () {
            final text = widget.syncedLines.isNotEmpty
                ? LrcStorageService.formatLrc(title: '', lines: widget.syncedLines)
                : widget.plainText;
            if (text.trim().isNotEmpty) {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lyrics copied to clipboard'), duration: Duration(seconds: 2)),
              );
            }
          }),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70, size: 18),
            color: const Color(0xFF1E293B),
            tooltip: 'Lyrics actions',
            onSelected: (v) {
              if (v == 'create') widget.onOpenCreator();
              else if (v == 'search') widget.onSearchOnline();
              else if (v == 'paste') widget.onPasteClipboard();
              else if (v == 'import') widget.onImportFile();
              else if (v == 'folder') widget.onOpenLyricsFolder();
              else if (v == 'expand') widget.onExpandFullscreen?.call();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'create', child: Text('Create / Sync Lyrics Studio', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'search', child: Text('Search Online & Offline', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'paste', child: Text('Paste from Clipboard', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'import', child: Text('Import .lrc / .txt File', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'folder', child: Text('Open MakawLyrics Folder', style: TextStyle(color: Colors.white))),
              if (widget.onExpandFullscreen != null)
                const PopupMenuItem(value: 'expand', child: Text('Full-Screen Karaoke View', style: TextStyle(color: Color(0xFF38BDF8)))),
            ],
          ),
          if (widget.onExpandFullscreen != null)
            _miniToolBtn(Icons.open_in_full_rounded, 'Expand', widget.onExpandFullscreen!),
        ],
      ),
    );
  }

  Widget _miniToolBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: widget.accentColor),
            const SizedBox(height: 10),
            const Text('Searching offline & online lyrics...', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }

    if (widget.syncedLines.isNotEmpty) {
      final activeIdx = _computeActiveIndex();
      return NotificationListener<UserScrollNotification>(
        onNotification: (_) {
          _userScrolledAt = DateTime.now();
          return false;
        },
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            children: [
              const SizedBox(height: 24),
              for (int i = 0; i < widget.syncedLines.length; i++) _buildSyncedRow(i, activeIdx),
              const SizedBox(height: 48),
            ],
          ),
        ),
      );
    }

    if (widget.plainText.trim().isNotEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            SelectableText(
              widget.plainText,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.87), fontSize: 15, height: 1.7),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.onOpenCreator,
              icon: Icon(Icons.timer_rounded, size: 16, color: widget.accentColor),
              label: Text('Add Timers in Lyrics Studio', style: TextStyle(color: widget.accentColor, fontSize: 12)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: widget.accentColor.withValues(alpha: 0.5))),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lyrics_outlined, color: Colors.white24, size: 42),
            const SizedBox(height: 10),
            const Text('No lyrics found for this track yet',
                style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: widget.onOpenCreator,
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text('Create / Sync Lyrics', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: widget.onSearchOnline,
                  icon: const Icon(Icons.search_rounded, size: 15),
                  label: const Text('Retry Search', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncedRow(int i, int activeIdx) {
    final key = _itemKeys.putIfAbsent(i, () => GlobalKey());
    final line = widget.syncedLines[i];
    final isActive = i == activeIdx;
    final isPast = i < activeIdx;

    return GestureDetector(
      key: key,
      onTap: () => widget.onSeekToLine?.call(line.time),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: isActive ? 10 : 6),
        decoration: isActive
            ? BoxDecoration(
                color: widget.accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.accentColor.withValues(alpha: 0.45)),
              )
            : null,
        child: Text(
          line.text,
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            color: isActive
                ? Colors.white
                : (isPast ? Colors.white.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.68)),
            fontSize: isActive ? 17.5 : 14,
            height: 1.45,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
            shadows: isActive
                ? [Shadow(color: widget.accentColor.withValues(alpha: 0.6), blurRadius: 12)]
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildOffsetBar() {
    final sec = (widget.offsetMs / 1000).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Sync Offset:', style: TextStyle(color: Colors.white54, fontSize: 10.5)),
          const SizedBox(width: 6),
          _offsetStep('-0.5s', () => widget.onOffsetChanged!(widget.offsetMs - 500)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('${widget.offsetMs > 0 ? '+' : ''}${sec}s',
                style: TextStyle(color: widget.accentColor, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          _offsetStep('+0.5s', () => widget.onOffsetChanged!(widget.offsetMs + 500)),
        ],
      ),
    );
  }

  Widget _offsetStep(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
