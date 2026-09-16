import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vedic/library/scripture_repository.dart';
import 'package:vedic/packs/build/pack_builder.dart';
import 'package:vedic/packs/pack_store.dart';
import 'package:vedic/packs/signature.dart';
import 'package:vedic/ui/verse_reader.dart';

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

Future<void> openReader(WidgetTester tester) async {
  // A phone-sized window, so a verse and its notes are all built.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final work = repository.works().single;
  final chapter = repository.sections(work).first;
  await tester.pumpWidget(
    MaterialApp(
      home: VerseReaderScreen(
        repository: repository,
        work: work,
        section: chapter,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vedic-reader-test-');
    await installFixture();
  });
  tearDown(() => temp.delete(recursive: true));

  testWidgets('shows the verse, its meaning, explanation and takeaways', (
    tester,
  ) async {
    await openReader(tester);

    expect(find.text('Verse 2.47'), findsOneWidget);
    expect(find.text('Chapter 2  ·  साङ्ख्ययोगः'), findsOneWidget);
    expect(find.text('श्रीभगवानुवाच'), findsOneWidget);
    expect(find.textContaining('कर्मण्येवाधिकारस्ते'), findsOneWidget);
    expect(
      find.textContaining('karmaṇyevādhikāraste'),
      findsOneWidget,
      reason: 'transliterated by the app when the pack has none',
    );
    expect(find.text('Test English rendering of 2.47.'), findsOneWidget);
    expect(find.text('Test explanation of 2.47.'), findsOneWidget);
    expect(find.text('First takeaway.'), findsOneWidget);
    expect(find.text('Meter: anuṣṭubh'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('the toggle hides the Sanskrit or the meaning', (tester) async {
    await openReader(tester);

    await tester.tap(find.byKey(const ValueKey('show-meaning')));
    await tester.pumpAndSettle();
    expect(find.textContaining('कर्मण्येवाधिकारस्ते'), findsNothing);
    expect(find.text('Test English rendering of 2.47.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('show-sanskrit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('कर्मण्येवाधिकारस्ते'), findsOneWidget);
    expect(find.text('Test English rendering of 2.47.'), findsNothing);
  });

  testWidgets('moving on says when a verse has no translation yet', (
    tester,
  ) async {
    await openReader(tester);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('Verse 2.48'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(
      find.text('No translation is installed for this verse yet.'),
      findsOneWidget,
    );
  });

  testWidgets('offers an on-device translation only where one is missing', (
    tester,
  ) async {
    await openReader(tester);

    // 2.47's English is published, so it is settled. Its Hindi is marked
    // machine in the pack itself, so it is offered again.
    expect(find.byKey(const ValueKey('translate-en')), findsNothing);
    expect(find.byKey(const ValueKey('translate-hi')), findsOneWidget);
    expect(
      find.textContaining('Translate again on this phone'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('translate-en')), findsOneWidget);
    expect(find.byKey(const ValueKey('translate-hi')), findsOneWidget);
    // Nothing has been translated here at all, so it is not "again".
    expect(find.textContaining('Translate on this phone'), findsOneWidget);
  });

  testWidgets('shows a translation this phone already made, labelled', (
    tester,
  ) async {
    repository.store.saveLocalTranslation(
      LocalTranslation(
        packId: 'bhagavad-gita',
        workSlug: 'bhagavad-gita',
        ref: '2.48',
        language: 'en',
        text: 'Steadfast in yoga, do your work.',
        model: 'gemma-4-E2B-it.litertlm',
        createdAt: DateTime.utc(2026, 9, 16),
      ),
    );
    await openReader(tester);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('Steadfast in yoga, do your work.'), findsOneWidget);
    expect(find.text('Machine translation'), findsOneWidget);

    // A machine translation is not coverage: it can be wrong, and when it is
    // the reader needs the button that made it rather than a dead end.
    expect(find.byKey(const ValueKey('translate-en')), findsOneWidget);
    expect(
      find.textContaining('Translate again on this phone'),
      findsOneWidget,
    );
  });

  testWidgets('remembers the verse reached and bookmarks it', (tester) async {
    await openReader(tester);
    final store = repository.store;
    expect(store.lastRead('bhagavad-gita', 'bhagavad-gita'), '2.47');

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(store.lastRead('bhagavad-gita', 'bhagavad-gita'), '2.48');

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();
    expect(
      store.isBookmarked('bhagavad-gita', 'bhagavad-gita', '2.48'),
      isTrue,
    );
    expect(store.bookmarks().single.ref, '2.48');

    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();
    expect(store.bookmarks(), isEmpty);
  });
}
