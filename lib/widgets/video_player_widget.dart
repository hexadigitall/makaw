import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import '../services/video_player_service.dart';

// ─── Subtitle data ───────────────────────────────────────────────────────────
class _SubtitleEntry {
  final Duration start;
  final Duration end;
  final String text;
  const _SubtitleEntry(this.start, this.end, this.text);
}

List<_SubtitleEntry> _parseSrt(String data) {
  final entries = <_SubtitleEntry>[];
  final blocks = data.trim().split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.length < 3) continue;
    final timeLine = lines[1].trim();
    final times = timeLine.split(RegExp(r'\s*-->\s*'));
    if (times.length != 2) continue;
    final parseTime = (String s) {
      final parts = s.replaceAll(',', '.').split(':');
      if (parts.length == 3) {
        return Duration(
          hours: int.tryParse(parts[0]) ?? 0,
          minutes: int.tryParse(parts[1]) ?? 0,
          seconds: (double.tryParse(parts[2]) ?? 0).toInt(),
          milliseconds: ((double.tryParse(parts[2]) ?? 0) % 1 * 1000).round(),
        );
      }
      return Duration.zero;
    };
    final start = parseTime(times[0]);
    final end = parseTime(times[1]);
    final text = lines.sublist(2).join('\n').trim();
    if (text.isNotEmpty) entries.add(_SubtitleEntry(start, end, text));
  }
  return entries;
}

// ─── Thumbnail widget (placeholder for now) ─────────────────────────────
class _ThumbnailView extends StatelessWidget {
  final String filePath;
  final Map<String, String> thumbCache;
  const _ThumbnailView({required this.filePath, required this.thumbCache});

  @override
  Widget build(BuildContext context) {
    return Container(color: const Color(0xFF1A202C), child: const Center(child: Icon(Icons.videocam, color: Color(0xFF818CF8), size: 32)));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen video player
// ─────────────────────────────────────────────────────────────────────────────
// Full-screen video player
// ─────────────────────────────────────────────────────────────────────────────
class DirectVideoPlayer extends StatefulWidget {
  final String? filePath;
  final String? url;
  final String title;
  final List<String>? playlist;
  final int initialIndex;
  final VoidCallback? onClose;
  const DirectVideoPlayer({super.key, this.filePath, this.url, this.title = '', this.playlist, this.initialIndex = 0, this.onClose});
  @override
  State<DirectVideoPlayer> createState() => _DirectVideoPlayerState();
}

class _DirectVideoPlayerState extends State<DirectVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  int _currentIndex = 0;
  String _dimensionMode = 'bestfit';
  static const _modes = ['bestfit', 'fit', 'fill', '16:9', '4:3', 'center'];
  static const _modeLabels = ['Best Fit', 'Fit Screen', 'Fill', '16:9', '4:3', 'Center'];
  bool _subtitleOn = false;
  bool _locked = false;
  List<_SubtitleEntry> _subtitles = [];
  String _subtitlePath = '';
  String _subtitleFileLabel = '';
  Timer? _subtitleTimer;
  double _subFontSize = 16;
  String _subFont = 'default';
  Color _subColor = Colors.white;
  bool _subShadow = true;
  bool _subBold = false;
  TextAlign _subAlign = TextAlign.center;
  bool _subBg = false;
  bool _subOutline = true;
  double _subOutlineSize = 1.0;
  Color _subOutlineColor = Colors.black87;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _initPlayer();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF0F0F1A),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  void _initPlayer() {
    final path = _currentFile();
    if (path != null && File(path).existsSync()) {
      _controller = VideoPlayerController.file(File(path));
    } else if (path != null && (path.startsWith('http://') || path.startsWith('https://'))) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(path));
    } else if (widget.url != null) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    }
    if (_controller == null) {
      setState(() => _initialized = true);
      return;
    }
    _controller!.initialize().then((_) {
      if (!mounted) return;
      _controller!.addListener(_onVideoEvent);
      _controller!.play();
      setState(() => _initialized = true);
      _startAutoHide();
      _loadSubtitlesForFile();
    }).catchError((e) {
      if (!mounted) return;
      print('Video init error: $e');
      setState(() => _initialized = true);
    });
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && !_initialized) {
        setState(() => _initialized = true);
      }
    });
  }

  void _onVideoEvent() {
    if (!mounted || _controller == null) return;
    setState(() => _isPlaying = _controller!.value.isPlaying);
  }

  String? _currentFile() {
    if (widget.playlist != null && widget.playlist!.isNotEmpty) return widget.playlist![_currentIndex];
    return widget.filePath ?? widget.url;
  }

  void _startAutoHide() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _subtitleTimer?.cancel();
    _controller?.removeListener(_onVideoEvent);
    _controller?.dispose();
    SystemChrome.restoreSystemUIOverlays();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF0B1119),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    super.dispose();
  }

  void _togglePlay() {
    if (_controller == null) return;
    _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
    _startAutoHide();
  }

  void _onToggleControls() {
    if (_locked) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startAutoHide();
    }
  }

  String _fmt(Duration d) { final m = d.inMinutes.remainder(60).toString().padLeft(2, '0'); final s = d.inSeconds.remainder(60).toString().padLeft(2, '0'); return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s'; }

  void _cycleDim() { final idx = _modes.indexOf(_dimensionMode); setState(() => _dimensionMode = _modes[(idx + 1) % _modes.length]); }

  void _switchVideo(int index) {
    _controller?.removeListener(_onVideoEvent);
    _controller?.pause();
    _controller?.dispose();
    setState(() { _currentIndex = index; _initialized = false; _isPlaying = false; });
    _initPlayer();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return Scaffold(backgroundColor: Colors.black, body: const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8))));
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(backgroundColor: Colors.black, body: const Center(child: Text('Failed to load video', style: TextStyle(color: Colors.white54))));
    }
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    final hasMulti = widget.playlist != null && widget.playlist!.length > 1;
    final curTitle = _currentFile()?.split('\\').last.split('/').last ?? widget.title;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    Widget videoWidget;
    switch (_dimensionMode) {
      case 'fit':
        videoWidget = FittedBox(fit: BoxFit.fill, child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ));
        break;
      case 'fill':
        videoWidget = FittedBox(fit: BoxFit.cover, child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ));
        break;
      case '16:9':
        videoWidget = AspectRatio(aspectRatio: 16 / 9, child: ClipRect(child: FittedBox(fit: BoxFit.contain, child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ))));
        break;
      case '4:3':
        videoWidget = AspectRatio(aspectRatio: 4 / 3, child: ClipRect(child: FittedBox(fit: BoxFit.contain, child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ))));
        break;
      default:
        videoWidget = FittedBox(fit: BoxFit.contain, child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: _onToggleControls,
            child: Container(
              color: Colors.black,
              width: double.infinity, height: double.infinity,
              child: videoWidget,
            ),
          ),
          if (_showControls && !_locked && !isLandscape)
            _buildSeekOverlay(pos),
          if (_showControls && !_locked) ...[
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.only(top: topPad + 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87.withOpacity(0.7), Colors.transparent]),
                ),
                child: _buildTopBar(curTitle, isLandscape),
              ),
            ),
            Positioned(
              left: 32, right: 32,
              bottom: bottomPad + 172,
              child: _subtitleOn && _subtitles.isNotEmpty
                  ? _buildStyledSubtitle()
                  : const SizedBox.shrink(),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.only(bottom: bottomPad + 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
                ),
                child: _buildBottomControls(pos, dur, hasMulti, isLandscape),
              ),
            ),
          ],
          if (_locked)
            Center(
              child: GestureDetector(
                onTap: () => setState(() => _locked = false),
                child: const Icon(Icons.lock, color: Colors.white54, size: 40),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(String title, bool isLandscape) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22), onPressed: () => (widget.onClose ?? () => Navigator.pop(context))()),
            if (isLandscape) IconButton(icon: const Icon(Icons.queue_music, color: Colors.white70, size: 20), onPressed: _showPlaylistSheet),
            Expanded(
              child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            ),
            if (!isLandscape)
              Column(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.cast, color: Colors.white70, size: 18), constraints: const BoxConstraints(), padding: EdgeInsets.zero, onPressed: _toastCast),
                IconButton(icon: const Icon(Icons.screenshot_monitor, color: Colors.white70, size: 18), constraints: const BoxConstraints(), padding: EdgeInsets.zero, onPressed: _toastCapture),
                IconButton(icon: const Icon(Icons.volume_up, color: Colors.white70, size: 18), constraints: const BoxConstraints(), padding: EdgeInsets.zero, onPressed: _toastMute),
                IconButton(icon: const Icon(Icons.screen_rotation, color: Colors.white70, size: 18), constraints: const BoxConstraints(), padding: EdgeInsets.zero, onPressed: () => SystemChrome.setPreferredOrientations(DeviceOrientation.values)),
              ])
            else
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.cast, color: Colors.white70, size: 20), onPressed: _toastCast),
                IconButton(icon: const Icon(Icons.screenshot_monitor, color: Colors.white70, size: 20), onPressed: _toastCapture),
                IconButton(icon: const Icon(Icons.volume_up, color: Colors.white70, size: 20), onPressed: _toastMute),
                IconButton(icon: const Icon(Icons.screen_rotation, color: Colors.white70, size: 20), onPressed: () => SystemChrome.setPreferredOrientations(DeviceOrientation.values)),
              ]),
          ],
        ),
        if (!isLandscape)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(icon: const Icon(Icons.queue_music, color: Colors.white70, size: 18), constraints: const BoxConstraints(), padding: EdgeInsets.zero, onPressed: _showPlaylistSheet),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSeekOverlay(Duration pos) {
    return Positioned(
      left: 0, right: 0, top: 0, bottom: 0,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _controller!.seekTo(Duration(seconds: (pos.inSeconds - 10).clamp(0, 999999))),
              child: Container(
                color: Colors.transparent,
                child: const Center(
                  child: Icon(Icons.replay_10, color: Colors.white38, size: 48),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _controller!.seekTo(Duration(seconds: pos.inSeconds + 10)),
              child: Container(
                color: Colors.transparent,
                child: const Center(
                  child: Icon(Icons.forward_10, color: Colors.white38, size: 48),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(Duration pos, Duration dur, bool hasMulti, bool isLandscape) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _toolBtn(Icons.audiotrack, 'Audio', 18, _toastAudio),
              const SizedBox(width: 4),
              _toolBtn(Icons.subtitles, 'Subtitle', 18, _showSubtitlePanel),
              const SizedBox(width: 4),
              _toolBtn(Icons.speed, 'Speed', 18, _speedSheet),
              const SizedBox(width: 4),
              _toolBtn(Icons.more_horiz, 'Settings', 20, _showVideoSettings),
            ],
          ),
        ),
        if (dur > Duration.zero)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                Expanded(
                  child: SliderTheme(
                    data: const SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5), activeTrackColor: Color(0xFF818CF8), inactiveTrackColor: Colors.white24, thumbColor: Color(0xFF818CF8)),
                    child: Slider(value: pos.inMilliseconds.toDouble().clamp(0, dur.inMilliseconds.toDouble()), max: dur.inMilliseconds.toDouble().clamp(1, double.infinity), onChanged: (v) => _controller!.seekTo(Duration(milliseconds: v.round()))),
                  ),
                ),
                Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ],
            ),
          ),
        SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(_locked ? Icons.lock : Icons.lock_open, color: Colors.white54, size: 20),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                onPressed: () => setState(() => _locked = true),
              ),
              if (isLandscape) ...[
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.replay_10, color: Colors.white70, size: 22), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _controller!.seekTo(Duration(seconds: (pos.inSeconds - 10).clamp(0, 999999)))),
              ],
              if (hasMulti) const SizedBox(width: 4),
              if (hasMulti)
                IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white70, size: 26), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: _currentIndex > 0 ? () => _switchVideo(_currentIndex - 1) : null),
              const SizedBox(width: 6),
              Container(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF818CF8)),
                child: IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  onPressed: _togglePlay,
                ),
              ),
              const SizedBox(width: 6),
              if (hasMulti)
                IconButton(icon: const Icon(Icons.skip_next, color: Colors.white70, size: 26), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: _currentIndex < widget.playlist!.length - 1 ? () => _switchVideo(_currentIndex + 1) : null),
              if (isLandscape) ...[
                if (hasMulti) const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.forward_10, color: Colors.white70, size: 22), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _controller!.seekTo(Duration(seconds: pos.inSeconds + 10))),
              ],
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _cycleDim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(_modeLabels[_modes.indexOf(_dimensionMode)], style: const TextStyle(color: Color(0xFF818CF8), fontSize: 9, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, double size, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white70, size: size),
        ),
      ),
    );
  }

  void _toastCast() => _toast('Cast coming soon');
  void _toastCapture() => _toast('Screen capture coming soon');
  void _toastMute() => _toast('Mute coming soon');
  void _toastAudio() => _toast('Audio track coming soon');

  void _showPlaylistSheet() {
    _toast('Playlist not available');
  }

  void _showVideoInfo() {
    final path = _currentFile() ?? '';
    final name = path.split('\\').last.split('/').last;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Path: $path', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (_controller != null && _controller!.value.isInitialized) ...[
            const SizedBox(height: 4),
            Text('Resolution: ${_controller!.value.size.width}x${_controller!.value.size.height}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('Duration: ${_fmt(_controller!.value.duration)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Color(0xFF818CF8))))],
      ),
    );
  }

  void _jumpToTimeDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Jump to time', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(hintText: 'MM:SS or HH:MM:SS', hintStyle: TextStyle(color: Color(0xFF666680)), border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () {
              final parts = ctrl.text.trim().split(':').map((e) => int.tryParse(e) ?? 0).toList();
              if (parts.length == 2) _controller!.seekTo(Duration(minutes: parts[0], seconds: parts[1]));
              else if (parts.length == 3) _controller!.seekTo(Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]));
              Navigator.pop(ctx);
            },
            child: const Text('Jump', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  void _speedSheet() {
    final cur = _controller!.value.playbackSpeed;
    final presets = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0];
    const accent = Color(0xFF818CF8);
    const card = Color(0xFF1A1A2E);
    showModalBottomSheet(
      context: context, backgroundColor: card, isScrollControlled: true,
      builder: (ctx) {
        double val = cur;
        return StatefulBuilder(
          builder: (ctx, setDlg) => DraggableScrollableSheet(
            initialChildSize: 0.55, maxChildSize: 0.75, minChildSize: 0.3,
            builder: (_, sc) => ListView(
              controller: sc,
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Playback Speed', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 28),
                      onPressed: () {
                        val = (val - 0.25).clamp(0.25, 4.0);
                        _controller!.setPlaybackSpeed(val);
                        setDlg(() {});
                      },
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        final ctrl = TextEditingController(text: val.toStringAsFixed(2));
                        showDialog(
                          context: ctx,
                          builder: (dCtx) => AlertDialog(
                            backgroundColor: card,
                            title: const Text('Enter speed', style: TextStyle(color: Colors.white, fontSize: 15)),
                            content: TextField(
                              controller: ctrl, autofocus: true, keyboardType: TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: const InputDecoration(hintText: 'e.g. 1.5', hintStyle: TextStyle(color: Color(0xFF666680)), border: OutlineInputBorder()),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
                              TextButton(
                                onPressed: () {
                                  final v = double.tryParse(ctrl.text.trim());
                                  if (v != null && v >= 0.25 && v <= 4.0) {
                                    val = v;
                                    _controller!.setPlaybackSpeed(val);
                                    setDlg(() {});
                                  }
                                  Navigator.pop(dCtx);
                                },
                                child: const Text('Set', style: TextStyle(color: accent)),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(12)),
                        child: Text('${val.toStringAsFixed(2)}x'.replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), ''), style: const TextStyle(color: Colors.black, fontSize: 28, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 28),
                      onPressed: () {
                        val = (val + 0.25).clamp(0.25, 4.0);
                        _controller!.setPlaybackSpeed(val);
                        setDlg(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white54, size: 22),
                      onPressed: () {
                        final ctrl = TextEditingController(text: val.toStringAsFixed(2));
                        showDialog(
                          context: ctx,
                          builder: (dCtx) => AlertDialog(
                            backgroundColor: card,
                            title: const Text('Enter speed', style: TextStyle(color: Colors.white, fontSize: 15)),
                            content: TextField(
                              controller: ctrl, autofocus: true, keyboardType: TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: const InputDecoration(hintText: 'e.g. 1.5', hintStyle: TextStyle(color: Color(0xFF666680)), border: OutlineInputBorder()),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
                              TextButton(
                                onPressed: () {
                                  final v = double.tryParse(ctrl.text.trim());
                                  if (v != null && v >= 0.25 && v <= 4.0) {
                                    val = v;
                                    _controller!.setPlaybackSpeed(val);
                                    setDlg(() {});
                                  }
                                  Navigator.pop(dCtx);
                                },
                                child: const Text('Set', style: TextStyle(color: accent)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SliderTheme(
                  data: const SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6), activeTrackColor: accent, inactiveTrackColor: Colors.white24, thumbColor: accent, overlayColor: Color(0x29818CF8)),
                  child: Slider(
                    value: val.toDouble(), min: 0.25, max: 4.0, divisions: 60,
                    label: '${val.toStringAsFixed(2)}x',
                    onChanged: (v) {
                      val = v;
                      _controller!.setPlaybackSpeed(val);
                      setDlg(() {});
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('0.25x', style: TextStyle(color: Color(0xFF666680), fontSize: 10)),
                      Text('4x', style: TextStyle(color: Color(0xFF666680), fontSize: 10)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: presets.map((s) {
                    final active = (val - s).abs() < 0.01;
                    return GestureDetector(
                      onTap: () {
                        val = s;
                        _controller!.setPlaybackSpeed(s);
                        setDlg(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: active ? accent : card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: active ? accent : const Color(0xFF2D3748)),
                        ),
                        child: Text(
                          s == 1.0 ? '${s}x\n(normal)' : '${s}x',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 13, fontWeight: active ? FontWeight.bold : FontWeight.normal),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Subtitles ─────────────────────────────────────────────────────────────
  Future<void> _loadSubtitlesForFile() async {
    _subtitles = [];
    _subtitlePath = '';
    _subtitleFileLabel = '';
    _subtitleTimer?.cancel();
    final path = _currentFile();
    if (path == null) return;
    final base = path.replaceAll(RegExp(r'\.[^.]+$'), '');
    // Check for local sidecar files first
    for (final ext in ['.srt', '.vtt', '.ass', '.ssa', '.sub']) {
      final f = File('$base$ext');
      if (f.existsSync()) {
        try {
          final raw = f.readAsStringSync();
          final parsed = _parseSrt(raw);
          if (parsed.isNotEmpty) {
            _subtitles = parsed;
            _subtitlePath = f.path;
            _subtitleFileLabel = _subtitlePath.split('\\').last.split('/').last;
            _subtitleOn = true;
            _subtitleTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
              if (mounted) setState(() {});
            });
            return;
          }
        } catch (_) {}
      }
    }
    // Auto-search online if no local subtitle found
    _autoSearchSubtitle(path, base);
  }

  Future<void> _autoSearchSubtitle(String videoPath, String basePath) async {
    final query = videoPath.split('\\').last.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
    if (query.isEmpty) return;
    try {
      final results = await _fetchOpenSubtitles(query);
      if (results.isEmpty) return;
      final top = results.first;
      final url = top['url'];
      if (url == null || url.isEmpty) return;
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return;
      final parsed = _parseSrt(res.body);
      if (parsed.isEmpty) return;
      final srtPath = '$basePath.srt';
      File(srtPath).writeAsStringSync(res.body);
      if (!mounted) return;
      setState(() {
        _subtitles = parsed;
        _subtitlePath = srtPath;
        _subtitleFileLabel = srtPath.split('\\').last.split('/').last;
        _subtitleOn = true;
      });
      _subtitleTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
    } catch (_) {}
  }

  String get _activeSubtitle {
    final pos = _controller?.value.position;
    if (pos == null) return '';
    for (final s in _subtitles) {
      if (pos >= s.start && pos <= s.end) return s.text;
    }
    return '';
  }

  void _showSubtitlePanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => DraggableScrollableSheet(
          initialChildSize: 0.45,
          maxChildSize: 0.7,
          minChildSize: 0.3,
          builder: (_, sc) => ListView(
            controller: sc,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Subtitles', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    if (_subtitlePath.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(_subtitleFileLabel, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11)),
                      ),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2D3748), height: 1),
              RadioListTile<bool>(
                title: const Text('Disable', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Turn off subtitles', style: TextStyle(color: Colors.white54, fontSize: 11)),
                value: false,
                groupValue: _subtitleOn,
                activeColor: const Color(0xFF818CF8),
                onChanged: (v) {
                  setState(() => _subtitleOn = v ?? false);
                  setDlg(() {});
                },
              ),
              if (_subtitlePath.isNotEmpty)
                RadioListTile<bool>(
                  title: Text(_subtitleFileLabel, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Current subtitle', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  value: true,
                  groupValue: _subtitleOn,
                  activeColor: const Color(0xFF818CF8),
                  onChanged: (v) {
                    setState(() => _subtitleOn = v ?? false);
                    setDlg(() {});
                  },
                ),
              const Divider(color: Color(0xFF2D3748), height: 1),
              ListTile(
                leading: const Icon(Icons.file_open, color: Color(0xFF818CF8)),
                title: const Text('Import Local File', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () { Navigator.pop(ctx); _showImportLocalSubtitle(); },
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Color(0xFF818CF8)),
                title: const Text('Download', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () { Navigator.pop(ctx); _showDownloadPage(); },
              ),
              ListTile(
                leading: const Icon(Icons.palette, color: Color(0xFF818CF8)),
                title: const Text('Customization', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () { Navigator.pop(ctx); _showSubtitleCustomization(); },
              ),
              ListTile(
                leading: const Icon(Icons.sync, color: Color(0xFF818CF8)),
                title: const Text('Synchronization', style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () { Navigator.pop(ctx); _toast('Subtitle synchronization coming soon'); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImportLocalSubtitle() {
    final subExts = ['.srt', '.vtt', '.ass', '.ssa', '.sub'];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (ctx) {
        var currentPath = '/storage/emulated/0/Download';
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            List<FileSystemEntity> entities = [];
            try { entities = Directory(currentPath).listSync(recursive: false, followLinks: false); } catch (_) {}
            final folders = entities.whereType<Directory>().where((d) => !d.path.contains('/.') && !d.path.contains('\\.')).toList()..sort((a, b) => a.path.compareTo(b.path));
            final subFiles = entities.whereType<File>().where((f) => subExts.any((e) => f.path.toLowerCase().endsWith(e))).toList()..sort((a, b) => a.path.compareTo(b.path));
            final segs = currentPath.split(RegExp(r'[/\\]')); final folderName = segs.isNotEmpty ? segs.last : currentPath;
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              minChildSize: 0.4,
              builder: (_, sc) => ListView(
                controller: sc,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Import subtitle', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                        ),
                        Text(folderName, style: const TextStyle(color: Color(0xFF666680), fontSize: 11)),
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFF2D3748), height: 1),
                  ListTile(
                    leading: const Icon(Icons.arrow_upward, color: Color(0xFF818CF8)),
                    title: const Text('Folder Up', style: TextStyle(color: Colors.white, fontSize: 14)),
                    onTap: () {
                      final parent = Directory(currentPath).parent.path;
                      if (parent != currentPath) { currentPath = parent; setDlg(() {}); }
                    },
                  ),
                  const Divider(color: Color(0xFF2D3748), height: 1),
                  if (folders.isEmpty && subFiles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No subtitle files found', style: TextStyle(color: Color(0xFF666680)))),
                    ),
                  ...folders.map((f) => ListTile(
                    leading: const Icon(Icons.folder, color: Color(0xFF818CF8), size: 22),
                    title: Text(f.path.split(RegExp(r'[/\\]')).last, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    onTap: () { currentPath = f.path; setDlg(() {}); },
                  )),
                  ...subFiles.map((f) {
                    final fName = f.path.split(RegExp(r'[/\\]')).last;
                    return ListTile(
                      leading: const Icon(Icons.subtitles, color: Colors.white54, size: 22),
                      title: Text(fName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      onTap: () {
                        try {
                          final raw = f.readAsStringSync();
                          final parsed = _parseSrt(raw);
                          if (parsed.isEmpty) { _toast('Invalid subtitle file'); return; }
                          setState(() {
                            _subtitles = parsed;
                            _subtitlePath = f.path;
                            _subtitleFileLabel = fName;
                            _subtitleOn = true;
                          });
                          _subtitleTimer?.cancel();
                          _subtitleTimer = Timer.periodic(const Duration(milliseconds: 200), (_) { if (mounted) setState(() {}); });
                        } catch (e) {
                          _toast('Error: $e');
                        }
                        Navigator.pop(ctx);
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDownloadPage() {
    final defaultQuery = _currentFile()?.split('\\').last.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '') ?? '';
    final queryCtrl = TextEditingController(text: defaultQuery);
    String selectedLang = 'English';
    final langs = ['English', 'All', 'Arabic', 'Bengali', 'Chinese', 'Dutch', 'French', 'German', 'Greek', 'Hebrew', 'Hindi', 'Indonesian', 'Italian', 'Japanese', 'Korean', 'Persian', 'Polish', 'Portuguese', 'Romanian', 'Russian', 'Spanish', 'Swedish', 'Thai', 'Turkish', 'Ukrainian', 'Vietnamese'];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => DraggableScrollableSheet(
          initialChildSize: 0.45,
          maxChildSize: 0.65,
          minChildSize: 0.3,
          builder: (_, sc) => ListView(
            controller: sc,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Search subtitles from\nopensubtitles.org', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2D3748), height: 1),
              ListTile(
                leading: const Icon(Icons.language, color: Color(0xFF818CF8)),
                title: const Text('Language', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(selectedLang, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
                trailing: const Icon(Icons.arrow_drop_down, color: Colors.white38),
                onTap: () {
                  showDialog(
                    context: ctx,
                    builder: (langCtx) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1A2E),
                      title: const Text('Select Language', style: TextStyle(color: Colors.white, fontSize: 15)),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView(shrinkWrap: true, children: langs.map((l) => RadioListTile<String>(
                          title: Text(l, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          value: l, groupValue: selectedLang,
                          activeColor: const Color(0xFF818CF8),
                          onChanged: (v) { selectedLang = v ?? 'English'; Navigator.pop(langCtx); setDlg(() {}); },
                        )).toList()),
                      ),
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: queryCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search subtitles...',
                    hintStyle: const TextStyle(color: Color(0xFF666680)),
                    border: const OutlineInputBorder(),
                    suffixIcon: queryCtrl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 18), onPressed: () { queryCtrl.clear(); setDlg(() {}); })
                        : null,
                  ),
                  onChanged: (_) => setDlg(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final q = queryCtrl.text.trim();
                      if (q.isEmpty) return;
                      Navigator.pop(ctx);
                      _showSearchResults(q, selectedLang);
                    },
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Search', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF818CF8), foregroundColor: Colors.black),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchResults(String query, String lang) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (ctx) {
        String? selectedUrl;
        return StatefulBuilder(
          builder: (ctx, setDlg) => DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            builder: (_, sc) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Results for "$query"', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF2D3748), height: 1),
                Expanded(
                  child: FutureBuilder<List<Map<String, String>>>(
                    future: _fetchOpenSubtitles(query, lang),
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)));
                      }
                      if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
                        return const Center(child: Text('No results found', style: TextStyle(color: Colors.white54)));
                      }
                      return ListView(
                        controller: sc,
                        children: snap.data!.map((entry) => RadioListTile<String>(
                          title: Text(entry['lang'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          subtitle: Text(entry['downloads'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          value: entry['url'] ?? '',
                          groupValue: selectedUrl,
                          activeColor: const Color(0xFF818CF8),
                          onChanged: (v) { selectedUrl = v; setDlg(() {}); },
                        )).toList(),
                      );
                    },
                  ),
                ),
                const Divider(color: Color(0xFF2D3748), height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: selectedUrl == null ? null : () => _downloadAndApplySubtitle(selectedUrl!, ctx),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download', style: TextStyle(fontSize: 14)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF818CF8), foregroundColor: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _downloadAndApplySubtitle(String url, BuildContext sheetCtx) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final parsed = _parseSrt(res.body);
        if (parsed.isEmpty || !mounted) {
          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
          _toast('Could not download subtitle');
          return;
        }
        final base = _currentFile()?.replaceAll(RegExp(r'\.[^.]+$'), '.srt');
        if (base != null) {
          File(base).writeAsStringSync(res.body);
          setState(() {
            _subtitles = parsed; _subtitlePath = base;
            _subtitleFileLabel = base.split('\\').last.split('/').last; _subtitleOn = true;
          });
          _subtitleTimer?.cancel();
          _subtitleTimer = Timer.periodic(const Duration(milliseconds: 200), (_) { if (mounted) setState(() {}); });
        }
        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
        _toast('Subtitle downloaded');
      } else {
        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
        _toast('Could not download subtitle');
      }
    } catch (_) {
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      _toast('Could not download subtitle');
    }
  }

  Future<List<Map<String, String>>> _fetchOpenSubtitles(String query, [String lang = 'English']) async {
    final results = <Map<String, String>>[];
    try {
      final encoded = Uri.encodeComponent(query);
      final res = await http.get(
        Uri.parse('https://rest.opensubtitles.org/search/query-$encoded'),
        headers: {'User-Agent': 'Makaw v1.0'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        for (final item in data.take(20)) {
          final subUrl = item['SubDownloadLink'] as String?;
          if (subUrl == null) continue;
          results.add({
            'lang': '${item['LanguageName']} (${item['SubFormat']})',
            'downloads': 'Downloads: ${item['SubDownloadsCnt'] ?? '?'}',
            'url': subUrl,
          });
        }
      }
    } catch (_) {}
    if (results.isEmpty) {
      try {
        final encoded = Uri.encodeComponent(query.replaceAll(RegExp(r'\s*\(\d{4}\).*'), ''));
        final res = await http.get(
          Uri.parse('https://yifysubtitles.org/api/search?query=$encoded'),
        ).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final movies = data['movies'] as List? ?? [];
          if (movies.isNotEmpty) {
            final imdb = movies.first['imdb_id'] as String?;
            if (imdb != null) {
              final subRes = await http.get(
                Uri.parse('https://yifysubtitles.org/api/subtitles/$imdb'),
              ).timeout(const Duration(seconds: 10));
              if (subRes.statusCode == 200) {
                final subs = jsonDecode(subRes.body)['subtitles'] as List? ?? [];
                for (final s in subs.take(20)) {
                  final url = s['url'] as String?;
                  if (url == null) continue;
                  results.add({
                    'lang': '${s['language'] ?? '?'} (English)',
                    'downloads': 'Rating: ${s['rating'] ?? '?'}',
                    'url': 'https://yifysubtitles.org$url',
                  });
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    return results;
  }

  Paint? _subBgPaint() => _subBg ? (Paint()..color = Colors.black54) : null;

  Widget _buildStyledSubtitle() {
    final textStyle = TextStyle(
      color: _subColor,
      fontSize: _subFontSize,
      fontWeight: _subBold ? FontWeight.bold : FontWeight.normal,
      fontFamily: _subFont == 'default' ? null : _subFont,
      height: 1.4,
      shadows: _buildSubtitleShadows(),
      background: _subBgPaint(),
    );
    return Text(
      _activeSubtitle,
      textAlign: _subAlign,
      style: textStyle,
    );
  }

  List<Shadow> _buildSubtitleShadows() {
    final list = <Shadow>[];
    if (_subShadow) {
      list.addAll([
        const Shadow(blurRadius: 4, color: Colors.black87),
        const Shadow(blurRadius: 8, color: Colors.black54),
      ]);
    }
    if (_subOutline) {
      final d = _subOutlineSize;
      list.addAll([
        Shadow(blurRadius: d, color: _subOutlineColor, offset: Offset(d, d)),
        Shadow(blurRadius: d, color: _subOutlineColor, offset: Offset(-d, d)),
        Shadow(blurRadius: d, color: _subOutlineColor, offset: Offset(d, -d)),
        Shadow(blurRadius: d, color: _subOutlineColor, offset: Offset(-d, -d)),
      ]);
    }
    return list;
  }

  void _showSubtitleCustomization() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SubtitleCustomizationPage(
          fontSize: _subFontSize,
          font: _subFont,
          color: _subColor,
          shadow: _subShadow,
          bold: _subBold,
          align: _subAlign,
          bg: _subBg,
          outline: _subOutline,
          outlineSize: _subOutlineSize,
          outlineColor: _subOutlineColor,
        ),
      ),
    ).then((result) {
      if (result != null && mounted) {
        setState(() {
          _subFontSize = result['fontSize'] as double;
          _subFont = result['font'] as String;
          _subColor = result['color'] as Color;
          _subShadow = result['shadow'] as bool;
          _subBold = result['bold'] as bool;
          _subAlign = result['align'] as TextAlign;
          _subBg = result['bg'] as bool;
          _subOutline = result['outline'] as bool;
          _subOutlineSize = result['outlineSize'] as double;
          _subOutlineColor = result['outlineColor'] as Color;
        });
      }
    });
  }

  void _showVideoSettings() {
    const accent = Color(0xFF818CF8);
    const card = Color(0xFF1A1A2E);
    showModalBottomSheet(
      context: context, backgroundColor: card, isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65, maxChildSize: 0.9, minChildSize: 0.3,
        builder: (_, sc) => ListView(
          controller: sc,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Video Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(color: Color(0xFF2D3748), height: 1),
            _settingsTile(Icons.play_circle_outline, 'Background play', () { Navigator.pop(ctx); _toast('Background play coming soon'); }),
            _settingsTile(Icons.tune, 'Equalizer', () { Navigator.pop(ctx); _toast('Equalizer coming soon'); }),
            _settingsTile(Icons.dark_mode, 'Night Mode', () { Navigator.pop(ctx); _toast('Night mode coming soon'); }),
            _settingsTile(Icons.timer, 'Timer', () { Navigator.pop(ctx); _toast('Sleep timer coming soon'); }),
            _settingsTile(Icons.repeat_one, 'AB Repeat', () { Navigator.pop(ctx); _toast('AB Repeat coming soon'); }),
            _settingsTile(Icons.flip, 'Mirror', () { Navigator.pop(ctx); _toast('Mirror mode coming soon'); }),
            _settingsTile(Icons.settings_ethernet, 'Decoder', () { Navigator.pop(ctx); _toast('Decoder selection coming soon'); }),
            _settingsTile(Icons.loop, 'Loop', () { Navigator.pop(ctx); _toast('Loop mode coming soon'); }),
            _settingsTile(Icons.shuffle, 'Shuffle', () { Navigator.pop(ctx); _toast('Shuffle mode coming soon'); }),
            _settingsTile(Icons.info, 'Properties', () { Navigator.pop(ctx); _showVideoInfo(); }),
            _settingsTile(Icons.share, 'Share', () { Navigator.pop(ctx); _shareVideo(); }),
            _settingsTile(Icons.delete, 'Delete', () { Navigator.pop(ctx); _deleteVideo(); }),
            _settingsTile(Icons.feedback, 'Feedback', () { Navigator.pop(ctx); _toast('Feedback coming soon'); }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _settingsTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF818CF8), size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
      onTap: onTap,
    );
  }

  void _shareVideo() {
    final path = _currentFile();
    if (path == null || !File(path).existsSync()) { _toast('File not found'); return; }
    Share.shareXFiles([XFile(path)]);
  }

  void _deleteVideo() {
    final path = _currentFile();
    if (path == null || !File(path).existsSync()) { _toast('File not found'); return; }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete this video?', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text('This will permanently delete the file.', style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () {
              try { File(path).deleteSync(); } catch (_) {}
              Navigator.pop(ctx);
              (widget.onClose ?? () => Navigator.pop(context))();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontSize: 13)), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subtitle Customization Page
// ─────────────────────────────────────────────────────────────────────────────
class _SubtitleCustomizationPage extends StatefulWidget {
  final double fontSize;
  final String font;
  final Color color;
  final bool shadow;
  final bool bold;
  final TextAlign align;
  final bool bg;
  final bool outline;
  final double outlineSize;
  final Color outlineColor;

  const _SubtitleCustomizationPage({
    required this.fontSize, required this.font, required this.color,
    required this.shadow, required this.bold, required this.align,
    required this.bg, required this.outline, required this.outlineSize,
    required this.outlineColor,
  });

  @override
  State<_SubtitleCustomizationPage> createState() => _SubtitleCustomizationPageState();
}

class _SubtitleCustomizationPageState extends State<_SubtitleCustomizationPage> {
  late double _fontSize;
  late String _font;
  late Color _color;
  late bool _shadow;
  late bool _bold;
  late TextAlign _align;
  late bool _bg;
  late bool _outline;
  late double _outlineSize;
  late Color _outlineColor;

  static const _kAccent = Color(0xFF818CF8);
  static const _kCard = Color(0xFF1A1A2E);
  static const _kDark = Color(0xFF0F0F1A);

  static const _colors = [
    Colors.white, Color(0xFFE2E8F0), Color(0xFFCBD5E1), Color(0xFF94A3B8),
    Colors.black, Color(0xFF1E293B), Color(0xFF0F172A),
    Color(0xFFFCA5A5), Color(0xFFF87171), Color(0xFFEF4444),
    Color(0xFFFCD34D), Color(0xFFFBBF24), Color(0xFFF59E0B),
    Color(0xFF6EE7B7), Color(0xFF34D399), Color(0xFF10B981),
    Color(0xFF67E8F9), Color(0xFF22D3EE), Color(0xFF06B6D4),
    Color(0xFF93C5FD), Color(0xFF60A5FA), Color(0xFF3B82F6),
    Color(0xFFC4B5FD), Color(0xFFA78BFA), Color(0xFF8B5CF6),
    Color(0xFFF0ABFC), Color(0xFFE879F9), Color(0xFFD946EF),
    Color(0xFFFDBA74), Color(0xFFFB923C), Color(0xFFF97316),
  ];

  Paint? _bgPaint() => _bg ? (Paint()..color = Colors.black54) : null;

  List<Shadow> _buildPreviewShadows() {
    final list = <Shadow>[];
    if (_shadow) {
      list.addAll([
        const Shadow(blurRadius: 4, color: Colors.black87),
        const Shadow(blurRadius: 8, color: Colors.black54),
      ]);
    }
    if (_outline) {
      final d = _outlineSize;
      list.addAll([
        Shadow(blurRadius: d, color: _outlineColor, offset: Offset(d, d)),
        Shadow(blurRadius: d, color: _outlineColor, offset: Offset(-d, d)),
        Shadow(blurRadius: d, color: _outlineColor, offset: Offset(d, -d)),
        Shadow(blurRadius: d, color: _outlineColor, offset: Offset(-d, -d)),
      ]);
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _fontSize = widget.fontSize;
    _font = widget.font;
    _color = widget.color;
    _shadow = widget.shadow;
    _bold = widget.bold;
    _align = widget.align;
    _bg = widget.bg;
    _outline = widget.outline;
    _outlineSize = widget.outlineSize;
    _outlineColor = widget.outlineColor;
  }

  void _accept() {
    Navigator.pop(context, {
      'fontSize': _fontSize, 'font': _font, 'color': _color,
      'shadow': _shadow, 'bold': _bold, 'align': _align,
      'bg': _bg, 'outline': _outline, 'outlineSize': _outlineSize,
      'outlineColor': _outlineColor,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        backgroundColor: _kDark,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Subtitle Customization', style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: _kAccent),
            onPressed: _accept,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildPreview(),
            const SizedBox(height: 20),
            _buildSectionHeader('Text'),
            const SizedBox(height: 8),
            _buildSizeSlider(),
            const SizedBox(height: 4),
            _buildFontDropdown(),
            const SizedBox(height: 4),
            _buildColorPicker('Color', _color, (c) => setState(() => _color = c)),
            const SizedBox(height: 4),
            _buildSwitch('Shadow', _shadow, (v) => setState(() => _shadow = v)),
            const SizedBox(height: 4),
            _buildSwitch('Bold', _bold, (v) => setState(() => _bold = v)),
            const SizedBox(height: 4),
            _buildAlignmentPicker(),
            const SizedBox(height: 20),
            _buildSectionHeader('Background'),
            const SizedBox(height: 8),
            _buildSwitch('Background', _bg, (v) => setState(() => _bg = v)),
            const SizedBox(height: 20),
            _buildSectionHeader('Outline'),
            const SizedBox(height: 8),
            _buildSwitch('Outline', _outline, (v) => setState(() => _outline = v)),
            if (_outline) ...[
              const SizedBox(height: 4),
              _buildOutlineSizeSlider(),
              const SizedBox(height: 4),
              _buildColorPicker('Outline Color', _outlineColor, (c) => setState(() => _outlineColor = c)),
            ],
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(8)),
              child: const Text(
                'Styles cannot be customized for hardcoded subtitles or image-based tracks (e.g., PGS). For full styling options, please use external text-based subtitle files such as .srt or .ass.',
                style: TextStyle(color: Color(0xFF666680), fontSize: 11),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D3748)),
      ),
      child: Center(
        child: Text(
          'Sample subtitle text',
          textAlign: _align,
          style: TextStyle(
            color: _color,
            fontSize: _fontSize,
            fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
            fontFamily: _font == 'default' ? null : _font,
            height: 1.4,
            shadows: _buildPreviewShadows(),
            background: _bgPaint(),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold));
  }

  Widget _buildSizeSlider() {
    return Row(
      children: [
        const SizedBox(width: 8),
        const Text('Size', style: TextStyle(color: Colors.white70, fontSize: 13)),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6), activeTrackColor: _kAccent, inactiveTrackColor: Colors.white24, thumbColor: _kAccent),
            child: Slider(value: _fontSize, min: 10, max: 40, divisions: 30, label: '${_fontSize.round()}', onChanged: (v) => setState(() => _fontSize = v)),
          ),
        ),
        SizedBox(width: 36, child: Text('${_fontSize.round()}', style: const TextStyle(color: Colors.white70, fontSize: 12))),
      ],
    );
  }

  Widget _buildOutlineSizeSlider() {
    return Row(
      children: [
        const SizedBox(width: 8),
        const Text('Size', style: TextStyle(color: Colors.white70, fontSize: 13)),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6), activeTrackColor: _kAccent, inactiveTrackColor: Colors.white24, thumbColor: _kAccent),
            child: Slider(value: _outlineSize, min: 0.5, max: 4, divisions: 14, label: _outlineSize.toStringAsFixed(1), onChanged: (v) => setState(() => _outlineSize = v)),
          ),
        ),
        SizedBox(width: 36, child: Text(_outlineSize.toStringAsFixed(1), style: const TextStyle(color: Colors.white70, fontSize: 12))),
      ],
    );
  }

  Widget _buildFontDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Text('Font', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _font,
            dropdownColor: _kCard,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            underline: Container(height: 1, color: const Color(0xFF2D3748)),
            items: ['default', 'monospace', 'serif', 'sans-serif'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            onChanged: (v) { if (v != null) setState(() => _font = v); },
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker(String label, Color current, ValueChanged<Color> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: _colors.map((c) => GestureDetector(
              onTap: () => onChanged(c),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: c == current ? _kAccent : const Color(0xFF2D3748), width: c == current ? 2.5 : 1),
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Switch(value: value, onChanged: onChanged, activeColor: _kAccent),
        ],
      ),
    );
  }

  Widget _buildAlignmentPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Text('Alignment', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 16),
          _alignBtn(Icons.format_align_left, TextAlign.left),
          const SizedBox(width: 4),
          _alignBtn(Icons.format_align_center, TextAlign.center),
          const SizedBox(width: 4),
          _alignBtn(Icons.format_align_right, TextAlign.right),
        ],
      ),
    );
  }

  Widget _alignBtn(IconData icon, TextAlign a) {
    final active = _align == a;
    return GestureDetector(
      onTap: () => setState(() => _align = a),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? _kAccent : _kCard,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: active ? Colors.black : Colors.white70, size: 20),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Video Player Widget
// ─────────────────────────────────────────────────────────────────────────────
class VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerService service;
  final void Function()? onOpenMusic;
  final void Function()? onHome;
  const VideoPlayerWidget({super.key, required this.service, this.onOpenMusic, this.onHome});
  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  String _page = 'home';
  String _homeTab = 'videos';
  String _browseSection = 'favourites';
  String? _selectedFolder;
  String _searchQuery = '';
  int _playIndex = 0;
  String _displayMode = 'grid';
  String _sortMode = 'date_new';
  final Map<String, String> _thumbCache = {};
  final _searchCtrl = TextEditingController();
  final _kDark = const Color(0xFF0F0F1A);
  final _kAccent = const Color(0xFF818CF8);
  final _kCard = const Color(0xFF1A1A2E);
  final _kMuted = const Color(0xFF666680);

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);
    if (widget.service.allVideos.isEmpty && !widget.service.isScanning) {
      widget.service.scanAllVideos();
    }
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  List<VideoFileInfo> get _sortedVideos {
    final list = List<VideoFileInfo>.from(widget.service.allVideos);
    switch (_sortMode) {
      case 'name_az':
        list.sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
        break;
      case 'name_za':
        list.sort((a, b) => b.fileName.toLowerCase().compareTo(a.fileName.toLowerCase()));
        break;
      case 'date_new':
        list.sort((a, b) => (b.dateTime ?? DateTime.now()).compareTo(a.dateTime ?? DateTime.now()));
        break;
      case 'date_old':
        list.sort((a, b) => (a.dateTime ?? DateTime.now()).compareTo(b.dateTime ?? DateTime.now()));
        break;
      case 'size_largest':
        list.sort((a, b) => b.fileSize.compareTo(a.fileSize));
        break;
      case 'size_smallest':
        list.sort((a, b) => a.fileSize.compareTo(b.fileSize));
        break;
    }
    return list;
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Sort by', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const Divider(color: Color(0xFF2D3748), height: 1),
            _sortOption('Name (A-Z)', 'name_az', ctx),
            _sortOption('Name (Z-A)', 'name_za', ctx),
            _sortOption('Date (newest)', 'date_new', ctx),
            _sortOption('Date (oldest)', 'date_old', ctx),
            _sortOption('Size (largest)', 'size_largest', ctx),
            _sortOption('Size (smallest)', 'size_smallest', ctx),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(String label, String mode, BuildContext ctx) {
    return ListTile(
      title: Text(label, style: TextStyle(color: _sortMode == mode ? _kAccent : Colors.white, fontSize: 14)),
      trailing: _sortMode == mode ? const Icon(Icons.check, color: Color(0xFF818CF8), size: 18) : null,
      onTap: () { setState(() => _sortMode = mode); Navigator.pop(ctx); },
    );
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_page == 'player') return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          SystemChrome.restoreSystemUIOverlays();
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
            systemNavigationBarColor: Color(0xFF0F0F1A),
            systemNavigationBarIconBrightness: Brightness.light,
          ));
          setState(() => _page = 'home');
        }
      },
      child: _buildFullPlayer(),
    );
    return Scaffold(
      backgroundColor: _kDark,
      appBar: _buildAppBar(),
      body: SafeArea(child: _buildBody()),
      floatingActionButton: _page == 'home' && _homeTab == 'videos' && widget.service.allVideos.isNotEmpty
          ? Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 60),
              child: FloatingActionButton(
                backgroundColor: _kAccent,
                onPressed: () => setState(() { _page = 'player'; }),
                child: const Icon(Icons.play_arrow, color: Colors.black),
              ),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isHome = _page == 'home';
    final isBrowse = _page == 'browse';
    final isSearch = _page == 'search';
    String title;
    if (isSearch) title = 'Search Videos';
    else if (isBrowse) title = 'Browse';
    else if (_page == 'playlists_page') title = 'Playlists';
    else if (_page == 'more') title = 'More';
    else if (_page == 'settings') title = 'Settings';
    else if (_page == 'history') title = 'History';
    else title = 'Makaw Video';

    return AppBar(
      backgroundColor: _kDark,
      title: isSearch ? TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: const InputDecoration(hintText: 'Search videos...', hintStyle: TextStyle(color: Color(0xFF666680)), border: InputBorder.none),
        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
      ) : Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      leading: isHome
          ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () { if (widget.onHome != null) widget.onHome!(); else Navigator.maybePop(context); })
          : IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => setState(() => _page = 'home')),
    );
  }

  Widget _buildBody() {
    if (_page == 'search') return _buildSearchPage();
    if (_page == 'browse') return _buildBrowsePage();
    if (_page == 'playlists_page') return _buildPlaylistsPage();
    if (_page == 'more') return _buildMorePage();
    if (_page == 'settings') return const Center(child: Text('Settings', style: TextStyle(color: Colors.white)));
    if (_page == 'history') return const Center(child: Text('History', style: TextStyle(color: Colors.white)));
    return RefreshIndicator(
      onRefresh: () => widget.service.scanAllVideos(),
      color: const Color(0xFF818CF8),
      child: _buildHomePage(),
    );
  }

  Widget _buildFullPlayer() {
    return DirectVideoPlayer(
      filePath: widget.service.allVideos[_playIndex].filePath,
      title: widget.service.allVideos[_playIndex].fileName,
      playlist: widget.service.allVideos.map((v) => v.filePath).toList(),
      initialIndex: _playIndex,
      onClose: () => setState(() => _page = 'home'),
    );
  }

  Widget _buildVideoToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_displayMode == 'grid' ? Icons.grid_view : _displayMode == 'list' ? Icons.list : Icons.article,
                color: Colors.white, size: 20),
            onPressed: () {
              setState(() {
                _displayMode = _displayMode == 'grid' ? 'list' : _displayMode == 'list' ? 'details' : 'grid';
              });
            },
          ),
          IconButton(icon: const Icon(Icons.sort, color: Colors.white, size: 20), onPressed: _showSortMenu),
          const SizedBox(width: 4),
          Text('${widget.service.allVideos.length} videos', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => setState(() { _page = 'search'; _searchCtrl.clear(); _searchQuery = ''; }),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) {
              if (v == 'refresh') widget.service.scanAllVideos();
              else if (v == 'select') _toast('Select mode coming soon');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'select', child: ListTile(leading: Icon(Icons.checklist), title: Text('Select'))),
              PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh), title: Text('Refresh'))),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Home Page ─────────────────────────────────────────────────────────────
  Widget _buildHomePage() {
    return Column(
      children: [
        // Toolbar
        if (_homeTab == 'videos') _buildVideoToolbar(),
        // Tabs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _tabBtn('Videos', _homeTab == 'videos'),
              const SizedBox(width: 12),
              _tabBtn('Playlists', _homeTab == 'playlists'),
            ],
          ),
        ),
        Expanded(child: _homeTab == 'videos' ? _buildVideosTab() : _buildPlaylistsTab()),
        // Footer nav
        _buildFooter(),
      ],
    );
  }

  Widget _tabBtn(String label, bool active) {
    return GestureDetector(
      onTap: () => setState(() => _homeTab = label.toLowerCase()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(color: active ? _kAccent : _kCard, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ─── Videos Tab ────────────────────────────────────────────────────────────
  Widget _buildVideosTab() {
    if (widget.service.allVideos.isEmpty) {
      return Center(child: Text(widget.service.isScanning ? 'Scanning...' : 'No videos found', style: const TextStyle(color: Color(0xFF666680))));
    }
    if (_displayMode == 'grid') return _buildGridVideos();
    if (_displayMode == 'list') return _buildListVideos();
    return _buildDetailsVideos();
  }

  Widget _buildGridVideos() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.85,
      ),
      itemCount: widget.service.allVideos.length,
      itemBuilder: (_, i) => _gridCard(widget.service.allVideos[i], i),
    );
  }

  Widget _gridCard(VideoFileInfo v, int index) {
    return GestureDetector(
      onTap: () => setState(() { _playIndex = index; _page = 'player'; }),
      child: Container(
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF2D3748), width: 0.5)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ThumbnailView(filePath: v.filePath, thumbCache: _thumbCache),
                  Positioned(top: 4, right: 4, child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                    onSelected: (opt) => _videoMenuAction(opt, v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'play', child: Text('Play')),
                      PopupMenuItem(value: 'play_start', child: Text('Play from the start')),
                      PopupMenuItem(value: 'play_all', child: Text('Play all')),
                      PopupMenuItem(value: 'audio', child: Text('Play as audio')),
                      PopupMenuItem(value: 'queue', child: Text('Add to play queue')),
                      PopupMenuItem(value: 'subtitle', child: Text('Download subtitle')),
                      PopupMenuItem(value: 'info', child: Text('Information')),
                      PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
                      PopupMenuItem(value: 'favorite', child: Text('Add to favourites')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                      PopupMenuItem(value: 'share', child: Text('Share')),
                    ],
                  )),
                  if (v.fileSize > 0)
                    Positioned(right: 4, bottom: 4, child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                      child: Text(_fmtSize(v.fileSize), style: const TextStyle(color: Colors.white70, fontSize: 9)),
                    )),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Text(v.fileName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListVideos() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: widget.service.allVideos.length,
      itemBuilder: (_, i) {
        final v = widget.service.allVideos[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF2D3748), width: 0.5)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 52, height: 52, child: _ThumbnailView(filePath: v.filePath, thumbCache: _thumbCache)),
            ),
            title: Text(v.fileName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${v.folder}  •  ${_fmtSize(v.fileSize)}', style: TextStyle(color: _kMuted, fontSize: 11)),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
              onSelected: (opt) => _videoMenuAction(opt, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'play', child: Text('Play')),
                PopupMenuItem(value: 'play_start', child: Text('Play from the start')),
                PopupMenuItem(value: 'play_all', child: Text('Play all')),
                PopupMenuItem(value: 'audio', child: Text('Play as audio')),
                PopupMenuItem(value: 'queue', child: Text('Add to play queue')),
                PopupMenuItem(value: 'subtitle', child: Text('Download subtitle')),
                PopupMenuItem(value: 'info', child: Text('Information')),
                PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
                PopupMenuItem(value: 'favorite', child: Text('Add to favourites')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
                PopupMenuItem(value: 'share', child: Text('Share')),
              ],
            ),
            onTap: () => setState(() { _playIndex = i; _page = 'player'; }),
          ),
        );
      },
    );
  }

  Widget _buildDetailsVideos() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: widget.service.allVideos.length,
      itemBuilder: (_, i) {
        final v = widget.service.allVideos[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2D3748), width: 0.5)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() { _playIndex = i; _page = 'player'; }),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(width: 80, height: 60, child: _ThumbnailView(filePath: v.filePath, thumbCache: _thumbCache)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.fileName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(v.folder, style: TextStyle(color: _kMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 1),
                        Row(children: [
                          Text(_fmtSize(v.fileSize), style: TextStyle(color: _kMuted, fontSize: 10)),
                          if (v.dateTime != null) ...[
                            const Text('  •  ', style: TextStyle(color: Color(0xFF444455), fontSize: 10)),
                            Text(v.dateTime!.toString().split('.')[0], style: TextStyle(color: _kMuted, fontSize: 10)),
                          ],
                        ]),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
                    onSelected: (opt) => _videoMenuAction(opt, v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'play', child: Text('Play')),
                      PopupMenuItem(value: 'play_start', child: Text('Play from the start')),
                      PopupMenuItem(value: 'play_all', child: Text('Play all')),
                      PopupMenuItem(value: 'audio', child: Text('Play as audio')),
                      PopupMenuItem(value: 'queue', child: Text('Add to play queue')),
                      PopupMenuItem(value: 'subtitle', child: Text('Download subtitle')),
                      PopupMenuItem(value: 'info', child: Text('Information')),
                      PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
                      PopupMenuItem(value: 'favorite', child: Text('Add to favourites')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                      PopupMenuItem(value: 'share', child: Text('Share')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _videoMenuAction(String opt, VideoFileInfo v) {
    final idx = widget.service.allVideos.indexOf(v);
    if (opt == 'play') setState(() { _playIndex = idx; _page = 'player'; });
    else if (opt == 'play_start') setState(() { _playIndex = idx; _page = 'player'; });
    else if (opt == 'play_all') setState(() { _playIndex = 0; _page = 'player'; });
    else if (opt == 'favorite') { widget.service.toggleFavorite(v.id); _toast(widget.service.isFavorite(v.id) ? 'Added to favourites' : 'Removed from favourites'); }
    else if (opt == 'share') Share.shareXFiles([XFile(v.filePath)]);
    else if (opt == 'delete') _deleteDialog(v);
    else if (opt == 'info') _infoDialog(v);
    else if (opt == 'playlist') _addToPlaylistSheet(v);
    else if (opt == 'queue') _toast('Added to play queue');
    else if (opt == 'subtitle') _subtitleDownloadDialog(v);
    else if (opt == 'audio') _toast('Play as audio coming soon');
  }

  void _deleteDialog(VideoFileInfo v) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard, title: const Text('Delete this video?', style: TextStyle(color: Colors.white, fontSize: 15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () { try { File(v.filePath).deleteSync(); widget.service.scanAllVideos(); } catch (_) {} Navigator.pop(ctx); }, child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  void _infoDialog(VideoFileInfo v) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard, title: Text(v.fileName, style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _infoRow('File', v.fileName),
          _infoRow('Folder', v.folder),
          _infoRow('Path', v.filePath),
          _infoRow('Size', _fmtSize(v.fileSize)),
          _infoRow('Modified', v.dateTime?.toString().split('.')[0] ?? ''),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Color(0xFF818CF8))))],
      ),
    );
  }

  Widget _infoRow(String label, String val) { return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [SizedBox(width: 80, child: Text('$label:', style: const TextStyle(color: Color(0xFF666680), fontSize: 12))), Expanded(child: Text(val, style: const TextStyle(color: Colors.white, fontSize: 12)))])); }

  String _fmtSize(int bytes) { if (bytes < 1024) return '$bytes B'; if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB'; return '${(bytes / 1048576).toStringAsFixed(1)} MB'; }

  // ─── Playlists Tab ────────────────────────────────────────────────────────
  Widget _buildPlaylistsTab() {
    final pls = widget.service.playlists;
    if (pls.isEmpty) return const Center(child: Text('No playlists', style: TextStyle(color: Color(0xFF666680))));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pls.length,
      itemBuilder: (_, i) {
        final pl = pls[i];
        final count = (pl['videoIds'] as List).length;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.playlist_play, color: Color(0xFF818CF8)),
            title: Text(pl['name'], style: const TextStyle(color: Colors.white)),
            subtitle: Text('$count videos', style: TextStyle(color: _kMuted, fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              onPressed: () { widget.service.deletePlaylist(pl['name']); _toast('Playlist deleted'); },
            ),
          ),
        );
      },
    );
  }

  // ─── Search Page ──────────────────────────────────────────────────────────
  Widget _buildSearchPage() {
    final filtered = _searchQuery.isEmpty ? widget.service.allVideos
        : widget.service.allVideos.where((v) => v.fileName.toLowerCase().contains(_searchQuery)).toList();
    if (filtered.isEmpty) return const Center(child: Text('No results', style: TextStyle(color: Color(0xFF666680))));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final v = filtered[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(width: 48, height: 48, color: Colors.black26, child: const Icon(Icons.videocam, color: Color(0xFF818CF8), size: 24)),
            ),
            title: Text(v.fileName, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
            subtitle: Text(v.folder, style: TextStyle(color: _kMuted, fontSize: 11)),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54, size: 18),
              onSelected: (opt) => _videoMenuAction(opt, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'play', child: Text('Play')),
                PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
                PopupMenuItem(value: 'favorite', child: Text('Add to favourites')),
                PopupMenuItem(value: 'queue', child: Text('Stop after this track')),
                PopupMenuItem(value: 'share', child: Text('Share')),
              ],
            ),
            onTap: () => setState(() { _playIndex = widget.service.allVideos.indexOf(v); _page = 'player'; }),
          ),
        );
      },
    );
  }

  // ─── Browse Page ──────────────────────────────────────────────────────────
  Widget _buildBrowsePage() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _browseTab('Favourites', _browseSection == 'favourites'),
            const SizedBox(width: 8),
            _browseTab('Storages', _browseSection == 'storages'),
          ]),
        ),
        Expanded(child: _buildBrowseSection()),
      ],
    );
  }

  Widget _browseTab(String label, bool active) {
    return GestureDetector(
      onTap: () => setState(() => _browseSection = label.toLowerCase()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(color: active ? _kAccent : _kCard, borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildBrowseSection() {
    if (_browseSection == 'favourites') return _buildBrowseFavourites();
    if (_browseSection == 'storages') return _buildBrowseStorages();
    return _buildBrowseFavourites();
  }

  String _folderName(String path) {
    final sep = path.contains('\\') ? '\\' : '/';
    final segs = path.split(sep);
    return segs.where((s) => s.isNotEmpty).lastOrNull ?? path;
  }

  Widget _buildBrowseFavourites() {
    final favFolders = widget.service.favoriteFolders.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    if (favFolders.isEmpty) return const Center(child: Text('No favourites yet', style: TextStyle(color: Color(0xFF666680))));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: favFolders.length,
      itemBuilder: (_, i) {
        final entry = favFolders[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.folder, color: Color(0xFF818CF8)),
            title: Text(_folderName(entry.key), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            subtitle: Text('${entry.value.length} videos  •  ${entry.key}', style: TextStyle(color: _kMuted, fontSize: 11)),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54, size: 18),
              onSelected: (opt) {
                if (opt == 'play') { widget.service.setQueue(entry.value, 0); _openFolderSheet(entry.key, entry.value); }
                else if (opt == 'queue') { widget.service.addToQueue(entry.value); _toast('Added ${entry.value.length} videos to play queue'); }
                else if (opt == 'remove_fav') { widget.service.toggleFavoriteFolder(entry.key); _toast('Removed from favourites'); }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'play', child: Text('Play')),
                const PopupMenuItem(value: 'queue', child: Text('Add to play queue')),
                const PopupMenuItem(value: 'remove_fav', child: Text('Remove from favourites')),
              ],
            ),
            onTap: () => _openFolderSheet(entry.key, entry.value),
          ),
        );
      },
    );
  }

  // Directory tree state for Storages
  String _storageRoot = '';
  String _storagePath = '';

  Widget _buildBrowseStorages() {
    if (_storageRoot.isEmpty) {
      return FutureBuilder<List<Map<String, String>>>(
        future: _getAvailableStorages(),
        builder: (context, snapshot) {
          final storages = snapshot.data ?? <Map<String, String>>[];
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (storages.isEmpty) {
            return Center(child: Text('No external storage found', style: TextStyle(color: _kMuted)));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (int i = 0; i < storages.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _storageRootTile(storages[i]['path']!, storages[i]['label']!),
              ],
            ],
          );
        },
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () {
              if (_storagePath.isEmpty) setState(() { _storageRoot = ''; _storagePath = ''; });
              else { final p = _storagePath.substring(0, _storagePath.lastIndexOf(RegExp(r'[/\\]'))); setState(() => _storagePath = p.isEmpty ? _storageRoot : p); }
            }),
            const SizedBox(width: 8),
            Expanded(child: Text(_folderName(_storagePath.isEmpty ? _storageRoot : _storagePath), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          ]),
        ),
        Expanded(child: _buildStorageDirContent()),
      ],
    );
  }

  Future<List<Map<String, String>>> _getAvailableStorages() async {
    final candidates = [
      {'path': '/storage/emulated/0', 'label': 'Internal Storage'},
      {'path': '/storage/0000-0000', 'label': 'SD Card'},
      {'path': '/storage/extSdCard', 'label': 'External SD'},
    ];
    final result = <Map<String, String>>[];
    for (final c in candidates) {
      if (await Directory(c['path']!).exists()) {
        result.add(c);
      }
    }
    return result;
  }

  Widget _storageRootTile(String rootPath, String label) {
    return Container(
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.phone_android, color: Color(0xFF818CF8)),
        title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(rootPath, style: TextStyle(color: _kMuted, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF666680)),
        onTap: () async {
          final dir = Directory(rootPath);
          if (await dir.exists()) setState(() { _storageRoot = rootPath; _storagePath = ''; });
          else _toast('Not available');
        },
      ),
    );
  }

  Widget _buildStorageDirContent() {
    final path = _storagePath.isEmpty ? _storageRoot : _storagePath;
    return FutureBuilder<List<FileSystemEntity>>(
      future: Directory(path).list(recursive: false, followLinks: false).toList(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)));
        final items = snap.data!;
        final dirs = items.whereType<Directory>().where((d) => !d.path.contains('/.') && !d.path.contains('\\.')).toList()..sort((a, b) => a.path.compareTo(b.path));
        final videoFiles = items.whereType<File>().where((f) => ['.mp4', '.mkv', '.webm', '.avi', '.mov', '.flv', '.wmv', '.3gp'].any((e) => f.path.toLowerCase().endsWith(e))).toList()..sort((a, b) => a.path.compareTo(b.path));
        if (dirs.isEmpty && videoFiles.isEmpty) return const Center(child: Text('Empty folder', style: TextStyle(color: Color(0xFF666680))));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: dirs.length + videoFiles.length,
          itemBuilder: (_, i) {
            if (i < dirs.length) {
              final d = dirs[i];
              final localVideos = (){ try { return Directory(d.path).listSync(recursive: false).whereType<File>().where((f) => ['.mp4', '.mkv', '.webm', '.avi', '.mov', '.flv', '.wmv', '.3gp'].any((e) => f.path.toLowerCase().endsWith(e))).length; } catch(_){return 0;} }();
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder, color: Color(0xFF818CF8), size: 22),
                  title: Text(_folderName(d.path), style: const TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: localVideos > 0 ? Text('$localVideos videos', style: TextStyle(color: _kMuted, fontSize: 10)) : null,
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white54, size: 16),
                    onSelected: (opt) async {
                      if (opt == 'scan') { widget.service.scanAllVideos(); _toast('Scanning...'); }
                      else if (opt == 'fav') { widget.service.toggleFavoriteFolder(_folderName(d.path)); _toast('Toggled favourite'); }
                      else if (opt == 'ban') { _toast('Banned (not implemented)'); }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'play', child: Text('Play all')),
                      const PopupMenuItem(value: 'queue', child: Text('Add to play queue')),
                      const PopupMenuItem(value: 'fav', child: Text('Add to favourites')),
                      const PopupMenuItem(value: 'scan', child: Text('Scan this folder')),
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      const PopupMenuItem(value: 'ban', child: Text('Ban folder from media library')),
                    ],
                  ),
                  onTap: () => setState(() => _storagePath = d.path),
                ),
              );
            }
            final f = videoFiles[i - dirs.length];
            final v = widget.service.allVideos.where((v) => v.filePath == f.path).firstOrNull;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                dense: true,
                leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.videocam, color: Color(0xFF818CF8), size: 18)),
                title: Text(_folderName(f.path), style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                onTap: () { if (v != null) { final idx = widget.service.allVideos.indexOf(v); setState(() { _playIndex = idx; _page = 'player'; }); } },
              ),
            );
          },
        );
      },
    );
  }

  void _openFolderSheet(String title, List<VideoFileInfo> videos) {
    showModalBottomSheet(
      context: context, backgroundColor: _kDark, isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (_, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                Text('${videos.length}', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
                const SizedBox(width: 8),
              ]),
            ),
            Expanded(child: GridView.builder(
              controller: sc,
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.75,
              ),
              itemCount: videos.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () { final idx = widget.service.allVideos.indexOf(videos[i]); Navigator.pop(context); setState(() { _playIndex = idx; _page = 'player'; }); },
                child: Container(
                  decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF2D3748), width: 0.5)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          width: double.infinity, color: Colors.black26,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(color: const Color(0xFF1A202C), child: const Icon(Icons.videocam, color: Color(0xFF818CF8), size: 36)),
                              Positioned(
                                right: 4, bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                                  child: Text(videos[i].fileSize > 0 ? '${(videos[i].fileSize / 1048576).toStringAsFixed(1)}MB' : '', style: const TextStyle(color: Colors.white70, fontSize: 9)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(videos[i].fileName, style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  // ─── Playlists Page ───────────────────────────────────────────────────────
  Widget _buildPlaylistsPage() {
    final pls = widget.service.playlists;
    return Stack(
      children: [
        pls.isEmpty
            ? const Center(child: Text('No playlists', style: TextStyle(color: Color(0xFF666680))))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: pls.length,
                itemBuilder: (_, i) {
                  final pl = pls[i];
                  final videos = widget.service.getPlaylistVideos(pl['name']);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const Icon(Icons.playlist_play, color: Color(0xFF818CF8)),
                      title: Text(pl['name'], style: const TextStyle(color: Colors.white)),
                      subtitle: Text('${videos.length} videos', style: TextStyle(color: _kMuted, fontSize: 12)),
                      onTap: videos.isNotEmpty ? () => _openPlaylistVideos(videos) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () { widget.service.deletePlaylist(pl['name']); _toast('Playlist deleted'); },
                      ),
                    ),
                  );
                },
              ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.small(
            backgroundColor: _kAccent,
            onPressed: _createPlaylistDialog,
            child: const Icon(Icons.add, color: Colors.black),
          ),
        ),
      ],
    );
  }

  void _createPlaylistDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Playlist name', hintStyle: TextStyle(color: Color(0xFF666680)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () { if (ctrl.text.isNotEmpty) { widget.service.createPlaylist(ctrl.text); _toast('Playlist created'); } Navigator.pop(ctx); }, child: const Text('Create', style: TextStyle(color: Color(0xFF818CF8)))),
        ],
      ),
    );
  }

  void _openPlaylistVideos(List<VideoFileInfo> videos) {
    showModalBottomSheet(
      context: context, backgroundColor: _kDark, isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (_, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                const Expanded(child: Text('Playlist', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                TextButton.icon(onPressed: () { final first = videos.isNotEmpty ? widget.service.allVideos.indexOf(videos[0]) : 0; Navigator.pop(context); setState(() { _playIndex = first; _page = 'player'; }); }, icon: const Icon(Icons.play_arrow, size: 18, color: Color(0xFF818CF8)), label: const Text('Play All', style: TextStyle(color: Color(0xFF818CF8)))),
              ]),
            ),
            Expanded(child: ListView.builder(
              controller: sc, itemCount: videos.length,
              itemBuilder: (_, i) => ListTile(
                leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: Container(width: 44, height: 44, color: Colors.black26, child: const Icon(Icons.videocam, color: Color(0xFF818CF8), size: 20))),
                title: Text(videos[i].fileName, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                onTap: () { final idx = widget.service.allVideos.indexOf(videos[i]); Navigator.pop(context); setState(() { _playIndex = idx; _page = 'player'; }); },
              ),
            )),
          ],
        ),
      ),
    );
  }

  // ─── More Page ────────────────────────────────────────────────────────────
  Widget _buildMorePage() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _moreTile(Icons.settings, 'Settings', () => setState(() => _page = 'settings')),
        const SizedBox(height: 8),
        _moreTile(Icons.history, 'History', () => setState(() => _page = 'history')),
      ],
    );
  }

  Widget _moreTile(IconData icon, String label, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
      child: ListTile(leading: Icon(icon, color: _kAccent), title: Text(label, style: const TextStyle(color: Colors.white)), trailing: const Icon(Icons.chevron_right, color: Color(0xFF666680)), onTap: onTap),
    );
  }

  // ─── Footer ───────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      color: _kCard,
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.videocam, 'Video', _page == 'home'),
          _navItem(Icons.music_note, 'My Music', false, onTap: widget.onOpenMusic ?? () {}),
          _navItem(Icons.explore, 'Browse', false, onTap: () => setState(() => _page = 'browse')),
          _navItem(Icons.playlist_play, 'Playlists', false, onTap: () => setState(() => _page = 'playlists_page')),
          _navItem(Icons.more_horiz, 'More', false, onTap: () => setState(() => _page = 'more')),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool active, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: active ? _kAccent : _kMuted, size: 26),
          Text(label, style: TextStyle(color: active ? _kAccent : _kMuted, fontSize: 11)),
        ],
      ),
    );
  }

  // ─── Add to Playlist Sheet ────────────────────────────────────────────────
  void _addToPlaylistSheet(VideoFileInfo v) {
    showModalBottomSheet(
      context: context, backgroundColor: _kCard, isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5, maxChildSize: 0.8, minChildSize: 0.3,
        builder: (_, sc) => CustomScrollView(controller: sc, slivers: [
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Text('Add to Playlist', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))),
          SliverList(delegate: SliverChildBuilderDelegate((_, i) {
            final pl = widget.service.playlists[i];
            return ListTile(
              leading: const Icon(Icons.playlist_play, color: Color(0xFF818CF8)),
              title: Text(pl['name'], style: const TextStyle(color: Colors.white)),
              onTap: () { widget.service.addToPlaylist(pl['name'], v.id); Navigator.pop(context); _toast('Added to ${pl['name']}'); },
            );
          }, childCount: widget.service.playlists.length)),
          SliverToBoxAdapter(child: ListTile(
            leading: const Icon(Icons.add, color: Color(0xFF818CF8)),
            title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _createPlaylistDialog(); },
          )),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ]),
      ),
    );
  }

  void _subtitleDownloadDialog(VideoFileInfo v) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Download Subtitle', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('For: ${v.fileName}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Paste subtitle URL (.srt):', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(hintText: 'https://.../subtitles.srt', hintStyle: TextStyle(color: _kMuted), border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () async {
              final url = ctrl.text.trim();
              if (url.isEmpty) return;
              try {
                final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
                if (res.statusCode == 200) {
                  final parsed = _parseSrt(res.body);
                  if (parsed.isEmpty) { _toast('Invalid subtitle file'); return; }
                  final srtPath = v.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.srt');
                  File(srtPath).writeAsStringSync(res.body);
                  _toast('Subtitle saved! Will load on next play');
                } else {
                  _toast('Download failed (${res.statusCode})');
                }
              } catch (e) {
                _toast('Error: $e');
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Download', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _kCard, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
  }
}
