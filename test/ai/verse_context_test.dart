import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/verse_context.dart';
import 'package:vedic/library/scripture_repository.dart';

const _section = SectionSummary(
  id: 1,
  number: '2',
  title: 'साङ्ख्ययोगः',
  passageCount: 2,
  verseCount: 2,
);

PassageView _verse({List<TranslationView> translations = const []}) =>
    PassageView(
      ref: '2.47',
      label: '2.47',
      type: PassageType.verse,
      text: 'कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।',
      variants: const [],
      speaker: 'श्रीभगवानुवाच',
      translations: translations,
    );

void main() {
  test('carries the pack\'s own account of the verse', () {
    final context = verseContext(
      workTitle: 'Bhagavad Gītā',
      section: _section,
      verse: _verse(
        translations: const [
          TranslationView(
            language: 'en',
            text: 'Your right is to action alone.',
            translator: 'A translator',
            machine: false,
          ),
        ],
      ),
      previous: null,
    );

    expect(context.work, 'Bhagavad Gītā');
    expect(context.chapter, 'Chapter 2');
    expect(context.speaker, 'श्रीभगवानुवाच');
    expect(context.published['English'], 'Your right is to action alone.');
    // No transliteration in the pack, so the app's mechanical one stands in.
    expect(context.transliteration, startsWith('karma'));
    expect(context.previous, isNull);
  });

  test('carries the verse before, transliterated even when untranslated', () {
    final context = verseContext(
      workTitle: 'Bhagavad Gītā',
      section: _section,
      verse: _verse(),
      previous: PassageView(
        ref: '2.46',
        label: '2.46',
        type: PassageType.verse,
        text: 'यावानर्थ उदपाने',
        variants: const [],
        speaker: 'श्रीभगवानुवाच',
      ),
    );

    final previous = context.previous!;
    expect(previous.label, '2.46');
    expect(previous.speaker, 'श्रीभगवानुवाच');
    expect(previous.published, isEmpty);
    // The one thing always available for a verse nobody has translated.
    expect(previous.transliteration, startsWith('y'));
  });

  test('never offers a machine translation as evidence', () {
    // One phone's guess is not a source: translating from it would launder a
    // guess into a second language.
    final context = verseContext(
      workTitle: 'Bhagavad Gītā',
      section: _section,
      verse: _verse(
        translations: const [
          TranslationView(
            language: 'en',
            text: 'Guessed on this phone.',
            translator: null,
            machine: true,
          ),
          TranslationView(
            language: 'hi',
            text: 'प्रकाशित अनुवाद।',
            translator: 'A translator',
            machine: false,
          ),
        ],
      ),
    );

    expect(context.published, hasLength(1));
    expect(context.published['Hindi'], 'प्रकाशित अनुवाद।');
    expect(context.published.values, isNot(contains('Guessed on this phone.')));
  });

  test('a chapter with no number falls back to its title', () {
    final context = verseContext(
      workTitle: 'Bhagavad Gītā',
      section: const SectionSummary(
        id: null,
        number: null,
        title: 'Invocation',
        passageCount: 1,
        verseCount: 0,
      ),
      verse: _verse(),
    );
    expect(context.chapter, 'Invocation');
    expect(context.isEmpty, isFalse);
  });
}
