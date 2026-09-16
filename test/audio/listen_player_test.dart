import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/audio/listen_player.dart';
import 'package:vedic/audio/speech.dart';

const _meaning = SpokenChoice(
  text: 'One line.',
  locale: 'en-IN',
  languageCode: 'en',
  description: 'Read aloud in English',
);

const _explanation = SpokenChoice(
  text: 'What it means.',
  locale: 'en-IN',
  languageCode: 'en',
  description: 'Read aloud in English',
);

/// A recording that plays until the test says it has finished.
class _Recording implements ChantPlayer {
  Completer<bool>? _current;
  final played = <String>[];
  var stops = 0;
  bool broken = false;

  @override
  Future<bool> play(File file) {
    played.add(file.path);
    if (broken) return Future.error(const FileSystemException('no codec'));
    return (_current = Completer<bool>()).future;
  }

  @override
  Future<void> stop() async {
    stops++;
    final current = _current;
    if (current != null && !current.isCompleted) current.complete(false);
  }

  void finish() {
    final current = _current;
    if (current != null && !current.isCompleted) current.complete(true);
  }
}

/// A voice that speaks instantly, recording what it was given.
class _Voice implements SpeechEngine {
  final spoken = <String>[];

  @override
  Future<List<Object?>> languages() async => ['en-IN'];

  @override
  Future<void> awaitCompletion() async {}

  @override
  Future<void> configure({required String locale, required double rate}) async {}

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('plays the chant, then the meaning, then the explanation', () async {
    final recording = _Recording();
    final voice = _Voice();
    final player = VersePlayer(
      speech: VerseSpeech(engine: voice),
      chant: recording,
    );

    final done = player.play('2.47', [
      ChantSegment(File('2.47.wav')),
      const SpokenSegment(_meaning),
      const SpokenSegment(_explanation),
    ]);
    await _settle();

    // The chant holds the floor until it is finished with.
    expect(recording.played.single, '2.47.wav');
    expect(voice.spoken, isEmpty);
    expect(player.playing.value, '2.47');

    recording.finish();
    expect(await done, isTrue);
    expect(voice.spoken, ['One line.', 'What it means.']);
    expect(player.playing.value, isNull);
  });

  test('stopping part way does not count as finishing', () async {
    // The bug this guards, in its new form: reading straight through takes a
    // finished play as its cue to turn the page. A reader who pressed stop
    // during the chant must not have the page turn under them.
    final recording = _Recording();
    final voice = _Voice();
    final player = VersePlayer(
      speech: VerseSpeech(engine: voice),
      chant: recording,
    );

    final done = player.play('2.47', [
      ChantSegment(File('2.47.wav')),
      const SpokenSegment(_meaning),
    ]);
    await _settle();
    await player.stop();

    expect(await done, isFalse);
    expect(voice.spoken, isEmpty, reason: 'and nothing after it is played');
    expect(player.playing.value, isNull);
  });

  test('a recording that will not play does not cost the meaning', () async {
    final recording = _Recording()..broken = true;
    final voice = _Voice();
    final player = VersePlayer(
      speech: VerseSpeech(engine: voice),
      chant: recording,
    );

    expect(
      await player.play('2.47', [
        ChantSegment(File('2.47.wav')),
        const SpokenSegment(_meaning),
      ]),
      isTrue,
    );
    expect(voice.spoken, ['One line.']);
  });

  test('choosing nothing plays nothing, and says so calmly', () async {
    final player = VersePlayer(
      speech: VerseSpeech(engine: _Voice()),
      chant: _Recording(),
    );
    expect(await player.play('2.47', const []), isTrue);
    expect(player.playing.value, isNull);
  });
}
