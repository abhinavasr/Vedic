import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/reading_languages.dart';
import 'package:vedic/audio/speech.dart';
import 'package:vedic/library/scripture_repository.dart';
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
  child: const MaterialApp(home: Scaffold(body: ListenMeaning(verse: _verse))),
);

void main() {
  setUp(() => VerseSpeech.instance = VerseSpeech(engine: _Voice()));

  testWidgets('a setting changed elsewhere reaches the listen row', (
    tester,
  ) async {
    // The bug this guards: the row was decided once, so turning the
    // explanation off in Settings left it still offering to read it.
    final reading = ReadingLanguage(null)..withExplanation = true;
    await tester.pumpWidget(_app(reading));
    await tester.pumpAndSettle();
    expect(find.textContaining('with the explanation'), findsOneWidget);

    reading.withExplanation = false;
    await tester.pumpAndSettle();
    expect(find.textContaining('with the explanation'), findsNothing);
    expect(find.textContaining('Read aloud in English'), findsOneWidget);
  });

  testWidgets('the toggle beside the control turns it on', (tester) async {
    final reading = ReadingLanguage(null);
    await tester.pumpWidget(_app(reading));
    await tester.pumpAndSettle();
    expect(find.textContaining('with the explanation'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('with-explanation')));
    await tester.pumpAndSettle();
    expect(reading.withExplanation, isTrue);
    expect(find.textContaining('with the explanation'), findsOneWidget);
  });

  testWidgets('no toggle where the explanation is not on screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ReadingLanguageScope(
        language: ReadingLanguage(null),
        child: const MaterialApp(
          home: Scaffold(
            body: ListenMeaning(verse: _verse, offerExplanation: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('with-explanation')), findsNothing);
  });
}
