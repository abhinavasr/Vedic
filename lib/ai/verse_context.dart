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
  required SectionSummary section,
  required PassageView verse,
  PassageView? previous,
}) => VerseContext(
  work: workTitle,
  chapter: section.number == null ? section.title : 'Chapter ${section.number}',
  speaker: verse.speaker,
  // The pack's own transliteration where there is one; otherwise the app's,
  // which is a mechanical mapping rather than anybody's reading.
  transliteration: verse.transliteration ?? devanagariToIast(verse.text),
  published: {
    for (final translation in verse.translations)
      if (!translation.machine)
        TargetLanguage.forCode(translation.language)?.name ??
                translation.language:
            translation.text,
  },
  previousVerse: previous?.text,
);
