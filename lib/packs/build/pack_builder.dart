import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../content.dart';
import '../manifest.dart';
import '../pack_database.dart';
import '../pack_schema.dart';
import '../pack_store.dart' show bundledAssetName;
import '../payload_codec.dart';
import '../signature.dart';

export '../content.dart';

// Turns pack content into a signed pack: docs/CONTENT_PACKS.md §9.
// Runs on the build machine, never on a phone.

class PackSource {
  const PackSource({
    required this.packId,
    required this.revision,
    required this.kind,
    required this.createdAt,
    required this.minAppBuild,
    required this.title,
    required this.languages,
    required this.licences,
    required this.works,
    this.voices = const [],
  });

  /// Reads a decoded `pack.yaml`, taking each work's passages from
  /// [passagesBySlug].
  factory PackSource.fromConfig(
    Map<String, Object?> config, {
    required Map<String, List<PassageSource>> passagesBySlug,
  }) {
    final c = JsonReader(config, 'pack.yaml');
    return PackSource(
      packId: c.string('pack_id'),
      revision: c.integer('revision', min: 1),
      kind: c.string('kind'),
      createdAt: packCreatedAt(c),
      minAppBuild: c.integer('min_app_build'),
      title: c.stringMap('title'),
      languages: c.strings('languages'),
      licences: [
        for (final l in c.objects('licences'))
          LicenceSource(
            id: l.string('id'),
            name: l.string('name'),
            commercialRedistribution: l.boolean('commercial_redistribution'),
            attribution: l.string('attribution'),
            grantReference: l.optionalString('grant_reference'),
            notice: l.optionalString('notice'),
          ),
      ],
      works: [
        for (final w in c.objects('works'))
          WorkSource(
            slug: w.string('slug'),
            kind: w.oneOf('kind', {for (final k in WorkKind.values) k: k.name}),
            title: w.string('title'),
            titleNative: w.optionalString('title_native'),
            language: w.string('language'),
            script: w.optionalString('script'),
            edition: w.optionalString('edition'),
            licenceId: w.string('licence'),
            sourceNote: w.optionalString('source_note'),
            passages:
                passagesBySlug[w.string('slug')] ??
                (throw PackFormatException(
                  'no extracted text for work "${w.string('slug')}"',
                )),
          ),
      ],
    );
  }

  /// A pack whose content is a ready-made content JSON document (e.g. from
  /// the content server), with build metadata from `pack.yaml`.
  factory PackSource.fromContent(
    Map<String, Object?> config,
    PackContent content,
  ) {
    final c = JsonReader(config, 'pack.yaml');
    if (c.string('pack_id') != content.packId ||
        c.integer('revision', min: 1) != content.revision) {
      throw const PackFormatException(
        'pack.yaml and the content JSON disagree on pack_id or revision',
      );
    }
    return PackSource(
      packId: content.packId,
      revision: content.revision,
      kind: c.string('kind'),
      createdAt: packCreatedAt(c),
      minAppBuild: c.integer('min_app_build'),
      title: c.stringMap('title'),
      languages: content.languages,
      licences: content.licences,
      voices: content.voices,
      works: content.works,
    );
  }

  final String packId;
  final int revision;
  final String kind;
  final DateTime createdAt;
  final int minAppBuild;
  final Map<String, String> title;
  final List<String> languages;
  final List<LicenceSource> licences;
  final List<VoiceSource> voices;
  final List<WorkSource> works;

  PackContent get content => PackContent(
    packId: packId,
    revision: revision,
    languages: languages,
    licences: licences,
    voices: voices,
    works: works,
  );
}

DateTime packCreatedAt(JsonReader config) {
  final createdAt = DateTime.tryParse(config.string('created_at'));
  if (createdAt == null) {
    throw const PackFormatException('pack.yaml.created_at is not a date');
  }
  return createdAt;
}

class PackSigner {
  const PackSigner({required this.keyId, required this.seed});

  final String keyId;

  /// 32-byte Ed25519 seed. Development only; production signing is offline.
  final List<int> seed;
}

class BuiltPack {
  const BuiltPack({required this.directory, required this.manifest});

  /// `<out>/<pack_id>/<revision>/`, laid out as on the static host.
  final Directory directory;
  final PackManifest manifest;
}

/// Builds and signs one pack revision under
/// `outputRoot/<pack_id>/<revision>/`.
///
/// The payload is the content JSON, deflated, and encrypted for download when
/// [contentKey] is given. Refuses to overwrite a revision that already exists,
/// because published revisions are immutable.
Future<BuiltPack> buildPack(
  PackSource source, {
  required Directory outputRoot,
  required PackSigner signer,
  List<int>? contentKey,
}) async {
  final plaintext = utf8.encode(jsonEncode(source.content.toJson()));
  final out = Directory(
    p.join(outputRoot.path, source.packId, '${source.revision}'),
  );
  if (await out.exists()) {
    throw FileSystemException(
      'revision already built; published revisions are immutable',
      out.path,
    );
  }

  // Never publish content the app would reject: parse it back exactly as the
  // phone will, and build the database it installs to.
  final scratch = await Directory.systemTemp.createTemp('vedic-pack-');
  try {
    writePackDatabase(
      p.join(scratch.path, 'check.sqlite'),
      PackContent.fromJson(jsonDecode(utf8.decode(plaintext))),
      createdAt: source.createdAt,
    );
  } finally {
    await scratch.delete(recursive: true);
  }

  final compressed = ZLibCodec(level: 9).encode(plaintext);
  final payload = contentKey == null
      ? compressed
      : await encryptPayload(
          compressed,
          cek: contentKey,
          packId: source.packId,
          revision: source.revision,
        );
  final encrypted = contentKey != null;

  final manifest = PackManifest(
    packId: source.packId,
    revision: source.revision,
    kind: source.kind,
    schemaVersion: packSchemaVersion,
    minAppBuild: source.minAppBuild,
    createdAt: source.createdAt,
    title: source.title,
    languages: source.languages,
    payload: PackPayload(
      file: 'payload.bin',
      size: payload.length,
      sha256: _sha256Hex(payload),
      compression: PayloadCompression.deflate,
      encryption: encrypted ? PayloadEncryption.vpk1 : PayloadEncryption.none,
      keyDelivery: encrypted
          ? KeyDelivery.hpkeDeviceEnvelope
          : KeyDelivery.none,
      plaintextSize: plaintext.length,
      plaintextSha256: _sha256Hex(plaintext),
    ),
    embeddings: const [],
    licences: [
      for (final l in source.licences)
        PackLicence(
          id: l.id,
          commercialRedistribution: l.commercialRedistribution,
          grantReference: l.grantReference,
        ),
    ],
  );
  final manifestBytes = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
  );
  PackManifest.parse(manifestBytes);

  await out.create(recursive: true);
  await File(p.join(out.path, 'manifest.json')).writeAsBytes(manifestBytes);
  await File(p.join(out.path, 'manifest.json.sig')).writeAsBytes(
    await signDetached(
      bytes: manifestBytes,
      seed: signer.seed,
      keyId: signer.keyId,
    ),
  );
  await File(p.join(out.path, 'payload.bin')).writeAsBytes(payload);
  await File(p.join(out.path, 'payload.bin.sha256'))
      .writeAsString('${manifest.payload.sha256}  payload.bin\n');
  return BuiltPack(directory: out, manifest: manifest);
}

/// Copies an unencrypted pack into the app's bundled assets, removing older
/// bundled revisions of the same pack.
Future<void> copyToBundledAssets(BuiltPack pack, Directory assetsDir) async {
  final m = pack.manifest;
  if (m.payload.isEncrypted) {
    throw ArgumentError(
      'bundled packs must not be encrypted: any key in the app binary is public',
    );
  }
  await assetsDir.create(recursive: true);
  final ownFiles = RegExp('^${RegExp.escape(m.packId)}\\.r(\\d+)\\.');
  for (final entity in assetsDir.listSync().whereType<File>()) {
    final match = ownFiles.firstMatch(p.basename(entity.path));
    if (match != null && int.parse(match[1]!) != m.revision) {
      await entity.delete();
    }
  }
  for (final file in ['manifest.json', 'manifest.json.sig', m.payload.file]) {
    await File(p.join(pack.directory.path, file)).copy(
      p.join(assetsDir.path, bundledAssetName(m.packId, m.revision, file)),
    );
  }
}

String _sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();
