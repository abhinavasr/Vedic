import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/reading_languages.dart';
import 'package:vedic/audio/speech.dart';
import 'package:vedic/library/scripture_repository.dart';
import 'package:vedic/audio/listen_mix.dart';
import 'package:vedic/ui/listen_meaning.dart';

/// A phone with an English voice and nothing to say.
class _Voice implements SpeechEngine {
  @override
  Future<List<Object?>> languages() async => ['en-IN'];

  @override
  Future<void> awaitCompletion() async {}

  @override
  Future<void> configure({
    required String locale,
    required double rate,
  }) async {}

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}

const _verse = PassageView(
  ref: '1.9',
  label: '1.9',
  type: PassageType.verse,
  text: 'अन्ये च बहवः शूरा',
  variants: [],
  translations: [
    TranslationView(
      language: 'en',
      text: 'And many other heroes.',
      translator: null,
      machine: false,
    ),
  ],
  explanations: [
    NoteView(language: 'en', text: 'Duryodhana names his own commanders.'),
  ],
);

Widget _app(ReadingLanguage reading) => ReadingLanguageScope(
  language: reading,
  child: const MaterialApp(home: Scaffold(body: ListenControl(verse: _verse))),
);

void main() {
  setUp(() => VerseSpeech.instance = VerseSpeech(engine: _Voice()));

  testWidgets('a choice made elsewhere reaches the listen row', (
    tester,
  ) async {
    // The bug this guards: the row was decided once, so a choice changed in
    // Settings left it still offering to play something else.
    final reading = ReadingLanguage(null)
      ..mix = const ListenMix(meaning: true, explanation: true);
    await tester.pumpWidget(_app(reading));
    await tester.pumpAndSettle();
    expect(find.textContaining('and the explanation'), findsOneWidget);

    reading.mix = const ListenMix();
    await tester.pumpAndSettle();
    expect(find.textContaining('and the explanation'), findsNothing);
    expect(find.textContaining('The meaning in English'), findsOneWidget);
  });

  testWidgets('the chips beside the control change what plays', (tester) async {
    final reading = ReadingLanguage(null);
    await tester.pumpWidget(_app(reading));
    await tester.pumpAndSettle();
    expect(find.textContaining('and the explanation'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mix-explanation')));
    await tester.pumpAndSettle();
    expect(reading.mix.explanation, isTrue);
    expect(find.textContaining('and the explanation'), findsOneWidget);

    // And off again, from the same place.
    await tester.tap(find.byKey(const ValueKey('mix-meaning')));
    await tester.pumpAndSettle();
    expect(reading.mix.meaning, isFalse);
    expect(find.textContaining('The explanation in English'), findsOneWidget);
  });

  testWidgets('no chant chip where no chant has been published', (
    tester,
  ) async {
    // Every feature degrades to absent: a verse with no recording does not
    // offer one.
    await tester.pumpWidget(_app(ReadingLanguage(null)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mix-chant')), findsNothing);
    expect(find.byKey(const ValueKey('mix-meaning')), findsOneWidget);
  });

  testWidgets('the compact card has the control and no chips', (tester) async {
    await tester.pumpWidget(
      ReadingLanguageScope(
        language: ReadingLanguage(null),
        child: const MaterialApp(
          home: Scaffold(body: ListenControl(verse: _verse, compact: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mix-meaning')), findsNothing);
    expect(find.textContaining('The meaning in English'), findsOneWidget);
  });
}
