enum Script {
  latin,
  devanagari,
  bengali,
  gurmukhi,
  gujarati,
  odia,
  tamil,
  telugu,
  kannada,
  malayalam,
}

/// Where each Indic script's 128-code-point block starts.
///
/// They are laid out alike, so the offsets inside a block mean the same thing
/// in all of them: `+0x64`/`+0x65` are the danda, which every Indic script
/// shares and none is identified by, and `+0x66`–`+0x6F` are its digits.
const Map<Script, int> _indicBlocks = {
  Script.devanagari: 0x0900,
  Script.bengali: 0x0980,
  Script.gurmukhi: 0x0A00,
  Script.gujarati: 0x0A80,
  Script.odia: 0x0B00,
  Script.tamil: 0x0B80,
  Script.telugu: 0x0C00,
  Script.kannada: 0x0C80,
  Script.malayalam: 0x0D00,
};

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
  // Devanagari Extended and the Vedic Extensions, which sit apart from the
  // main block.
  if ((c >= 0xA8E0 && c <= 0xA8FF) || (c >= 0x1CD0 && c <= 0x1CFF)) {
    return Script.devanagari;
  }
  for (final entry in _indicBlocks.entries) {
    final base = entry.value;
    if (c < base || c > base + 0x7F) continue;
    final offset = c - base;
    // The danda and the digits say nothing about which script this is.
    if (offset == 0x64 || offset == 0x65) return null;
    if (offset >= 0x66 && offset <= 0x6F) return null;
    return entry.key;
  }
  return null;
}
