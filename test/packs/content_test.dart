import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:vedic/packs/build/verse_text.dart';
import 'package:vedic/packs/content.dart';
import 'package:vedic/packs/manifest.dart' show PackFormatException;
import 'package:vedic/packs/pack_database.dart';

Map<String, dynamic> minimal() => jsonDecode(
  File('test/fixtures/packs/content-minimal.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> firstPassage(Map<String, dynamic> json) =>
    (((json['works'] as List).first as Map)['sections'] as List)
            .first['passages']
            .first
        as Map<String, dynamic>;

void expectRejected(void Function(Map<String, dynamic> json) mutate) {
  final json = minimal();
  mutate(json);
  expect(() => PackContent.fromJson(json), throwsA(isA<PackFormatException>()));
}

void main() {
  test('reads the documented example', () {
    final content = PackContent.fromJson(minimal());
    final work = content.works.single;
    expect(work.title, 'Bhagavad Gītā');
    expect(work.titleNative, 'श्रीमद्भगवद्गीता');
    expect(work.passages.map((p) => p.ref), [
      'invocation',
      '2.47.speaker',
      '2.47',
    ]);

    final speaker = work.passages[1];
    expect(speaker.kind, PassageKind.heading);
    expect(speaker.text, 'श्रीभगवानुवाच');
    expect(speaker.renderings.single.text, 'The Blessed Lord said');

    final verse = work.passages[2];
    expect(verse.text, contains('\nमा कर्मफलहेतुर्'));
    expect(verse.section!.titles['en'], 'The Yoga of Knowledge');
    expect(verse.audio.single.durationMs, 11840);
    final translations = {
      for (final r in verse.renderings)
        if (r.kind == RenderingKind.translation) r.language: r,
    };
    expect(translations['en']!.origin, TextOrigin.human);
    expect(translations['hi']!.origin, TextOrigin.machine);
    expect(
      verse.renderings.where((r) => r.kind == RenderingKind.variant),
      hasLength(1),
    );
  });

  test('round-trips JSON, including the parsed Gita', () {
    final example = PackContent.fromJson(minimal());
    expect(
      jsonEncode(PackContent.fromJson(example.toJson()).toJson()),
      jsonEncode(example.toJson()),
    );

    final gita = PackContent(
      packId: 'bhagavad-gita.sa',
      revision: 1,
      languages: const ['sa'],
      licences: const [
        LicenceSource(
          id: 'gita-sanskrit',
          name: 'Gita',
          commercialRedistribution: true,
          attribution: 'Sanskrit text.',
        ),
      ],
      voices: const [],
      works: [
        WorkSource(
          slug: 'bhagavad-gita',
          kind: WorkKind.scripture,
          title: 'Bhagavad Gītā',
          titleNative: 'श्रीमद्भगवद्गीता',
          language: 'sa',
          script: 'Deva',
          licenceId: 'gita-sanskrit',
          passages: passagesFromVerseText(
            File('content/bhagavad-gita.sa/sources/bhagavad-gita.txt')
                .readAsStringSync(),
          ),
        ),
      ],
    );
    final json = gita.toJson();
    final back = PackContent.fromJson(jsonDecode(jsonEncode(json)));
    expect(jsonEncode(back.toJson()), jsonEncode(json));
    expect(
      back.works.single.passages.map((p) => p.ref),
      gita.works.single.passages.map((p) => p.ref),
    );
  });

  group('rejects', () {
    test('an unknown format version', () {
      expectRejected((j) => j['format_version'] = 2);
    });

    test('audio for a voice that is not listed', () {
      expectRejected(
        (j) => (firstPassage(j)['audio'] as List).first['voice'] = 'other',
      );
    });

    test('audio paths that leave the audio directory', () {
      expectRejected(
        (j) => (firstPassage(j)['audio'] as List).first['file'] = '../x.m4a',
      );
      expectRejected(
        (j) => (firstPassage(j)['audio'] as List).first['file'] = 'x.m4a',
      );
    });

    test('two translations in one language', () {
      expectRejected(
        (j) => (firstPassage(j)['translations'] as List).add({
          'language': 'en',
          'text': 'again',
          'licence': 'gita-en',
        }),
      );
    });

    test('a translation under a licence that is not listed', () {
      expectRejected(
        (j) => (firstPassage(j)['translations'] as List).first['licence'] = 'x',
      );
    });

    test('repeated refs and repeated section numbers', () {
      expectRejected((j) {
        final passages =
            (((j['works'] as List).first as Map)['sections'] as List)
                    .first['passages']
                as List;
        passages.add(jsonDecode(jsonEncode(passages.first)));
      });
      expectRejected((j) {
        final sections =
            ((j['works'] as List).first as Map)['sections'] as List;
        sections.add(jsonDecode(jsonEncode(sections.first)));
      });
    });

    test('a verse with no text, or a title missing the original language', () {
      expectRejected((j) => firstPassage(j)['lines'] = ['  ']);
      expectRejected(
        (j) => ((j['works'] as List).first as Map)['title'] = {'en': 'Only'},
      );
    });
  });

  test('builds the local database with titles, translations and audio', () {
    final dir = Directory.systemTemp.createTempSync('vedic-content-db-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'pack.sqlite');
    writePackDatabase(
      path,
      PackContent.fromJson(minimal()),
      createdAt: DateTime.utc(2026, 9, 15),
    );

    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    addTearDown(db.close);
    Object? one(String sql) => db.select(sql).first.columnAt(0);
    expect(
      one("SELECT title FROM section_titles WHERE language = 'en'"),
      'The Yoga of Knowledge',
    );
    expect(
      one("SELECT title FROM work_titles WHERE language = 'sa'"),
      'श्रीमद्भगवद्गीता',
    );
    expect(
      one(
        "SELECT origin FROM renderings WHERE language = 'hi' "
        "AND kind = 'translation' AND passage_id = "
        "(SELECT id FROM passages WHERE ref = '2.47')",
      ),
      'machine',
    );
    expect(one('SELECT duration_ms FROM audio'), 11840);
    expect(one('SELECT style FROM voices'), 'chant');
    expect(one("SELECT count(*) FROM passages WHERE section_id IS NULL"), 1);
  });
}
