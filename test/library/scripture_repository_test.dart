import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vedic/library/scripture_repository.dart';
import 'package:vedic/packs/build/pack_builder.dart';
import 'package:vedic/packs/build/verse_text.dart';
import 'package:vedic/packs/pack_store.dart';
import 'package:vedic/packs/signature.dart';

const verses = '''
॥ ॐ श्री परमात्मने नमः ॥
अथ प्रथमोऽध्यायः ।   अर्जुनविषादयोगः
        धृतराष्ट्र उवाच ।
धर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।
मामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥ १-१॥
दृष्ट्वा तु पाण्डवानीकं व्यूढं दुर्योधनस्तदा ।
आचार्यमुपसङ्गम्य राजा वचनमब्रवीत् ॥ १-२॥ (पाठभेदः)
अर्जुनविषादयोगो नाम प्रथमोऽध्यायः ॥ १॥
अथ द्वितीयोऽध्यायः ।   साङ्ख्ययोगः
कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।
मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥ २-४७॥
''';

void main() {
  late Directory temp;
  late ScriptureRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vedic-repo-test-');
    final seed = List<int>.filled(32, 11);
    final built = await buildPack(
      PackSource(
        packId: 'mini.gita',
        revision: 1,
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 15),
        minAppBuild: 1,
        title: const {'sa': 'गीता'},
        languages: const ['sa'],
        licences: const [
          LicenceSource(
            id: 'test',
            name: 'Test',
            commercialRedistribution: true,
            attribution: 'Test text',
          ),
        ],
        works: [
          WorkSource(
            slug: 'gita',
            kind: WorkKind.scripture,
            title: 'Gita',
            titleNative: 'गीता',
            language: 'sa',
            licenceId: 'test',
            passages: passagesFromVerseText(verses),
          ),
        ],
      ),
      outputRoot: Directory(p.join(temp.path, 'out')),
      signer: PackSigner(keyId: 'test', seed: seed),
    );
    final store = PackStore(
      root: Directory(p.join(temp.path, 'store')),
      trustedKeys: [
        PublisherKey(keyId: 'test', publicKey: await publicKeyFromSeed(seed)),
      ],
      appBuild: 1,
    );
    await store.install(built.directory, origin: PackOrigin.bundled);
    repository = ScriptureRepository(store);
  });

  tearDown(() => temp.delete(recursive: true));

  test('lists works with their verse counts', () {
    final work = repository.works().single;
    expect(work.titleNative, 'गीता');
    expect(work.verseCount, 3);
  });

  test('lists chapters, then text outside any chapter', () {
    final sections = repository.sections(repository.works().single);
    expect(sections.map((s) => s.number), ['1', '2', null]);
    expect(sections.first.title, 'अर्जुनविषादयोगः');
    expect(sections.map((s) => s.verseCount), [2, 1, 0]);
  });

  test('reads a chapter in order with speakers and variants', () {
    final work = repository.works().single;
    final chapterOne = repository.sections(work).first;
    final passages = repository.passages(work, chapterOne);
    expect(passages.map((p) => p.type), [
      PassageType.heading,
      PassageType.speaker,
      PassageType.verse,
      PassageType.verse,
      PassageType.prose,
    ]);
    expect(passages[3].label, '1.2');
    expect(passages[3].variants, ['पाठभेदः']);
    expect(passages[2].variants, isEmpty);
  });

  test('verse of the day is stable within a day and varies across days', () {
    final day = DateTime(2026, 9, 15);
    final pick = repository.verseOfTheDay(day)!;
    expect(pick.verse.type, PassageType.verse);
    expect(['1.1', '1.2', '2.47'], contains(pick.verse.ref));
    expect(
      repository.verseOfTheDay(DateTime(2026, 9, 15, 23))!.verse.ref,
      pick.verse.ref,
    );

    final refs = {
      for (var i = 0; i < 30; i++)
        repository.verseOfTheDay(day.add(Duration(days: i)))!.verse.ref,
    };
    expect(refs.length, greaterThan(1));
  });

  test('searches verses in Devanagari and in plain Latin', () {
    expect(repository.searchVerses('कदाचन').single.verse.ref, '2.47');
    expect(repository.searchVerses('karmanye').single.verse.ref, '2.47');
    expect(repository.searchVerses('Dharmakshetre'), isEmpty);
    expect(repository.searchVerses('dharmaksetre').single.verse.ref, '1.1');
  });

  test('reads the text outside any chapter', () {
    final work = repository.works().single;
    final other = repository.sections(work).last;
    expect(repository.passages(work, other).single.ref, 'invocation');
  });
}
