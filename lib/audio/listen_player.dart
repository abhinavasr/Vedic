import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'speech.dart';

// Playing a verse: the chant, the meaning and the explanation, one after
// another, from two different machines — a recording played back, and a voice
// synthesised on the phone.
//
// The thing that matters here is the same thing that mattered for reading
// straight through: a play that was *stopped* must be told apart from one that
// *finished*. Silence means "turn the page" to the reader reading on, and a
// reader who pressed stop and had the page turn under them reported it as the
// stop button behaving like next.

/// One thing to play for a verse.
sealed class ListenSegment {
  const ListenSegment();
}

/// A recording, played as it was recorded.
class ChantSegment extends ListenSegment {
  const ChantSegment(this.file);

  final File file;
}

/// Something the phone reads aloud.
class SpokenSegment extends ListenSegment {
  const SpokenSegment(this.choice);

  final SpokenChoice choice;
}

/// Plays a recording. A seam, so the player is testable without a speaker.
abstract interface class ChantPlayer {
  /// Plays [file] to the end. False when it was stopped instead.
  Future<bool> play(File file);

  Future<void> stop();
}

/// The real one.
class DeviceChantPlayer implements ChantPlayer {
  DeviceChantPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  Completer<bool>? _playing;

  @override
  Future<bool> play(File file) async {
    await stop();
    final done = _playing = Completer<bool>();
    final finished = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete(true);
    });
    try {
      await _player.play(DeviceFileSource(file.path));
      return await done.future;
    } finally {
      await finished.cancel();
      if (identical(_playing, done)) _playing = null;
    }
  }

  @override
  Future<void> stop() async {
    final playing = _playing;
    if (playing != null && !playing.isCompleted) playing.complete(false);
    await _player.stop();
  }

  Future<void> dispose() => _player.dispose();
}

/// Plays what the reader chose to hear, in order.
class VersePlayer {
  VersePlayer({VerseSpeech? speech, ChantPlayer? chant})
    : _speech = speech ?? VerseSpeech.instance,
      _chant = chant ?? DeviceChantPlayer();

  /// The app's. Replaceable in tests.
  static VersePlayer instance = VersePlayer();

  final VerseSpeech _speech;
  final ChantPlayer _chant;

  /// The passage being played, so one verse's control shows as playing and
  /// the others do not.
  final playing = ValueNotifier<String?>(null);

  /// Bumped by every stop and every new verse, so a play that has finished can
  /// tell whether it ran to the end or was cut off.
  var _token = 0;

  /// Plays [segments] in order. False when it was stopped part way.
  ///
  /// A segment that fails — a recording that will not decode, a voice the
  /// phone turns out not to have — does not stop the rest: the meaning is
  /// still worth hearing when the chant will not play.
  Future<bool> play(String ref, List<ListenSegment> segments) async {
    await stop();
    if (segments.isEmpty) return true;
    final token = ++_token;
    playing.value = ref;
    for (final segment in segments) {
      if (token != _token) return false;
      var finished = true;
      try {
        finished = switch (segment) {
          ChantSegment(:final file) => await _chant.play(file),
          SpokenSegment(:final choice) => await _speech.speak(ref, choice),
        };
      } on Object {
        // Carry on to the next thing the reader asked for.
        continue;
      }
      // A segment that reports it was cut off, and a token that has moved on,
      // are the same news: somebody else has the speaker now.
      if (!finished || token != _token) return false;
    }
    if (token != _token) return false;
    playing.value = null;
    return true;
  }

  Future<void> stop() async {
    _token++;
    playing.value = null;
    await _chant.stop();
    await _speech.stop();
  }
}
