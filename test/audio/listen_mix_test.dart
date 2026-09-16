import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/assistant.dart';
import 'package:vedic/ai/reading_languages.dart';
import 'package:vedic/audio/listen_mix.dart';

class _MemorySettings implements AssistantSettings {
  final values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String? value) =>
      value == null ? values.remove(key) : values[key] = value;
}

void main() {
  test('every way of listening the reader asked for is expressible', () {
    // The five combinations named in the request, and the two that fall out
    // of the same three switches.
    const cases = {
      'chant only': ListenMix(chant: true, meaning: false),
      'chant and meaning': ListenMix(chant: true, meaning: true),
      'chant, meaning and explanation':
          ListenMix(chant: true, meaning: true, explanation: true),
      'meaning and explanation': ListenMix(meaning: true, explanation: true),
      'chant and explanation':
          ListenMix(chant: true, meaning: false, explanation: true),
      'meaning alone': ListenMix(),
      'explanation alone': ListenMix(meaning: false, explanation: true),
    };
    // Each is a distinct setting, and each survives being written down.
    final codes = {for (final c in cases.values) c.code};
    expect(codes.length, cases.length);
    for (final entry in cases.entries) {
      expect(ListenMix.parse(entry.value.code), entry.value, reason: entry.key);
    }
  });

  test('the meaning alone is what a reader gets before choosing', () {
    const fresh = ListenMix();
    expect(fresh.meaning, isTrue);
    expect(fresh.chant, isFalse);
    expect(fresh.explanation, isFalse);
  });

  test('turning everything off is a state, not a crash', () {
    const nothing = ListenMix(meaning: false);
    expect(nothing.isSilent, isTrue);
    expect(
      nothing.describe(reading: 'en', nameOf: (c) => c),
      'Nothing selected',
    );
    expect(ListenMix.parse(''), nothing);
  });

  test('it says what is about to be played, in the order it plays', () {
    String name(String code) => switch (code) {
      'hi' => 'Hindi',
      'en' => 'English',
      _ => code,
    };
    String describe(ListenMix mix) =>
        mix.describe(reading: 'hi', nameOf: name);

    // One language for both reads as a sentence, not a specification.
    expect(
      describe(const ListenMix(chant: true, meaning: true, explanation: true)),
      'The chant and the meaning and the explanation in Hindi',
    );
    expect(describe(const ListenMix(chant: true, meaning: false)), 'The chant');
    // Two languages are worth saying twice, because that is the point of
    // being able to choose them separately.
    expect(
      describe(
        const ListenMix(
          meaning: true,
          explanation: true,
          explanationLanguage: 'en',
        ),
      ),
      'The meaning in Hindi and the explanation in English',
    );
  });

  test('each clip carries its own language, and the chant carries none', () {
    const mix = ListenMix(
      chant: true,
      meaning: true,
      explanation: true,
      meaningLanguage: 'hi',
      explanationLanguage: 'en',
    );
    expect(mix.meaningIn('ta'), 'hi');
    expect(mix.explanationIn('ta'), 'en');
    expect(ListenMix.parse(mix.code), mix);
  });

  test('a clip with no language of its own follows the app', () {
    const mix = ListenMix(meaning: true, explanation: true);
    expect(mix.meaningIn('bn'), 'bn');
    expect(mix.explanationIn('bn'), 'bn');
    // And an explanation with none follows the meaning, not the app.
    const chosen = ListenMix(
      meaning: true,
      explanation: true,
      meaningLanguage: 'en',
    );
    expect(chosen.explanationIn('bn'), 'en');
  });

  test('a setting written by a newer version is not half-read', () {
    expect(ListenMix.parse('c,m,x'), isNull);
    expect(ListenMix.parse(null), isNull);
  });

  test('the choice is remembered', () {
    final settings = _MemorySettings();
    ReadingLanguage(settings).mix = const ListenMix(
      chant: true,
      meaning: false,
      explanation: true,
    );
    expect(settings.values['reading.listenMix'], 'c,e');
    expect(ReadingLanguage(settings).mix.chant, isTrue);
    expect(ReadingLanguage(settings).mix.meaning, isFalse);
  });

  test('a phone that had the old explanation switch keeps its choice', () {
    // It shipped as one switch before it became three, and turning it off
    // behind someone's back would read as the app forgetting.
    final settings = _MemorySettings()
      ..values['reading.speakExplanation'] = 'true';
    final reading = ReadingLanguage(settings);
    expect(reading.mix.explanation, isTrue);
    expect(reading.mix.meaning, isTrue, reason: 'and still reads the meaning');
  });
}
