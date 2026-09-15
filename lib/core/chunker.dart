import 'dart:math' as math;

/// A piece of a document small enough to embed, with its place in the source.
class TextChunk {
  const TextChunk({
    required this.ordinal,
    required this.start,
    required this.end,
    required this.text,
  });

  final int ordinal;

  /// UTF-16 offsets into the source, so `source.substring(start, end) == text`.
  final int start;
  final int end;
  final String text;
}

/// Splits [text] into overlapping chunks of at most [maxChars].
///
/// Each chunk ends at the strongest boundary in the back half of its window:
/// a paragraph break, then a sentence end (including the danda । and double
/// danda ॥), then a space. Unbroken text is cut hard, but never between a
/// consonant and its vowel sign or virama, so no chunk starts with a dangling
/// mark.
List<TextChunk> chunkText(
  String text, {
  int maxChars = 1000,
  int overlapChars = 150,
}) {
  if (maxChars <= 0) {
    throw ArgumentError.value(maxChars, 'maxChars', 'must be positive');
  }
  if (overlapChars < 0 || overlapChars >= maxChars) {
    throw ArgumentError.value(
      overlapChars,
      'overlapChars',
      'must be at least 0 and less than maxChars',
    );
  }

  final chunks = <TextChunk>[];
  final n = text.length;
  var start = _skipSpace(text, 0);
  while (start < n) {
    var end = math.min(start + maxChars, n);
    if (end < n) end = _breakBefore(text, start, end);

    var trimmedEnd = end;
    while (trimmedEnd > start && _isSpace(text.codeUnitAt(trimmedEnd - 1))) {
      trimmedEnd--;
    }
    if (trimmedEnd > start) {
      chunks.add(
        TextChunk(
          ordinal: chunks.length,
          start: start,
          end: trimmedEnd,
          text: text.substring(start, trimmedEnd),
        ),
      );
    }
    if (end >= n) break;

    final back = end - overlapChars;
    final next = back <= start ? end : _alignForward(text, back, end);
    start = _skipSpace(text, next);
  }
  return chunks;
}

int _breakBefore(String t, int start, int end) {
  final floor = start + (end - start) ~/ 2;

  final paragraph = end >= 2 ? t.lastIndexOf('\n\n', end - 2) : -1;
  if (paragraph >= floor) return paragraph + 2;

  for (var i = end - 1; i >= floor; i--) {
    final c = t.codeUnitAt(i);
    if (c == 0x0964 || c == 0x0965 || c == 0x0A) return i + 1;
    final isStop = c == 0x2E || c == 0x3F || c == 0x21;
    if (isStop && _isSpace(t.codeUnitAt(i + 1))) return i + 1;
  }

  for (var i = end - 1; i >= floor; i--) {
    if (_isSpace(t.codeUnitAt(i))) return i + 1;
  }

  var cut = end;
  while (cut > start + 1 && _splitsCharacter(t, cut)) {
    cut--;
  }
  return cut;
}

/// Moves an overlap start forward to the beginning of a word, or at least off
/// a dangling mark.
int _alignForward(String t, int from, int limit) {
  if (from > 0 && _isSpace(t.codeUnitAt(from - 1))) return from;
  for (var i = from; i < limit; i++) {
    if (_isSpace(t.codeUnitAt(i))) return i;
  }
  var i = from;
  while (i < limit && _splitsCharacter(t, i)) {
    i++;
  }
  return i;
}

int _skipSpace(String t, int i) {
  while (i < t.length && _isSpace(t.codeUnitAt(i))) {
    i++;
  }
  return i;
}

/// Whether a boundary at [i] would separate a character from what completes it.
bool _splitsCharacter(String t, int i) {
  if (i <= 0 || i >= t.length) return false;
  final c = t.codeUnitAt(i);
  final before = t.codeUnitAt(i - 1);
  final isLowSurrogate = c >= 0xDC00 && c <= 0xDFFF;
  final afterVirama = before == 0x094D || before == 0x0CCD;
  return isLowSurrogate || afterVirama || _isMark(c);
}

bool _isMark(int c) =>
    (c >= 0x0300 && c <= 0x036F) ||
    c == 0x200C ||
    c == 0x200D ||
    // Devanagari signs (0x093D avagraha is a letter).
    (c >= 0x0900 && c <= 0x0903) ||
    (c >= 0x093A && c <= 0x094F && c != 0x093D) ||
    (c >= 0x0951 && c <= 0x0957) ||
    (c >= 0x0962 && c <= 0x0963) ||
    // Kannada signs.
    (c >= 0x0C81 && c <= 0x0C83) ||
    c == 0x0CBC ||
    (c >= 0x0CBE && c <= 0x0CCD) ||
    (c >= 0x0CD5 && c <= 0x0CD6) ||
    (c >= 0x0CE2 && c <= 0x0CE3);

bool _isSpace(int c) =>
    c == 0x20 ||
    (c >= 0x09 && c <= 0x0D) ||
    c == 0xA0 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000;
