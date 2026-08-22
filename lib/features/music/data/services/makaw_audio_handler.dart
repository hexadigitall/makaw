import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/entities.dart';

class MakawAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);

  List<SongInfo> _masterQueue = [];
  List<SongInfo> get masterQueue => _masterQueue;
  int _masterIndex = -1;
  int get masterIndex => _masterIndex;

  bool _isShuffled = false;
  bool get isShuffled => _isShuffled;
  List<SongInfo>? _savedQueue;

  MakawAudioHandler() {
    _initPlayer();
  }

  AudioPlayer get player => _player;

  void _initPlayer() {
    _player.playbackEventStream.listen((event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ));
    });

    _player.currentIndexStream.listen((index) {
      if (index != null && queue.value.isNotEmpty && index < queue.value.length) {
        _masterIndex = index;
        mediaItem.add(queue.value[index]);
      }
    });
  }

  MediaItem _songToMediaItem(SongInfo song) {
    return MediaItem(
      id: song.filePath,
      title: song.displayTitle,
      artist: song.displayArtist,
      album: song.displayAlbum,
      duration: Duration(milliseconds: song.duration),
      extras: {
        'filePath': song.filePath,
        'songId': song.id,
      },
    );
  }

  Future<void> loadQueue(List<SongInfo> songs, {int initialIndex = 0, bool shuffle = false}) async {
    _masterQueue = List.from(songs);

    if (shuffle && songs.isNotEmpty) {
      final current = songs[initialIndex];
      final shuffled = List<SongInfo>.from(songs)..shuffle();
      if (!shuffled.contains(current)) {
        shuffled.removeLast();
        shuffled.insert(0, current);
      } else {
        shuffled.remove(current);
        shuffled.insert(0, current);
      }
      _masterQueue = shuffled;
      _masterIndex = 0;
      _isShuffled = true;
    } else {
      _masterIndex = initialIndex;
      _isShuffled = false;
    }

    final items = _masterQueue.map(_songToMediaItem).toList();
    queue.add(items);

    final audioSources = items.map((item) {
      return AudioSource.uri(
        Uri.parse('file://${item.extras!['filePath']}'),
        tag: item,
      );
    }).toList();

    _playlist.clear();
    await _playlist.addAll(audioSources);
    await _player.setAudioSource(_playlist, initialIndex: _masterIndex);
    _player.play();

    mediaItem.add(items[_masterIndex]);
  }

  SongInfo? get currentSong =>
      _masterIndex >= 0 && _masterIndex < _masterQueue.length
          ? _masterQueue[_masterIndex]
          : null;

  List<SongInfo> get queueList => _masterQueue;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_masterIndex < _masterQueue.length - 1) {
      _masterIndex++;
      await _player.seekToNext();
      mediaItem.add(queue.value[_masterIndex]);
    } else if (_player.loopMode == LoopMode.all) {
      _masterIndex = 0;
      await _player.seek(Duration.zero);
      mediaItem.add(queue.value[0]);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else if (_masterIndex > 0) {
      _masterIndex--;
      await _player.seekToPrevious();
      mediaItem.add(queue.value[_masterIndex]);
    } else if (_player.loopMode == LoopMode.all) {
      _masterIndex = _masterQueue.length - 1;
      await _player.seek(Duration.zero);
      await _player.setAudioSource(_playlist, initialIndex: _masterIndex);
      _player.play();
      mediaItem.add(queue.value[_masterIndex]);
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    if (enabled && !_isShuffled) {
      _toggleShuffleInternal();
    } else if (!enabled && _isShuffled) {
      _toggleShuffleInternal();
    }
  }

  void _toggleShuffleInternal() {
    final cur = currentSong;
    if (_isShuffled) {
      if (_savedQueue != null) {
        _masterQueue = List.from(_savedQueue!);
        _savedQueue = null;
      }
      if (cur != null) {
        _masterIndex = _masterQueue.indexWhere((s) => s.id == cur.id);
      }
      _isShuffled = false;
    } else {
      _savedQueue = List.from(_masterQueue);
      if (cur != null) {
        _masterQueue.removeWhere((s) => s.id == cur.id);
        _masterQueue.shuffle();
        _masterQueue.insert(0, cur);
        _masterIndex = 0;
      } else {
        _masterQueue.shuffle();
        _masterIndex = 0;
      }
      _isShuffled = true;
    }

    final items = _masterQueue.map(_songToMediaItem).toList();
    queue.add(items);
  }

  void toggleShuffle() {
    _toggleShuffleInternal();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = {
      AudioServiceRepeatMode.none: LoopMode.off,
      AudioServiceRepeatMode.one: LoopMode.one,
      AudioServiceRepeatMode.all: LoopMode.all,
      AudioServiceRepeatMode.group: LoopMode.all,
    }[repeatMode]!;
    await _player.setLoopMode(loopMode);
  }

  Future<void> setLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
  }

  LoopMode get loopMode => _player.loopMode;

  void addToQueue(SongInfo song) {
    _masterQueue.add(song);
    final item = _songToMediaItem(song);
    final currentItems = List<MediaItem>.from(queue.value);
    currentItems.add(item);
    queue.add(currentItems);
    _playlist.add(AudioSource.uri(
      Uri.parse('file://${song.filePath}'),
      tag: item,
    ));
  }

  void playNext(SongInfo song) {
    final insertAt = _masterIndex + 1;
    _masterQueue.insert(insertAt, song);
    final item = _songToMediaItem(song);
    final currentItems = List<MediaItem>.from(queue.value);
    currentItems.insert(insertAt, item);
    queue.add(currentItems);
    _playlist.insert(insertAt, AudioSource.uri(
      Uri.parse('file://${song.filePath}'),
      tag: item,
    ));
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _masterQueue.length && index != _masterIndex) {
      _masterQueue.removeAt(index);
      final currentItems = List<MediaItem>.from(queue.value);
      currentItems.removeAt(index);
      queue.add(currentItems);
      _playlist.removeAt(index);
      if (index < _masterIndex) _masterIndex--;
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = _masterQueue.removeAt(oldIndex);
    _masterQueue.insert(newIndex, item);

    if (oldIndex == _masterIndex) {
      _masterIndex = newIndex;
    } else if (oldIndex < _masterIndex && newIndex >= _masterIndex) {
      _masterIndex--;
    } else if (oldIndex > _masterIndex && newIndex <= _masterIndex) {
      _masterIndex++;
    }

    final currentItems = List<MediaItem>.from(queue.value);
    final movedItem = currentItems.removeAt(oldIndex);
    currentItems.insert(newIndex, movedItem);
    queue.add(currentItems);
  }

  void clearQueue() {
    _masterQueue.clear();
    _masterIndex = -1;
    _playlist.clear();
    queue.add([]);
    mediaItem.add(null);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  Future<void> disposeHandler() async {
    await _player.dispose();
  }
}
