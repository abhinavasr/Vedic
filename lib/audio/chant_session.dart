import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

// The notification and the lock screen.
//
// This handler plays nothing itself, which is the unusual part. A verse is a
// recording followed by two pieces of speech synthesised on the phone, and
// synthesised speech does not belong to a media player — so the listening
// screen keeps the playing loop, and this keeps the notification, the lock
// screen and the headset buttons pointed at it.
//
// What it does own is the foreground service, and that is why it exists.
// Without one Android stops the app seconds after the screen goes off, which
// is precisely the situation listening is for.

/// What the notification's buttons do. Implemented by whoever is playing.
abstract interface class ListenControls {
  Future<void> resume();
  Future<void> halt();
  Future<void> forward();
  Future<void> back();
}

class ChantSession extends BaseAudioHandler {
  /// The app's, created by [AudioService.init]. Null where the platform has
  /// no media session, and nothing above here depends on there being one.
  static ChantSession? instance;

  /// Whoever is listening at the moment. Null when nobody is.
  ListenControls? controls;

  static const _permissions = MethodChannel('com.batiyao.veda/notifications');

  var _asked = false;

  /// Asks for the one permission the notification needs, once.
  ///
  /// From Android 13 a media notification simply does not appear without it,
  /// with no error and nothing in the log — which is exactly how it looks when
  /// you have forgotten to ask for it. Refusing costs the notification and
  /// nothing else: the recitation still plays.
  Future<void> ensureNotificationAllowed() async {
    if (_asked) return;
    _asked = true;
    try {
      await _permissions.invokeMethod<bool>('request');
    } on Object {
      // A platform with no such notion, which is every platform but Android.
    }
  }

  /// Shows [item] in the notification and on the lock screen.
  void show(MediaItem item, {required bool playing}) {
    mediaItem.add(item);
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        // All three on the lock screen: skipping a verse is the one thing a
        // listener does without looking.
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: playing,
      ),
    );
  }

  /// Takes the notification down.
  void clear() {
    controls = null;
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle, playing: false),
    );
  }

  @override
  Future<void> play() async => controls?.resume();

  @override
  Future<void> pause() async => controls?.halt();

  @override
  Future<void> skipToNext() async => controls?.forward();

  @override
  Future<void> skipToPrevious() async => controls?.back();

  @override
  Future<void> stop() async {
    await controls?.halt();
    clear();
    await super.stop();
  }
}
