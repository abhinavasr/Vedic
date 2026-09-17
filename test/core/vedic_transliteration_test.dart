import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/core/transliteration.dart';

void main() {
  test('Vedic accents do not leak into the Latin', () {
    // RV 1.1.1. The bug this guards: the tone marks were passed through
    // untouched, so the transliteration came out as "a॒gnimī॑ḷe" — Devanagari
    // combining marks sitting inside Latin words.
    const accented = 'अ॒ग्निमी॑ळे पु॒रोहि॑तं य॒ज्ञस्य॑ दे॒वमृ॒त्विज॑म्';
    final iast = devanagariToIast(accented);
    expect(iast, 'agnimīḷe purohitaṃ yajñasya devamṛtvijam');
    // IAST is full of Latin Extended — ī, ṃ, ñ, ḷ — so "no high codepoints"
    // is the wrong test. What must not survive is Devanagari itself, and the
    // Vedic extensions the tone marks come from.
    for (final rune in iast.runes) {
      final devanagari = rune >= 0x0900 && rune <= 0x097F;
      final vedic = rune >= 0x1CD0 && rune <= 0x1CFF;
      final vedicExtra = rune >= 0xA8E0 && rune <= 0xA8FF;
      expect(
        devanagari || vedic || vedicExtra,
        isFalse,
        reason: 'U+${rune.toRadixString(16)} survived in "$iast"',
      );
    }
  });

  test('the unaccented text is unchanged by the fix', () {
    expect(
      devanagariToIast('कर्मण्येवाधिकारस्ते'),
      'karmaṇyevādhikāraste',
    );
  });
}
