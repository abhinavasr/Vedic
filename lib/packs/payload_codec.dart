import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'manifest.dart' show PackFormatException;

// VPK1 segmented AES-256-GCM payload encryption: docs/CONTENT_PACKS.md §6.2.

const int vpk1HeaderLength = 56;
const int vpk1TagLength = 16;
const int vpk1DefaultSegmentSize = 1 << 20;
const int _maxSegmentSize = 16 << 20;
const List<int> _magic = [0x56, 0x50, 0x4B, 0x31];

final _aes = AesGcm.with256bits();

/// The payload failed authentication: it was altered, truncated, reordered,
/// or opened with the wrong key, pack or revision.
class PayloadAuthenticationException implements Exception {
  const PayloadAuthenticationException(this.message);

  final String message;

  @override
  String toString() => 'PayloadAuthenticationException: $message';
}

class Vpk1Header {
  Vpk1Header({
    required this.segmentSize,
    required List<int> salt,
    required List<int> noncePrefix,
  }) : salt = Uint8List.fromList(salt),
       noncePrefix = Uint8List.fromList(noncePrefix) {
    if (segmentSize < 1 || segmentSize > _maxSegmentSize) {
      throw PackFormatException('invalid segment size $segmentSize');
    }
    if (this.salt.length != 32 || this.noncePrefix.length != 7) {
      throw const PackFormatException('salt must be 32 bytes, nonce prefix 7');
    }
  }

  factory Vpk1Header.parse(Uint8List bytes) {
    if (bytes.length < vpk1HeaderLength) {
      throw const PackFormatException('payload is shorter than its header');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const PackFormatException('payload is not a VPK1 file');
      }
    }
    if (bytes[4] != 1) {
      throw PackFormatException('unsupported payload version ${bytes[4]}');
    }
    if (bytes[5] != 1) {
      throw PackFormatException('unsupported payload suite ${bytes[5]}');
    }
    final reservedZero =
        bytes[6] == 0 &&
        bytes[7] == 0 &&
        bytes.sublist(51, 56).every((b) => b == 0);
    if (!reservedZero) {
      throw const PackFormatException('payload header reserved bytes are set');
    }
    return Vpk1Header(
      segmentSize: ByteData.sublistView(bytes).getUint32(8),
      salt: bytes.sublist(12, 44),
      noncePrefix: bytes.sublist(44, 51),
    );
  }

  final int segmentSize;
  final Uint8List salt;
  final Uint8List noncePrefix;

  Uint8List toBytes() {
    final b = Uint8List(vpk1HeaderLength)
      ..setAll(0, _magic)
      ..[4] = 1
      ..[5] = 1
      ..setAll(12, salt)
      ..setAll(44, noncePrefix);
    ByteData.sublistView(b).setUint32(8, segmentSize);
    return b;
  }

  List<int> nonceFor(int index, {required bool last}) {
    final n = Uint8List(12)..setAll(0, noncePrefix);
    ByteData.sublistView(n).setUint32(7, index);
    n[11] = last ? 1 : 0;
    return n;
  }
}

/// payload key = HKDF-SHA256(CEK, salt, "vedic/pack/v1" 0 pack_id 0 u32(revision)).
Future<SecretKey> derivePayloadKey({
  required List<int> cek,
  required List<int> salt,
  required String packId,
  required int revision,
}) {
  if (cek.length != 32) {
    throw ArgumentError.value(cek.length, 'cek', 'must be 32 bytes');
  }
  final info = BytesBuilder()
    ..add(utf8.encode('vedic/pack/v1'))
    ..addByte(0)
    ..add(utf8.encode(packId))
    ..addByte(0)
    ..add((ByteData(4)..setUint32(0, revision)).buffer.asUint8List());
  return Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: SecretKey(cek), nonce: salt, info: info.takeBytes());
}

/// Encrypts an already-compressed payload. Used by the pack builder.
///
/// [salt] and [noncePrefix] are random unless given; pass them only for test
/// vectors.
Future<Uint8List> encryptPayload(
  List<int> plaintext, {
  required List<int> cek,
  required String packId,
  required int revision,
  int segmentSize = vpk1DefaultSegmentSize,
  List<int>? salt,
  List<int>? noncePrefix,
}) async {
  final header = Vpk1Header(
    segmentSize: segmentSize,
    salt: salt ?? _randomBytes(32),
    noncePrefix: noncePrefix ?? _randomBytes(7),
  );
  final headerBytes = header.toBytes();
  final key = await derivePayloadKey(
    cek: cek,
    salt: header.salt,
    packId: packId,
    revision: revision,
  );

  final segments = math.max(
    1,
    (plaintext.length + segmentSize - 1) ~/ segmentSize,
  );
  final out = BytesBuilder(copy: false)..add(headerBytes);
  for (var i = 0; i < segments; i++) {
    final start = i * segmentSize;
    final end = math.min(start + segmentSize, plaintext.length);
    final box = await _aes.encrypt(
      plaintext.sublist(start, end),
      secretKey: key,
      nonce: header.nonceFor(i, last: i == segments - 1),
      aad: headerBytes,
    );
    out
      ..add(box.cipherText)
      ..add(box.mac.bytes);
  }
  return out.takeBytes();
}

/// Decrypts a VPK1 payload as it streams in, holding at most two segments in
/// memory.
///
/// Yields plaintext only after each segment authenticates. Throws
/// [PackFormatException] for a malformed header and
/// [PayloadAuthenticationException] for anything tampered with or keyed
/// wrongly. Partial output from a stream that later throws must be discarded.
Stream<Uint8List> decryptPayload(
  Stream<List<int>> payload, {
  required List<int> cek,
  required String packId,
  required int revision,
}) async* {
  final pending = _ByteQueue();
  Vpk1Header? header;
  late Uint8List headerBytes;
  late SecretKey key;
  var index = 0;

  await for (final data in payload) {
    pending.add(data);
    if (header == null) {
      if (pending.length < vpk1HeaderLength) continue;
      headerBytes = pending.take(vpk1HeaderLength);
      header = Vpk1Header.parse(headerBytes);
      key = await derivePayloadKey(
        cek: cek,
        salt: header.salt,
        packId: packId,
        revision: revision,
      );
    }
    // Hold back the final segment until the stream ends: only then is it
    // known to be last.
    final segmentLength = header.segmentSize + vpk1TagLength;
    while (pending.length > segmentLength) {
      yield await _open(
        pending.take(segmentLength),
        header,
        headerBytes,
        key,
        index++,
        last: false,
      );
    }
  }

  if (header == null) {
    throw const PackFormatException('payload is shorter than its header');
  }
  if (pending.length < vpk1TagLength) {
    throw const PayloadAuthenticationException('payload is truncated');
  }
  yield await _open(
    pending.take(pending.length),
    header,
    headerBytes,
    key,
    index,
    last: true,
  );
}

Future<Uint8List> _open(
  Uint8List segment,
  Vpk1Header header,
  Uint8List headerBytes,
  SecretKey key,
  int index, {
  required bool last,
}) async {
  final tagStart = segment.length - vpk1TagLength;
  try {
    final clear = await _aes.decrypt(
      SecretBox(
        Uint8List.sublistView(segment, 0, tagStart),
        nonce: header.nonceFor(index, last: last),
        mac: Mac(Uint8List.sublistView(segment, tagStart)),
      ),
      secretKey: key,
      aad: headerBytes,
    );
    return clear is Uint8List ? clear : Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw PayloadAuthenticationException(
      'segment $index failed authentication',
    );
  }
}

List<int> _randomBytes(int n) {
  final rng = math.Random.secure();
  return List<int>.generate(n, (_) => rng.nextInt(256));
}

class _ByteQueue {
  final _chunks = ListQueue<Uint8List>();
  var _offset = 0;
  var _length = 0;

  int get length => _length;

  void add(List<int> data) {
    if (data.isEmpty) return;
    _chunks.add(Uint8List.fromList(data));
    _length += data.length;
  }

  /// Removes and returns the first [n] bytes. [n] must not exceed [length].
  Uint8List take(int n) {
    final out = Uint8List(n);
    var filled = 0;
    while (filled < n) {
      final first = _chunks.first;
      final count = math.min(first.length - _offset, n - filled);
      out.setRange(filled, filled + count, first, _offset);
      filled += count;
      _offset += count;
      if (_offset == first.length) {
        _chunks.removeFirst();
        _offset = 0;
      }
    }
    _length -= n;
    return out;
  }
}
