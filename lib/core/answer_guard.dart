import 'grounding.dart';

final _citation = RegExp(r'\[(\d+(?:\s*,\s*\d+)*)\]');
final _citationWithSpace = RegExp(r'\s*\[(\d+(?:\s*,\s*\d+)*)\]');

class Citations {
  const Citations(this.valid, this.invalid);

  /// 1-based passage numbers that exist, in ascending order.
  final List<int> valid;

  /// Numbers the model cited that match no passage, i.e. invented citations.
  final List<int> invalid;
}

/// Reads the `[n]` and `[n, m]` citations in [answer].
Citations extractCitations(String answer, int passageCount) {
  final valid = <int>{};
  final invalid = <int>{};
  for (final m in _citation.allMatches(answer)) {
    for (final n in _numbers(m[1]!)) {
      (n >= 1 && n <= passageCount ? valid : invalid).add(n);
    }
  }
  return Citations(valid.toList()..sort(), invalid.toList()..sort());
}

/// Removes citations to passages that don't exist, so every citation shown is
/// a link that works.
String stripInvalidCitations(String answer, int passageCount) =>
    answer.replaceAllMapped(_citationWithSpace, (m) {
      final kept = _numbers(m[1]!)
          .where((n) => n >= 1 && n <= passageCount)
          .toList();
      if (kept.isEmpty) return '';
      final match = m[0]!;
      final leadingSpace = match.substring(0, match.indexOf('['));
      return '$leadingSpace[${kept.join(', ')}]';
    });

Iterable<int> _numbers(String list) =>
    list.split(',').map((p) => int.tryParse(p.trim())).whereType<int>();

/// Shown where the model tried to write verse text itself.
const String omittedVerse = '[verse omitted: open the cited source to read it]';

// A run of Devanagari or Kannada text ending in a double danda, optionally
// followed by a verse number and another double danda. Single dandas and
// newlines may appear inside, since a verse is usually two half-lines.
final _verse = RegExp(
  r'[\u0900-\u0963\u0966-\u097F\u0C80-\u0CFF\uA8E0-\uA8FF\u1CD0-\u1CFF]'
  r'[\u0900-\u0964\u0966-\u097F\u0C80-\u0CFF\uA8E0-\uA8FF\u1CD0-\u1CFF\u200C\u200D \t\n]*'
  r'\u0965'
  r'(?:[ \t]*[0-9\u0966-\u096F\u0CE6-\u0CEF.]+[ \t]*\u0965)?',
);

/// Enforces ground rule 2 in code: **the model never generates scripture
/// text**.
///
/// Replaces any verse-shaped Indic text in [answer] that is not a verbatim
/// quote of one of [passages], ignoring whitespace, dandas and verse numbers.
/// Prose (Hindi uses the single danda as a full stop) is untouched. It errs
/// towards removal: if model-written prose runs straight into a verse on the
/// same lines, both go.
String removeUngroundedVerses(String answer, List<Passage> passages) {
  final sources = [for (final p in passages) _letters(p.text)];
  return answer.replaceAllMapped(_verse, (m) {
    final key = _letters(m[0]!);
    if (key.isEmpty) return m[0]!;
    return sources.any((s) => s.contains(key)) ? m[0]! : omittedVerse;
  });
}

String _letters(String s) =>
    s.replaceAll(RegExp(r'[\s0-9.\u0964\u0965\u0966-\u096F\u0CE6-\u0CEF]'), '');
