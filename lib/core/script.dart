enum Script { latin, devanagari, kannada }

/// Counts the letters of [text] in each script.
///
/// Spaces, punctuation, digits and the danda (shared by every Indic script)
/// are ignored. Latin includes the IAST letters used for transliteration.
Map<Script, int> countScripts(String text) {
  final counts = {for (final s in Script.values) s: 0};
  for (final c in text.codeUnits) {
    final script = _scriptOf(c);
    if (script != null) counts[script] = counts[script]! + 1;
  }
  return counts;
}

/// The script most of [text]'s letters are written in, or null if it has none.
Script? dominantScript(String text) {
  Script? best;
  var bestCount = 0;
  countScripts(text).forEach((script, count) {
    if (count > bestCount) {
      best = script;
      bestCount = count;
    }
  });
  return best;
}

/// Whether at least [minShare] of [text]'s letters are in [expected].
///
/// Used to catch an answer that drifted into the wrong script. Text with no
/// letters passes, since there is nothing to get wrong.
bool isInScript(String text, Script expected, {double minShare = 0.8}) {
  final counts = countScripts(text);
  final total = counts.values.fold(0, (a, b) => a + b);
  if (total == 0) return true;
  return counts[expected]! / total >= minShare;
}

Script? _scriptOf(int c) {
  if ((c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0xC0 && c <= 0x24F && c != 0xD7 && c != 0xF7) ||
      (c >= 0x1E00 && c <= 0x1EFF)) {
    return Script.latin;
  }
  if ((c >= 0x0900 && c <= 0x0963) ||
      (c >= 0x0970 && c <= 0x097F) ||
      (c >= 0xA8E0 && c <= 0xA8FF) ||
      (c >= 0x1CD0 && c <= 0x1CFF)) {
    return Script.devanagari;
  }
  if ((c >= 0x0C80 && c <= 0x0CE5) || (c >= 0x0CF0 && c <= 0x0CFF)) {
    return Script.kannada;
  }
  return null;
}
