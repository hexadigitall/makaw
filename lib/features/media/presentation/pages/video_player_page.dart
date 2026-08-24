import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../data/services/video_db_service.dart';
import '../../data/services/subtitle_service.dart';

class MakawVideoPlayerScreen extends StatefulWidget {
  final String videoPath;
  final String videoTitle;

  const MakawVideoPlayerScreen({
    super.key,
    required this.videoPath,
    required this.videoTitle,
  });

  @override
  State<MakawVideoPlayerScreen> createState() => _MakawVideoPlayerScreenState();
}

class _MakawVideoPlayerScreenState extends State<MakawVideoPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  bool _showControls = true;
  String? _gestureIndicator;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
      ]);
    }

    _player = Player();
    _videoController = VideoController(_player);
    _initAndResumePlayback();
  }

  Future<void> _initAndResumePlayback() async {
    final record = await MakawVideoDbService.getRecord(widget.videoPath);
    await _player.open(Media(widget.videoPath));

    if (record != null && !record.isCompleted && record.positionMs > 5000) {
      await _player.seek(Duration(milliseconds: record.positionMs));
      if (mounted) {
        _showToast('Resumed from ${_fmt(Duration(milliseconds: record.positionMs))}');
      }
    }

    _player.stream.position.listen((pos) {
      final duration = _player.state.duration.inMilliseconds;
      if (duration > 0) {
        MakawVideoDbService.savePlaybackPosition(
          path: widget.videoPath,
          title: widget.videoTitle,
          positionMs: pos.inMilliseconds,
          durationMs: duration,
        );
      }
    });
  }

  @override
  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    _player.dispose();
    super.dispose();
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  void _showSubtitlesModal() {
    final searchController = TextEditingController(text: widget.videoTitle);
    List<SubtitleResult> results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF252526),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Expanded(child: TextField(
                controller: searchController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Search OpenSubtitles'),
              )),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.blueAccent),
                onPressed: () async {
                  setModalState(() => searching = true);
                  final res = await MakawSubtitleService.searchSubtitles(searchController.text);
                  setModalState(() { results = res; searching = false; });
                },
              ),
            ]),
            const SizedBox(height: 12),
            if (searching) const LinearProgressIndicator(color: Colors.blueAccent)
            else Expanded(child: results.isEmpty
                ? const Center(child: Text('No subtitles found.', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final sub = results[index];
                      return ListTile(
                        leading: const Icon(Icons.subtitles, color: Colors.amberAccent),
                        title: Text(sub.fileName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: Text('Lang: ${sub.language.toUpperCase()} • Rating: ${sub.rating}', style: const TextStyle(color: Colors.white38)),
                        trailing: IconButton(
                          icon: const Icon(Icons.download, color: Colors.blueAccent),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final file = await MakawSubtitleService.downloadSubtitle(sub.fileId, widget.videoPath);
                            if (file != null) {
                              await _player.setSubtitleTrack(SubtitleTrack.uri(file.path));
                              _showToast('Subtitle applied!');
                            }
                          },
                        ),
                      );
                    },
                  )),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(children: [
          Center(child: Video(controller: _videoController, controls: NoVideoControls)),
          if (_gestureIndicator != null)
            Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
              child: Text(_gestureIndicator!, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            )),
          if (_showControls) _buildControlsOverlay(),
        ]),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      color: Colors.black45,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppBar(
            backgroundColor: Colors.transparent, elevation: 0,
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
            title: Text(widget.videoTitle, style: const TextStyle(fontSize: 15)),
            actions: [
              IconButton(icon: const Icon(Icons.subtitles_outlined), tooltip: 'Subtitles', onPressed: _showSubtitlesModal),
              IconButton(
                icon: const Icon(Icons.audiotrack),
                tooltip: 'Audio Tracks',
                onPressed: () {
                  final tracks = _player.state.tracks.audio;
                  showModalBottomSheet(
                    context: context, backgroundColor: const Color(0xFF252526),
                    builder: (_) => ListView(children: tracks.map((t) => ListTile(
                      title: Text(t.title ?? t.language ?? 'Track ${t.id}', style: const TextStyle(color: Colors.white)),
                      onTap: () { _player.setAudioTrack(t); Navigator.pop(context); },
                    )).toList()),
                  );
                },
              ),
            ],
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(iconSize: 40, icon: const Icon(Icons.replay_10, color: Colors.white),
              onPressed: () => _player.seek(_player.state.position - const Duration(seconds: 10))),
            const SizedBox(width: 24),
            StreamBuilder<bool>(
              stream: _player.stream.playing,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? true;
                return IconButton(
                  iconSize: 64,
                  icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, color: Colors.blueAccent),
                  onPressed: _player.playOrPause,
                );
              },
            ),
            const SizedBox(width: 24),
            IconButton(iconSize: 40, icon: const Icon(Icons.forward_10, color: Colors.white),
              onPressed: () => _player.seek(_player.state.position + const Duration(seconds: 10))),
          ]),
          StreamBuilder<Duration>(
            stream: _player.stream.position,
            builder: (context, snapshot) {
              final pos = snapshot.data ?? Duration.zero;
              final dur = _player.state.duration;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Expanded(child: Slider(
                    value: dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0,
                    onChanged: (val) => _player.seek(Duration(milliseconds: (val * dur.inMilliseconds).toInt())),
                  )),
                  Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}
