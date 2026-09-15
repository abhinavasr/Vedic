import 'dart:convert';

import 'package:cryptography/cryptography.dart';

// Detached Ed25519 signatures over exact bytes: docs/CONTENT_PACKS.md §4.

class SignatureException implements Exception {
  const SignatureException(this.message);

  final String message;

  @override
  String toString() => 'SignatureException: $message';
}

/// A publisher key the app trusts to sign catalogues and manifests.
class PublisherKey {
  const PublisherKey({required this.keyId, required this.publicKey});

  final String keyId;

  /// Raw 32-byte Ed25519 public key.
  final List<int> publicKey;
}

final _ed25519 = Ed25519();

/// Throws [SignatureException] unless [signatureFile] is a valid signature
/// over exactly [signed] by one of [trusted].
Future<void> verifyDetached({
  required List<int> signed,
  required List<int> signatureFile,
  required List<PublisherKey> trusted,
}) async {
  final (keyId, signature) = _parseSignatureFile(signatureFile);
  PublisherKey? key;
  for (final k in trusted) {
    if (k.keyId == keyId) key = k;
  }
  if (key == null) {
    throw SignatureException('signed by untrusted key "$keyId"');
  }
  final ok = await _ed25519.verify(
    signed,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(key.publicKey, type: KeyPairType.ed25519),
    ),
  );
  if (!ok) {
    throw const SignatureException('signature does not match the signed bytes');
  }
}

/// Signs [bytes] and returns the detached signature file. Used by the pack
/// builder; the app only verifies.
Future<List<int>> signDetached({
  required List<int> bytes,
  required List<int> seed,
  required String keyId,
}) async {
  final keyPair = await _ed25519.newKeyPairFromSeed(seed);
  final signature = await _ed25519.sign(bytes, keyPair: keyPair);
  final json = const JsonEncoder.withIndent('  ').convert({
    'alg': 'ed25519',
    'key_id': keyId,
    'signature': base64Url.encode(signature.bytes).replaceAll('=', ''),
  });
  return utf8.encode('$json\n');
}

Future<List<int>> publicKeyFromSeed(List<int> seed) async {
  final keyPair = await _ed25519.newKeyPairFromSeed(seed);
  return (await keyPair.extractPublicKey()).bytes;
}

(String, List<int>) _parseSignatureFile(List<int> bytes) {
  const malformed = SignatureException('malformed signature file');
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, Object?>) throw malformed;
    final alg = json['alg'];
    final keyId = json['key_id'];
    final encoded = json['signature'];
    if (alg != 'ed25519' || keyId is! String || encoded is! String) {
      throw malformed;
    }
    final signature = base64Url.decode(base64Url.normalize(encoded));
    if (signature.length != 64) throw malformed;
    return (keyId, signature);
  } on FormatException {
    throw malformed;
  }
}
