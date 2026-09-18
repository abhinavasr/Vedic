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

  test('reads a colon after Devanagari as a visarga', () {
    // The Rigveda sources type visarga as an ASCII colon as often as "ः".
    // Without this the "ḥ" disappears and jaritāraḥ reads "jaritāra".
    expect(devanagariToIast('अ॒द्रुह॑:'), 'adruhaḥ');
    expect(devanagariToIast('जरि॒तार॑: सु॒तसो॑मा अह॒र्विद॑:'),
        'jaritāraḥ sutasomā aharvidaḥ');
    // The same colon doing its own job is left alone.
    expect(devanagariToIast('note: श्री'), 'note: śrī');
  });

  test('drops a numeral used to mark an independent svarita', () {
    // The digit sits inside the word and is an accent, not a number;
    // passing it through gave "makṣvi1tthā".
    expect(devanagariToIast('म॒क्ष्वि१त्था'), 'makṣvitthā');
    expect(devanagariToIast('रा॒यो॒३ऽवनि॑:'), "rāyo'vaniḥ");
    // A numeral standing on its own is still a number.
    expect(devanagariToIast('॥१२॥'), '||12||');
    expect(devanagariToIast('९ मेधातिथिः'), '9 medhātithiḥ');
  });

  test('the skeleton keeps what a misreading changes', () {
    // Accents, word division and punctuation are the two editions
    // disagreeing; they do not change which sounds are in the verse.
    expect(
      iastSkeleton('agním īḷe puróhitaṃ'),
      iastSkeleton('agnimīḷe purohitaṃ'),
    );
    expect(iastSkeleton('ṛtásya'), iastSkeleton('r̥tásya'));
    // Vowel length does. This is the error that survives review, because
    // "ratnadhatamam" reads perfectly well and is a different word — so
    // unlike foldIast, the skeleton must keep the two apart.
    expect(
      iastSkeleton('ratnadhátamam'),
      isNot(iastSkeleton('ratnadhātamam')),
    );
    expect(iastSkeleton('anāvadyair'), isNot(iastSkeleton('anavadyair')));
    expect(iastSkeleton('deva'), isNot(iastSkeleton('devā')));
  });

  test('folds IAST for accent-insensitive search', () {
    expect(foldIast('Karmaṇyevādhikāraste mā'), 'karmanyevadhikarastema');
    expect(foldIast("saṅgo'stu"), 'sangostu');
  });
}
