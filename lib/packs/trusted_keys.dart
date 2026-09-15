import 'signature.dart';

/// Publisher keys this build trusts to sign catalogues and manifests.
///
/// `dev-publisher-1` signs packs built locally with `tool/build_pack.dart`; its
/// seed is in `tool/keys/dev-publisher.seed`, which is never committed.
/// Production builds must pin the offline production key instead and drop
/// this one (docs/CONTENT_PACKS.md §4).
const List<PublisherKey> trustedPublisherKeys = [
  PublisherKey(
    keyId: 'dev-publisher-1',
    publicKey: [
      0x15, 0xf4, 0x97, 0xf4, 0x6f, 0xb0, 0x6e, 0x40, //
      0xdb, 0x51, 0x60, 0x85, 0x14, 0x04, 0x08, 0x81,
      0x92, 0xf3, 0x06, 0x5d, 0xca, 0x53, 0x6d, 0x7b,
      0x22, 0xca, 0x06, 0xf4, 0x1c, 0xbb, 0xaf, 0x9b,
    ],
  ),
];
