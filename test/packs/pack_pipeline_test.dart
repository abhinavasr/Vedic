import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:vedic/packs/build/pack_builder.dart';
import 'package:vedic/packs/build/text_sources.dart';
import 'package:vedic/packs/bundled_install.dart';
import 'package:vedic/packs/manifest.dart';
import 'package:vedic/packs/pack_store.dart';
import 'package:vedic/packs/payload_codec.dart'
    show PayloadAuthenticationException;
import 'package:vedic/packs/signature.dart';
import 'package:yaml/yaml.dart';

const fixture = 'test/fixtures/packs/sample.docs';
final seed = List<int>.generate(32, (i) => i * 3 % 256);
final signer = PackSigner(keyId: 'test-key', seed: seed);

late Directory temp;
late List<PublisherKey> trusted;

Map<String, Object?> config({
  int revision = 1,
  Map<String, Object?> overrides = const {},
}) {
  final yaml = File(p.join(fixture, 'pack.yaml')).readAsStringSync();
  final c = jsonDecode(jsonEncode(loadYaml(yaml))) as Map<String, Object?>;
  return {...c, 'revision': revision, ...overrides};
}

Map<String, List<PassageSource>> fixturePassages() => {
  'about-packs': passagesFromPlainText(
    File(p.join(fixture, 'sources', 'about-packs.txt')).readAsStringSync(),
  ),
};

Future<BuiltPack> build({
  int revision = 1,
  List<int>? contentKey,
  Map<String, Object?> overrides = const {},
}) => buildPack(
  PackSource.fromConfig(
    config(revision: revision, overrides: overrides),
    passagesBySlug: fixturePassages(),
  ),
  outputRoot: Directory(p.join(temp.path, 'out')),
  signer: signer,
  contentKey: contentKey,
);

PackStore store({int appBuild = 1}) => PackStore(
  root: Directory(p.join(temp.path, 'store')),
  trustedKeys: trusted,
  appBuild: appBuild,
);

T query<T>(PackStore s, T Function(Database db) body) {
  final db = s.openReadOnly(s.installed().single);
  try {
    return body(db);
  } finally {
    db.close();
  }
}

int count(Database db, String table) =>
    db.select('SELECT count(*) AS n FROM $table').first['n'] as int;

String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

void main() {
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vedic-pack-test-');
    trusted = [
      PublisherKey(keyId: 'test-key', publicKey: await publicKeyFromSeed(seed)),
    ];
  });
  tearDown(() => temp.delete(recursive: true));

  group('text sources', () {
    test('plain text gives one passage per paragraph', () {
      final passages = passagesFromPlainText(
        'First line\nwraps here.\r\n\r\n  \nSecond.\n',
      );
      expect(passages.map((p) => p.text), [
        'First line wraps here.',
        'Second.',
      ]);
      expect(passages.map((p) => p.ref), ['para1', 'para2']);
    });

    test('PDF pages keep their numbers when blank pages are skipped', () {
      final passages = passagesFromPages([
        'One',
        '  \n ',
        'Three with hyphen-\nated word',
      ]);
      expect(passages.map((p) => p.ref), ['p1', 'p3']);
      expect(passages.last.text, 'Three with hyphenated word');
    });
  });

  group('build and install', () {
    test('a bundled pack installs and its content can be read', () async {
      final built = await build();
      expect(built.manifest.payload.isEncrypted, isFalse);

      final s = store();
      expect(
        await s.install(built.directory, origin: PackOrigin.bundled),
        isA<Installed>(),
      );
      query(s, (db) {
        expect(count(db, 'works'), 1);
        expect(count(db, 'passages'), 4);
        expect(count(db, 'chunks'), greaterThan(0));
        final meta = {
          for (final r in db.select('SELECT key, value FROM pack_meta'))
            r['key']: r['value'],
        };
        expect(meta['pack_id'], 'sample.docs');
        expect(
          db
              .select("SELECT text FROM passages WHERE ref = 'para4'")
              .first['text'],
          startsWith('यह एक परीक्षण'),
        );
        expect(
          db.select('SELECT attribution FROM licences').first['attribution'],
          contains('test suite'),
        );
        for (final row in db.select(
          'SELECT f.ordinal AS first, l.ordinal AS last FROM chunks c '
          'JOIN passages f ON f.id = c.first_passage_id '
          'JOIN passages l ON l.id = c.last_passage_id',
        )) {
          expect(row['first'] as int, lessThanOrEqualTo(row['last'] as int));
        }
      });
      expect(s.tempDirectory.listSync(), isEmpty);
    });

    test('a revision installs once; a newer one replaces it', () async {
      final s = store();
      final first = await build();
      await s.install(first.directory, origin: PackOrigin.bundled);
      expect(
        await s.install(first.directory, origin: PackOrigin.bundled),
        isA<AlreadyInstalled>(),
      );

      final second = await build(revision: 2);
      expect(
        await s.install(second.directory, origin: PackOrigin.bundled),
        isA<Installed>(),
      );
      expect(s.installed().single.revision, 2);
      expect(s.installed().single.file, p.join('sample.docs', '2.sqlite'));
      final root = p.join(temp.path, 'store', 'sample.docs');
      expect(File(p.join(root, '1.sqlite')).existsSync(), isFalse);
      expect(File(p.join(root, '2.sqlite')).existsSync(), isTrue);
    });

    test('published revisions are immutable', () async {
      await build();
      await expectLater(build(), throwsA(isA<FileSystemException>()));
    });

    test(
      'an encrypted pack installs only with the right content key',
      () async {
        final cek = List<int>.generate(32, (i) => 200 - i);
        final built = await build(contentKey: cek);
        expect(built.manifest.payload.isEncrypted, isTrue);
        final s = store();

        await expectLater(
          s.install(
            built.directory,
            origin: PackOrigin.downloaded,
            contentKey: (_) async => List.filled(32, 1),
          ),
          throwsA(isA<PayloadAuthenticationException>()),
        );
        expect(s.installed(), isEmpty);
        expect(s.tempDirectory.listSync(), isEmpty);

        await expectLater(
          s.install(built.directory, origin: PackOrigin.downloaded),
          throwsArgumentError,
        );
        await expectLater(
          s.install(built.directory, origin: PackOrigin.bundled),
          throwsA(isA<PackFormatException>()),
        );

        final result = await s.install(
          built.directory,
          origin: PackOrigin.downloaded,
          contentKey: (manifest) async {
            expect(manifest.packId, 'sample.docs');
            return cek;
          },
        );
        expect(result, isA<Installed>());
        query(s, (db) => expect(count(db, 'passages'), 4));
      },
    );
  });

  group('refuses', () {
    test('a payload changed after signing', () async {
      final built = await build();
      final payload = File(p.join(built.directory.path, 'payload.bin'));
      final bytes = await payload.readAsBytes();
      bytes[bytes.length ~/ 2] ^= 1;
      await payload.writeAsBytes(bytes);
      await expectLater(
        store().install(built.directory, origin: PackOrigin.bundled),
        throwsA(isA<PackIntegrityException>()),
      );
    });

    test('a manifest changed after signing', () async {
      final built = await build();
      final manifest = File(p.join(built.directory.path, 'manifest.json'));
      await manifest.writeAsString(
        (await manifest.readAsString()).replaceFirst(
          '"revision": 1',
          '"revision": 9',
        ),
      );
      await expectLater(
        store().install(built.directory, origin: PackOrigin.bundled),
        throwsA(isA<SignatureException>()),
      );
    });

    test('a pack signed by a key the app does not trust', () async {
      final built = await buildPack(
        PackSource.fromConfig(config(), passagesBySlug: fixturePassages()),
        outputRoot: Directory(p.join(temp.path, 'out')),
        signer: PackSigner(keyId: 'test-key', seed: List.filled(32, 5)),
      );
      await expectLater(
        store().install(built.directory, origin: PackOrigin.bundled),
        throwsA(isA<SignatureException>()),
      );
    });

    test('a pack built for a newer app', () async {
      final built = await build(overrides: {'min_app_build': 5});
      expect(
        await store().install(built.directory, origin: PackOrigin.bundled),
        isA<NeedsAppUpdate>(),
      );
      expect(store().installed(), isEmpty);
    });

    test('to build content not cleared for commercial use', () async {
      final c = config();
      final licences = c['licences'] as List<Object?>;
      (licences.first as Map<String, Object?>)['commercial_redistribution'] =
          false;
      await expectLater(
        buildPack(
          PackSource.fromConfig(c, passagesBySlug: fixturePassages()),
          outputRoot: Directory(p.join(temp.path, 'out')),
          signer: signer,
        ),
        throwsA(isA<PackFormatException>()),
      );
    });

    test('a signed payload that is not a pack database', () async {
      final junk = utf8.encode('not a database ' * 100);
      final compressed = ZLibCodec().encode(junk);
      final json = (await build()).manifest.toJson();
      (json['payload'] as Map<String, Object?>)
        ..['size'] = compressed.length
        ..['sha256'] = sha256Hex(compressed)
        ..['plaintext_size'] = junk.length
        ..['plaintext_sha256'] = sha256Hex(junk);
      final manifestBytes = utf8.encode(jsonEncode(json));

      final dir = await Directory(p.join(temp.path, 'junk')).create();
      await File(p.join(dir.path, 'manifest.json')).writeAsBytes(manifestBytes);
      await File(p.join(dir.path, 'manifest.json.sig')).writeAsBytes(
        await signDetached(bytes: manifestBytes, seed: seed, keyId: 'test-key'),
      );
      await File(p.join(dir.path, 'payload.bin')).writeAsBytes(compressed);

      await expectLater(
        store().install(dir, origin: PackOrigin.bundled),
        throwsA(isA<PackIntegrityException>()),
      );
      expect(store().installed(), isEmpty);
    });
  });

  group('bundled assets', () {
    test('installs bundled packs, then skips them without copying', () async {
      final assets = Directory(p.join(temp.path, 'assets', 'packs'));
      await copyToBundledAssets(await build(), assets);
      final files = {
        for (final f in assets.listSync().whereType<File>())
          'assets/packs/${p.basename(f.path)}': f,
      };
      var loads = 0;
      Future<List<int>> load(String key) {
        loads++;
        return files[key]!.readAsBytes();
      }

      final s = store();
      final first = await installBundledPacks(
        s,
        assetKeys: [...files.keys, 'assets/fonts/other.ttf'],
        load: load,
      );
      expect(first.single, isA<Installed>());

      loads = 0;
      final second = await installBundledPacks(
        s,
        assetKeys: files.keys,
        load: load,
      );
      expect(second.single, isA<AlreadyInstalled>());
      expect(loads, 1, reason: 'only the manifest is read');
    });

    test('refuses to bundle an encrypted pack', () async {
      final built = await build(contentKey: List.filled(32, 3));
      await expectLater(
        copyToBundledAssets(built, Directory(p.join(temp.path, 'assets'))),
        throwsArgumentError,
      );
    });

    test('bundling a newer revision removes the older one', () async {
      final assets = Directory(p.join(temp.path, 'assets', 'packs'));
      await copyToBundledAssets(await build(), assets);
      await copyToBundledAssets(await build(revision: 2), assets);
      expect(
        assets.listSync().map((f) => p.basename(f.path)).toList()..sort(),
        [
          'sample.docs.r2.manifest.json',
          'sample.docs.r2.manifest.json.sig',
          'sample.docs.r2.payload.bin',
        ],
      );
    });
  });
}
