import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/packs/signature.dart';

final seed = List<int>.generate(32, (i) => 255 - i);
final manifest = utf8.encode('{"pack_id":"test.pack","revision":1}\n');

Future<List<PublisherKey>> trusted() async => [
  PublisherKey(keyId: 'test-key', publicKey: await publicKeyFromSeed(seed)),
];

Matcher get rejected => throwsA(isA<SignatureException>());

void main() {
  test('accepts a signature from a trusted key', () async {
    final sig = await signDetached(
      bytes: manifest,
      seed: seed,
      keyId: 'test-key',
    );
    await verifyDetached(
      signed: manifest,
      signatureFile: sig,
      trusted: await trusted(),
    );
  });

  test('rejects bytes changed after signing', () async {
    final sig = await signDetached(
      bytes: manifest,
      seed: seed,
      keyId: 'test-key',
    );
    final altered = [...manifest]..[5] ^= 1;
    await expectLater(
      verifyDetached(
        signed: altered,
        signatureFile: sig,
        trusted: await trusted(),
      ),
      rejected,
    );
  });

  test('rejects a key the app does not trust', () async {
    final otherSeed = List<int>.filled(32, 7);
    final sig = await signDetached(
      bytes: manifest,
      seed: otherSeed,
      keyId: 'test-key',
    );
    await expectLater(
      verifyDetached(
        signed: manifest,
        signatureFile: sig,
        trusted: await trusted(),
      ),
      rejected,
    );
    final unknownId = await signDetached(
      bytes: manifest,
      seed: seed,
      keyId: 'other',
    );
    await expectLater(
      verifyDetached(
        signed: manifest,
        signatureFile: unknownId,
        trusted: await trusted(),
      ),
      rejected,
    );
  });

  test('rejects malformed signature files', () async {
    final keys = await trusted();
    for (final file in [
      'not json',
      '[]',
      '{"alg":"rsa","key_id":"test-key","signature":"AAAA"}',
      '{"alg":"ed25519","key_id":"test-key","signature":"AAAA"}',
      '{"alg":"ed25519","key_id":"test-key","signature":"***"}',
    ]) {
      await expectLater(
        verifyDetached(
          signed: manifest,
          signatureFile: utf8.encode(file),
          trusted: keys,
        ),
        rejected,
        reason: file,
      );
    }
  });
}
