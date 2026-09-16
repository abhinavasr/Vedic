import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/library/scripture_repository.dart';

const _verse = PassageView(
  ref: '1.1',
  label: '1.1',
  type: PassageType.verse,
  text: 'धर्मक्षेत्रे कुरुक्षेत्रे',
  variants: [],
  explanations: [
    NoteView(language: 'en', text: 'In English.'),
    NoteView(language: 'hi', text: 'हिन्दी में।'),
  ],
);

void main() {
  test('a language the pack has is the one that is used', () {
    expect(_verse.notesFor(_verse.explanations, ['hi']), ['हिन्दी में।']);
    expect(_verse.noteLanguageOf(_verse.explanations, ['hi']), 'hi');
  });

  test('a language the pack lacks falls back to ONE language', () {
    // The bug this guards: asked for Bengali, the explanation came back in
    // every language the pack had, and the phone read the verse out in
    // English and then again in Hindi.
    final shown = _verse.notesFor(_verse.explanations, ['bn']);
    expect(shown, hasLength(1));
    expect(shown.single, 'In English.');
    expect(_verse.noteLanguageOf(_verse.explanations, ['bn']), 'en');
  });

  test('several paragraphs in one language still all show', () {
    const many = PassageView(
      ref: '1.1',
      label: '1.1',
      type: PassageType.verse,
      text: 'x',
      variants: [],
      explanations: [
        NoteView(language: 'en', text: 'First.'),
        NoteView(language: 'en', text: 'Second.'),
        NoteView(language: 'hi', text: 'हिन्दी।'),
      ],
    );
    expect(many.notesFor(many.explanations, ['en']), ['First.', 'Second.']);
    // And the fallback keeps both paragraphs of the one language it picks.
    expect(many.notesFor(many.explanations, ['ta']), ['First.', 'Second.']);
  });

  test('a verse with no explanation at all says nothing', () {
    const bare = PassageView(
      ref: '1.1',
      label: '1.1',
      type: PassageType.verse,
      text: 'x',
      variants: [],
    );
    expect(bare.notesFor(bare.explanations, ['en']), isEmpty);
    expect(bare.noteLanguageOf(bare.explanations, ['en']), isNull);
  });
}
