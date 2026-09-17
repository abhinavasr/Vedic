import 'package:flutter/material.dart';

import '../library/scripture_repository.dart';
import 'theme.dart';

// Reaching any verse in the book without leaving what you are doing.
//
// Moving one verse at a time is fine for reading straight through and hopeless
// for looking something up, and going out to the chapter list to come back in
// is worse. It is the same problem whether you are reading the verses or
// listening to them, so it is the same sheet.

/// Where the reader or the listener wants to go.
typedef JumpTarget = ({SectionSummary section, String ref});

/// Asks which chapter and which verse. Null when the sheet was dismissed.
Future<JumpTarget?> showJumpSheet(
  BuildContext context, {
  required ScriptureRepository repository,
  required WorkSummary work,
  required SectionSummary section,
  String? currentRef,
}) {
  final sections = repository.sections(work);
  var chosen = section;
  return showModalBottomSheet<JumpTarget>(
    context: context,
    backgroundColor: SadhanaColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final verses = repository.verses(work, chosen);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    'Go to',
                    style: serif(size: 20, color: SadhanaColors.ink),
                  ),
                ),
                _JumpLabel(divisionName(chosen)),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final option in sections)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey('jump-chapter-${option.number}'),
                            label: Text(_chapterLabel(option)),
                            selected: option.id == chosen.id,
                            onSelected: (_) => setSheet(() => chosen = option),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _JumpLabel(
                  chosen.number == null
                      ? 'Verse'
                      : 'Verse in '
                            '${divisionName(chosen).toLowerCase()} '
                            '${chosen.number}',
                ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 5,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (final verse in verses)
                        Material(
                          color:
                              verse.ref == currentRef &&
                                  chosen.id == section.id
                              ? SadhanaColors.greenTint
                              : SadhanaColors.searchFill,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(
                              context,
                            ).pop((section: chosen, ref: verse.ref)),
                            child: Center(
                              child: Text(
                                (verse.label ?? verse.ref).split('.').last,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: SadhanaColors.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// What this book calls its divisions, capitalised for a heading.
///
/// A Gītā has chapters and a Veda has sūktas, and telling a reader that the
/// Ṛgveda's first sūkta is "Chapter 1.1" is simply the wrong word.
String divisionName(SectionSummary section) => switch (section.kind) {
  'sukta' => 'Sūkta',
  'kanda' => 'Kāṇḍa',
  'mandala' => 'Maṇḍala',
  'anuvaka' => 'Anuvāka',
  'canto' => 'Canto',
  _ => 'Chapter',
};

/// A chapter, named the way the book names it.
///
/// "1" on its own is a number, not a place. With the title beside it — "1 ·
/// अर्जुनविषादयोगः" — it is a chapter somebody can recognise.
String _chapterLabel(SectionSummary section) {
  final number = section.number;
  final title = section.title;
  if (number == null) return title ?? 'Other';
  return title == null ? number : '$number  ·  $title';
}

/// How a chapter is named outside the sheet: on a button, in a heading.
String chapterName(SectionSummary section) => _chapterLabel(section);

/// A quiet heading inside the sheet, so a row of numbers says what it is a
/// row of.
class _JumpLabel extends StatelessWidget {
  const _JumpLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
        color: SadhanaColors.gold,
      ),
    ),
  );
}
