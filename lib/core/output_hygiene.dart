/// Control tokens the runtime can leak into visible text.
const List<String> _leakedTokens = [
  '<start_of_turn>',
  '<end_of_turn>',
  '<eos>',
  '<bos>',
  '<pad>',
];

/// Removes leaked control tokens and tidies whitespace in model output.
String cleanOutput(String raw) {
  var s = raw.replaceAll('\r\n', '\n');
  for (final token in _leakedTokens) {
    s = s.replaceAll(token, '');
  }
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Detects degenerate generation, such as one character or phrase repeated
/// forever.
///
/// Returns how many leading characters of [visible] to keep: everything
/// before the loop plus one copy of the repeated unit. Returns null while the
/// text looks healthy.
///
/// Run it on the visible answer only, never on the reasoning, which
/// legitimately repeats itself.
int? detectRunaway(
  String visible, {
  int maxChars = 6000,
  int maxCharRun = 40,
  int maxUnitLength = 64,
  int maxUnitRepeats = 8,
  int minRepeatSpan = 120,
}) {
  final n = visible.length;
  if (n > maxChars) return maxChars;

  for (var unit = 1; unit <= maxUnitLength && unit * 2 <= n; unit++) {
    var repeats = 1;
    while ((repeats + 1) * unit <= n &&
        _sameSpan(visible, n - unit, n - (repeats + 1) * unit, unit)) {
      repeats++;
    }
    final isLoop = unit == 1
        ? repeats >= maxCharRun
        : repeats >= maxUnitRepeats && repeats * unit >= minRepeatSpan;
    if (isLoop) return n - (repeats - 1) * unit;
  }
  return null;
}

bool _sameSpan(String s, int a, int b, int length) {
  for (var i = 0; i < length; i++) {
    if (s.codeUnitAt(a + i) != s.codeUnitAt(b + i)) return false;
  }
  return true;
}
