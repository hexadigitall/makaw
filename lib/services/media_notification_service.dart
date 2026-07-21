import 'package:flutter/services.dart';

class MediaNotificationService {
  static const _channel = MethodChannel('com.example.makaw_mobile/media');
  static final MediaNotificationService _instance = MediaNotificationService._();
  static MediaNotificationService get instance => _instance;
  MediaNotificationService._();

  VoidCallback? onPlay;
  VoidCallback? onPause;
  VoidCallback? onNext;
  VoidCallback? onPrevious;
  void Function(Duration position)? onSeek;

  bool _initialized = false;
  String _channelImportance = 'unknown';

  String get channelImportance => _channelImportance;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      final imp = await _channel.invokeMethod<String>('getNotificationChannelImportance');
      _channelImportance = imp ?? 'unknown';
    } catch (_) {
      _channelImportance = 'error';
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onMediaAction') {
      final action = call.arguments['action'] as String?;
      final position = (call.arguments['position'] as num?)?.toInt() ?? 0;
      switch (action) {
        case 'play':
          onPlay?.call();
        case 'pause':
          onPause?.call();
        case 'next':
          onNext?.call();
        case 'prev':
          onPrevious?.call();
        case 'seek':
          onSeek?.call(Duration(milliseconds: position));
      }
    }
  }

  Future<void> show({
    required String title,
    required String artist,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) async {
    try {
      await _channel.invokeMethod('startForeground', {
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
      });
    } catch (_) {}
  }

  Future<void> update({
    required String title,
    required String artist,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) async {
    try {
      await _channel.invokeMethod('updateNotification', {
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
      });
    } catch (_) {}
  }

  Future<void> syncPlaybackState({
    required bool isPlaying,
    required Duration position,
  }) async {
    try {
      await _channel.invokeMethod('updatePlaybackState', {
        'isPlaying': isPlaying,
        'position': position.inMilliseconds,
      });
    } catch (_) {}
  }

  Future<void> hide() async {
    try {
      await _channel.invokeMethod('stopForeground');
    } catch (_) {}
  }
}
