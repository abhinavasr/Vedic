import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/packs/manifest.dart';

final hash = 'ab' * 32;

Map<String, dynamic> validJson() => {
  'format': 'vedic-pack',
  'format_version': 1,
  'pack_id': 'bhagavad-gita.sa-en',
  'revision': 3,
  'kind': 'text',
  'schema_version': 1,
  'min_app_build': 1,
  'created_at': '2026-09-15T00:00:00Z',
  'title': {'en': 'Bhagavad Gita', 'sa': 'भगवद्गीता'},
  'languages': ['sa', 'en'],
  'payload': {
    'file': 'payload.bin',
    'size': 1024,
    'sha256': hash,
    'compression': 'deflate',
    'encryption': 'none',
    'key_delivery': 'none',
    'plaintext_size': 4096,
    'plaintext_sha256': hash,
  },
  'licences': [
    {
      'id': 'translation-2026',
      'commercial_redistribution': true,
      'grant_reference': 'LIC-2026-004',
    },
  ],
};

PackManifest parse(Map<String, dynamic> json) =>
    PackManifest.parse(utf8.encode(jsonEncode(json)));

void expectRejected(void Function(Map<String, dynamic> json) mutate) {
  final json = validJson();
  mutate(json);
  expect(() => parse(json), throwsA(isA<PackFormatException>()));
}

Map<String, dynamic> payloadOf(Map<String, dynamic> json) =>
    json['payload'] as Map<String, dynamic>;

void main() {
  test('parses a valid bundled manifest', () {
    final m = parse(validJson());
    expect(m.packId, 'bhagavad-gita.sa-en');
    expect(m.revision, 3);
    expect(m.payload.compression, PayloadCompression.deflate);
    expect(m.payload.isEncrypted, isFalse);
    expect(m.titleFor('sa'), 'भगवद्गीता');
    expect(m.titleFor('kn'), 'Bhagavad Gita');
    expect(m.embeddings, isEmpty);
    expect(m.createdAt, DateTime.utc(2026, 9, 15));
  });

  test('parses an encrypted manifest with embeddings', () {
    final json = validJson();
    payloadOf(json)
      ..['encryption'] = 'vpk1-aes256gcm-stream'
      ..['key_delivery'] = 'hpke-device-envelope';
    json['embeddings'] = [
      {
        'embedder_id': 'gecko-110m',
        'embedder_revision': hash,
        'dimensions': 768,
        'quantisation': 'int8-symmetric-per-vector',
      },
    ];
    final m = parse(json);
    expect(m.payload.encryption, PayloadEncryption.vpk1);
    expect(m.payload.keyDelivery, KeyDelivery.hpkeDeviceEnvelope);
    expect(m.embeddings.single.dimensions, 768);
  });

  test('toJson round-trips', () {
    final m = parse(validJson());
    expect(parse(jsonDecode(jsonEncode(m.toJson()))).toJson(), m.toJson());
  });

  group('rejects', () {
    test('bytes that are not JSON', () {
      expect(
        () => PackManifest.parse(utf8.encode('nope')),
        throwsA(isA<PackFormatException>()),
      );
    });

    test('another format or a newer format version', () {
      expectRejected((j) => j['format'] = 'zip');
      expectRejected((j) => j['format_version'] = 2);
    });

    test('pack ids that could escape a directory', () {
      expectRejected((j) => j['pack_id'] = '../evil');
      expectRejected((j) => j['pack_id'] = 'Upper');
    });

    test('payload file names with a path', () {
      expectRejected((j) => payloadOf(j)['file'] = 'x/payload.bin');
      expectRejected((j) => payloadOf(j)['file'] = '../payload.bin');
    });

    test('revision zero and malformed hashes', () {
      expectRejected((j) => j['revision'] = 0);
      expectRejected((j) => payloadOf(j)['sha256'] = hash.toUpperCase());
      expectRejected((j) => payloadOf(j)['plaintext_sha256'] = 'abc');
    });

    test('encryption without key delivery, and the reverse', () {
      expectRejected(
        (j) => payloadOf(j)['encryption'] = 'vpk1-aes256gcm-stream',
      );
      expectRejected(
        (j) => payloadOf(j)['key_delivery'] = 'hpke-device-envelope',
      );
    });

    test('unknown compression', () {
      expectRejected((j) => payloadOf(j)['compression'] = 'zstd');
    });

    test('content not cleared for commercial redistribution', () {
      expectRejected(
        (j) =>
            (j['licences'] as List).first['commercial_redistribution'] = false,
      );
      expectRejected((j) => j['licences'] = []);
    });

    test('missing or empty titles', () {
      expectRejected((j) => j.remove('title'));
      expectRejected((j) => j['title'] = <String, String>{});
    });
  });

  group('installBlock', () {
    final m = parse(validJson());

    test('allows a newer revision this app understands', () {
      expect(m.installBlock(appBuild: 1), isNull);
      expect(m.installBlock(appBuild: 1, installedRevision: 2), isNull);
    });

    test('asks for an app update when the pack is ahead of the app', () {
      expect(
        parse(validJson()..['schema_version'] = 2).installBlock(appBuild: 99),
        InstallBlock.needsAppUpdate,
      );
      expect(
        parse(validJson()..['min_app_build'] = 99).installBlock(appBuild: 1),
        InstallBlock.needsAppUpdate,
      );
    });

    test('never reinstalls the same or an older revision', () {
      expect(
        m.installBlock(appBuild: 1, installedRevision: 3),
        InstallBlock.notNewer,
      );
      expect(
        m.installBlock(appBuild: 1, installedRevision: 4),
        InstallBlock.notNewer,
      );
    });
  });
}
