import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/platform/session_paths.dart';
import '../../../../core/platform/platform_paths.dart';
import '../../../../core/ui/makaw_toast.dart';
import '../../data/services/video_player_service.dart';
import '../../data/services/media_thumbnail_service.dart';
import '../../../music/data/services/music_player_service.dart';
import '../../../../app/providers/service_providers.dart';
import '../../../../core/storage/subtitle_service.dart';
import '../../../../core/utils/natural_sort.dart';

// ─── Subtitle data & Multi-Format Parser ──────────────────────────────────────
class SubtitleLine {
  final Duration start;
  final Duration end;
  final String text;
  const SubtitleLine(this.start, this.end, this.text);
}

typedef _SubtitleEntry = SubtitleLine;

String decodeSubtitleBytes(List<int> bytes) {
  var payload = bytes;
  // Auto-decompress gzip-encoded subtitle downloads (common on OpenSubtitles).
  if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    try {
      payload = GZipDecoder().decodeBytes(bytes);
    } catch (_) {}
  }
  if (payload.length >= 2 && payload[0] == 0xFF && payload[1] == 0xFE) {
    final u = <int>[];
    for (var i = 2; i + 1 < payload.length; i += 2) {
      u.add(payload[i] | (payload[i + 1] << 8));
    }
    return String.fromCharCodes(u);
  }
  if (payload.length >= 2 && payload[0] == 0xFE && payload[1] == 0xFF) {
    final u = <int>[];
    for (var i = 2; i + 1 < payload.length; i += 2) {
      u.add((payload[i] << 8) | payload[i + 1]);
    }
    return String.fromCharCodes(u);
  }
  return utf8.decode(payload, allowMalformed: true);
}

Duration _parseSubTimestamp(String raw) {
  final clean = raw.trim().split(RegExp(r'\s+')).first.replaceAll(',', '.');
  final parts = clean.split(':');
  if (parts.length == 3) {
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final secDouble = double.tryParse(parts[2]) ?? 0.0;
    final msTotal = (secDouble * 1000).round();
    return Duration(hours: h, minutes: m, milliseconds: msTotal);
  }
  if (parts.length == 2) {
    final m = int.tryParse(parts[0]) ?? 0;
    final secDouble = double.tryParse(parts[1]) ?? 0.0;
    return Duration(minutes: m, milliseconds: (secDouble * 1000).round());
  }
  return Duration.zero;
}

String _cleanSubtitleText(String s) => s
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\n', '\n')
    .replaceAll(RegExp(r'\{[^}]*\}'), '')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();

/// Parses SRT, WebVTT, ASS/SSA, and MicroDVD (.sub) subtitle payloads cleanly.
List<SubtitleLine> parseSubtitleContent(String raw, {String? filePath}) {
  var data = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (data.startsWith('\uFEFF')) data = data.substring(1);
  final lowerPath = (filePath ?? '').toLowerCase();
  final entries = <SubtitleLine>[];

  // 1. ASS / SSA format
  if (lowerPath.endsWith('.ass') ||
      lowerPath.endsWith('.ssa') ||
      data.contains('[Events]') ||
      data.contains('Dialogue:')) {
    var startIdx = 1;
    var endIdx = 2;
    var textIdx = 9;
    for (final line in data.split('\n')) {
      final t = line.trim();
      if (t.startsWith('Format:')) {
        final cols = t.substring(7).split(',').map((c) => c.trim().toLowerCase()).toList();
        final sI = cols.indexOf('start');
        final eI = cols.indexOf('end');
        final tI = cols.indexOf('text');
        if (sI >= 0) startIdx = sI;
        if (eI >= 0) endIdx = eI;
        if (tI >= 0) textIdx = tI;
      } else if (t.startsWith('Dialogue:')) {
        final rest = t.substring(9).trimLeft();
        final parts = <String>[];
        var pos = 0;
        for (var k = 0; k < textIdx; k++) {
          final comma = rest.indexOf(',', pos);
          if (comma == -1) break;
          parts.add(rest.substring(pos, comma).trim());
          pos = comma + 1;
        }
        parts.add(pos <= rest.length ? rest.substring(pos) : '');
        if (parts.length > textIdx) {
          final start = _parseSubTimestamp(parts[startIdx]);
          final end = _parseSubTimestamp(parts[endIdx]);
          final txt = _cleanSubtitleText(parts[textIdx]);
          if (txt.isNotEmpty && end > start) {
            entries.add(SubtitleLine(start, end, txt));
          }
        }
      }
    }
    if (entries.isNotEmpty) {
      entries.sort((a, b) => a.start.compareTo(b.start));
      return entries;
    }
  }

  // 2. MicroDVD .sub ({startFrame}{endFrame}Text)
  if (lowerPath.endsWith('.sub') || RegExp(r'^\{\d+\}\{\d+\}', multiLine: true).hasMatch(data)) {
    const fps = 23.976;
    for (final line in data.split('\n')) {
      final m = RegExp(r'^\{(\d+)\}\{(\d+)\}(.+)$').firstMatch(line.trim());
      if (m != null) {
        final f1 = int.tryParse(m.group(1)!) ?? 0;
        final f2 = int.tryParse(m.group(2)!) ?? 0;
        final start = Duration(milliseconds: ((f1 / fps) * 1000).round());
        final end = Duration(milliseconds: ((f2 / fps) * 1000).round());
        final txt = _cleanSubtitleText(m.group(3)!.replaceAll('|', '\n'));
        if (txt.isNotEmpty && end > start) entries.add(SubtitleLine(start, end, txt));
      }
    }
    if (entries.isNotEmpty) {
      entries.sort((a, b) => a.start.compareTo(b.start));
      return entries;
    }
  }

  // 3. SRT & WebVTT blocks (tolerates optional cue IDs, MM:SS.mmm, and settings)
  final blocks = data.trim().split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.isEmpty) continue;
    final firstUpper = lines.first.trim().toUpperCase();
    if (firstUpper.startsWith('WEBVTT') || firstUpper.startsWith('NOTE') || firstUpper.startsWith('STYLE')) {
      continue;
    }
    final timeIdx = lines.indexWhere((l) => l.contains('-->'));
    if (timeIdx == -1 || timeIdx + 1 >= lines.length) continue;
    final times = lines[timeIdx].trim().split(RegExp(r'\s*-->\s*'));
    if (times.length != 2) continue;
    final start = _parseSubTimestamp(times[0]);
    final end = _parseSubTimestamp(times[1]);
    final text = _cleanSubtitleText(lines.sublist(timeIdx + 1).join('\n'));
    if (text.isNotEmpty && end >= start) {
      entries.add(SubtitleLine(start, end, text));
    }
  }
  entries.sort((a, b) => a.start.compareTo(b.start));
  return entries;
}

List<_SubtitleEntry> _parseSrt(String data, {String? filePath}) =>
    parseSubtitleContent(data, filePath: filePath);

// ─── Thumbnail widget (placeholder for now) ─────────────────────────────
class _ThumbnailView extends StatelessWidget {
  final String filePath;
  final Map<String, String> thumbCache;
  const _ThumbnailView({required this.filePath, required this.thumbCache});

  @override
  Widget build(BuildContext context) {
    return MediaArtworkWidget(
      filePath: filePath,
      isVideo: true,
      fallbackColor: const Color(0xFF1A202C),
      iconColor: const Color(0xFF818CF8),
      fallbackIcon: Icons.videocam,
    );
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
  final VoidCallback? onDownload;
  const DirectVideoPlayer({super.key, this.filePath, this.url, this.title = '', this.playlist, this.initialIndex = 0, this.onClose, this.onDownload});
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
  Duration _subtitleOffset = Duration.zero;
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

  // ─── Gesture / Volume / Brightness ──────────────────────────────────────
  static const _videoChannel = MethodChannel('com.hexadigitall.makaw/video_control');
  final GlobalKey _videoKey = GlobalKey();
  double _volume = 1.0;
  int _maxVolume = 15;
  double _brightness = 0.5;
  bool _showVolumeOverlay = false;
  bool _showBrightnessOverlay = false;
  bool _showSeekPreview = false;
  int _seekPreviewDelta = 0;
  Timer? _overlayTimer;
  bool _draggingVertical = false;
  double _dragStartY = 0;
  double _dragStartX = 0;
  String _dragSide = '';
  String _doubleTapSide = '';
  Timer? _doubleTapTimer;
  Timer? _hideTimer;
  bool _isScrubbing = false;
  double _scrubMs = 0;
  DateTime _lastChannelAdjust = DateTime.fromMillisecondsSinceEpoch(0);
  int _skipSeconds = 10;
  bool _bgPlay = false;
  bool _nightMode = false;
  bool _mirrorVideo = false;
  bool _loopVideo = false;
  bool _shufflePlaylist = false;
  bool _hwDecoder = true;
  int _autoHideSeconds = 4;
  int _sleepTimerMinutes = 0;
  Timer? _sleepTimer;
  Duration? _abPointA;
  Duration? _abPointB;
  bool _advancingNext = false;
  bool _showResumeBanner = false;
  String _resumeTimeLabel = '';
  Timer? _resumeBannerTimer;
  bool _showAspectBanner = false;
  String _aspectBannerLabel = '';
  Timer? _aspectBannerTimer;
  bool _showRemainingTime = false;

  // Resume/watch-progress persistence
  final VideoPlayerService _resumeService =
      VideoPlayerService.shared ?? VideoPlayerService();
  DateTime _lastResumeSave = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadVideoPrefs().then((_) {
      if (mounted) _initPlayer();
    });
    _loadSystemVolume();
    _loadSystemBrightness();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF0F0F1A),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  Future<void> _loadVideoPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _bgPlay = prefs.getBool('video_bg_play') ?? false;
      _nightMode = prefs.getBool('video_night_mode') ?? false;
      _mirrorVideo = prefs.getBool('video_mirror') ?? false;
      _loopVideo = prefs.getBool('video_loop') ?? false;
      _shufflePlaylist = prefs.getBool('video_shuffle') ?? false;
      _hwDecoder = prefs.getBool('video_hw_decoder') ?? true;
      _skipSeconds = prefs.getInt('video_skip_seconds') ?? 10;
      _autoHideSeconds = prefs.getInt('video_auto_hide_sec') ?? 4;
      final savedDim = prefs.getString('video_dimension_mode');
      if (savedDim != null && _modes.contains(savedDim)) {
        _dimensionMode = savedDim;
      }
    } catch (_) {}
  }

  Future<void> _saveVideoPref(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) await prefs.setBool(key, value);
      if (value is int) await prefs.setInt(key, value);
      if (value is String) await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<void> _loadSystemVolume() async {
    try {
      _maxVolume = await _videoChannel.invokeMethod<int>('getMaxVolume') ?? 15;
      final vol = await _videoChannel.invokeMethod<int>('getVolume') ?? _maxVolume;
      _volume = vol / _maxVolume;
    } catch (_) {}
  }

  Future<void> _loadSystemBrightness() async {
    try {
      _brightness = (await _videoChannel.invokeMethod<double>('getScreenBrightness')) ?? 0.5;
    } catch (_) {}
  }

  Future<void> _setKeepScreenOn(bool keep) async {
    try {
      await _videoChannel.invokeMethod('setKeepScreenOn', {'keep': keep});
    } catch (_) {}
  }

  void _initPlayer() {
    // Pause background music cleanly so ExoPlayer gets clean AudioFocus without stuttering
    if (MusicPlayerService.shared?.isPlaying == true) {
      MusicPlayerService.shared?.player.pause();
    }
    final opts = VideoPlayerOptions(mixWithOthers: false, allowBackgroundPlayback: _bgPlay);
    final path = _currentFile();
    if (path != null && File(path).existsSync()) {
      _controller = VideoPlayerController.file(File(path), videoPlayerOptions: opts);
    } else if (path != null && (path.startsWith('http://') || path.startsWith('https://'))) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(path), videoPlayerOptions: opts);
    } else if (widget.url != null) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url!), videoPlayerOptions: opts);
    }
    if (_controller == null) {
      setState(() => _initialized = true);
      return;
    }
    _controller!.initialize().then((_) {
      if (!mounted) return;
      _controller!.setLooping(_loopVideo);
      _controller!.addListener(_onVideoEvent);
      _restoreResume();
      _controller!.play();
      _setKeepScreenOn(true);
      final cur = _currentFile();
      if (cur != null && cur.isNotEmpty) {
        _resumeService.setActiveVideo(path: cur, title: widget.title, isPlaying: true);
      }
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
    final val = _controller!.value;
    final isPlayingNow = val.isPlaying;
    if (_isPlaying != isPlayingNow) {
      _isPlaying = isPlayingNow;
      _setKeepScreenOn(isPlayingNow);
      setState(() {});
    }

    // AB Repeat loop
    if (_abPointA != null && _abPointB != null && _abPointB! > _abPointA!) {
      if (val.position >= _abPointB!) {
        _controller!.seekTo(_abPointA!);
      }
    }

    // Auto-advance playlist when video finishes (unless single-video loop is active)
    if (!_loopVideo &&
        !_advancingNext &&
        val.isInitialized &&
        val.duration > Duration.zero &&
        !val.isPlaying &&
        val.position >= val.duration - const Duration(milliseconds: 250)) {
      final list = widget.playlist;
      if (list != null && list.length > 1) {
        _advancingNext = true;
        final nextIdx = _shufflePlaylist
            ? Random().nextInt(list.length)
            : (_currentIndex + 1);
        if (nextIdx < list.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _switchVideo(nextIdx);
          });
        }
      }
    }

    final now = DateTime.now();
    if (now.difference(_lastResumeSave).inSeconds >= 5) {
      _lastResumeSave = now;
      _persistWatchProgress();
    }
  }

  void _restoreResume() {
    final path = _currentFile();
    if (path == null || path.isEmpty) return;
    if (!_resumeService.hasResume(path)) return;
    final pos = _resumeService.resumePosition(path);
    if (pos <= 0) return;
    _controller?.seekTo(Duration(milliseconds: pos));
    _lastResumeSave = DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dur = Duration(milliseconds: pos);
      final fmt = dur.inHours > 0
          ? '${dur.inHours}:${(dur.inMinutes % 60).toString().padLeft(2, '0')}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}'
          : '${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}';
      _resumeBannerTimer?.cancel();
      setState(() {
        _resumeTimeLabel = fmt;
        _showResumeBanner = true;
      });
      _resumeBannerTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _showResumeBanner) {
          setState(() => _showResumeBanner = false);
        }
      });
    });
  }

  void _persistWatchProgress() {
    final c = _controller;
    final path = _currentFile();
    if (c == null || path == null || path.isEmpty) return;
    final value = c.value;
    if (!value.isInitialized) return;
    final pos = value.position.inMilliseconds;
    final dur = value.duration.inMilliseconds;
    if (pos <= 0 || dur <= 0) return;
    if (dur - pos <= 20000) {
      _resumeService.clearResume(path);
      return;
    }
    _resumeService.saveResume(path, pos, dur);
  }

  String? _currentFile() {
    if (widget.playlist != null && widget.playlist!.isNotEmpty) return widget.playlist![_currentIndex];
    return widget.filePath ?? widget.url;
  }

  void _startAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(seconds: _autoHideSeconds), () {
      if (mounted && _isPlaying && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  /// "Wake" the controls: show them and restart the idle-hide countdown.
  ///
  /// Triggered by external input (mouse movement over the player on desktop,
  /// tap/click/touch on touch devices) so the header + controls reappear
  /// without requiring a separate toggle gesture.
  void _wakeControls() {
    if (_locked || !mounted) return;
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    if (_isPlaying) _startAutoHide();
  }

  @override
  void dispose() {
    _setKeepScreenOn(false);
    _sleepTimer?.cancel();
    _subtitleTimer?.cancel();
    _overlayTimer?.cancel();
    _doubleTapTimer?.cancel();
    _hideTimer?.cancel();
    _resumeBannerTimer?.cancel();
    _aspectBannerTimer?.cancel();
    _persistWatchProgress();
    _resumeService.stopActiveVideo();
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
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _setKeepScreenOn(false);
      _persistWatchProgress();
    } else {
      _controller!.play();
      _setKeepScreenOn(true);
    }
    _startAutoHide();
  }

  void _onToggleControls() {
    if (_locked) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startAutoHide();
    }
  }

  // ─── Double-tap seek ────────────────────────────────────────────────────
  void _onDoubleTapDown(TapDownDetails details) {
    if (_locked || _controller == null) return;
    final screenW = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;
    final isLeft = dx < screenW / 2;
    final delta = isLeft ? -_skipSeconds : _skipSeconds;
    final pos = _controller!.value.position;
    final maxMs = _controller!.value.duration.inMilliseconds;
    final targetMs = (pos.inMilliseconds + delta * 1000).clamp(0, maxMs);
    _controller!.seekTo(Duration(milliseconds: targetMs));
    setState(() {
      _doubleTapSide = isLeft ? 'left' : 'right';
      _seekPreviewDelta = delta;
      _showSeekPreview = true;
    });
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _showSeekPreview = false);
    });
  }

  // ─── Vertical drag (volume / brightness) ────────────────────────────────
  void _onVerticalDragStart(DragStartDetails details) {
    if (_locked || _controller == null) return;
    final screenW = MediaQuery.of(context).size.width;
    _dragStartX = details.globalPosition.dx;
    _dragSide = _dragStartX > screenW / 2 ? 'volume' : 'brightness';
    _dragStartY = details.globalPosition.dy;
    _draggingVertical = true;
    if (_dragSide == 'volume') {
      _showVolumeOverlay = true;
      _showBrightnessOverlay = false;
    } else {
      _showBrightnessOverlay = true;
      _showVolumeOverlay = false;
    }
    _overlayTimer?.cancel();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_draggingVertical) return;
    final dy = _dragStartY - details.globalPosition.dy;
    final sensitivity = MediaQuery.of(context).size.height * 0.6;
    final delta = (dy / sensitivity).clamp(-1.0, 1.0);
    final now = DateTime.now();
    final canInvokeChannel = now.difference(_lastChannelAdjust).inMilliseconds >= 45;

    if (_dragSide == 'volume') {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      if (canInvokeChannel) {
        _lastChannelAdjust = now;
        final vol = (_volume * _maxVolume).round();
        _videoChannel.invokeMethod('setVolume', {'volume': vol});
      }
    } else {
      _brightness = (_brightness + delta).clamp(0.01, 1.0);
      if (canInvokeChannel) {
        _lastChannelAdjust = now;
        _videoChannel.invokeMethod('setScreenBrightness', {'brightness': _brightness});
      }
    }
    _dragStartY = details.globalPosition.dy;
    setState(() {});
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _draggingVertical = false;
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() {
        _showVolumeOverlay = false;
        _showBrightnessOverlay = false;
      });
    });
  }

  Widget _buildVolumeOverlay() {
    final pct = (_volume * 100).round();
    return Container(
      width: 52, height: 140,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(26),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_volume > 0 ? Icons.volume_up : Icons.volume_off, color: Colors.white, size: 18),
          const SizedBox(height: 6),
          Expanded(
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: const SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5), activeTrackColor: Color(0xFF818CF8), inactiveTrackColor: Colors.white24, thumbColor: Color(0xFF818CF8)),
                child: Slider(value: _volume, min: 0, max: 1, onChanged: null),
              ),
            ),
          ),
          Text('$pct', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildBrightnessOverlay() {
    final pct = (_brightness * 100).round();
    return Container(
      width: 52, height: 140,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(26),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_brightness > 0.5 ? Icons.brightness_high : Icons.brightness_low, color: Colors.white, size: 18),
          const SizedBox(height: 6),
          Expanded(
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: const SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5), activeTrackColor: Color(0xFFFFC107), inactiveTrackColor: Colors.white24, thumbColor: Color(0xFFFFC107)),
                child: Slider(value: _brightness, min: 0.01, max: 1, onChanged: null),
              ),
            ),
          ),
          Text('$pct%', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _fmt(Duration d) { final m = d.inMinutes.remainder(60).toString().padLeft(2, '0'); final s = d.inSeconds.remainder(60).toString().padLeft(2, '0'); return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s'; }

  void _cycleDim() {
    final idx = _modes.indexOf(_dimensionMode);
    final next = _modes[(idx + 1) % _modes.length];
    final nextLabel = _modeLabels[(idx + 1) % _modes.length];
    _aspectBannerTimer?.cancel();
    setState(() {
      _dimensionMode = next;
      _aspectBannerLabel = 'Aspect: $nextLabel';
      _showAspectBanner = true;
    });
    _aspectBannerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _showAspectBanner) setState(() => _showAspectBanner = false);
    });
    _saveVideoPref('video_dimension_mode', _dimensionMode);
  }

  void _switchVideo(int index) {
    _persistWatchProgress();
    _controller?.removeListener(_onVideoEvent);
    _controller?.pause();
    _controller?.dispose();
    _abPointA = null;
    _abPointB = null;
    _advancingNext = false;
    setState(() { _currentIndex = index; _initialized = false; _isPlaying = false; });
    _initPlayer();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Color(0xFF818CF8))));
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text('Failed to load video', style: TextStyle(color: Colors.white54))));
    }
    final hasMulti = widget.playlist != null && widget.playlist!.length > 1;
    final curTitle = _currentFile()?.split('\\').last.split('/').last ?? widget.title;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final vidSize = _controller!.value.size;
    final vw = vidSize.width > 0 ? vidSize.width : 1280.0;
    final vh = vidSize.height > 0 ? vidSize.height : 720.0;

    Widget videoWidget;
    switch (_dimensionMode) {
      case 'fit':
        videoWidget = SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(width: vw, height: vh, child: VideoPlayer(_controller!)),
          ),
        );
        break;
      case 'fill':
        videoWidget = SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: vw, height: vh, child: VideoPlayer(_controller!)),
          ),
        );
        break;
      case '16:9':
        videoWidget = Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: vw, height: vh, child: VideoPlayer(_controller!)),
            ),
          ),
        );
        break;
      case '4:3':
        videoWidget = Center(
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: vw, height: vh, child: VideoPlayer(_controller!)),
            ),
          ),
        );
        break;
      case 'center':
        videoWidget = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: AspectRatio(
              aspectRatio: vw / vh,
              child: VideoPlayer(_controller!),
            ),
          ),
        );
        break;
      default:
        videoWidget = Center(
          child: AspectRatio(
            aspectRatio: vw / vh,
            child: VideoPlayer(_controller!),
          ),
        );
    }

    final renderedVideo = _mirrorVideo
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
            child: videoWidget,
          )
        : videoWidget;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MouseRegion(
            onHover: (_) => _wakeControls(),
            child: GestureDetector(
              onTap: _onToggleControls,
              onDoubleTapDown: _onDoubleTapDown,
              onVerticalDragStart: _locked ? null : _onVerticalDragStart,
              onVerticalDragUpdate: _locked ? null : _onVerticalDragUpdate,
              onVerticalDragEnd: _locked ? null : _onVerticalDragEnd,
              child: Container(
                color: Colors.black,
                width: double.infinity,
                height: double.infinity,
                child: RepaintBoundary(
                  key: _videoKey,
                  child: renderedVideo,
                ),
              ),
            ),
          ),
          if (_nightMode)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: const Color(0x28FF8F00)),
              ),
            ),
          if (_abPointA != null)
            Positioned(
              left: 16,
              top: topPad + 56,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.65)),
                ),
                child: Text(
                  'A ${_fmt(_abPointA!)}  ->  ${_abPointB != null ? 'B ${_fmt(_abPointB!)}' : 'B ...'}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (_showAspectBanner)
            Center(
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    _aspectBannerLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          // Double-tap seek preview
          if (_showSeekPreview)
            Positioned(
              left: _doubleTapSide == 'left' ? 0 : null,
              right: _doubleTapSide == 'right' ? 0 : null,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(24)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_doubleTapSide == 'left' ? Icons.replay_10 : Icons.forward_10, color: Colors.white, size: 20),
                      const SizedBox(width: 6),
                      Text('${_seekPreviewDelta > 0 ? '+' : ''}${_seekPreviewDelta}s',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          if (_showVolumeOverlay)
            Positioned(right: 20, top: MediaQuery.of(context).size.height * 0.25, child: _buildVolumeOverlay()),
          if (_showBrightnessOverlay)
            Positioned(left: 20, top: MediaQuery.of(context).size.height * 0.25, child: _buildBrightnessOverlay()),
          if (_showResumeBanner)
            Positioned(
              left: 20,
              right: 20,
              bottom: bottomPad + (_showControls && !_locked ? 168 : 24),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141826).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.5)),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history_rounded, color: Color(0xFF818CF8), size: 17),
                      const SizedBox(width: 7),
                      Text(
                        'Resumed from $_resumeTimeLabel',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: const Color(0xFF818CF8).withValues(alpha: 0.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          _resumeBannerTimer?.cancel();
                          _controller?.seekTo(Duration.zero);
                          final p = _currentFile();
                          if (p != null) _resumeService.clearResume(p);
                          setState(() => _showResumeBanner = false);
                        },
                        child: const Text('Start Over', style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          _resumeBannerTimer?.cancel();
                          setState(() => _showResumeBanner = false);
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_subtitleOn && _subtitles.isNotEmpty && _activeSubtitle.isNotEmpty)
            Positioned(
              left: 24,
              right: 24,
              bottom: (_showControls && !_locked) ? bottomPad + 168 : bottomPad + 28,
              child: IgnorePointer(
                child: _buildStyledSubtitle(),
              ),
            ),
          if (_showControls && !_locked) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(top: topPad + 4, left: 6, right: 8, bottom: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.84), Colors.transparent],
                  ),
                ),
                child: _buildTopBar(curTitle, isLandscape, hasMulti),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _controller!,
                builder: (_, val, __) => Container(
                  padding: EdgeInsets.only(bottom: bottomPad + 8, top: 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.88)],
                    ),
                  ),
                  child: _buildBottomControls(val.position, val.duration, hasMulti, isLandscape),
                ),
              ),
            ),
          ],
          if (_locked)
            Positioned(
              left: 20,
              bottom: bottomPad + 28,
              child: GestureDetector(
                onTap: () => setState(() => _locked = false),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(String title, bool isLandscape, bool hasMulti) {
    final resH = _controller?.value.size.height.round() ?? 0;
    final speed = _controller?.value.playbackSpeed ?? 1.0;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
          onPressed: () => (widget.onClose ?? () => Navigator.pop(context))(),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (resH > 0 || (speed - 1.0).abs() > 0.01)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      if (resH > 0)
                        _playerMiniBadge('${resH}p'),
                      if ((speed - 1.0).abs() > 0.01) ...[
                        const SizedBox(width: 6),
                        _playerMiniBadge('${speed.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}x', color: const Color(0xFF38BDF8)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (widget.onDownload != null)
          IconButton(icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20), onPressed: widget.onDownload),
        if (hasMulti)
          IconButton(
            icon: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 22),
            tooltip: 'Playlist (${widget.playlist!.length})',
            onPressed: _showPlaylistSheet,
          ),
        IconButton(
          icon: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white, size: 20),
          tooltip: _isMuted ? 'Unmute' : 'Mute',
          onPressed: _toastMute,
        ),
        IconButton(
          icon: const Icon(Icons.screen_rotation_rounded, color: Colors.white, size: 20),
          tooltip: 'Rotate',
          onPressed: () {
            final cur = MediaQuery.of(context).orientation;
            if (cur == Orientation.portrait) {
              SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
            } else {
              SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 21),
          tooltip: 'Player Actions',
          onPressed: _showPlayerMoreSheet,
        ),
      ],
    );
  }

  Widget _playerMiniBadge(String label, {Color color = const Color(0xFF818CF8)}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.6), width: 0.8),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
  );

  Widget _buildBottomControls(Duration pos, Duration dur, bool hasMulti, bool isLandscape) {
    final dimLabel = _modeLabels[_modes.indexOf(_dimensionMode)];
    final speed = _controller?.value.playbackSpeed ?? 1.0;
    final rem = dur > pos ? dur - pos : Duration.zero;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dur > Duration.zero)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Text(
                  _fmt(_isScrubbing ? Duration(milliseconds: _scrubMs.round()) : pos),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                Expanded(
                  child: SliderTheme(
                    data: const SliderThemeData(
                      trackHeight: 3.5,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Color(0xFF818CF8),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: (_isScrubbing ? _scrubMs : pos.inMilliseconds.toDouble())
                          .clamp(0.0, dur.inMilliseconds.toDouble().clamp(1.0, double.infinity)),
                      max: dur.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                      onChangeStart: (v) {
                        _hideTimer?.cancel();
                        setState(() {
                          _isScrubbing = true;
                          _scrubMs = v;
                        });
                      },
                      onChanged: (v) => setState(() => _scrubMs = v),
                      onChangeEnd: (v) {
                        _controller?.seekTo(Duration(milliseconds: v.round()));
                        setState(() => _isScrubbing = false);
                        _startAutoHide();
                      },
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showRemainingTime = !_showRemainingTime),
                  child: Text(
                    _showRemainingTime ? '-${_fmt(rem)}' : _fmt(dur),
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.lock_open_rounded, color: Colors.white70, size: 20),
                tooltip: 'Lock Controls',
                onPressed: () => setState(() => _locked = true),
              ),
              const Spacer(),
              if (hasMulti)
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                  onPressed: _currentIndex > 0 ? () => _switchVideo(_currentIndex - 1) : null,
                ),
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 25),
                tooltip: '-${_skipSeconds}s',
                onPressed: () => _controller!.seekTo(Duration(seconds: (pos.inSeconds - _skipSeconds).clamp(0, 999999))),
              ),
              const SizedBox(width: 8),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF818CF8), Color(0xFF6366F1)]),
                  boxShadow: [BoxShadow(color: const Color(0xFF818CF8).withValues(alpha: 0.4), blurRadius: 14)],
                ),
                child: IconButton(
                  icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 32),
                  onPressed: _togglePlay,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 25),
                tooltip: '+${_skipSeconds}s',
                onPressed: () => _controller!.seekTo(Duration(seconds: pos.inSeconds + _skipSeconds)),
              ),
              if (hasMulti)
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                  onPressed: _currentIndex < widget.playlist!.length - 1 ? () => _switchVideo(_currentIndex + 1) : null,
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.screenshot_monitor_rounded, color: Colors.white70, size: 20),
                tooltip: 'Capture Frame',
                onPressed: _toastCapture,
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _controlPill(Icons.aspect_ratio_rounded, dimLabel, true, _cycleDim),
              const SizedBox(width: 8),
              _controlPill(Icons.speed_rounded, '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}x', (speed - 1.0).abs() > 0.01, _speedSheet),
              const SizedBox(width: 8),
              _controlPill(Icons.subtitles_rounded, 'Subtitles', _subtitleOn, _showSubtitlePanel),
              const SizedBox(width: 8),
              _controlPill(Icons.tune_rounded, 'Settings', false, _showVideoSettings),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controlPill(IconData icon, String label, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF818CF8).withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? const Color(0xFF818CF8).withValues(alpha: 0.7) : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? const Color(0xFFA5B4FC) : Colors.white70, size: 15),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showPlayerMoreSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141826),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8)),
              title: const Text('Video Information', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _showVideoInfo(); },
            ),
            ListTile(
              leading: const Icon(Icons.cast_rounded, color: Colors.white70),
              title: const Text('Cast', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _toastCast(); },
            ),
            ListTile(
              leading: const Icon(Icons.audiotrack_rounded, color: Colors.white70),
              title: const Text('Audio Track', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _toastAudio(); },
            ),
            ListTile(
              leading: const Icon(Icons.settings_rounded, color: Color(0xFF818CF8)),
              title: const Text('All Player Settings & Equalizer', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _showVideoSettings(); },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Mute toggle ────────────────────────────────────────────────────────
  bool _isMuted = false;
  double _volumeBeforeMute = 1.0;

  void _toastCast() => _toast('Cast not supported on this device');

  Future<void> _toastCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final boundary = _videoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) { _toast('Capture failed'); return; }
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) { _toast('Capture failed'); return; }
      final bytes = byteData.buffer.asUint8List();
      final dir = await SessionPaths.downloadsSubDir('Makaw');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('$dir/screenshot_$ts.png');
      await file.writeAsBytes(bytes);
      image.dispose();
      if (mounted) {
        _toast('Screenshot saved: ${file.path.split('/').last}');
        Share.shareXFiles([XFile(file.path)], text: 'Screenshot from Makaw');
      }
    } catch (e) {
      _toast('Capture error: $e');
    }
  }

  Future<void> _toastMute() async {
    if (_controller == null) return;
    try {
      if (_isMuted) {
        _isMuted = false;
        final vol = (_volumeBeforeMute * _maxVolume).round();
        _videoChannel.invokeMethod('setVolume', {'volume': vol});
      } else {
        _isMuted = true;
        _volumeBeforeMute = _volume;
        _videoChannel.invokeMethod('setVolume', {'volume': 0});
      }
      _toast(_isMuted ? 'Muted' : 'Unmuted');
    } catch (_) {
      _toast('Volume control not available');
    }
  }

  void _toastAudio() => _toast('Audio track not available');

  void _showPlaylistSheet() {
    final list = widget.playlist;
    if (list == null || list.isEmpty) {
      _toast('No playlist loaded');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141826),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.35,
        builder: (_, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.playlist_play_rounded, color: Color(0xFF818CF8)),
                  const SizedBox(width: 8),
                  Text('Up Next (${list.length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Divider(color: Color(0xFF283148), height: 1),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: list.length,
                itemBuilder: (_, idx) {
                  final p = list[idx];
                  final name = p.split('\\').last.split('/').last;
                  final active = idx == _currentIndex;
                  return ListTile(
                    dense: true,
                    leading: Icon(active ? Icons.play_circle_filled_rounded : Icons.movie_outlined, color: active ? const Color(0xFF818CF8) : Colors.white54),
                    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? const Color(0xFFA5B4FC) : Colors.white, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _switchVideo(idx);
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
  void _activateSubtitles(List<_SubtitleEntry> parsed, String subPath, {bool showNotice = false}) {
    _subtitles = parsed;
    _subtitlePath = subPath;
    _subtitleFileLabel = subPath.split('\\').last.split('/').last;
    _subtitleOn = true;
    _subtitleTimer?.cancel();
    _subtitleTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (mounted && _subtitleOn) setState(() {});
    });
    if (mounted) setState(() {});
    _persistSubtitles();
    if (showNotice && mounted) {
      MakawToast.success(context, 'Loaded $_subtitleFileLabel (${parsed.length} lines)', title: 'Subtitles Active');
    }
  }

  Future<void> _loadSubtitlesForFile() async {
    _subtitles = [];
    _subtitlePath = '';
    _subtitleFileLabel = '';
    _subtitleOffset = Duration.zero;
    _subtitleTimer?.cancel();
    final path = _currentFile();
    if (path == null) return;
    final base = path.replaceAll(RegExp(r'\.[^.]+$'), '');
    final baseName = base.split('\\').last.split('/').last.toLowerCase();
    final cleanStem = baseName.replaceAll(RegExp(r'[\.\-_]+'), ' ').trim();
    const exts = ['.srt', '.vtt', '.ass', '.ssa', '.sub'];

    // 1. Exact sidecar paths first
    final candidates = <File>[
      for (final ext in exts) File('$base$ext'),
    ];

    // 2. Scan same folder + Subs/Subtitles subfolders for language-tagged or case-variant sidecars
    try {
      final parentDir = File(path).parent;
      final scanDirs = <Directory>[
        parentDir,
        Directory('${parentDir.path}${Platform.pathSeparator}Subs'),
        Directory('${parentDir.path}${Platform.pathSeparator}Subtitles'),
        Directory('${parentDir.path}${Platform.pathSeparator}subs'),
      ];
      for (final dir in scanDirs) {
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is! File) continue;
          final fLower = entity.path.toLowerCase();
          if (!exts.any((e) => fLower.endsWith(e))) continue;
          final fStem = fLower.split('\\').last.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
          final fClean = fStem.replaceAll(RegExp(r'[\.\-_]+'), ' ').trim();
          if (fStem.startsWith(baseName) || fClean.startsWith(cleanStem) || dir != parentDir) {
            if (!candidates.any((c) => c.path == entity.path)) {
              candidates.add(entity);
            }
          }
        }
      }
    } catch (_) {}

    for (final f in candidates) {
      if (!f.existsSync()) continue;
      try {
        final raw = decodeSubtitleBytes(f.readAsBytesSync());
        final parsed = parseSubtitleContent(raw, filePath: f.path);
        if (parsed.isNotEmpty) {
          _activateSubtitles(parsed, f.path);
          return;
        }
      } catch (_) {}
    }

    // 3. Fallback to persisted cues in SubtitleService (if user previously synced/loaded one)
    try {
      final savedCues = await SubtitleService.cuesForMedia(path);
      if (savedCues.isNotEmpty) {
        final parsed = savedCues
            .map((c) => _SubtitleEntry(
                  Duration(milliseconds: c.startMs),
                  Duration(milliseconds: c.endMs),
                  c.text,
                ))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        _activateSubtitles(parsed, 'Saved Subtitle (${savedCues.length})');
        return;
      }
    } catch (_) {}

    // 4. Auto-search online if no local subtitle found
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
      final raw = decodeSubtitleBytes(res.bodyBytes);
      final parsed = parseSubtitleContent(raw, filePath: '$basePath.srt');
      if (parsed.isEmpty) return;
      final srtPath = '$basePath.srt';
      try {
        File(srtPath).writeAsStringSync(raw);
      } catch (_) {}
      if (!mounted) return;
      _activateSubtitles(parsed, srtPath);
    } catch (_) {}
  }

  /// Persist the currently-loaded subtitles into the Subtitles manager so they
  /// appear in the Subtitles hub.
  void _persistSubtitles() {
    final mediaId = widget.filePath ?? widget.url ?? (_subtitlePath.isNotEmpty ? _subtitlePath : null);
    if (mediaId == null || mediaId.isEmpty || _subtitles.isEmpty) return;
    final mediaTitle = widget.title.isNotEmpty
        ? widget.title
        : mediaId.split('\\').last.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
    try {
      final cues = _subtitles.map((s) => SubtitleCue(
            mediaId: mediaId,
            mediaTitle: mediaTitle,
            text: s.text,
            startMs: s.start.inMilliseconds,
            endMs: s.end.inMilliseconds,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )).toList();
      SubtitleService.saveCues(mediaId, mediaTitle, cues);
    } catch (_) {}
  }

  String get _activeSubtitle {
    final rawPos = _controller?.value.position;
    if (rawPos == null) return '';
    final pos = rawPos - _subtitleOffset;
    for (final s in _subtitles) {
      if (pos >= s.start && pos <= s.end) return s.text;
    }
    return '';
  }

  void _showSubtitleSyncSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141826),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final sec = _subtitleOffset.inMilliseconds / 1000.0;
          void nudge(double deltaSec) {
            setState(() {
              final nextMs = (_subtitleOffset.inMilliseconds + (deltaSec * 1000).round()).clamp(-15000, 15000);
              _subtitleOffset = Duration(milliseconds: nextMs);
            });
            setDlg(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Subtitle Sync Offset', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    '${sec >= 0 ? '+' : ''}${sec.toStringAsFixed(1)}s ${sec > 0 ? '(Delayed)' : sec < 0 ? '(Earlier)' : '(In Sync)'}',
                    style: const TextStyle(color: Color(0xFF818CF8), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton(onPressed: () => nudge(-0.5), child: const Text('-0.5s')),
                      OutlinedButton(onPressed: () => nudge(-0.1), child: const Text('-0.1s')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF818CF8), foregroundColor: Colors.black),
                        onPressed: () {
                          setState(() => _subtitleOffset = Duration.zero);
                          setDlg(() {});
                        },
                        child: const Text('Reset'),
                      ),
                      OutlinedButton(onPressed: () => nudge(0.1), child: const Text('+0.1s')),
                      OutlinedButton(onPressed: () => nudge(0.5), child: const Text('+0.5s')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
                subtitle: Text(
                  _subtitleOffset == Duration.zero
                      ? 'In sync (0.0s)'
                      : 'Offset: ${(_subtitleOffset.inMilliseconds / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSubtitleSyncSheet();
                },
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
        final defaultSubPath = PlatformPaths.home().isEmpty
              ? '/storage/emulated/0/Download'
              : '${PlatformPaths.home()}${Platform.pathSeparator}Downloads';
        var currentPath = defaultSubPath;
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
                          final raw = decodeSubtitleBytes(f.readAsBytesSync());
                          final parsed = parseSubtitleContent(raw, filePath: f.path);
                          if (parsed.isEmpty) {
                            MakawToast.warning(context, 'No timing cues found in $fName');
                            return;
                          }
                          _activateSubtitles(parsed, f.path, showNotice: true);
                        } catch (e) {
                          MakawToast.error(context, 'Could not load subtitle: $e');
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
        final raw = decodeSubtitleBytes(res.bodyBytes);
        final parsed = parseSubtitleContent(raw, filePath: url);
        if (parsed.isEmpty || !mounted) {
          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
          MakawToast.error(context, 'Downloaded file had no readable subtitle cues');
          return;
        }
        final base = _currentFile()?.replaceAll(RegExp(r'\.[^.]+$'), '.srt') ?? '';
        if (base.isNotEmpty) {
          try {
            File(base).writeAsStringSync(raw);
          } catch (_) {}
          _activateSubtitles(parsed, base);
        } else {
          _activateSubtitles(parsed, 'Downloaded Subtitle');
        }
        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
        if (mounted) MakawToast.success(context, 'Subtitle downloaded (${parsed.length} lines)', title: 'Subtitles Active');
      } else {
        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
        if (mounted) MakawToast.error(context, 'Subtitle server returned HTTP ${res.statusCode}');
      }
    } catch (_) {
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      if (mounted) MakawToast.error(context, 'Could not download subtitle');
    }
  }

  Future<List<Map<String, String>>> _fetchOpenSubtitles(String query, [String lang = 'English']) async {
    final results = <Map<String, String>>[];
    final cleanQuery = query
        .replaceAll(RegExp(r'[\.\-_]+'), ' ')
        .replaceAll(RegExp(r'\b(1080p|720p|2160p|4k|x264|x265|hevc|bluray|webrip|web-dl|hdrip|brrip|aac)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    try {
      final encoded = Uri.encodeComponent(cleanQuery.isNotEmpty ? cleanQuery : query);
      final langSlug = lang == 'All' ? '' : '/sublanguageid-eng';
      final res = await http.get(
        Uri.parse('https://rest.opensubtitles.org/search$langSlug/query-$encoded'),
        headers: {'User-Agent': 'TemporaryUserAgent', 'X-User-Agent': 'TemporaryUserAgent'},
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        for (final item in data.take(25)) {
          final subUrl = item['SubDownloadLink'] as String?;
          if (subUrl == null) continue;
          final langName = item['LanguageName']?.toString() ?? 'Unknown';
          if (lang != 'All' && langName.toLowerCase() != lang.toLowerCase()) continue;
          results.add({
            'lang': '$langName (${item['SubFormat'] ?? 'srt'}) · ${item['MovieName'] ?? ''}',
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
    const card = Color(0xFF131B2E);
    const accent = Color(0xFF818CF8);
    showModalBottomSheet(
      context: context,
      backgroundColor: card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => DraggableScrollableSheet(
          initialChildSize: 0.78,
          maxChildSize: 0.94,
          minChildSize: 0.4,
          expand: false,
          builder: (_, sc) => ListView(
            controller: sc,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 16, 10),
                child: Text('Video Settings', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
              ),
              const Divider(color: Color(0xFF2D3748), height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.play_circle_outline, color: accent),
                title: const Text('Background play', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Keep audio playing when switching apps (applies on next video load)', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                value: _bgPlay,
                activeColor: accent,
                onChanged: (v) {
                  setState(() => _bgPlay = v);
                  _saveVideoPref('video_bg_play', v);
                  setDlg(() {});
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.nightlight_round, color: accent),
                title: const Text('Night Mode (Blue-light filter)', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Warm amber overlay reduces eye strain in dark rooms', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                value: _nightMode,
                activeColor: accent,
                onChanged: (v) {
                  setState(() => _nightMode = v);
                  _saveVideoPref('video_night_mode', v);
                  setDlg(() {});
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.flip, color: accent),
                title: const Text('Mirror flip horizontally', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: _mirrorVideo,
                activeColor: accent,
                onChanged: (v) {
                  setState(() => _mirrorVideo = v);
                  _saveVideoPref('video_mirror', v);
                  setDlg(() {});
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.loop, color: accent),
                title: const Text('Loop current video', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: _loopVideo,
                activeColor: accent,
                onChanged: (v) {
                  setState(() => _loopVideo = v);
                  _controller?.setLooping(v);
                  _saveVideoPref('video_loop', v);
                  setDlg(() {});
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.shuffle, color: accent),
                title: const Text('Shuffle playlist', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: _shufflePlaylist,
                activeColor: accent,
                onChanged: (v) {
                  setState(() => _shufflePlaylist = v);
                  _saveVideoPref('video_shuffle', v);
                  setDlg(() {});
                },
              ),
              _settingsTile(
                Icons.repeat_one,
                _abPointA == null
                    ? 'AB Repeat: Off'
                    : _abPointB == null
                        ? 'AB Repeat: A=${_fmt(_abPointA!)} (Tap to set B)'
                        : 'AB Repeat: ${_fmt(_abPointA!)} – ${_fmt(_abPointB!)}',
                () {
                  final pos = _controller?.value.position ?? Duration.zero;
                  setState(() {
                    if (_abPointA == null) {
                      _abPointA = pos;
                      _abPointB = null;
                      _toast('Loop Point A set at ${_fmt(pos)}');
                    } else if (_abPointB == null) {
                      if (pos > _abPointA!) {
                        _abPointB = pos;
                        _controller?.seekTo(_abPointA!);
                        _toast('AB Repeat active');
                      } else {
                        _toast('Point B must be after Point A');
                      }
                    } else {
                      _abPointA = null;
                      _abPointB = null;
                      _toast('AB Repeat cleared');
                    }
                  });
                  setDlg(() {});
                },
              ),
              _settingsTile(
                Icons.fast_forward_outlined,
                'Double-tap skip interval: ${_skipSeconds}s',
                () {
                  final opts = [5, 10, 15, 30];
                  final next = opts[(opts.indexOf(_skipSeconds) + 1) % opts.length];
                  setState(() => _skipSeconds = next);
                  _saveVideoPref('video_skip_seconds', next);
                  setDlg(() {});
                },
              ),
              _settingsTile(
                Icons.timer_outlined,
                _sleepTimerMinutes > 0 ? 'Sleep timer: ${_sleepTimerMinutes}m' : 'Sleep timer: Off',
                () {
                  final opts = [0, 10, 15, 30, 60, 90];
                  final next = opts[(opts.indexOf(_sleepTimerMinutes) + 1) % opts.length];
                  _sleepTimer?.cancel();
                  setState(() => _sleepTimerMinutes = next);
                  if (next > 0) {
                    _sleepTimer = Timer(Duration(minutes: next), () {
                      if (mounted) {
                        _controller?.pause();
                        setState(() => _sleepTimerMinutes = 0);
                        _toast('Sleep timer paused playback');
                      }
                    });
                  }
                  setDlg(() {});
                },
              ),
              _settingsTile(
                Icons.visibility_outlined,
                'Auto-hide controls: ${_autoHideSeconds}s',
                () {
                  final opts = [2, 4, 6, 10];
                  final next = opts[(opts.indexOf(_autoHideSeconds) + 1) % opts.length];
                  setState(() => _autoHideSeconds = next);
                  _saveVideoPref('video_auto_hide_sec', next);
                  _startAutoHide();
                  setDlg(() {});
                },
              ),
              _settingsTile(
                Icons.aspect_ratio_rounded,
                'Aspect ratio: ${_modeLabels[_modes.indexOf(_dimensionMode)]}',
                () {
                  _cycleDim();
                  setDlg(() {});
                },
              ),
              _settingsTile(
                Icons.memory_rounded,
                'Video decoder: ${_hwDecoder ? 'Hardware (MediaCodec)' : 'Compatibility Mode'}',
                () {
                  setState(() => _hwDecoder = !_hwDecoder);
                  _saveVideoPref('video_hw_decoder', _hwDecoder);
                  _toast('Decoder preference updated');
                  setDlg(() {});
                },
              ),
              const Divider(color: Color(0xFF2D3748), height: 16),
              _settingsTile(Icons.info_outline, 'Video properties', () { Navigator.pop(ctx); _showVideoInfo(); }),
              _settingsTile(Icons.share_outlined, 'Share video', () { Navigator.pop(ctx); _shareVideo(); }),
              _settingsTile(Icons.delete_outline, 'Delete video', () { Navigator.pop(ctx); _deleteVideo(); }),
              const SizedBox(height: 24),
            ],
          ),
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
    MakawToast.info(context, msg);
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
class VideoPlayerWidget extends ConsumerStatefulWidget {
  final void Function()? onOpenMusic;
  final void Function()? onHome;
  const VideoPlayerWidget({super.key, this.onOpenMusic, this.onHome});
  @override
  ConsumerState<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends ConsumerState<VideoPlayerWidget> {
  VideoPlayerService? _boundService;
  VideoPlayerService get _service => _boundService ?? ref.read(videoPlayerServiceProvider) ?? VideoPlayerService();
  String _page = 'home';
  String _homeTab = 'videos';
  String _browseSection = 'favourites';
  String _searchQuery = '';
  int _playIndex = 0;
  String _displayMode = 'grid';
  String _sortMode = 'name_az';
  bool _selectMode = false;
  final Set<String> _selectedVideoPaths = {};
  List<String>? _customPlayQueue;
  final Map<String, String> _thumbCache = {};

  void _toggleSelectVideo(VideoFileInfo v) {
    setState(() {
      if (_selectedVideoPaths.contains(v.filePath)) {
        _selectedVideoPaths.remove(v.filePath);
        if (_selectedVideoPaths.isEmpty) _selectMode = false;
      } else {
        _selectMode = true;
        _selectedVideoPaths.add(v.filePath);
      }
    });
  }

  void _exitVideoSelectMode() => setState(() {
    _selectMode = false;
    _selectedVideoPaths.clear();
  });
  final _searchCtrl = TextEditingController();
  final _kDark = const Color(0xFF0F0F1A);
  final _kAccent = const Color(0xFF818CF8);
  final _kCard = const Color(0xFF1A1A2E);
  final _kMuted = const Color(0xFF666680);

  List<VideoFileInfo> get _sortedVideos {
    final list = List<VideoFileInfo>.from(_service.allVideos);
    switch (_sortMode) {
      case 'name_az':
        list.sort((a, b) => naturalCompare(a.fileName, b.fileName));
        break;
      case 'name_za':
        list.sort((a, b) => naturalCompare(b.fileName, a.fileName));
        break;
      case 'date_new':
        list.sort((a, b) => (b.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0)));
        break;
      case 'date_old':
        list.sort((a, b) => (a.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(b.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0)));
        break;
      case 'size_largest':
        list.sort((a, b) => b.fileSize.compareTo(a.fileSize));
        break;
      case 'size_smallest':
        list.sort((a, b) => a.fileSize.compareTo(b.fileSize));
        break;
      default:
        list.sort((a, b) => naturalCompare(a.fileName, b.fileName));
        break;
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _boundService = ref.read(videoPlayerServiceProvider) ?? VideoPlayerService();
    _service.addListener(_onServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _service.scanAllVideos(force: false);
    });
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
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
    _service.removeListener(_onServiceChanged);
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectMode) {
          _exitVideoSelectMode();
          return;
        }
        if (_page != 'home') {
          setState(() => _page = 'home');
          return;
        }
        if (widget.onHome != null) {
          widget.onHome!();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: _kDark,
        appBar: _buildAppBar(),
        body: SafeArea(child: _buildBody()),
        floatingActionButton: _page == 'home' && _homeTab == 'videos' && _service.allVideos.isNotEmpty
            ? Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 60),
                child: FloatingActionButton(
                  backgroundColor: _kAccent,
                  onPressed: () => setState(() { _page = 'player'; }),
                  child: const Icon(Icons.play_arrow, color: Colors.black),
                ),
              )
            : null,
      ),
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
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (widget.onHome != null) {
                  widget.onHome!();
                } else {
                  Navigator.of(context).pop();
                }
              },
            )
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
      onRefresh: () => _service.scanAllVideos(),
      color: const Color(0xFF818CF8),
      child: _buildHomePage(),
    );
  }

  Widget _buildFullPlayer() {
    final queue = _customPlayQueue;
    if (queue != null && queue.isNotEmpty) {
      return DirectVideoPlayer(
        filePath: queue.first,
        title: queue.first.split('\\').last.split('/').last,
        playlist: queue,
        initialIndex: 0,
        onClose: () => setState(() {
          _customPlayQueue = null;
          _page = 'home';
        }),
      );
    }
    return DirectVideoPlayer(
      filePath: _service.allVideos[_playIndex].filePath,
      title: _service.allVideos[_playIndex].fileName,
      playlist: _service.allVideos.map((v) => v.filePath).toList(),
      initialIndex: _playIndex,
      onClose: () => setState(() => _page = 'home'),
    );
  }

  Widget _buildVideoToolbar() {
    if (_selectMode) return _buildVideoSelectionBar();
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
          Text('${_service.allVideos.length} videos', style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => setState(() { _page = 'search'; _searchCtrl.clear(); _searchQuery = ''; }),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) {
              if (v == 'refresh') _service.scanAllVideos();
              else if (v == 'select') setState(() => _selectMode = true);
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

  Widget _buildVideoSelectionBar() {
    final selected = _sortedVideos.where((v) => _selectedVideoPaths.contains(v.filePath)).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            onPressed: _exitVideoSelectMode,
          ),
          Text('${selected.length} selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.select_all_rounded, color: Colors.white70, size: 20),
            tooltip: 'Select All',
            onPressed: () => setState(() => _selectedVideoPaths.addAll(_sortedVideos.map((v) => v.filePath))),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF38BDF8), size: 24),
            tooltip: 'Play Selected Sequence',
            onPressed: selected.isEmpty
                ? null
                : () {
                    final paths = selected.map((v) => v.filePath).toList();
                    setState(() {
                      _customPlayQueue = paths;
                      _selectMode = false;
                      _selectedVideoPaths.clear();
                      _page = 'player';
                    });
                  },
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded, color: Color(0xFF818CF8), size: 22),
            tooltip: 'Add to Playlist',
            onPressed: selected.isEmpty ? null : () => _addBatchToPlaylistSheet(selected),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music_rounded, color: Color(0xFF34D399), size: 21),
            tooltip: 'Add to Play Queue',
            onPressed: selected.isEmpty
                ? null
                : () {
                    _service.addToQueue(selected);
                    _exitVideoSelectMode();
                    _toast('Added ${selected.length} videos to queue');
                  },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 20),
            tooltip: 'Share Selected',
            onPressed: selected.isEmpty ? null : () => Share.shareXFiles(selected.map((v) => XFile(v.filePath)).toList()),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 21),
            tooltip: 'Delete Selected',
            onPressed: selected.isEmpty ? null : () => _deleteBatchDialog(selected),
          ),
        ],
      ),
    );
  }

  void _addBatchToPlaylistSheet(List<VideoFileInfo> videos) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Add ${videos.length} Videos to Playlist', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final pl in _service.playlists)
              ListTile(
                leading: const Icon(Icons.playlist_play, color: Color(0xFF818CF8)),
                title: Text(pl['name'], style: const TextStyle(color: Colors.white)),
                onTap: () {
                  for (final v in videos) {
                    _service.addToPlaylist(pl['name'], v.id);
                  }
                  Navigator.pop(ctx);
                  _exitVideoSelectMode();
                  _toast('Added ${videos.length} videos to ${pl['name']}');
                },
              ),
            ListTile(
              leading: const Icon(Icons.add, color: Color(0xFF818CF8)),
              title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _createPlaylistDialog(videoId: videos.first.id);
                _exitVideoSelectMode();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _deleteBatchDialog(List<VideoFileInfo> videos) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: Text('Delete ${videos.length} video${videos.length == 1 ? '' : 's'}?', style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text('This permanently removes the selected files from storage.', style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () {
              for (final v in videos) {
                try {
                  File(v.filePath).deleteSync();
                } catch (_) {}
              }
              _exitVideoSelectMode();
              _service.scanAllVideos(force: true);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
    if (_service.allVideos.isEmpty) {
      return RefreshIndicator(
        color: _kAccent,
        backgroundColor: _kCard,
        onRefresh: () async => await _service.scanAllVideos(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 300,
              child: Center(
                child: Text(
                  _service.isScanning ? 'Scanning for videos...' : 'No videos found',
                  style: const TextStyle(color: Color(0xFF666680)),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _kAccent,
      backgroundColor: _kCard,
      onRefresh: () async => await _service.scanAllVideos(force: true),
      child: _displayMode == 'grid'
          ? _buildGridVideos()
          : _displayMode == 'list'
              ? _buildListVideos()
              : _buildDetailsVideos(),
    );
  }

  Widget _buildGridVideos() {
    final videos = _sortedVideos;
    return LayoutBuilder(builder: (context, constraints) {
      final cols = _videoColumns(constraints.maxWidth);
      return GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.85,
        ),
        itemCount: videos.length,
        itemBuilder: (_, i) => _gridCard(videos[i], i),
      );
    });
  }

  /// Column count for the responsive video grid. Wider / landscape surfaces get
  /// more columns so tiles stay a reasonable size instead of stretching to the
  /// full panel width.
  int _videoColumns(double width) {
    if (width >= 1600) return 6;
    if (width >= 1280) return 5;
    if (width >= 1000) return 4;
    if (width >= 720) return 3;
    if (width >= 480) return 2;
    return 2;
  }

  Widget _gridCard(VideoFileInfo v, int index) {
    final isCurrent = _service.activeVideoPath == v.filePath;
    final isPlaying = isCurrent && _service.isVideoPlaying;
    final isNew = _service.isNewFile(v.filePath);
    final progress = _service.resumeProgress(v.filePath);
    final selected = _selectedVideoPaths.contains(v.filePath);

    return GestureDetector(
      onLongPress: () => _toggleSelectVideo(v),
      onTap: () {
        if (_selectMode) {
          _toggleSelectVideo(v);
          return;
        }
        final actualIdx = _service.allVideos.indexOf(v);
        setState(() { _playIndex = actualIdx >= 0 ? actualIdx : index; _page = 'player'; });
      },
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF38BDF8).withValues(alpha: 0.16)
              : (isCurrent ? _kAccent.withValues(alpha: 0.12) : _kCard),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFF38BDF8)
                : (isCurrent ? _kAccent : const Color(0xFF2D3748)),
            width: (selected || isCurrent) ? 2 : 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ThumbnailView(filePath: v.filePath, thumbCache: _thumbCache),
                  if (isCurrent)
                    Container(
                      color: Colors.black38,
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isPlaying ? Icons.equalizer_rounded : Icons.pause_rounded, color: Colors.black, size: 13),
                            const SizedBox(width: 3),
                            Text(isPlaying ? 'PLAYING' : 'PAUSED', style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  if (isNew)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 2)],
                        ),
                        child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ),
                    ),
                  if (_selectMode)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(
                        selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: selected ? const Color(0xFF38BDF8) : Colors.white70,
                        size: 21,
                      ),
                    )
                  else
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
                    Positioned(right: 4, bottom: progress > 0 ? 8 : 4, child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                      child: Text(_fmtSize(v.fileSize), style: const TextStyle(color: Colors.white70, fontSize: 9)),
                    )),
                  if (progress > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3.5,
                        color: _kAccent,
                        backgroundColor: Colors.black38,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Text(v.fileName, style: TextStyle(color: isCurrent ? _kAccent : Colors.white, fontSize: 12, fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListVideos() {
    final videos = _sortedVideos;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: videos.length,
      itemBuilder: (_, i) {
        final v = videos[i];
        final isCurrent = _service.activeVideoPath == v.filePath;
        final isPlaying = isCurrent && _service.isVideoPlaying;
        final isNew = _service.isNewFile(v.filePath);
        final progress = _service.resumeProgress(v.filePath);
        final selected = _selectedVideoPaths.contains(v.filePath);

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF38BDF8).withValues(alpha: 0.16)
                : (isCurrent ? _kAccent.withValues(alpha: 0.12) : _kCard),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF38BDF8)
                  : (isCurrent ? _kAccent : const Color(0xFF2D3748)),
              width: (selected || isCurrent) ? 1.5 : 0.5,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            onLongPress: () => _toggleSelectVideo(v),
            leading: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(width: 52, height: 52, child: _ThumbnailView(filePath: v.filePath, thumbCache: _thumbCache)),
                ),
                if (isCurrent)
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                    child: Icon(isPlaying ? Icons.equalizer_rounded : Icons.play_arrow_rounded, color: _kAccent, size: 24),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    v.fileName,
                    style: TextStyle(color: isCurrent ? _kAccent : Colors.white, fontSize: 14, fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isNew) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                    ),
                    child: const Text('NEW', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${v.folder}  •  ${_fmtSize(v.fileSize)}${progress > 0 ? '  •  ${(progress * 100).toInt()}% watched' : ''}',
                  style: TextStyle(color: isCurrent ? _kAccent.withValues(alpha: 0.8) : _kMuted, fontSize: 11),
                ),
                if (progress > 0) ...[
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2.5,
                      color: _kAccent,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ],
              ],
            ),
            trailing: _selectMode
                ? Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? const Color(0xFF38BDF8) : Colors.white54,
                  )
                : PopupMenuButton<String>(
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
            onTap: () {
              if (_selectMode) {
                _toggleSelectVideo(v);
                return;
              }
              final actualIdx = _service.allVideos.indexOf(v);
              setState(() { _playIndex = actualIdx >= 0 ? actualIdx : i; _page = 'player'; });
            },
          ),
        );
      },
    );
  }

  Widget _buildDetailsVideos() {
    final videos = _sortedVideos;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: videos.length,
      itemBuilder: (_, i) {
        final v = videos[i];
        final isCurrent = _service.activeVideoPath == v.filePath;
        final isPlaying = isCurrent && _service.isVideoPlaying;
        final isNew = _service.isNewFile(v.filePath);
        final progress = _service.resumeProgress(v.filePath);
        final selected = _selectedVideoPaths.contains(v.filePath);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF38BDF8).withValues(alpha: 0.16)
                : (isCurrent ? _kAccent.withValues(alpha: 0.12) : _kCard),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF38BDF8)
                  : (isCurrent ? _kAccent : const Color(0xFF2D3748)),
              width: (selected || isCurrent) ? 1.5 : 0.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onLongPress: () => _toggleSelectVideo(v),
            onTap: () {
              if (_selectMode) {
                _toggleSelectVideo(v);
                return;
              }
              final actualIdx = _service.allVideos.indexOf(v);
              setState(() { _playIndex = actualIdx >= 0 ? actualIdx : i; _page = 'player'; });
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(width: 80, height: 60, child: _ThumbnailView(filePath: v.filePath, thumbCache: _thumbCache)),
                      ),
                      if (isCurrent)
                        Container(
                          width: 80,
                          height: 60,
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                          child: Icon(isPlaying ? Icons.equalizer_rounded : Icons.play_arrow_rounded, color: _kAccent, size: 28),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                v.fileName,
                                style: TextStyle(color: isCurrent ? _kAccent : Colors.white, fontSize: 14, fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isNew) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                                ),
                                child: const Text('NEW', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(v.folder, style: TextStyle(color: isCurrent ? _kAccent.withValues(alpha: 0.8) : _kMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 1),
                        Row(children: [
                          Text(_fmtSize(v.fileSize), style: TextStyle(color: _kMuted, fontSize: 10)),
                          if (progress > 0) ...[
                            const Text('  •  ', style: TextStyle(color: Color(0xFF444455), fontSize: 10)),
                            Text('${(progress * 100).toInt()}% watched', style: TextStyle(color: _kAccent, fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                          if (v.dateTime != null) ...[
                            const Text('  •  ', style: TextStyle(color: Color(0xFF444455), fontSize: 10)),
                            Text(v.dateTime!.toString().split('.')[0], style: TextStyle(color: _kMuted, fontSize: 10)),
                          ],
                        ]),
                        if (progress > 0) ...[
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 2.5,
                              color: _kAccent,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ],
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
    final idx = _service.allVideos.indexOf(v);
    if (opt == 'play') setState(() { _playIndex = idx; _page = 'player'; });
    else if (opt == 'play_start') setState(() { _playIndex = idx; _page = 'player'; });
    else if (opt == 'play_all') setState(() { _playIndex = 0; _page = 'player'; });
    else if (opt == 'favorite') { _service.toggleFavorite(v.id); _toast(_service.isFavorite(v.id) ? 'Added to favourites' : 'Removed from favourites'); }
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
          TextButton(onPressed: () { try { File(v.filePath).deleteSync(); _service.scanAllVideos(); } catch (_) {} Navigator.pop(ctx); }, child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
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
    final pls = _service.playlists;
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
              onPressed: () { _service.deletePlaylist(pl['name']); _toast('Playlist deleted'); },
            ),
          ),
        );
      },
    );
  }

  // ─── Search Page ──────────────────────────────────────────────────────────
  Widget _buildSearchPage() {
    final filtered = _searchQuery.isEmpty ? _service.allVideos
        : _service.allVideos.where((v) => v.fileName.toLowerCase().contains(_searchQuery)).toList();
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
            onTap: () => setState(() { _playIndex = _service.allVideos.indexOf(v); _page = 'player'; }),
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
    final favFolders = _service.favoriteFolders.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
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
                if (opt == 'play') { _service.setQueue(entry.value, 0); _openFolderSheet(entry.key, entry.value); }
                else if (opt == 'queue') { _service.addToQueue(entry.value); _toast('Added ${entry.value.length} videos to play queue'); }
                else if (opt == 'remove_fav') { _service.toggleFavoriteFolder(entry.key); _toast('Removed from favourites'); }
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
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20), constraints: const BoxConstraints(minWidth: 40, minHeight: 40), onPressed: () {
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
    if (PlatformPaths.isDesktop) {
      final h = PlatformPaths.home();
      final result = <Map<String, String>>[];
      for (final dir in [PlatformPaths.home(), PlatformPaths.defaultDownloadsHint()]) {
        if (dir.isNotEmpty && await Directory(dir).exists()) {
          result.add({'path': dir, 'label': dir == h ? 'Home' : 'Downloads'});
        }
      }
      return result;
    }
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
                      if (opt == 'scan') { _service.scanAllVideos(); _toast('Scanning...'); }
                      else if (opt == 'fav') { _service.toggleFavoriteFolder(_folderName(d.path)); _toast('Toggled favourite'); }
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
            final v = _service.allVideos.where((v) => v.filePath == f.path).firstOrNull;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                dense: true,
                leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.videocam, color: Color(0xFF818CF8), size: 18)),
                title: Text(_folderName(f.path), style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                onTap: () { if (v != null) { final idx = _service.allVideos.indexOf(v); setState(() { _playIndex = idx; _page = 'player'; }); } },
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
            Expanded(child: LayoutBuilder(
              builder: (_, constraints) => GridView.builder(
              controller: sc,
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _videoColumns(constraints.maxWidth), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.75,
              ),
              itemCount: videos.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () { final idx = _service.allVideos.indexOf(videos[i]); Navigator.pop(context); setState(() { _playIndex = idx; _page = 'player'; }); },
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
            ))),
          ],
        ),
      ),
    );
  }

  // ─── Playlists Page ───────────────────────────────────────────────────────
  Widget _buildPlaylistsPage() {
    final pls = _service.playlists;
    return Stack(
      children: [
        pls.isEmpty
            ? const Center(child: Text('No playlists', style: TextStyle(color: Color(0xFF666680))))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: pls.length,
                itemBuilder: (_, i) {
                  final pl = pls[i];
                  final videos = _service.getPlaylistVideos(pl['name']);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const Icon(Icons.playlist_play, color: Color(0xFF818CF8)),
                      title: Text(pl['name'], style: const TextStyle(color: Colors.white)),
                      subtitle: Text('${videos.length} videos', style: TextStyle(color: _kMuted, fontSize: 12)),
                      onTap: videos.isNotEmpty ? () => _openPlaylistVideos(pl['name'], videos) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () { _service.deletePlaylist(pl['name']); _toast('Playlist deleted'); },
                      ),
                    ),
                  );
                },
              ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.small(
            backgroundColor: _kAccent,
            onPressed: () => _createPlaylistDialog(),
            child: const Icon(Icons.add, color: Colors.black),
          ),
        ),
      ],
    );
  }

  void _createPlaylistDialog({int? videoId}) {
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
          TextButton(onPressed: () {
            final name = ctrl.text.trim();
            if (name.isNotEmpty) {
              _service.createPlaylist(name);
              if (videoId != null && videoId > 0) {
                _service.addToPlaylist(name, videoId);
                _toast('Created "$name" and added video');
              } else {
                _toast('Playlist created');
              }
            }
            Navigator.pop(ctx);
          }, child: const Text('Create', style: TextStyle(color: Color(0xFF818CF8)))),
        ],
      ),
    );
  }

  void _openPlaylistVideos(String plName, List<VideoFileInfo> videos) {
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
                Expanded(child: Text(plName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                TextButton.icon(onPressed: () { final first = videos.isNotEmpty ? _service.allVideos.indexOf(videos[0]) : 0; Navigator.pop(context); setState(() { _playIndex = first; _page = 'player'; }); }, icon: const Icon(Icons.play_arrow, size: 18, color: Color(0xFF818CF8)), label: const Text('Play All', style: TextStyle(color: Color(0xFF818CF8)))),
              ]),
            ),
            Expanded(child: ListView.builder(
              controller: sc, itemCount: videos.length,
              itemBuilder: (_, i) => ListTile(
                leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: Container(width: 44, height: 44, color: Colors.black26, child: const Icon(Icons.videocam, color: Color(0xFF818CF8), size: 20))),
                title: Text(videos[i].fileName, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                  tooltip: 'Remove from playlist',
                  onPressed: () {
                    _service.removeFromPlaylist(plName, videos[i].id);
                    _toast('Removed from $plName');
                    Navigator.pop(context);
                  },
                ),
                onTap: () { final idx = _service.allVideos.indexOf(videos[i]); Navigator.pop(context); setState(() { _playIndex = idx; _page = 'player'; }); },
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
            final pl = _service.playlists[i];
            return ListTile(
              leading: const Icon(Icons.playlist_play, color: Color(0xFF818CF8)),
              title: Text(pl['name'], style: const TextStyle(color: Colors.white)),
              onTap: () { _service.addToPlaylist(pl['name'], v.id); Navigator.pop(context); _toast('Added to ${pl['name']}'); },
            );
          }, childCount: _service.playlists.length)),
          SliverToBoxAdapter(child: ListTile(
            leading: const Icon(Icons.add, color: Color(0xFF818CF8)),
            title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _createPlaylistDialog(videoId: v.id); },
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
    MakawToast.info(context, msg);
  }
}
