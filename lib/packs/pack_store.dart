import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'content.dart';
import 'manifest.dart';
import 'pack_database.dart';
import 'pack_schema.dart';
import 'payload_codec.dart';
import 'signature.dart';

// Installs, tracks and opens pack databases: docs/CONTENT_PACKS.md §7–8.

enum PackOrigin { bundled, downloaded }

class InstalledPack {
  const InstalledPack({
    required this.packId,
    required this.revision,
    required this.file,
    required this.origin,
    required this.installedAt,
  });

  final String packId;
  final int revision;

  /// Path relative to the store root. Relative because the iOS app container
  /// path changes between app updates.
  final String file;
  final PackOrigin origin;
  final DateTime installedAt;
}

sealed class InstallResult {
  const InstallResult();
}

final class Installed extends InstallResult {
  const Installed(this.pack);

  final InstalledPack pack;
}

final class AlreadyInstalled extends InstallResult {
  const AlreadyInstalled(this.installedRevision);

  final int installedRevision;
}

final class NeedsAppUpdate extends InstallResult {
  const NeedsAppUpdate(this.manifest);

  final PackManifest manifest;
}

/// The pack's bytes don't match its signed manifest, or its database is not a
/// valid pack.
class PackIntegrityException implements Exception {
  const PackIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'PackIntegrityException: $message';
}

/// A place in a work the reader reached or bookmarked.
class ReadingMark {
  const ReadingMark({
    required this.packId,
    required this.workSlug,
    required this.ref,
    required this.at,
  });

  final String packId;
  final String workSlug;
  final String ref;
  final DateTime at;
}

/// A translation this phone produced, kept outside the pack so a pack update
/// never overwrites it and never passes it off as published text.
class LocalTranslation {
  const LocalTranslation({
    required this.packId,
    required this.workSlug,
    required this.ref,
    required this.language,
    required this.text,
    required this.model,
    required this.createdAt,
  });

  final String packId;
  final String workSlug;
  final String ref;

  /// BCP 47.
  final String language;
  final String text;

  /// Which model wrote it, so a later version can re-translate or drop it.
  final String model;
  final DateTime createdAt;
}

/// Returns the content key for an encrypted pack, e.g. by unwrapping its
/// device key envelope.
typedef ContentKeyProvider = Future<List<int>> Function(PackManifest manifest);

/// File name of a bundled pack's [file] under `assets/packs/`.
///
/// Flat names, because a Flutter asset directory entry does not include
/// subdirectories.
String bundledAssetName(String packId, int revision, String file) =>
    '$packId.r$revision.$file';

class PackStore {
  PackStore({
    required this.root,
    required this.trustedKeys,
    required this.appBuild,
  });

  final Directory root;
  final List<PublisherKey> trustedKeys;
  final int appBuild;

  /// Scratch space for installs in progress. Cleared by [removeLeftovers].
  Directory get tempDirectory => Directory(p.join(root.path, 'tmp'));

  /// Deletes files left behind by installs that were killed part-way.
  ///
  /// Call once at startup, before any install.
  Future<void> removeLeftovers() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  }

  List<InstalledPack> installed() => _withRegistry(
    (db) => [
      for (final row in db.select(
        'SELECT pack_id, revision, file, origin, installed_at '
        'FROM installed_packs ORDER BY pack_id',
      ))
        InstalledPack(
          packId: row['pack_id'] as String,
          revision: row['revision'] as int,
          file: row['file'] as String,
          origin: PackOrigin.values.byName(row['origin'] as String),
          installedAt: DateTime.parse(row['installed_at'] as String),
        ),
    ],
  );

  int? installedRevision(String packId) => _withRegistry((db) {
    final rows = db.select(
      'SELECT revision FROM installed_packs WHERE pack_id = ?',
      [packId],
    );
    return rows.isEmpty ? null : rows.first['revision'] as int;
  });

  /// Opens an installed pack for reading. The caller closes it, and must close
  /// it before installing a newer revision of the same pack.
  Database openReadOnly(InstalledPack pack) =>
      sqlite3.open(p.join(root.path, pack.file), mode: OpenMode.readOnly);

  /// Installs the pack in [packDir]: `manifest.json`, `manifest.json.sig` and
  /// the payload file the manifest names.
  ///
  /// Nothing changes unless every check passes; on any failure the previously
  /// installed revision stays active. Throws [SignatureException],
  /// [PackFormatException], [PackIntegrityException] or
  /// [PayloadAuthenticationException].
  Future<InstallResult> install(
    Directory packDir, {
    required PackOrigin origin,
    ContentKeyProvider? contentKey,
  }) async {
    final manifestBytes = await File(p.join(packDir.path, 'manifest.json'))
        .readAsBytes();
    await verifyDetached(
      signed: manifestBytes,
      signatureFile: await File(p.join(packDir.path, 'manifest.json.sig'))
          .readAsBytes(),
      trusted: trustedKeys,
    );
    final manifest = PackManifest.parse(manifestBytes);
    final payload = manifest.payload;
    if (origin == PackOrigin.bundled && payload.isEncrypted) {
      throw const PackFormatException('bundled packs must not be encrypted');
    }

    final current = installedRevision(manifest.packId);
    switch (manifest.installBlock(
      appBuild: appBuild,
      installedRevision: current,
    )) {
      case InstallBlock.needsAppUpdate:
        return NeedsAppUpdate(manifest);
      case InstallBlock.notNewer:
        return AlreadyInstalled(current!);
      case null:
        break;
    }

    final payloadFile = File(p.join(packDir.path, payload.file));
    if (await payloadFile.length() != payload.size) {
      throw const PackIntegrityException('payload size does not match');
    }
    if (await _sha256(payloadFile.openRead()) != payload.sha256) {
      throw const PackIntegrityException('payload checksum does not match');
    }

    await tempDirectory.create(recursive: true);
    final stem = p.join(
      tempDirectory.path,
      '${manifest.packId}-${manifest.revision}-${_randomHex()}',
    );
    final temp = File('$stem.json');
    final database = File('$stem.sqlite');
    try {
      Stream<List<int>> bytes = payloadFile.openRead();
      if (payload.isEncrypted) {
        if (contentKey == null) {
          throw ArgumentError('an encrypted pack needs a content key provider');
        }
        bytes = decryptPayload(
          bytes,
          cek: await contentKey(manifest),
          packId: manifest.packId,
          revision: manifest.revision,
        );
      }
      if (payload.compression == PayloadCompression.deflate) {
        bytes = zlib.decoder.bind(bytes);
      }
      await bytes.pipe(temp.openWrite());

      if (await temp.length() != payload.plaintextSize ||
          await _sha256(temp.openRead()) != payload.plaintextSha256) {
        throw const PackIntegrityException('pack content checksum mismatch');
      }
      final content = _readContent(await temp.readAsBytes(), manifest);
      try {
        writePackDatabase(
          database.path,
          content,
          createdAt: manifest.createdAt,
        );
      } on SqliteException catch (e) {
        throw PackIntegrityException(
          'pack content breaks the database schema: ${e.message}',
        );
      }
      _validateDatabase(database.path, manifest);

      final relative = p.join(manifest.packId, '${manifest.revision}.sqlite');
      final destination = File(p.join(root.path, relative));
      await destination.parent.create(recursive: true);
      await database.rename(destination.path);

      final installedAt = DateTime.now().toUtc();
      final previous = _withRegistry((db) {
        final rows = db.select(
          'SELECT file FROM installed_packs WHERE pack_id = ?',
          [manifest.packId],
        );
        db.execute(
          'INSERT INTO installed_packs '
          '(pack_id, revision, file, origin, installed_at) '
          'VALUES (?, ?, ?, ?, ?) '
          'ON CONFLICT (pack_id) DO UPDATE SET revision = excluded.revision, '
          'file = excluded.file, origin = excluded.origin, '
          'installed_at = excluded.installed_at',
          [
            manifest.packId,
            manifest.revision,
            relative,
            origin.name,
            installedAt.toIso8601String(),
          ],
        );
        return rows.isEmpty ? null : rows.first['file'] as String;
      });
      if (previous != null && previous != relative) {
        final old = File(p.join(root.path, previous));
        if (await old.exists()) await old.delete();
      }

      return Installed(
        InstalledPack(
          packId: manifest.packId,
          revision: manifest.revision,
          file: relative,
          origin: origin,
          installedAt: installedAt,
        ),
      );
    } finally {
      for (final file in [temp, database]) {
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// The passage the reader last opened in a work.
  String? lastRead(String packId, String workSlug) => _withRegistry((db) {
    final rows = db.select(
      'SELECT ref FROM reading_progress WHERE pack_id = ? AND work_slug = ?',
      [packId, workSlug],
    );
    return rows.isEmpty ? null : rows.first['ref'] as String;
  });

  void saveLastRead({
    required String packId,
    required String workSlug,
    required String ref,
  }) => _withRegistry(
    (db) => db.execute(
      'INSERT INTO reading_progress (pack_id, work_slug, ref, updated_at) '
      'VALUES (?, ?, ?, ?) ON CONFLICT (pack_id, work_slug) DO UPDATE SET '
      'ref = excluded.ref, updated_at = excluded.updated_at',
      [packId, workSlug, ref, DateTime.now().toUtc().toIso8601String()],
    ),
  );

  /// Works the reader has opened, most recent first.
  List<ReadingMark> recentlyRead({int limit = 10}) => _withRegistry(
    (db) => [
      for (final row in db.select(
        'SELECT pack_id, work_slug, ref, updated_at FROM reading_progress '
        'ORDER BY updated_at DESC LIMIT ?',
        [limit],
      ))
        _mark(row, 'updated_at'),
    ],
  );

  bool isBookmarked(String packId, String workSlug, String ref) =>
      _withRegistry(
        (db) => db.select(
          'SELECT 1 FROM bookmarks WHERE pack_id = ? AND work_slug = ? '
          'AND ref = ?',
          [packId, workSlug, ref],
        ).isNotEmpty,
      );

  /// Adds or removes a bookmark, and returns whether it is now bookmarked.
  bool toggleBookmark({
    required String packId,
    required String workSlug,
    required String ref,
  }) {
    final bookmarked = isBookmarked(packId, workSlug, ref);
    _withRegistry(
      (db) => bookmarked
          ? db.execute(
              'DELETE FROM bookmarks WHERE pack_id = ? AND work_slug = ? '
              'AND ref = ?',
              [packId, workSlug, ref],
            )
          : db.execute(
              'INSERT INTO bookmarks (pack_id, work_slug, ref, created_at) '
              'VALUES (?, ?, ?, ?)',
              [packId, workSlug, ref, DateTime.now().toUtc().toIso8601String()],
            ),
    );
    return !bookmarked;
  }

  List<ReadingMark> bookmarks({int limit = 200}) => _withRegistry(
    (db) => [
      for (final row in db.select(
        'SELECT pack_id, work_slug, ref, created_at FROM bookmarks '
        'ORDER BY created_at DESC LIMIT ?',
        [limit],
      ))
        _mark(row, 'created_at'),
    ],
  );

  /// Every on-device translation for a work, for merging into what the pack
  /// ships.
  List<LocalTranslation> localTranslations(String packId, String workSlug) =>
      _withRegistry(
        (db) => [
          for (final row in db.select(
            'SELECT ref, language, text, model, created_at '
            'FROM local_translations WHERE pack_id = ? AND work_slug = ? '
            'ORDER BY ref',
            [packId, workSlug],
          ))
            LocalTranslation(
              packId: packId,
              workSlug: workSlug,
              ref: row['ref'] as String,
              language: row['language'] as String,
              text: row['text'] as String,
              model: row['model'] as String,
              createdAt: DateTime.parse(row['created_at'] as String),
            ),
        ],
      );

  /// Stores a translation, replacing any earlier one for the same verse and
  /// language.
  void saveLocalTranslation(LocalTranslation translation) => _withRegistry(
    (db) => db.execute(
      'INSERT INTO local_translations '
      '(pack_id, work_slug, ref, language, text, model, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (pack_id, work_slug, ref, language) DO UPDATE SET '
      'text = excluded.text, model = excluded.model, '
      'created_at = excluded.created_at',
      [
        translation.packId,
        translation.workSlug,
        translation.ref,
        translation.language,
        translation.text,
        translation.model,
        translation.createdAt.toUtc().toIso8601String(),
      ],
    ),
  );

  /// A small app setting, such as the download host the reader picked.
  String? setting(String key) => _withRegistry((db) {
    final rows = db.select('SELECT value FROM app_settings WHERE key = ?', [
      key,
    ]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  });

  /// Stores a setting, or removes it when [value] is null.
  void saveSetting(String key, String? value) => _withRegistry(
    (db) => value == null
        ? db.execute('DELETE FROM app_settings WHERE key = ?', [key])
        : db.execute(
            'INSERT INTO app_settings (key, value) VALUES (?, ?) '
            'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
            [key, value],
          ),
  );

  /// Forgets on-device translations: all of them, or one language's.
  void clearLocalTranslations({String? language}) => _withRegistry(
    (db) => language == null
        ? db.execute('DELETE FROM local_translations')
        : db.execute('DELETE FROM local_translations WHERE language = ?', [
            language,
          ]),
  );

  ReadingMark _mark(Row row, String timeColumn) => ReadingMark(
    packId: row['pack_id'] as String,
    workSlug: row['work_slug'] as String,
    ref: row['ref'] as String,
    at: DateTime.parse(row[timeColumn] as String),
  );

  T _withRegistry<T>(T Function(Database db) body) {
    root.createSync(recursive: true);
    final db = sqlite3.open(p.join(root.path, 'registry.sqlite'));
    try {
      db
        ..execute(
          'CREATE TABLE IF NOT EXISTS installed_packs ('
          'pack_id TEXT PRIMARY KEY, revision INTEGER NOT NULL, '
          'file TEXT NOT NULL, origin TEXT NOT NULL, installed_at TEXT NOT NULL)',
        )
        // Reading marks reference content by (pack, work, ref), which stays
        // stable across pack revisions, never by database row id.
        ..execute(
          'CREATE TABLE IF NOT EXISTS reading_progress ('
          'pack_id TEXT NOT NULL, work_slug TEXT NOT NULL, ref TEXT NOT NULL, '
          'updated_at TEXT NOT NULL, PRIMARY KEY (pack_id, work_slug))',
        )
        ..execute(
          'CREATE TABLE IF NOT EXISTS bookmarks ('
          'pack_id TEXT NOT NULL, work_slug TEXT NOT NULL, ref TEXT NOT NULL, '
          'created_at TEXT NOT NULL, PRIMARY KEY (pack_id, work_slug, ref))',
        )
        // Kept here rather than in the pack database, which is replaced whole
        // on every pack update and holds published text only.
        ..execute(
          'CREATE TABLE IF NOT EXISTS local_translations ('
          'pack_id TEXT NOT NULL, work_slug TEXT NOT NULL, ref TEXT NOT NULL, '
          'language TEXT NOT NULL, text TEXT NOT NULL, model TEXT NOT NULL, '
          'created_at TEXT NOT NULL, '
          'PRIMARY KEY (pack_id, work_slug, ref, language))',
        )
        ..execute(
          'CREATE TABLE IF NOT EXISTS app_settings ('
          'key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      return body(db);
    } finally {
      db.close();
    }
  }
}

PackContent _readContent(List<int> bytes, PackManifest manifest) {
  final PackContent content;
  try {
    content = PackContent.fromJson(jsonDecode(utf8.decode(bytes)));
  } on FormatException catch (e) {
    throw PackIntegrityException('pack content is not JSON: ${e.message}');
  } on PackFormatException catch (e) {
    throw PackIntegrityException('pack content is invalid: ${e.message}');
  }
  if (content.packId != manifest.packId ||
      content.revision != manifest.revision) {
    throw const PackIntegrityException('pack content does not match manifest');
  }
  return content;
}

void _validateDatabase(String path, PackManifest manifest) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    Object? pragma(String name) => db.select('PRAGMA $name').first.columnAt(0);

    if (pragma('application_id') != packApplicationId) {
      throw const PackIntegrityException('payload is not a pack database');
    }
    if (pragma('user_version') != manifest.schemaVersion) {
      throw const PackIntegrityException('schema version does not match');
    }
    if (pragma('integrity_check') != 'ok') {
      throw const PackIntegrityException('pack database is corrupt');
    }

    final meta = {
      for (final row in db.select('SELECT key, value FROM pack_meta'))
        row['key']: row['value'],
    };
    if (meta['pack_id'] != manifest.packId ||
        meta['revision'] != '${manifest.revision}' ||
        meta['schema_version'] != '${manifest.schemaVersion}') {
      throw const PackIntegrityException('pack_meta does not match manifest');
    }

    final cleared = {for (final l in manifest.licences) l.id};
    for (final row in db.select(
      'SELECT id, commercial_redistribution FROM licences',
    )) {
      if (row['commercial_redistribution'] != 1 ||
          !cleared.contains(row['id'])) {
        throw PackIntegrityException(
          'licence "${row['id']}" is not cleared in the manifest',
        );
      }
    }
  } on SqliteException catch (e) {
    throw PackIntegrityException('pack database is unreadable: ${e.message}');
  } finally {
    db.close();
  }
}

Future<String> _sha256(Stream<List<int>> bytes) async =>
    (await crypto.sha256.bind(bytes).first).toString();

String _randomHex() {
  final rng = math.Random.secure();
  return List.generate(
    8,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
