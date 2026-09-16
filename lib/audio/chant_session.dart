import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'chant_queue.dart';

// Listening, as opposed to reading: the phone in a pocket, the screen off,
// one verse after another, with the controls on the lock screen.
//
// This is the part the reader cannot do. The reader needs its screen, turns
// its own pages, and stops when the app goes to the background — which is
// right for reading along and useless for a walk.
//
// One file at a time rather than a gapless playlist. A recitation wants the
// breath between verses, and playing them one by one means each is fetched
// and checked just before it is needed rather than all at once.

/// Fetches a verse's recording, verified and cached.
typedef ChantFetch = Future<File?> Function(ChantItem item);

class ChantSession extends BaseAudioHandler with SeekHandler {
  ChantSession({required this.fetch, AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    _player.playbackEventStream.listen(_broadcast, onError: (_) {});
    _player.processingStateStream.listen((state) {
      // The end of a verse is the cue for the next one. Only when it was
      // played to the end: a stop is not a finish.
      if (state == ProcessingState.completed) unawaited(skipToNext());
    });
  }

  /// How a verse's recording is obtained: downloaded, checked and cached.
  final ChantFetch fetch;
  final AudioPlayer _player;

  var _queue = ChantQueue.empty;

  /// The passages being listened to. Named apart from the handler's own
  /// `queue`, which is the media items the system shows.
  ChantQueue get listening => _queue;

  /// Bumped whenever the listener moves, so a fetch that was already running
  /// for an earlier verse cannot start playing after they have moved on.
  var _token = 0;

  /// Starts a session at [queue]'s current position.
  Future<void> start(ChantQueue queue) async {
    _queue = queue;
    await _load(play: true);
  }

  Future<void> _load({required bool play}) async {
    final item = _queue.current;
    if (item == null) return;
    final token = ++_token;
    mediaItem.add(_mediaItem(item));
    _publishQueue();

    final file = await fetch(item);
    if (token != _token) return;
    if (file == null) {
      // Nothing to play for this verse — skip rather than stall. A queue
      // where one recording is missing is still worth listening to.
      if (_queue.hasNext) return skipToNext();
      return stop();
    }
    try {
      await _player.setFilePath(file.path);
      if (token != _token) return;
      if (play) await _player.play();
    } on Object {
      if (token == _token && _queue.hasNext) await skipToNext();
    }
  }

  MediaItem _mediaItem(ChantItem item) => MediaItem(
    id: item.ref,
    title: item.title,
    album: item.subtitle,
    artist: 'Vāgdhenu',
    duration: Duration(milliseconds: item.durationMs),
  );

  void _publishQueue() =>
      queueTitle.add(_queue.current?.subtitle ?? '');

  void _broadcast(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _queue.index,
      ),
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (!_queue.hasNext) return stop();
    _queue = _queue.next;
    await _load(play: true);
  }

  @override
  Future<void> skipToPrevious() async {
    // Within the first few seconds, back means the verse before; later it
    // means the start of this one, which is what every player does.
    if (_player.position > const Duration(seconds: 3)) {
      return _player.seek(Duration.zero);
    }
    if (!_queue.hasPrevious) return _player.seek(Duration.zero);
    _queue = _queue.previous;
    await _load(play: true);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _queue = _queue.at(index);
    await _load(play: true);
  }

  @override
  Future<void> stop() async {
    _token++;
    await _player.stop();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
    await super.stop();
  }
}
