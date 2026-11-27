import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../../core/storage/lrc_storage_service.dart';
import '../../../../core/storage/lyric_service.dart';
import '../../../documents/presentation/pages/folders_page.dart';
import '../../../music/data/services/music_player_service.dart';
import '../../../music/presentation/pages/lyrics_creator_page.dart';

class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<_SongGroup> _groups = [];
  List<File> _lrcFiles = [];
  String _lyricsFolder = '';
  bool _isLoading = true;
  String _query = '';
  final _searchController = TextEditingController();

  _SongGroup? _selectedGroup;
  List<Lyric> _selectedLines = [];
  File? _selectedFile;
  String _selectedFileContent = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final q = _query.trim().toLowerCase();

    final folder = await LrcStorageService.lyricsFolderPath();
    final files = await LrcStorageService.listFolderLrcFiles();
    final filteredFiles = q.isEmpty
        ? files
        : files.where((f) => p.basename(f.path).toLowerCase().contains(q)).toList();

    final search = q.isNotEmpty ? await LyricService.search(_query.trim()) : await LyricService.listSongs();
    final grouped = <String, List<Lyric>>{};
    for (final l in search) {
      grouped.putIfAbsent(l.songId, () => []).add(l);
    }
    final groups = grouped.entries
        .map((e) => _SongGroup(e.key, e.value.first.songTitle, e.value.first.artist, e.value))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    if (mounted) {
      setState(() {
        _lyricsFolder = folder;
        _lrcFiles = filteredFiles;
        _groups = groups;
        _isLoading = false;
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pasteNewLrc() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final titleCtrl = TextEditingController();
    final artistCtrl = TextEditingController();
    final bodyCtrl = TextEditingController(text: data?.text ?? '');

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Save Pasted Lyrics / .LRC', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Song Title *',
                  labelStyle: TextStyle(color: Colors.white60),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: artistCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Artist',
                  labelStyle: TextStyle(color: Colors.white60),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                maxLines: 8,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: '[00:12.40] Line of lyrics...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF472B6), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save .lrc'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _toast('Song title and lyrics are required');
      return;
    }
    final parsed = LrcStorageService.parseLrc(body);
    await LrcStorageService.saveLyricsForSong(
      songPath: '',
      title: title,
      artist: artistCtrl.text.trim(),
      syncedLines: parsed,
      plainText: parsed.isEmpty ? body : '',
    );
    _toast('Saved to MakawLyrics folder');
    await _load();
  }

  Future<void> _importFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc', 'txt'],
      );
      final src = picked?.files.single.path;
      if (src == null) return;
      final folder = await LrcStorageService.lyricsFolderPath();
      final destPath = p.join(folder, p.basename(src));
      final raw = await File(src).readAsString();
      await File(destPath).writeAsString(raw);
      final base = p.basenameWithoutExtension(src);
      final parsed = LrcStorageService.parseLrc(raw);
      await LrcStorageService.saveLyricsForSong(
        songPath: '',
        title: base,
        artist: '',
        syncedLines: parsed,
        plainText: parsed.isEmpty ? raw : '',
      );
      _toast('Imported ${p.basename(src)} into MakawLyrics');
      await _load();
    } catch (e) {
      _toast('Import error: $e');
    }
  }

  Future<void> _launchCreatorForSong() async {
    final music = MusicPlayerService.shared;
    SongInfo? target = music?.currentSong;
    if (target == null && music != null && music.allSongs.isNotEmpty) {
      target = await showModalBottomSheet<SongInfo>(
        context: context,
        backgroundColor: const Color(0xFF1E293B),
        builder: (ctx) => ListView.builder(
          itemCount: music.allSongs.length,
          itemBuilder: (_, i) {
            final s = music.allSongs[i];
            return ListTile(
              leading: const Icon(Icons.music_note, color: Color(0xFFF472B6)),
              title: Text(s.displayTitle, style: const TextStyle(color: Colors.white)),
              subtitle: Text(s.displayArtist, style: const TextStyle(color: Colors.white54)),
              onTap: () => Navigator.pop(ctx, s),
            );
          },
        ),
      );
    }
    if (target == null || music == null) {
      _toast('Play or scan a song in Music to time lyrics');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LyricsCreatorPage(service: music, song: target!)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final inDetail = _selectedGroup != null || _selectedFile != null;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (inDetail) {
              setState(() {
                _selectedGroup = null;
                _selectedLines = [];
                _selectedFile = null;
                _selectedFileContent = '';
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: inDetail
            ? Text(
                _selectedFile != null
                    ? p.basenameWithoutExtension(_selectedFile!.path)
                    : _selectedGroup!.title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              )
            : TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search lyrics & .lrc files',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: Colors.white38, size: 22),
                  prefixIconConstraints: BoxConstraints(minWidth: 36),
                ),
                onChanged: (v) {
                  _query = v.trim();
                  _load();
                },
              ),
        actions: [
          if (!inDetail && _query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                _query = '';
                _load();
              },
            ),
          if (!inDetail) ...[
            IconButton(
              tooltip: 'Paste .lrc / Lyrics',
              icon: const Icon(Icons.content_paste_rounded, color: Colors.white70),
              onPressed: _pasteNewLrc,
            ),
            IconButton(
              tooltip: 'Import .lrc File',
              icon: const Icon(Icons.file_upload_outlined, color: Colors.white70),
              onPressed: _importFile,
            ),
            IconButton(
              tooltip: 'Open MakawLyrics Folder',
              icon: const Icon(Icons.folder_open_rounded, color: Color(0xFFF472B6)),
              onPressed: () {
                if (_lyricsFolder.isEmpty) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FoldersPage(
                      initialPath: _lyricsFolder,
                      openFile: (path) async => OpenFilex.open(path),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
        bottom: inDetail
            ? null
            : TabBar(
                controller: _tabCtrl,
                indicatorColor: const Color(0xFFF472B6),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(text: 'MakawLyrics (${_lrcFiles.length})'),
                  Tab(text: 'Library (${_groups.length})'),
                ],
              ),
      ),
      floatingActionButton: inDetail
          ? null
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFFF472B6),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Lyrics Creator', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: _launchCreatorForSong,
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF472B6)))
          : _selectedFile != null
              ? _buildFileDetail()
              : _selectedGroup != null
                  ? _buildDbDetail()
                  : TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _lrcFiles.isEmpty ? _buildEmptyFilesState() : _buildFilesList(),
                        _groups.isEmpty ? _buildEmptyState() : _buildDbList(),
                      ],
                    ),
    );
  }

  Widget _buildEmptyFilesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_special_outlined, size: 60, color: Colors.white24),
            const SizedBox(height: 14),
            const Text('No .lrc files in MakawLyrics yet', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(_lyricsFolder, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pasteNewLrc,
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: const Text('Paste Lyrics'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF472B6), foregroundColor: Colors.black),
                  onPressed: _launchCreatorForSong,
                  icon: const Icon(Icons.timer, size: 16),
                  label: const Text('Open Lyrics Creator'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lyrics_outlined, size: 60, color: Colors.white24),
          const SizedBox(height: 14),
          Text(
            _query.isNotEmpty ? 'No results' : 'No saved library lyrics',
            style: const TextStyle(color: Colors.white54, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Synced lyrics fetched or created in Music appear here',
            style: TextStyle(color: Colors.white38, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 84),
      itemCount: _lrcFiles.length,
      itemBuilder: (_, i) {
        final f = _lrcFiles[i];
        final name = p.basename(f.path);
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFF1E293B),
            child: Icon(Icons.subtitles_outlined, color: Color(0xFFF472B6)),
          ),
          title: Text(p.basenameWithoutExtension(f.path), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(name, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () async {
            final content = await f.readAsString();
            if (!mounted) return;
            setState(() {
              _selectedFile = f;
              _selectedFileContent = content;
            });
          },
        );
      },
    );
  }

  Widget _buildDbList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 84),
      itemCount: _groups.length,
      itemBuilder: (_, i) {
        final g = _groups[i];
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFF1E293B),
            child: Icon(Icons.music_note, color: Color(0xFFF472B6)),
          ),
          title: Text(g.title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(g.artist ?? '', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () async {
            final lines = g.items.any((l) => l.startMs != null)
                ? await LyricService.linesForSong(g.songId)
                : g.items;
            if (!mounted) return;
            setState(() {
              _selectedGroup = g;
              _selectedLines = lines;
            });
          },
        );
      },
    );
  }

  Widget _buildFileDetail() {
    final file = _selectedFile!;
    final parsed = LrcStorageService.parseLrc(_selectedFileContent);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      backgroundColor: const Color(0xFF1E293B),
                      avatar: const Icon(Icons.copy_all, size: 15, color: Color(0xFFF472B6)),
                      label: const Text('Copy .lrc', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _selectedFileContent));
                        _toast('Copied .lrc content');
                      },
                    ),
                    ActionChip(
                      backgroundColor: const Color(0xFF1E293B),
                      avatar: const Icon(Icons.notes, size: 15, color: Colors.white70),
                      label: const Text('Copy Text', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: () {
                        final plain = parsed.isNotEmpty
                            ? parsed.map((l) => l.text).join('\n')
                            : _selectedFileContent;
                        Clipboard.setData(ClipboardData(text: plain));
                        _toast('Copied plain lyrics');
                      },
                    ),
                    ActionChip(
                      backgroundColor: const Color(0xFF1E293B),
                      avatar: const Icon(Icons.edit_note, size: 15, color: Color(0xFF818CF8)),
                      label: const Text('Edit', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: () => _editRawFile(file),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171)),
                onPressed: () async {
                  try {
                    await file.delete();
                  } catch (_) {}
                  setState(() {
                    _selectedFile = null;
                    _selectedFileContent = '';
                  });
                  await _load();
                },
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF1E293B), height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: parsed.isEmpty
                ? SelectableText(
                    _selectedFileContent,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.7),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: parsed
                        .map((l) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _fmtTime(l.time.inMilliseconds),
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontFamily: 'monospace'),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(l.text, style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.5)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _editRawFile(File file) async {
    final ctrl = TextEditingController(text: _selectedFileContent);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Edit ${p.basename(file.path)}', style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: TextField(
            controller: ctrl,
            maxLines: null,
            expands: true,
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontFamily: 'monospace'),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await file.writeAsString(ctrl.text);
      if (mounted) {
        setState(() => _selectedFileContent = ctrl.text);
        _toast('Saved ${p.basename(file.path)}');
      }
    }
  }

  Widget _buildDbDetail() {
    final g = _selectedGroup!;
    final s = g.items.first;
    final hasTimed = _selectedLines.any((l) => l.startMs != null);
    final asLrc = hasTimed
        ? LrcStorageService.formatLrc(
            lines: _selectedLines
                .where((l) => l.startMs != null)
                .map((l) => LrcLine(Duration(milliseconds: l.startMs!), l.text))
                .toList(),
            title: s.songTitle,
            artist: s.artist ?? '',
          )
        : s.text;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      backgroundColor: const Color(0xFF1E293B),
                      avatar: const Icon(Icons.copy_all, size: 15, color: Color(0xFFF472B6)),
                      label: Text(hasTimed ? 'Copy .lrc' : 'Copy Text', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: asLrc));
                        _toast('Copied lyrics');
                      },
                    ),
                    ActionChip(
                      backgroundColor: const Color(0xFF1E293B),
                      avatar: const Icon(Icons.save_alt, size: 15, color: Color(0xFF10B981)),
                      label: const Text('Export .lrc', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: () async {
                        final path = await LrcStorageService.saveLyricsForSong(
                          songPath: '',
                          title: s.songTitle,
                          artist: s.artist ?? '',
                          syncedLines: hasTimed
                              ? _selectedLines
                                  .where((l) => l.startMs != null)
                                  .map((l) => LrcLine(Duration(milliseconds: l.startMs!), l.text))
                                  .toList()
                              : [],
                          plainText: hasTimed ? '' : s.text,
                        );
                        _toast('Saved ${p.basename(path)}');
                        await _load();
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171)),
                onPressed: () async {
                  await LyricService.deleteSong(s.songId);
                  setState(() {
                    _selectedGroup = null;
                    _selectedLines = [];
                  });
                  await _load();
                },
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF1E293B), height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: !hasTimed
                ? SelectableText(s.text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.7))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _selectedLines
                        .map((l) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _fmtTime(l.startMs ?? 0),
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontFamily: 'monospace'),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(l.text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }

  String _fmtTime(int ms) {
    final s = (ms / 1000).floor();
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _SongGroup {
  final String songId;
  final String title;
  final String? artist;
  final List<Lyric> items;
  _SongGroup(this.songId, this.title, this.artist, this.items);
}
