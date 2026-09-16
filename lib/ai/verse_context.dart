import '../core/transliteration.dart';
import '../library/scripture_repository.dart';
import 'translation.dart';

/// Gathers what the installed pack knows about a verse, for grounding a
/// translation in the passage rather than the sentence.
///
/// Only published material is included. A machine translation is never fed
/// back in as evidence: one phone's guess is not a source, and translating
/// from it would launder a guess into a second language.
VerseContext verseContext({
  required String workTitle,
  required SectionSummary? section,
  required PassageView verse,
  PassageView? previous,
}) => VerseContext(
  work: workTitle,
  chapter: switch (section) {
    null => null,
    SectionSummary(number: null, :final title) => title,
    SectionSummary(:final number) => 'Chapter $number',
  },
  speaker: verse.speaker,
  // The pack's own transliteration where there is one; otherwise the app's,
  // which is a mechanical mapping rather than anybody's reading.
  transliteration: verse.transliteration ?? devanagariToIast(verse.text),
  published: _published(verse),
  previous: previous == null
      ? null
      : PrecedingVerse(
          text: previous.text,
          label: previous.label ?? previous.ref,
          speaker: previous.speaker,
          // Carries most of the weight when that verse has no translation at
          // all, which is the common case in a work still being translated.
          transliteration:
              previous.transliteration ?? devanagariToIast(previous.text),
          published: _published(previous),
        ),
);

/// Published translations only, by language name.
Map<String, String> _published(PassageView verse) => {
  for (final translation in verse.translations)
    if (!translation.machine)
      TargetLanguage.forCode(translation.language)?.name ??
              translation.language:
          translation.text,
};
