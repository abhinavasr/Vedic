import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../core/chunker.dart';
import '../manifest.dart';
import '../pack_schema.dart';
import '../pack_store.dart' show bundledAssetName;
import '../payload_codec.dart';
import '../signature.dart';

// Converts extracted source text into a signed pack: docs/CONTENT_PACKS.md §9.
// Runs on the build machine, never on a phone.

enum WorkKind { scripture, commentary, document }

enum PassageKind { verse, prose, heading, page }

class LicenceSource {
  const LicenceSource({
    required this.id,
    required this.name,
    required this.commercialRedistribution,
    required this.attribution,
    this.grantReference,
    this.notice,
  });

  final String id;
  final String name;
  final bool commercialRedistribution;
  final String attribution;
  final String? grantReference;
  final String? notice;
}

class SectionSource {
  const SectionSource({required this.kind, required this.number, this.title});

  /// e.g. "chapter".
  final String kind;

  /// As printed, e.g. "2". Passages whose sections have the same kind and
  /// number belong to the same section.
  final String number;
  final String? title;
}

enum RenderingKind { transliteration, translation, commentary, variant }

class RenderingSource {
  const RenderingSource({
    required this.kind,
    required this.language,
    required this.text,
    this.script,
    this.scheme,
    this.author,
  });

  final RenderingKind kind;
  final String language;
  final String text;
  final String? script;
  final String? scheme;
  final String? author;
}

class PassageSource {
  const PassageSource({
    required this.ref,
    required this.kind,
    required this.text,
    this.label,
    this.section,
    this.renderings = const [],
  });

  /// Stable citation key within the work, e.g. "2.47" or "p12".
  final String ref;
  final PassageKind kind;
  final String text;
  final String? label;
  final SectionSource? section;
  final List<RenderingSource> renderings;
}

class WorkSource {
  const WorkSource({
    required this.slug,
    required this.kind,
    required this.title,
    required this.language,
    required this.licenceId,
    required this.passages,
    this.titleNative,
    this.script,
    this.edition,
    this.sourceNote,
  });

  final String slug;
  final WorkKind kind;
  final String title;
  final String? titleNative;
  final String language;
  final String? script;
  final String? edition;
  final String licenceId;
  final String? sourceNote;
  final List<PassageSource> passages;
}

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
  });

  /// Reads a decoded `pack.yaml`, taking each work's passages from
  /// [passagesBySlug].
  factory PackSource.fromConfig(
    Map<String, Object?> config, {
    required Map<String, List<PassageSource>> passagesBySlug,
  }) {
    final c = JsonReader(config, 'pack.yaml');
    final createdAt = DateTime.tryParse(c.string('created_at'));
    if (createdAt == null) {
      throw const PackFormatException('pack.yaml.created_at is not a date');
    }
    return PackSource(
      packId: c.string('pack_id'),
      revision: c.integer('revision', min: 1),
      kind: c.string('kind'),
      createdAt: createdAt,
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

  final String packId;
  final int revision;
  final String kind;
  final DateTime createdAt;
  final int minAppBuild;
  final Map<String, String> title;
  final List<String> languages;
  final List<LicenceSource> licences;
  final List<WorkSource> works;
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
/// With [contentKey], the payload is encrypted for download; without it, the
/// pack is suitable for bundling. Refuses to overwrite a revision that already
/// exists, because published revisions are immutable.
Future<BuiltPack> buildPack(
  PackSource source, {
  required Directory outputRoot,
  required PackSigner signer,
  List<int>? contentKey,
  int maxChunkChars = 1000,
  int chunkOverlapChars = 150,
}) async {
  _validate(source);
  final out = Directory(
    p.join(outputRoot.path, source.packId, '${source.revision}'),
  );
  if (await out.exists()) {
    throw FileSystemException(
      'revision already built; published revisions are immutable',
      out.path,
    );
  }

  final scratch = await Directory.systemTemp.createTemp('vedic-pack-');
  try {
    final dbPath = p.join(scratch.path, 'pack.sqlite');
    _writeDatabase(dbPath, source, maxChunkChars, chunkOverlapChars);
    final plaintext = await File(dbPath).readAsBytes();
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
    // Never publish a manifest the app would reject.
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
  } finally {
    await scratch.delete(recursive: true);
  }
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

void _validate(PackSource s) {
  if (!PackManifest.packIdPattern.hasMatch(s.packId)) {
    throw PackFormatException('invalid pack_id "${s.packId}"');
  }
  final licences = <String, LicenceSource>{};
  for (final l in s.licences) {
    if (licences.putIfAbsent(l.id, () => l) != l) {
      throw PackFormatException('licence "${l.id}" is listed twice');
    }
    if (!l.commercialRedistribution) {
      throw PackFormatException(
        'licence "${l.id}" is not cleared for commercial redistribution',
      );
    }
  }
  if (s.works.isEmpty) {
    throw const PackFormatException('a pack needs at least one work');
  }
  final slugs = <String>{};
  for (final w in s.works) {
    if (!slugs.add(w.slug)) {
      throw PackFormatException('work "${w.slug}" is listed twice');
    }
    if (!licences.containsKey(w.licenceId)) {
      throw PackFormatException(
        'work "${w.slug}" uses unknown licence "${w.licenceId}"',
      );
    }
    if (w.passages.isEmpty) {
      throw PackFormatException('work "${w.slug}" has no text');
    }
    final refs = <String>{};
    for (final passage in w.passages) {
      if (passage.text.trim().isEmpty ||
          passage.renderings.any((r) => r.text.trim().isEmpty)) {
        throw PackFormatException(
          'work "${w.slug}" has empty text at "${passage.ref}"',
        );
      }
      if (!refs.add(passage.ref)) {
        throw PackFormatException(
          'work "${w.slug}" has two passages with ref "${passage.ref}"',
        );
      }
    }
  }
}

void _writeDatabase(
  String path,
  PackSource s,
  int maxChunkChars,
  int chunkOverlapChars,
) {
  final db = sqlite3.open(path);
  try {
    db
      ..execute('PRAGMA application_id = $packApplicationId')
      ..execute('PRAGMA user_version = $packSchemaVersion')
      ..execute(packSchemaSql)
      ..execute('BEGIN');

    for (final MapEntry(:key, :value) in {
      'pack_id': s.packId,
      'revision': '${s.revision}',
      'schema_version': '$packSchemaVersion',
      'created_at': s.createdAt.toUtc().toIso8601String(),
    }.entries) {
      db.execute('INSERT INTO pack_meta (key, value) VALUES (?, ?)', [
        key,
        value,
      ]);
    }

    for (final l in s.licences) {
      db.execute(
        'INSERT INTO licences (id, name, commercial_redistribution, '
        'grant_reference, attribution, notice) VALUES (?, ?, ?, ?, ?, ?)',
        [
          l.id,
          l.name,
          l.commercialRedistribution ? 1 : 0,
          l.grantReference,
          l.attribution,
          l.notice,
        ],
      );
    }

    for (final w in s.works) {
      db.execute(
        'INSERT INTO works (slug, kind, title, title_native, language, '
        'script, edition, licence_id, source_note) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          w.slug,
          w.kind.name,
          w.title,
          w.titleNative,
          w.language,
          w.script,
          w.edition,
          w.licenceId,
          w.sourceNote,
        ],
      );
      final workId = db.lastInsertRowId;

      final sectionIds = <String, int>{};
      final passageIds = <int>[];
      for (var i = 0; i < w.passages.length; i++) {
        final passage = w.passages[i];
        final section = passage.section;
        final sectionId = section == null
            ? null
            : sectionIds['${section.kind}:${section.number}'] ??=
                  _insertSection(db, workId, section, sectionIds.length + 1);
        db.execute(
          'INSERT INTO passages '
          '(work_id, section_id, ordinal, kind, ref, label, text) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            workId,
            sectionId,
            i + 1,
            passage.kind.name,
            passage.ref,
            passage.label,
            passage.text,
          ],
        );
        final passageId = db.lastInsertRowId;
        passageIds.add(passageId);

        for (final r in passage.renderings) {
          db.execute(
            'INSERT INTO renderings (passage_id, kind, language, script, '
            'scheme, author, licence_id, text) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [
              passageId,
              r.kind.name,
              r.language,
              r.script,
              r.scheme,
              r.author,
              w.licenceId,
              r.text,
            ],
          );
        }
      }
      _writeChunks(
        db,
        workId,
        w.passages,
        passageIds,
        maxChunkChars,
        chunkOverlapChars,
      );
    }

    db
      ..execute('COMMIT')
      ..execute('VACUUM');
  } finally {
    db.close();
  }
}

int _insertSection(
  Database db,
  int workId,
  SectionSource section,
  int ordinal,
) {
  db.execute(
    'INSERT INTO sections (work_id, ordinal, kind, number, title) '
    'VALUES (?, ?, ?, ?, ?)',
    [workId, ordinal, section.kind, section.number, section.title],
  );
  return db.lastInsertRowId;
}

/// Chunks a work's passages as one text, so retrieval units can span passage
/// boundaries, and records the first and last passage each chunk covers.
void _writeChunks(
  Database db,
  int workId,
  List<PassageSource> passages,
  List<int> passageIds,
  int maxChars,
  int overlapChars,
) {
  final joined = StringBuffer();
  final starts = <int>[];
  for (final passage in passages) {
    if (joined.isNotEmpty) joined.write('\n\n');
    starts.add(joined.length);
    joined.write(passage.text);
  }
  var ordinal = 0;
  for (final chunk in chunkText(
    joined.toString(),
    maxChars: maxChars,
    overlapChars: overlapChars,
  )) {
    db.execute(
      'INSERT INTO chunks (work_id, first_passage_id, last_passage_id, '
      'ordinal, text) VALUES (?, ?, ?, ?, ?)',
      [
        workId,
        passageIds[_passageAt(starts, chunk.start)],
        passageIds[_passageAt(starts, chunk.end - 1)],
        ++ordinal,
        chunk.text,
      ],
    );
  }
}

/// Index of the passage whose text contains [offset] in the joined text.
int _passageAt(List<int> starts, int offset) {
  var lo = 0;
  var hi = starts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (starts[mid] <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

String _sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();
