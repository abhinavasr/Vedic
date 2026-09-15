import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/packs/build/pack_builder.dart';
import 'package:vedic/packs/build/verse_text.dart';

const sample = '''
श्रीमद्भगवद्गीता
॥ ॐ श्री परमात्मने नमः ॥
अथ प्रथमोऽध्यायः ।   अर्जुनविषादयोगः

        धृतराष्ट्र उवाच ।

धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।
मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥ १-१॥

दृष्ट्वा तु पाण्डवानीकं व्यूढं दुर्योधनस्तदा । (पाठभेदः)
आचार्यमुपसङ्गम्य राजा वचनमब्रवीत् ॥ १-२॥ (वचनमब्रवीत्)

ॐ तत्सदिति श्रीमद्भगवद्गीतासूपनिषत्सु
अर्जुनविषादयोगो नाम प्रथमोऽध्यायः ॥ १॥

अथ द्वितीयोऽध्यायः ।   साङ्ख्ययोगः

        श्रीभगवानुवाच ।

कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।
मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥ २-४७॥

साङ्ख्ययोगो नाम द्वितीयोऽध्यायः ॥ २॥

ॐ
वन्दे विष्णुं भवभयहरं सर्वलोकैकनाथम् ॥
''';

PassageSource byRef(List<PassageSource> passages, String ref) =>
    passages.singleWhere((p) => p.ref == ref);

void main() {
  test('reads chapters, speakers, verses, colophons and framing text', () {
    final passages = passagesFromVerseText(sample);
    expect(passages.map((p) => p.ref), [
      'invocation',
      '1.opening',
      '1.1.speaker',
      '1.1',
      '1.2',
      '1.colophon',
      '2.opening',
      '2.47.speaker',
      '2.47',
      '2.colophon',
      'closing',
    ]);

    final verse = byRef(passages, '1.1');
    expect(verse.kind, PassageKind.verse);
    expect(verse.label, '1.1');
    expect(
      verse.text,
      'धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।\n'
      'मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥',
    );
    expect(verse.section!.number, '1');
    expect(verse.section!.title, 'अर्जुनविषादयोगः');

    expect(byRef(passages, '1.1.speaker').text, 'धृतराष्ट्र उवाच ।');
    expect(byRef(passages, '2.47.speaker').text, 'श्रीभगवानुवाच ।');
    expect(byRef(passages, '2.47').section!.title, 'साङ्ख्ययोगः');
    expect(byRef(passages, 'invocation').section, isNull);
    expect(byRef(passages, 'closing').text, startsWith('ॐ\n'));
  });

  test('keeps variant readings out of the verse text', () {
    final verse = byRef(passagesFromVerseText(sample), '1.2');
    expect(verse.text, isNot(contains('(')));
    expect(verse.text, endsWith('वचनमब्रवीत् ॥'));
    expect(verse.renderings.map((r) => r.text), ['पाठभेदः', 'वचनमब्रवीत्']);
    expect(verse.renderings.first.kind, RenderingKind.variant);
  });

  group('rejects', () {
    void expectRejected(String text, String fragment) => expect(
      () => passagesFromVerseText(text),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains(fragment),
        ),
      ),
    );

    test('a verse numbered for another chapter', () {
      expectRejected(
        sample.replaceFirst('॥ १-२॥', '॥ २-२॥'),
        'is in chapter 1',
      );
    });

    test('verses out of order', () {
      expectRejected(sample.replaceFirst('॥ १-२॥', '॥ १-१॥'), 'out of order');
    });

    test('stray text inside a chapter', () {
      expectRejected(
        sample.replaceFirst(
          'अथ द्वितीयोऽध्यायः',
          'अधूरी पंक्ति\nअथ द्वितीयोऽध्यायः',
        ),
        'not a verse',
      );
    });

    test('text with no chapter headings', () {
      expectRejected('कर्मण्येवाधिकारस्ते ॥ २-४७॥', 'no chapter headings');
    });
  });

  test('the bundled Gita source parses completely', () {
    final file = File('content/bhagavad-gita.sa/sources/bhagavad-gita.txt');
    final passages = passagesFromVerseText(file.readAsStringSync());
    final verses = passages.where((p) => p.kind == PassageKind.verse);

    final perChapter = <String, int>{};
    for (final v in verses) {
      perChapter.update(v.section!.number, (n) => n + 1, ifAbsent: () => 1);
    }
    // Standard counts, with 13 including the unnumbered-in-some-editions 13.0.
    expect(perChapter.values, [
      47,
      72,
      43,
      42,
      29,
      47,
      30,
      28,
      34,
      42,
      55,
      20,
      35,
      27,
      20,
      24,
      28,
      78,
    ]);
    expect(passages.where((p) => p.ref.endsWith('.colophon')), hasLength(18));
    // 60 speaker lines in the file; 2 fall inside verses 1.21 and 1.28 and
    // stay part of those verses' text.
    expect(passages.where((p) => p.ref.endsWith('.speaker')), hasLength(58));
    expect(byRef(passages, '1.21').text, contains('\nअर्जुन उवाच ।\n'));
    expect(verses.expand((v) => v.renderings), hasLength(6));
    expect(byRef(passages, '2.47').text, startsWith('कर्मण्येवाधिकारस्ते'));
  });
}
