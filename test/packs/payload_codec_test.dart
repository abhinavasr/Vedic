import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/packs/manifest.dart' show PackFormatException;
import 'package:vedic/packs/payload_codec.dart';

final cek = List<int>.generate(32, (i) => i);
const packId = 'test.pack';
const revision = 7;
const segment = 64;
const segmentBytes = segment + vpk1TagLength;

Future<Uint8List> seal(List<int> plain) => encryptPayload(
  plain,
  cek: cek,
  packId: packId,
  revision: revision,
  segmentSize: segment,
);

Future<List<int>> open(
  List<int> payload, {
  List<int>? key,
  String id = packId,
  int rev = revision,
  int pieceSize = 50,
}) async {
  Stream<List<int>> pieces() async* {
    for (var i = 0; i < payload.length; i += pieceSize) {
      yield payload.sublist(i, math.min(i + pieceSize, payload.length));
    }
  }

  final out = <int>[];
  await for (final part in decryptPayload(
    pieces(),
    cek: key ?? cek,
    packId: id,
    revision: rev,
  )) {
    out.addAll(part);
  }
  return out;
}

List<int> bytes(int n) => List<int>.generate(n, (i) => (i * 31 + 7) % 256);

Matcher get rejectedAsTampered =>
    throwsA(isA<PayloadAuthenticationException>());

void main() {
  test(
    'round-trips every boundary size, however the stream is split',
    () async {
      for (final size in [
        0,
        1,
        segment - 1,
        segment,
        segment + 1,
        3 * segment,
        200,
      ]) {
        final plain = bytes(size);
        final sealed = await seal(plain);
        final segments = math.max(1, (size + segment - 1) ~/ segment);
        expect(
          sealed.length,
          vpk1HeaderLength + segments * vpk1TagLength + size,
          reason: 'size $size',
        );
        for (final pieceSize in [1, 7, 10000]) {
          expect(
            await open(sealed, pieceSize: pieceSize),
            plain,
            reason: 'size $size, pieces of $pieceSize',
          );
        }
      }
    },
  );

  test(
    'fixed salt and nonce prefix give identical output; random do not',
    () async {
      Future<Uint8List> fixed() => encryptPayload(
        bytes(100),
        cek: cek,
        packId: packId,
        revision: revision,
        segmentSize: segment,
        salt: List.filled(32, 1),
        noncePrefix: List.filled(7, 2),
      );
      expect(await fixed(), await fixed());
      expect(await seal(bytes(100)), isNot(await seal(bytes(100))));
    },
  );

  group('detects tampering', () {
    // 200 bytes: three full segments and a final segment of 8.
    late Uint8List sealed;
    setUp(() async => sealed = await seal(bytes(200)));

    test('a flipped bit in a middle segment', () async {
      sealed[vpk1HeaderLength + segmentBytes + 3] ^= 1;
      await expectLater(open(sealed), rejectedAsTampered);
    });

    test('a flipped bit in the final tag', () async {
      sealed[sealed.length - 1] ^= 1;
      await expectLater(open(sealed), rejectedAsTampered);
    });

    test('a flipped bit in the salt', () async {
      sealed[20] ^= 1;
      await expectLater(open(sealed), rejectedAsTampered);
    });

    test('a dropped final segment', () async {
      final cut = sealed.sublist(0, sealed.length - (8 + vpk1TagLength));
      await expectLater(open(cut), rejectedAsTampered);
    });

    test('a truncated final segment', () async {
      await expectLater(
        open(sealed.sublist(0, sealed.length - 3)),
        rejectedAsTampered,
      );
    });

    test('swapped segments', () async {
      final a = vpk1HeaderLength;
      final b = a + segmentBytes;
      final first = sealed.sublist(a, b);
      sealed
        ..setRange(a, b, sealed.sublist(b, b + segmentBytes))
        ..setRange(b, b + segmentBytes, first);
      await expectLater(open(sealed), rejectedAsTampered);
    });

    test('bytes appended after the final segment', () async {
      await expectLater(
        open([...sealed, ...List.filled(20, 0)]),
        rejectedAsTampered,
      );
    });

    test('the wrong key, pack or revision', () async {
      await expectLater(
        open(sealed, key: List.filled(32, 9)),
        rejectedAsTampered,
      );
      await expectLater(open(sealed, id: 'other.pack'), rejectedAsTampered);
      await expectLater(open(sealed, rev: revision + 1), rejectedAsTampered);
    });
  });

  group('rejects malformed headers', () {
    test('wrong magic, version or reserved bytes', () async {
      for (final (offset, value) in [(0, 0), (4, 2), (5, 9), (6, 1), (55, 1)]) {
        final sealed = await seal(bytes(10));
        sealed[offset] = value;
        await expectLater(
          open(sealed),
          throwsA(isA<PackFormatException>()),
          reason: 'byte $offset = $value',
        );
      }
    });

    test('a payload shorter than its header', () async {
      await expectLater(open(bytes(10)), throwsA(isA<PackFormatException>()));
    });

    test('a header with no room for even an empty segment', () async {
      final sealed = await seal(const []);
      await expectLater(
        open(sealed.sublist(0, vpk1HeaderLength + 5)),
        rejectedAsTampered,
      );
    });
  });
}
