import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/library/scripture_repository.dart';

/// Choosing which chapter to open the player at.
///
/// Extracted because the bug it guards was invisible on a phone that had read
/// something before: with nothing saved, the lookup matched the work's front
/// matter — a section with no chapter number and no verses — and the player
/// opened on a chapter called "Other" holding nothing, reporting "1 of 0".
SectionSummary? chapterToOpen(List<SectionSummary> all, String? mark) {
  final sections = [
    for (final section in all)
      if (section.verseCount > 0) section,
  ];
  final chapter = mark?.split('.').first;
  return (chapter == null
          ? null
          : sections.where((s) => s.number == chapter).firstOrNull) ??
      sections.firstOrNull;
}

const _frontMatter = SectionSummary(
  id: 0,
  number: null,
  title: null,
  passageCount: 3,
  verseCount: 0,
);

const _chapters = [
  _frontMatter,
  SectionSummary(
    id: 1,
    number: '1',
    title: 'अर्जुनविषादयोगः',
    passageCount: 47,
    verseCount: 47,
  ),
  SectionSummary(
    id: 2,
    number: '2',
    title: 'साङ्ख्ययोगः',
    passageCount: 72,
    verseCount: 72,
  ),
];

void main() {
  test('with nothing saved it opens the first real chapter', () {
    final section = chapterToOpen(_chapters, null);
    expect(section?.number, '1');
    expect(section?.verseCount, 47);
  });

  test('it never opens a section with no verses in it', () {
    // The front matter matched a null chapter number and won, because it came
    // first.
    expect(chapterToOpen(_chapters, null)?.id, isNot(_frontMatter.id));
    expect(chapterToOpen([_frontMatter], null), isNull);
  });

  test('it returns to the chapter the listener left off in', () {
    expect(chapterToOpen(_chapters, '2.47')?.number, '2');
  });

  test('a mark in a chapter that is gone falls back to the first', () {
    // A pack revision can drop a chapter; the saved place must not strand the
    // player.
    expect(chapterToOpen(_chapters, '18.66')?.number, '1');
  });
}
