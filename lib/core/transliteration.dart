// Devanagari to IAST, letter for letter as written: no sandhi splitting.
// Deterministic and rule-based (roadmap Phase 2), never ML.

const _consonants = {
  'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ṅ', //
  'च': 'c', 'छ': 'ch', 'ज': 'j', 'झ': 'jh', 'ञ': 'ñ',
  'ट': 'ṭ', 'ठ': 'ṭh', 'ड': 'ḍ', 'ढ': 'ḍh', 'ण': 'ṇ',
  'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
  'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm',
  'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'ळ': 'ḷ',
  'श': 'ś', 'ष': 'ṣ', 'स': 's', 'ह': 'h',
};

const _vowels = {
  'अ': 'a', 'आ': 'ā', 'इ': 'i', 'ई': 'ī', 'उ': 'u', 'ऊ': 'ū', //
  'ऋ': 'ṛ', 'ॠ': 'ṝ', 'ऌ': 'ḷ', 'ॡ': 'ḹ',
  'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au',
};

const _vowelSigns = {
  'ा': 'ā', 'ि': 'i', 'ी': 'ī', 'ु': 'u', 'ू': 'ū', //
  'ृ': 'ṛ', 'ॄ': 'ṝ', 'ॢ': 'ḷ', 'ॣ': 'ḹ',
  'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au',
};

const _others = {
  'ं': 'ṃ', 'ः': 'ḥ', 'ँ': 'm̐', 'ऽ': "'", 'ॐ': 'oṃ', //
  '।': '|', '॥': '||',
  '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
  '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
};

const _virama = '्';

/// Ignored: nukta, and the joiners that only affect glyph shaping.
const _silent = {'़', '\u200C', '\u200D'};

String devanagariToIast(String text) {
  final out = StringBuffer();
  var inherentA = false;
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (_silent.contains(ch)) continue;

    final sign = _vowelSigns[ch];
    if (inherentA && sign != null) {
      out.write(sign);
      inherentA = false;
      continue;
    }
    if (inherentA && ch == _virama) {
      inherentA = false;
      continue;
    }
    if (inherentA) {
      out.write('a');
      inherentA = false;
    }

    final consonant = _consonants[ch];
    if (consonant != null) {
      out.write(consonant);
      inherentA = true;
      continue;
    }
    out.write(_vowels[ch] ?? _others[ch] ?? (ch == _virama ? '' : ch));
  }
  if (inherentA) out.write('a');
  return out.toString();
}

const _folds = {
  'ā': 'a', 'ī': 'i', 'ū': 'u', 'ṛ': 'r', 'ṝ': 'r', 'ḷ': 'l', 'ḹ': 'l', //
  'ṅ': 'n', 'ñ': 'n', 'ṭ': 't', 'ḍ': 'd', 'ṇ': 'n', 'ś': 's', 'ṣ': 's',
  'ṃ': 'm', 'ḥ': 'h',
};

/// Lowercase, diacritic-free, space- and punctuation-free form of IAST or
/// plain Latin text, so "karmanye" matches "karmaṇye".
String foldIast(String text) {
  final out = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final folded = _folds[ch] ?? ch;
    if (RegExp(r'[a-z0-9]').hasMatch(folded)) out.write(folded);
  }
  return out.toString();
}
