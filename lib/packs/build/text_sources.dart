import 'pack_builder.dart';

// Turns extracted source text into passages. Structured scripture (chapters
// and verses) gets its own parser once the real source files' markup is known.

/// One prose passage per paragraph, split at blank lines, with hard-wrapped
/// lines joined. Refs are `para1`, `para2`, ... in reading order.
List<PassageSource> passagesFromPlainText(String text) {
  final paragraphs = _normaliseNewlines(text)
      .split(RegExp(r'\n[ \t]*\n'))
      .map(_joinLines)
      .where((p) => p.isNotEmpty)
      .toList();
  return [
    for (var i = 0; i < paragraphs.length; i++)
      PassageSource(
        ref: 'para${i + 1}',
        label: '¶ ${i + 1}',
        kind: PassageKind.prose,
        text: paragraphs[i],
      ),
  ];
}

/// One passage per PDF page that has text. Refs use the page's position in
/// the file (`p12`), so skipping blank pages never renumbers the rest.
List<PassageSource> passagesFromPages(List<String> pages) => [
  for (var i = 0; i < pages.length; i++)
    if (_tidyPage(pages[i]) case final text when text.isNotEmpty)
      PassageSource(
        ref: 'p${i + 1}',
        label: 'p. ${i + 1}',
        kind: PassageKind.page,
        text: text,
      ),
];

String _normaliseNewlines(String s) =>
    s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _joinLines(String paragraph) => paragraph
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .join(' ')
    .replaceAll(RegExp(r'[ \t]+'), ' ');

final _hyphenatedBreak = RegExp(r'(\p{Ll})-\n(\p{Ll})', unicode: true);

String _tidyPage(String page) =>
    _normaliseNewlines(page)
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .join('\n')
        .replaceAllMapped(_hyphenatedBreak, (m) => '${m[1]}${m[2]}')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
