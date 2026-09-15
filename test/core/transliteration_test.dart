import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/core/transliteration.dart';

void main() {
  test('transliterates a verse letter for letter', () {
    expect(
      devanagariToIast(
        'कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।\n'
        'मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥',
      ),
      "karmaṇyevādhikāraste mā phaleṣu kadācana |\n"
      "mā karmaphalaheturbhūrmā te saṅgo'stvakarmaṇi ||",
    );
  });

  test('handles anusvara, visarga, vowels, om and digits', () {
    expect(
      devanagariToIast('धर्मो रक्षति रक्षितः ।'),
      'dharmo rakṣati rakṣitaḥ |',
    );
    expect(
      devanagariToIast('ॐ श्री परमात्मने नमः'),
      'oṃ śrī paramātmane namaḥ',
    );
    expect(devanagariToIast('संयमी ऋतम् ॥ २-४७॥'), 'saṃyamī ṛtam || 2-47||');
    expect(devanagariToIast('ऐश्वर्य औषधम्'), 'aiśvarya auṣadham');
  });

  test('ignores joiners that only shape glyphs', () {
    final zwj = String.fromCharCode(0x200D);
    final zwnj = String.fromCharCode(0x200C);
    expect(devanagariToIast('श$zwj्$zwnjऋणु'), 'śṛṇu');
  });

  test('folds IAST for accent-insensitive search', () {
    expect(foldIast('Karmaṇyevādhikāraste mā'), 'karmanyevadhikarastema');
    expect(foldIast("saṅgo'stu"), 'sangostu');
  });
}
