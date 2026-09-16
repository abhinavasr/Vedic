import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/audio/speech.dart';

const _english = SpokenChoice(
  text: 'One line.',
  locale: 'en-IN',
  languageCode: 'en',
  description: 'Read aloud in English',
);

/// A voice that only finishes when the test says so.
class _HeldVoice implements SpeechEngine {
  /// One per utterance: speak() begins by stopping whatever came before, and
  /// a single shared completer would mark the new utterance finished before
  /// it started.
  Completer<void>? _current;
  var stops = 0;
  final spoken = <String>[];

  @override
  Future<List<Object?>> languages() async => ['en-IN', 'hi-IN'];

  @override
  Future<void> awaitCompletion() async {}

  @override
  Future<void> configure({
    required String locale,
    required double rate,
  }) async {}

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    return (_current = Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    stops++;
    finishNaturally();
  }

  void finishNaturally() {
    final current = _current;
    if (current != null && !current.isCompleted) current.complete();
  }
}

/// Lets the awaits inside speak() run: it stops anything playing, wires the
/// engine and configures the voice before it starts.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a verse that is stopped reports that it did not finish', () async {
    // The bug this guards: reading straight through could not tell a stop
    // from the end of a verse, so pressing stop turned the page instead.
    final voice = _HeldVoice();
    final speech = VerseSpeech(engine: voice);

    final reading = speech.speak('4.5', _english);
    await _settle();
    expect(speech.speaking.value, '4.5');

    await speech.stop();
    expect(await reading, isFalse, reason: 'cut off, so do not advance');
    expect(speech.speaking.value, isNull);
  });

  test('a verse read to the end reports that it finished', () async {
    final voice = _HeldVoice();
    final speech = VerseSpeech(engine: voice);

    final reading = speech.speak('4.5', _english);
    await _settle();
    voice.finishNaturally();

    expect(await reading, isTrue);
    expect(speech.speaking.value, isNull);
    expect(voice.spoken.single, 'One line.');
  });

  test('a new verse cuts the last one off, and says so', () async {
    final voice = _HeldVoice();
    final speech = VerseSpeech(engine: voice);

    final first = speech.speak('4.5', _english);
    await _settle();
    // Starting another stops the first, which must not count as finished.
    unawaited(speech.speak('4.6', _english));
    expect(await first, isFalse);
  });

  test('the language a phone cannot speak is not offered', () async {
    final speech = VerseSpeech(engine: _HeldVoice());
    final choice = await speech.chooseForMeaning(
      available: {'ta': 'தமிழில்', 'en': 'In English.'},
      preferred: 'ta',
    );
    // This fake speaks English and Hindi only, so Tamil falls through.
    expect(choice?.languageCode, 'en');
  });
}
