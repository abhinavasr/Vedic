import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vedic/library/quote_sources.dart';
import 'package:vedic/library/scripture_repository.dart';
import 'package:vedic/packs/build/pack_builder.dart';
import 'package:vedic/packs/pack_store.dart';
import 'package:vedic/packs/signature.dart';

late Directory temp;
late ScriptureRepository repository;

Future<void> installFixture() async {
  final seed = List<int>.filled(32, 21);
  final content = PackContent.fromJson(
    jsonDecode(
      File('test/fixtures/packs/content-minimal.json').readAsStringSync(),
    ),
  );
  final built = await buildPack(
    PackSource(
      packId: content.packId,
      revision: content.revision,
      kind: 'text',
      createdAt: DateTime.utc(2026, 9, 16),
      minAppBuild: 1,
      title: const {'en': 'Bhagavad Gita'},
      languages: content.languages,
      licences: content.licences,
      voices: content.voices,
      works: content.works,
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
}

void main() {
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vedic-quotes-');
    await installFixture();
  });
  tearDown(() => temp.delete(recursive: true));

  test('the Gita is where the day\'s verse comes from until asked otherwise',
      () {
    final sources = QuoteSources(repository.store);
    final gita = repository.works().single;

    expect(sources.chosen, isFalse);
    expect(sources.includes(gita), isTrue);
    expect(repository.verseOfTheDay(DateTime(2026, 9, 19)), isNotNull);
  });

  test('turning a book off is a choice, and leaves the day without one', () {
    final sources = QuoteSources(repository.store);
    final all = repository.works();
    final gita = all.single;

    sources.set(gita, on: false, all: all);

    expect(sources.chosen, isTrue, reason: 'the reader has now chosen');
    expect(sources.includes(gita), isFalse);
    // Respected rather than quietly overridden: turning everything off and
    // being shown a verse anyway would make the setting look broken.
    expect(repository.verseOfTheDay(DateTime(2026, 9, 19)), isNull);
  });

  test('turning another book on does not turn the Gita off', () {
    final sources = QuoteSources(repository.store);
    final all = repository.works();
    final gita = all.single;

    // Standing in for a second installed book: the first explicit choice
    // must carry the default forward rather than replace it.
    sources.set(gita, on: true, all: all);

    expect(sources.selected, contains(QuoteSources.keyFor(gita)));
    expect(sources.includes(gita), isTrue);
  });

  test('the Gita is recognised however the pack spells it', () {
    // Packs have called it "gita" and "bhagavad-gita", inside a pack called
    // "bhagavad-gita.sa". A default matching one spelling exactly left the
    // reader with no verse of the day and nothing on screen to explain it.
    final gita = repository.works().single;
    expect(QuoteSources.isDefault(gita), isTrue);
  });

  test('a choice survives being read back', () {
    final sources = QuoteSources(repository.store);
    final all = repository.works();
    sources.set(all.single, on: false, all: all);

    expect(QuoteSources(repository.store).selected, isEmpty);
    expect(QuoteSources(repository.store).chosen, isTrue);
  });
}
