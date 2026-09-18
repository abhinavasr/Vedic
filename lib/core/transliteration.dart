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
const _silent = {
  '़',
  '\u200C',
  '\u200D',
  // Vedic tone marks: anudātta, svarita and the rest. They are dropped rather
  // than transliterated, because the conventions for writing them in Latin
  // disagree — one edition's acute is another's grave — and passing them
  // through untouched was worse than either: it put Devanagari combining
  // marks inside Latin words, so the Rigveda transliterated to "a॒gnimī॑ḷe".
  // A pack that ships its own accented transliteration is used in preference
  // to this, and the accents are always there in the Devanagari above it.
  '\u0951',
  '\u0952',
  '\u1CD0',
  '\u1CD1',
  '\u1CD2',
  '\u1CD3',
  '\u1CD4',
  '\u1CD5',
  '\u1CD6',
  '\u1CD7',
  '\u1CD8',
  '\u1CD9',
  '\u1CDA',
  '\u1CDB',
  '\u1CDC',
  '\u1CDD',
  '\u1CDE',
  '\u1CDF',
  '\u1CE0',
  '\u1CE1',
  '\uA8E0',
  '\uA8E1',
  '\uA8E2',
  '\uA8E3',
};

/// A colon standing in for a visarga.
///
/// The Rigveda sources type visarga as an ASCII colon about as often as they
/// use "ः" — "अ॒द्रुह॑:" rather than "अ॒द्रुहः". Left alone it is not a mark at
/// all, so the "ḥ" simply disappears and "jaritāraḥ" transliterates to
/// "jaritāra". Only a colon that follows Devanagari is rewritten, so a colon
/// doing its own job in a title or a note survives.
final _colonVisarga = RegExp(
  r'(?<=[\u0900-\u097F\u1CD0-\u1CFF\uA8E0-\uA8FF]):',
);

/// A numeral used as an accent mark rather than as a number.
///
/// An independent svarita is written as a digit inside the word — "म॒क्ष्वि१त्था",
/// "रा॒यो॒३ऽवनि॑:" — so passing it through put arabic numerals in the middle of
/// Latin words: "makṣvi1tthā". A digit that follows a letter or a mark belongs
/// to the word and is dropped with the other accents; a digit standing on its
/// own is a number and is kept.
final _svaritaDigit = RegExp(
  r'(?<=[\u0900-\u094F\u0951-\u0963\u0971-\u097F\u1CD0-\u1CFF\uA8E0-\uA8FF])'
  r'[\u0966-\u096F]',
);

String devanagariToIast(String text) {
  text = text
      .replaceAll(_colonVisarga, '\u0903')
      .replaceAll(_svaritaDigit, '');
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

/// Accent marks, written on their own or built into the letter.
const _accentMarks = {'̀', '́', '̀', '́'};
const _accentedVowels = {
  'á': 'a', 'à': 'a', 'é': 'e', 'è': 'e', 'í': 'i', //
  'ì': 'i', 'ó': 'o', 'ò': 'o', 'ú': 'u', 'ù': 'u',
};

/// The marks below a letter, which some editions write as combining marks and
/// others as one character. "r̥" and "ṛ" are the same sound.
const _belowMarks = {
  'r̥': 'ṛ', 'ṛ': 'ṛ', 'l̥': 'ḷ', 'ḷ': 'ḷ', //
  'ṭ': 'ṭ', 'ḍ': 'ḍ', 'ṇ': 'ṇ', 'ṣ': 'ṣ',
  'ḥ': 'ḥ', 'ṃ': 'ṃ', 'ṅ': 'ṅ', 'ś': 'ś',
};

/// A transliteration reduced to the letters it claims the text has.
///
/// Two good IAST renderings of one verse differ: one marks the Vedic accents,
/// another splits the sandhi into words, a third punctuates. None of that
/// changes which sounds are in the verse, so removing all of it should leave
/// two identical strings — and when it does not, one of them has misread the
/// text.
///
/// Vowel length and the marks below a letter are kept, unlike [foldIast],
/// because that is where a misreading hides: "ratnadhatamam" for
/// "ratnadhātamam" is a different word, and folding the two together is how
/// the error survives review.
String iastSkeleton(String text) {
  var plain = text;
  for (final entry in _belowMarks.entries) {
    plain = plain.replaceAll(entry.key, entry.value);
  }
  for (final mark in _accentMarks) {
    plain = plain.replaceAll(mark, '');
  }
  for (final entry in _accentedVowels.entries) {
    plain = plain.replaceAll(entry.key, entry.value);
  }
  return plain.toLowerCase().replaceAll(
    RegExp('[^a-zāīūṛṝḷḹṅñṭḍṇśṣṃḥm̐]'),
    '',
  );
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
