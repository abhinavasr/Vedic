import 'dart:convert';

/// A pack file that does not meet docs/CONTENT_PACKS.md.
class PackFormatException implements Exception {
  const PackFormatException(this.message);

  final String message;

  @override
  String toString() => 'PackFormatException: $message';
}

enum PayloadCompression { none, deflate }

enum PayloadEncryption { none, vpk1 }

enum KeyDelivery { none, hpkeDeviceEnvelope }

class PackPayload {
  const PackPayload({
    required this.file,
    required this.size,
    required this.sha256,
    required this.compression,
    required this.encryption,
    required this.keyDelivery,
    required this.plaintextSize,
    required this.plaintextSha256,
  });

  /// File name next to the manifest. Never contains a path separator.
  final String file;
  final int size;

  /// Lowercase hex SHA-256 of the payload file exactly as served.
  final String sha256;
  final PayloadCompression compression;
  final PayloadEncryption encryption;
  final KeyDelivery keyDelivery;
  final int plaintextSize;

  /// Lowercase hex SHA-256 of the decrypted, decompressed SQLite database.
  final String plaintextSha256;

  bool get isEncrypted => encryption != PayloadEncryption.none;
}

class PackLicence {
  const PackLicence({
    required this.id,
    required this.commercialRedistribution,
    this.grantReference,
  });

  final String id;
  final bool commercialRedistribution;
  final String? grantReference;
}

class PackEmbeddings {
  const PackEmbeddings({
    required this.embedderId,
    required this.embedderRevision,
    required this.dimensions,
    required this.quantisation,
  });

  final String embedderId;
  final String embedderRevision;
  final int dimensions;
  final String quantisation;
}

/// Why an otherwise valid pack can't be installed right now.
enum InstallBlock {
  /// Built for a newer app: its schema or minimum app build is ahead of us.
  needsAppUpdate,

  /// Same or older revision than the one installed.
  notNewer,
}

/// The signed description of one pack revision (docs/CONTENT_PACKS.md §4).
class PackManifest {
  const PackManifest({
    required this.packId,
    required this.revision,
    required this.kind,
    required this.schemaVersion,
    required this.minAppBuild,
    required this.createdAt,
    required this.title,
    required this.languages,
    required this.payload,
    required this.embeddings,
    required this.licences,
  });

  /// Parses and validates manifest bytes.
  ///
  /// Throws [PackFormatException] for anything malformed. Signature checks
  /// happen before this, on the raw bytes.
  factory PackManifest.parse(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw PackFormatException('manifest is not UTF-8 JSON: ${e.message}');
    }
    final j = JsonReader(decoded, 'manifest');

    if (j.string('format') != 'vedic-pack') {
      throw const PackFormatException('manifest.format must be "vedic-pack"');
    }
    final formatVersion = j.integer('format_version', min: 1);
    if (formatVersion != formatVersionSupported) {
      throw PackFormatException('unsupported format_version $formatVersion');
    }

    final packId = j.string('pack_id');
    if (!packIdPattern.hasMatch(packId)) {
      throw PackFormatException('invalid pack_id "$packId"');
    }

    final kind = j.string('kind');
    if (kind != 'text' && kind != 'audio') {
      throw PackFormatException('unknown kind "$kind"');
    }

    final createdAt = DateTime.tryParse(j.string('created_at'));
    if (createdAt == null) {
      throw const PackFormatException('manifest.created_at is not a date');
    }

    final licences = [
      for (final l in j.objects('licences'))
        PackLicence(
          id: l.string('id'),
          commercialRedistribution: l.boolean('commercial_redistribution'),
          grantReference: l.optionalString('grant_reference'),
        ),
    ];
    if (licences.isEmpty) {
      throw const PackFormatException('manifest.licences must not be empty');
    }
    for (final l in licences) {
      if (!l.commercialRedistribution) {
        throw PackFormatException(
          'licence "${l.id}" is not cleared for commercial redistribution',
        );
      }
    }

    return PackManifest(
      packId: packId,
      revision: j.integer('revision', min: 1),
      kind: kind,
      schemaVersion: j.integer('schema_version', min: 1),
      minAppBuild: j.integer('min_app_build'),
      createdAt: createdAt,
      title: j.stringMap('title'),
      languages: j.strings('languages'),
      payload: _parsePayload(j.object('payload')),
      embeddings: [
        for (final e in j.objects('embeddings', optional: true))
          PackEmbeddings(
            embedderId: e.string('embedder_id'),
            embedderRevision: e.string('embedder_revision'),
            dimensions: e.integer('dimensions', min: 1),
            quantisation: e.string('quantisation'),
          ),
      ],
      licences: licences,
    );
  }

  static const int formatVersionSupported = 1;
  static const int schemaVersionSupported = 1;
  static final RegExp packIdPattern = RegExp(r'^[a-z0-9]+(?:[.-][a-z0-9]+)*$');

  final String packId;
  final int revision;

  /// "text" or "audio".
  final String kind;
  final int schemaVersion;
  final int minAppBuild;
  final DateTime createdAt;

  /// Title by BCP 47 language tag.
  final Map<String, String> title;
  final List<String> languages;
  final PackPayload payload;
  final List<PackEmbeddings> embeddings;
  final List<PackLicence> licences;

  /// Title in [language], falling back to English, then any title.
  String titleFor(String language) =>
      title[language] ?? title['en'] ?? title.values.first;

  InstallBlock? installBlock({required int appBuild, int? installedRevision}) {
    if (schemaVersion > schemaVersionSupported || minAppBuild > appBuild) {
      return InstallBlock.needsAppUpdate;
    }
    if (installedRevision != null && revision <= installedRevision) {
      return InstallBlock.notNewer;
    }
    return null;
  }

  /// JSON in the field order of docs/CONTENT_PACKS.md §4, for the pack builder.
  Map<String, Object?> toJson() => {
    'format': 'vedic-pack',
    'format_version': formatVersionSupported,
    'pack_id': packId,
    'revision': revision,
    'kind': kind,
    'schema_version': schemaVersion,
    'min_app_build': minAppBuild,
    'created_at': createdAt.toUtc().toIso8601String(),
    'title': title,
    'languages': languages,
    'payload': {
      'file': payload.file,
      'size': payload.size,
      'sha256': payload.sha256,
      'compression': _compressionNames[payload.compression],
      'encryption': _encryptionNames[payload.encryption],
      'key_delivery': _keyDeliveryNames[payload.keyDelivery],
      'plaintext_size': payload.plaintextSize,
      'plaintext_sha256': payload.plaintextSha256,
    },
    if (embeddings.isNotEmpty)
      'embeddings': [
        for (final e in embeddings)
          {
            'embedder_id': e.embedderId,
            'embedder_revision': e.embedderRevision,
            'dimensions': e.dimensions,
            'quantisation': e.quantisation,
          },
      ],
    'licences': [
      for (final l in licences)
        {
          'id': l.id,
          'commercial_redistribution': l.commercialRedistribution,
          if (l.grantReference != null) 'grant_reference': l.grantReference,
        },
    ],
  };
}

const _compressionNames = {
  PayloadCompression.none: 'none',
  PayloadCompression.deflate: 'deflate',
};

const _encryptionNames = {
  PayloadEncryption.none: 'none',
  PayloadEncryption.vpk1: 'vpk1-aes256gcm-stream',
};

const _keyDeliveryNames = {
  KeyDelivery.none: 'none',
  KeyDelivery.hpkeDeviceEnvelope: 'hpke-device-envelope',
};

final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');
final _fileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

PackPayload _parsePayload(JsonReader p) {
  final file = p.string('file');
  if (!_fileName.hasMatch(file)) {
    throw PackFormatException('payload.file "$file" is not a plain file name');
  }
  final encryption = p.oneOf('encryption', _encryptionNames);
  final keyDelivery = p.oneOf('key_delivery', _keyDeliveryNames);
  if ((encryption == PayloadEncryption.none) !=
      (keyDelivery == KeyDelivery.none)) {
    throw const PackFormatException(
      'payload.encryption and payload.key_delivery must both be "none" or '
      'both be set',
    );
  }
  return PackPayload(
    file: file,
    size: p.integer('size'),
    sha256: p.hex('sha256'),
    compression: p.oneOf('compression', _compressionNames),
    encryption: encryption,
    keyDelivery: keyDelivery,
    plaintextSize: p.integer('plaintext_size'),
    plaintextSha256: p.hex('plaintext_sha256'),
  );
}

/// Typed access to a decoded JSON object, with the path in every error.
class JsonReader {
  JsonReader(Object? value, this.path)
    : map = value is Map<String, Object?>
          ? value
          : throw PackFormatException('$path must be an object');

  final Map<String, Object?> map;
  final String path;

  /// Whether [key] is present and not null.
  bool has(String key) => map[key] != null;

  Object? _require(String key) {
    if (!map.containsKey(key)) {
      throw PackFormatException('$path.$key is missing');
    }
    return map[key];
  }

  String string(String key) {
    final v = _require(key);
    if (v is String && v.isNotEmpty) return v;
    throw PackFormatException('$path.$key must be a non-empty string');
  }

  String? optionalString(String key) {
    final v = map[key];
    if (v == null || v is String) return v as String?;
    throw PackFormatException('$path.$key must be a string');
  }

  int integer(String key, {int min = 0}) {
    final v = _require(key);
    if (v is int && v >= min) return v;
    throw PackFormatException('$path.$key must be an integer of at least $min');
  }

  bool boolean(String key) {
    final v = _require(key);
    if (v is bool) return v;
    throw PackFormatException('$path.$key must be true or false');
  }

  String hex(String key) {
    final v = string(key);
    if (_sha256Hex.hasMatch(v)) return v;
    throw PackFormatException('$path.$key must be 64 lowercase hex digits');
  }

  T oneOf<T>(String key, Map<T, String> names) {
    final v = string(key);
    for (final MapEntry(:key, :value) in names.entries) {
      if (value == v) return key;
    }
    throw PackFormatException('$path.$key has unknown value "$v"');
  }

  JsonReader object(String key) => JsonReader(_require(key), '$path.$key');

  List<JsonReader> objects(String key, {bool optional = false}) {
    if (optional && map[key] == null) return const [];
    final v = _require(key);
    if (v is! List) throw PackFormatException('$path.$key must be a list');
    return [
      for (var i = 0; i < v.length; i++) JsonReader(v[i], '$path.$key[$i]'),
    ];
  }

  List<String> strings(String key) {
    final v = _require(key);
    if (v is List &&
        v.isNotEmpty &&
        v.every((e) => e is String && e.isNotEmpty)) {
      return List.unmodifiable(v.cast<String>());
    }
    throw PackFormatException('$path.$key must be a non-empty list of strings');
  }

  Map<String, String> stringMap(String key) {
    final v = _require(key);
    if (v is Map<String, Object?> &&
        v.isNotEmpty &&
        v.values.every((e) => e is String && e.isNotEmpty)) {
      return Map.unmodifiable(v.cast<String, String>());
    }
    throw PackFormatException(
      '$path.$key must be a non-empty object of strings',
    );
  }
}
