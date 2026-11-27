import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../../core/storage/lrc_storage_service.dart';
import '../../../media/data/services/media_thumbnail_service.dart';
import '../../data/services/music_player_service.dart';

/// Interactive Lyrics Creator & Live Tap-to-Sync Studio.
///
/// Allows users to type/paste lyrics (or edit existing `.lrc` lines) while the
/// track is playing, tap "STAMP & NEXT LINE" in real time to attach `[mm:ss.xx]`
/// timers until the song finishes, nudge timestamps (`±0.2s`), live-preview,
/// and export cleanly as universal `.lrc` into the `MakawLyrics` folder, sidecar
/// `.lrc`, and SQLite library.
class LyricsCreatorPage extends StatefulWidget {
  final MusicPlayerService service;
  final SongInfo song;
  final List<LrcLine> initialLines;
  final String initialPlainText;

  const LyricsCreatorPage({
    super.key,
    required this.service,
    required this.song,
    this.initialLines = const [],
    this.initialPlainText = '',
  });

  @override
  State<LyricsCreatorPage> createState() => _LyricsCreatorPageState();
}

class _LyricsCreatorPageState extends State<LyricsCreatorPage> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final TextEditingController _editorCtrl = TextEditingController();
  final TextEditingController _liveLineCtrl = TextEditingController();
  final ScrollController _syncScrollCtrl = ScrollController();
  final Map<int, GlobalKey> _rowKeys = {};

  List<LrcLine?> _syncTimestamps = [];
  List<String> _lineTexts = [];
  int _cursorIdx = 0;
  bool _saving = false;

  static const _bg = Color(0xFF0A0F1A);
  static const _card = Color(0xFF131B2E);
  static const _accent = Color(0xFF818CF8);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this, initialIndex: widget.initialLines.isNotEmpty || widget.initialPlainText.trim().isNotEmpty ? 1 : 0);
    widget.service.addListener(_onServiceTick);

    if (widget.initialLines.isNotEmpty) {
      _lineTexts = widget.initialLines.map((l) => l.text).toList();
      _syncTimestamps = List<LrcLine?>.from(widget.initialLines);
      _editorCtrl.text = LrcStorageService.formatLrc(
        title: widget.song.displayTitle,
        artist: widget.song.displayArtist,
        album: widget.song.displayAlbum,
        lines: widget.initialLines,
      );
    } else if (widget.initialPlainText.trim().isNotEmpty) {
      _editorCtrl.text = widget.initialPlainText.trim();
      _rebuildLinesFromEditor();
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceTick);
    _tabCtrl.dispose();
    _editorCtrl.dispose();
    _liveLineCtrl.dispose();
    _syncScrollCtrl.dispose();
    super.dispose();
  }

  void _onServiceTick() {
    if (mounted) setState(() {});
  }

  void _rebuildLinesFromEditor() {
    final raw = _editorCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _lineTexts = [];
        _syncTimestamps = [];
        _cursorIdx = 0;
      });
      return;
    }

    final lines = <String>[];
    final stamps = <LrcLine?>[];
    final tagRegex = RegExp(r'^\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\](.*)$');
    final metaRegex = RegExp(r'^\[(ti|ar|al|by|length|offset):.*\]$', caseSensitive: false);

    for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
      final t = rawLine.trim();
      if (t.isEmpty || metaRegex.hasMatch(t)) continue;
      final m = tagRegex.firstMatch(t);
      if (m != null) {
        final min = int.tryParse(m.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
        final msRaw = m.group(3) ?? '0';
        final ms = int.tryParse(msRaw.padRight(3, '0').substring(0, 3)) ?? 0;
        final body = (m.group(4) ?? '').trim();
        if (body.isNotEmpty) {
          lines.add(body);
          stamps.add(LrcLine(Duration(milliseconds: min * 60000 + sec * 1000 + ms), body));
        }
      } else {
        lines.add(t);
        stamps.add(null);
      }
    }

    setState(() {
      _lineTexts = lines;
      _syncTimestamps = stamps;
      _cursorIdx = _cursorIdx.clamp(0, lines.isEmpty ? 0 : lines.length - 1);
    });
  }

  void _syncLinesBackToEditor() {
    final buf = StringBuffer();
    for (int i = 0; i < _lineTexts.length; i++) {
      final stamp = _syncTimestamps[i];
      if (stamp != null) {
        final totalMs = stamp.time.inMilliseconds.clamp(0, 99999999);
        final mm = (totalMs ~/ 60000).toString().padLeft(2, '0');
        final ss = ((totalMs % 60000) ~/ 1000).toString().padLeft(2, '0');
        final xx = ((totalMs % 1000) ~/ 10).toString().padLeft(2, '0');
        buf.writeln('[$mm:$ss.$xx]${_lineTexts[i]}');
      } else {
        buf.writeln(_lineTexts[i]);
      }
    }
    _editorCtrl.text = buf.toString().trim();
  }

  void _stampCurrentLine() {
    if (_lineTexts.isEmpty) {
      _toast('Write or paste lyrics in Write tab first, or type a line below!');
      return;
    }
    final pos = widget.service.position;
    setState(() {
      _syncTimestamps[_cursorIdx] = LrcLine(pos, _lineTexts[_cursorIdx]);
      if (_cursorIdx + 1 < _lineTexts.length) {
        _cursorIdx++;
      }
    });
    _syncLinesBackToEditor();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCursor());
  }

  void _addAndStampLiveLine() {
    final txt = _liveLineCtrl.text.trim();
    if (txt.isEmpty) return;
    final pos = widget.service.position;
    setState(() {
      _lineTexts.add(txt);
      _syncTimestamps.add(LrcLine(pos, txt));
      _cursorIdx = _lineTexts.length - 1;
      _liveLineCtrl.clear();
    });
    _syncLinesBackToEditor();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCursor());
  }

  void _scrollToCursor() {
    final ctx = _rowKeys[_cursorIdx]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text?.trim() ?? '';
    if (txt.isEmpty) {
      _toast('Clipboard is empty');
      return;
    }
    setState(() => _editorCtrl.text = txt);
    _rebuildLinesFromEditor();
    _toast('Lyrics pasted from clipboard');
  }

  Future<void> _importFromFile() async {
    try {
      final lyricsDir = await LrcStorageService.lyricsFolderPath();
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc', 'txt'],
        initialDirectory: lyricsDir,
      );
      final path = res?.files.single.path;
      if (path == null) return;
      final raw = await File(path).readAsString();
      setState(() => _editorCtrl.text = raw);
      _rebuildLinesFromEditor();
      _toast('Loaded ${p.basename(path)}');
    } catch (e) {
      _toast('Import failed: $e');
    }
  }

  Future<void> _saveAndReturn() async {
    if (_lineTexts.isEmpty) _rebuildLinesFromEditor();
    if (_lineTexts.isEmpty) {
      _toast('Add at least one lyric line before saving');
      return;
    }
    setState(() => _saving = true);

    final stamped = <LrcLine>[];
    for (int i = 0; i < _lineTexts.length; i++) {
      final t = _syncTimestamps[i];
      if (t != null) stamped.add(LrcLine(t.time, _lineTexts[i]));
    }
    final plain = _lineTexts.join('\n');

    final path = await LrcStorageService.saveLyricsForSong(
      songPath: widget.song.filePath,
      title: widget.song.displayTitle,
      artist: widget.song.displayArtist,
      album: widget.song.displayAlbum,
      syncedLines: stamped,
      plainText: stamped.isEmpty ? plain : '',
      writeSidecar: true,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(ResolvedLyrics(
      syncedLines: stamped,
      plainText: stamped.isEmpty ? plain : '',
      sourceLabel: stamped.isNotEmpty ? 'Makaw Studio (.lrc)' : 'Makaw Studio (Plain)',
      lrcFilePath: path,
    ));
  }

  String _fmtMs(Duration d) {
    final total = d.inMilliseconds.clamp(0, 99999999);
    final mm = (total ~/ 60000).toString().padLeft(2, '0');
    final ss = ((total % 60000) ~/ 1000).toString().padLeft(2, '0');
    final cs = ((total % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$mm:$ss.$cs';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Lyrics Creator Studio', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _saveAndReturn,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                : const Icon(Icons.save_rounded, color: Color(0xFF10B981), size: 19),
            label: const Text('Save .lrc', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _accent,
          labelColor: _accent,
          unselectedLabelColor: const Color(0xFF94A3B8),
          onTap: (idx) {
            if (idx == 1) _rebuildLinesFromEditor();
            else _syncLinesBackToEditor();
          },
          tabs: const [
            Tab(icon: Icon(Icons.edit_document, size: 18), text: '1. Write / Paste Lyrics'),
            Tab(icon: Icon(Icons.timer_rounded, size: 18), text: '2. Live Tap-to-Sync'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildAudioDeck(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildWriteTab(),
                _buildSyncTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioDeck() {
    final s = widget.service;
    final durMs = s.duration.inMilliseconds.clamp(1, 1 << 30);
    final posMs = s.position.inMilliseconds.clamp(0, durMs);
    final speed = s.player.speed;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF101728),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              MediaArtworkWidget(
                filePath: widget.song.filePath,
                isVideo: false,
                width: 40,
                height: 40,
                borderRadius: BorderRadius.circular(8),
                fallbackColor: const Color(0xFF1E293B),
                iconColor: _accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.song.displayTitle, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    Text(widget.song.displayArtist, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _accent.withValues(alpha: 0.4)),
                ),
                child: Text(_fmtMs(s.position), style: const TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              ),
            ],
          ),
          SliderTheme(
            data: const SliderThemeData(
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: _accent,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: posMs / durMs,
              onChanged: (v) => s.seek(Duration(milliseconds: (v * durMs).round())),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_5_rounded, color: Colors.white70, size: 22),
                tooltip: 'Back 3s',
                onPressed: () => s.seek(Duration(milliseconds: (posMs - 3000).clamp(0, durMs))),
              ),
              GestureDetector(
                onTap: () => s.togglePlayPause(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                  ),
                  child: Icon(s.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 26),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.forward_5_rounded, color: Colors.white70, size: 22),
                tooltip: 'Forward 3s',
                onPressed: () => s.seek(Duration(milliseconds: (posMs + 3000).clamp(0, durMs))),
              ),
              ActionChip(
                backgroundColor: _card,
                side: const BorderSide(color: Color(0xFF334155)),
                label: Text('${speed.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}x',
                    style: const TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () {
                  final next = speed == 1.0 ? 0.75 : (speed == 0.75 ? 0.85 : 1.0);
                  s.player.setSpeed(next);
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWriteTab() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipAction(Icons.content_paste_rounded, 'Paste', _pasteFromClipboard),
                const SizedBox(width: 8),
                _chipAction(Icons.copy_rounded, 'Copy', () {
                  Clipboard.setData(ClipboardData(text: _editorCtrl.text));
                  _toast('Copied lyrics text');
                }),
                const SizedBox(width: 8),
                _chipAction(Icons.folder_open_rounded, 'Import File', _importFromFile),
                const SizedBox(width: 8),
                _chipAction(Icons.timer_off_outlined, 'Strip Timers', () {
                  final cleaned = _editorCtrl.text
                      .replaceAll(RegExp(r'\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]'), '')
                      .replaceAll(RegExp(r'^\[(ti|ar|al|by|length|offset):.*\]\r?\n?', multiLine: true, caseSensitive: false), '')
                      .trim();
                  setState(() => _editorCtrl.text = cleaned);
                  _rebuildLinesFromEditor();
                }),
                const SizedBox(width: 8),
                _chipAction(Icons.arrow_forward_rounded, 'Go to Sync ->', () {
                  _rebuildLinesFromEditor();
                  _tabCtrl.animateTo(1);
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              controller: _editorCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.55),
              decoration: InputDecoration(
                hintText: 'Type or paste one lyric line per row here...\n\nExample:\nFirst verse line\nSecond verse line\n\nThen switch to "2. Live Tap-to-Sync" to stamp timestamps while listening!',
                hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1E293B))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipAction(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: _accent),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        backgroundColor: _card,
        side: const BorderSide(color: Color(0xFF334155)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildSyncTab() {
    final curStamp = _fmtMs(widget.service.position);
    return Column(
      children: [
        Expanded(
          child: _lineTexts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lyrics_outlined, color: Colors.white24, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'Type lines live below while the song plays, or paste full lyrics in Tab 1.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _syncScrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _lineTexts.length,
                  itemBuilder: (_, i) {
                    final key = _rowKeys.putIfAbsent(i, () => GlobalKey());
                    final stamp = _syncTimestamps[i];
                    final isCursor = i == _cursorIdx;
                    final isCurrentPlaying = stamp != null &&
                        stamp.time <= widget.service.position &&
                        (i + 1 >= _syncTimestamps.length ||
                            _syncTimestamps[i + 1] == null ||
                            _syncTimestamps[i + 1]!.time > widget.service.position);

                    return GestureDetector(
                      key: key,
                      onTap: () => setState(() => _cursorIdx = i),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isCursor ? const Color(0xFF1E2942) : _card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCursor
                                ? _accent
                                : (isCurrentPlaying ? const Color(0xFF10B981) : const Color(0xFF1E293B)),
                            width: isCursor ? 1.5 : 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: stamp != null ? () => widget.service.seek(stamp.time) : null,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 68,
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                  color: stamp != null
                                      ? _accent.withValues(alpha: 0.18)
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  stamp != null ? _fmtMs(stamp.time) : '--:--.--',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: stamp != null ? _accent : Colors.white38,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _lineTexts[i],
                                style: TextStyle(
                                  color: isCursor ? Colors.white : Colors.white70,
                                  fontSize: 13.5,
                                  fontWeight: isCursor ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (stamp != null) ...[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                icon: const Icon(Icons.remove, color: Colors.white54, size: 15),
                                tooltip: '-0.2s',
                                onPressed: () {
                                  setState(() {
                                    final nextMs = (stamp.time.inMilliseconds - 200).clamp(0, 99999999);
                                    _syncTimestamps[i] = LrcLine(Duration(milliseconds: nextMs), _lineTexts[i]);
                                  });
                                  _syncLinesBackToEditor();
                                },
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                icon: const Icon(Icons.add, color: Colors.white54, size: 15),
                                tooltip: '+0.2s',
                                onPressed: () {
                                  setState(() {
                                    final nextMs = stamp.time.inMilliseconds + 200;
                                    _syncTimestamps[i] = LrcLine(Duration(milliseconds: nextMs), _lineTexts[i]);
                                  });
                                  _syncLinesBackToEditor();
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Live Type & Stamp input row + Master Stamp Button
        Container(
          padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 10),
          decoration: const BoxDecoration(
            color: _card,
            border: Border(top: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _liveLineCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Type next line live while playing...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: _bg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                      ),
                      onSubmitted: (_) => _addAndStampLiveLine(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _addAndStampLiveLine,
                    child: const Text('Add & Stamp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_lineTexts.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _stampCurrentLine,
                      icon: const Icon(Icons.timer_rounded, color: Colors.white, size: 20),
                      label: Text(
                        'STAMP LINE #${_cursorIdx + 1} & NEXT  ($curStamp)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
