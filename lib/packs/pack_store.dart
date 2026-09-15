import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'manifest.dart';
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
    final temp = File(
      p.join(
        tempDirectory.path,
        '${manifest.packId}-${manifest.revision}-${_randomHex()}.sqlite',
      ),
    );
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
        throw const PackIntegrityException('pack database checksum mismatch');
      }
      _validateDatabase(temp.path, manifest);

      final relative = p.join(manifest.packId, '${manifest.revision}.sqlite');
      final destination = File(p.join(root.path, relative));
      await destination.parent.create(recursive: true);
      await temp.rename(destination.path);

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
      if (await temp.exists()) await temp.delete();
    }
  }

  T _withRegistry<T>(T Function(Database db) body) {
    root.createSync(recursive: true);
    final db = sqlite3.open(p.join(root.path, 'registry.sqlite'));
    try {
      db.execute(
        'CREATE TABLE IF NOT EXISTS installed_packs ('
        'pack_id TEXT PRIMARY KEY, revision INTEGER NOT NULL, '
        'file TEXT NOT NULL, origin TEXT NOT NULL, installed_at TEXT NOT NULL)',
      );
      return body(db);
    } finally {
      db.close();
    }
  }
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
