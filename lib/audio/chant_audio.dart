import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

// Chant audio for a passage, from the best source available: an installed
// audio pack, the server, or generated on this phone and kept for replay so
// it is only ever generated once.

class ChantRequest {
  const ChantRequest({
    required this.packId,
    required this.workSlug,
    required this.ref,
    required this.text,
  });

  final String packId;
  final String workSlug;
  final String ref;

  /// The exact text to chant. Part of the cache key, so a corrected text in a
  /// newer pack revision never replays audio made from the old one.
  final String text;

  String get _identity => [packId, workSlug, ref, text].join('|');
}

enum ChantOrigin { pack, server, generated }

class ChantAudio {
  const ChantAudio({required this.file, required this.origin});

  final File file;
  final ChantOrigin origin;
}

/// Audio shipped in an installed audio pack.
abstract interface class PackAudioSource {
  Future<File?> find(ChantRequest request);
}

/// Audio published on the static host.
abstract interface class ServerAudioSource {
  /// Identifies the server's voice, so its audio is cached apart from
  /// on-device audio.
  String get voiceId;

  /// The audio file's bytes, or null if the server has none for [request].
  /// May throw when offline; the service then falls back to generating.
  Future<List<int>?> fetch(ChantRequest request);
}

/// On-device speech generation. Implementations serialise their own
/// inference (one model instance, one request at a time).
abstract interface class ChantEngine {
  /// Identifies the model and voice, including the model file's revision, so
  /// a new model never replays audio from the old one.
  String get voiceId;

  /// WAV bytes for [text].
  Future<List<int>> generate(String text);
}

/// What the cache is holding.
class CacheUsage {
  const CacheUsage({
    required this.bytes,
    required this.files,
    this.kept = 0,
  });

  final int bytes;
  final int files;

  /// How many were downloaded on purpose rather than picked up by listening.
  final int kept;

  bool get isEmpty => files == 0;

  /// Rounded the way a storage screen would say it.
  String get size {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).round()} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes bytes';
  }
}

/// Audio downloaded or generated on this phone, evicted least recently played
/// first once it outgrows [maxBytes].
class ChantCache {
  ChantCache(this.directory, {this.maxBytes = 300 * 1024 * 1024});

  final Directory directory;
  final int maxBytes;

  Future<File?> get(ChantRequest request, String voiceId) async {
    final file = _fileFor(request, voiceId);
    if (!await file.exists()) return null;
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // Recency is best-effort; a stale timestamp only affects eviction order.
    }
    return file;
  }

  Future<File> put(
    ChantRequest request,
    String voiceId,
    List<int> bytes,
  ) async {
    await directory.create(recursive: true);
    final file = _fileFor(request, voiceId);
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
    await _evict(keep: file.path);
    return file;
  }

  /// How much of the phone this has taken, and over how many recordings.
  ///
  /// Eviction keeps it under [maxBytes] without anyone being told, which is
  /// the right default and the wrong thing to be silent about: somebody
  /// looking for what is using their storage should find it and be able to
  /// take it back.
  Future<CacheUsage> usage() async {
    if (!await directory.exists()) return const CacheUsage(bytes: 0, files: 0);
    var bytes = 0, files = 0, kept = 0;
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.wav')) {
        bytes += await entity.length();
        files++;
        if (File('${entity.path}.pin').existsSync()) kept++;
      }
    }
    return CacheUsage(bytes: bytes, files: files, kept: kept);
  }

  /// Throws all of it away. Nothing is lost that cannot be fetched again.
  Future<CacheUsage> clear() async {
    final before = await usage();
    if (!await directory.exists()) return before;
    await for (final entity in directory.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } on FileSystemException {
          // A file being played is held open; the next sweep takes it.
        }
      }
    }
    return before;
  }

  /// Whether this verse is already on the phone.
  Future<bool> has(ChantRequest request, String voiceId) =>
      _fileFor(request, voiceId).exists();

  /// Keeps this recording until the reader says otherwise.
  ///
  /// Eviction exists so that listening to a lot does not quietly fill a
  /// phone. Downloading a book on purpose is the opposite: it is a promise
  /// that it will be there on a train with no signal, and a cache that
  /// evicted its way through the download would break that promise while
  /// appearing to keep it. A pinned recording is skipped by eviction and
  /// goes only when the reader removes the book or clears everything.
  Future<void> pin(ChantRequest request, String voiceId) async {
    final marker = File('${_fileFor(request, voiceId).path}.pin');
    if (!await marker.exists()) await marker.create(recursive: true);
  }

  Future<void> unpin(ChantRequest request, String voiceId) async {
    final marker = File('${_fileFor(request, voiceId).path}.pin');
    if (await marker.exists()) await marker.delete();
  }

  File _fileFor(ChantRequest request, String voiceId) {
    final digest = crypto.sha256.convert(
      utf8.encode('${request._identity}|$voiceId'),
    );
    return File(p.join(directory.path, '$digest.wav'));
  }

  Future<void> _evict({required String keep}) async {
    final entries = [
      for (final entity in directory.listSync())
        if (entity is File && entity.path.endsWith('.wav'))
          (
            file: entity,
            stat: entity.statSync(),
            pinned: File('${entity.path}.pin').existsSync(),
          ),
    ]..sort((a, b) => a.stat.modified.compareTo(b.stat.modified));

    // Pinned recordings count towards what is on the phone — the reader
    // asked for them and should see them in the total — but they are not
    // candidates for eviction.
    var total = entries.fold(0, (sum, e) => sum + e.stat.size);
    for (final e in entries) {
      if (total <= maxBytes) break;
      if (e.file.path == keep || e.pinned) continue;
      await e.file.delete();
      total -= e.stat.size;
    }
  }
}

class ChantAudioService {
  ChantAudioService({
    required this.cache,
    this.packs,
    this.server,
    this.engine,
  });

  final ChantCache cache;
  final PackAudioSource? packs;
  final ServerAudioSource? server;
  final ChantEngine? engine;

  final _inFlight = <String, Future<ChantAudio?>>{};

  /// Audio for [request], or null if no source can provide it (no pack, no
  /// server audio, no model installed).
  ///
  /// Order: installed audio pack; server audio (cached after the first
  /// download); audio generated earlier on this phone; otherwise generate now
  /// and keep it. Concurrent requests for the same passage share one result,
  /// so a double tap never generates twice.
  Future<ChantAudio?> resolve(ChantRequest request) {
    final id = request._identity;
    return _inFlight[id] ??= _resolve(request).whenComplete(() {
      _inFlight.remove(id);
    });
  }

  Future<ChantAudio?> _resolve(ChantRequest request) async {
    final packFile = await packs?.find(request);
    if (packFile != null) {
      return ChantAudio(file: packFile, origin: ChantOrigin.pack);
    }

    final server = this.server;
    if (server != null) {
      final cached = await cache.get(request, server.voiceId);
      if (cached != null) {
        return ChantAudio(file: cached, origin: ChantOrigin.server);
      }
      List<int>? bytes;
      try {
        bytes = await server.fetch(request);
      } on Exception {
        bytes = null;
      }
      if (bytes != null) {
        return ChantAudio(
          file: await cache.put(request, server.voiceId, bytes),
          origin: ChantOrigin.server,
        );
      }
    }

    final engine = this.engine;
    if (engine == null) return null;
    final cached = await cache.get(request, engine.voiceId);
    if (cached != null) {
      return ChantAudio(file: cached, origin: ChantOrigin.generated);
    }
    final wav = await engine.generate(request.text);
    return ChantAudio(
      file: await cache.put(request, engine.voiceId, wav),
      origin: ChantOrigin.generated,
    );
  }
}

/// Float samples in [-1, 1] as 16-bit PCM, clipping anything out of range.
Int16List pcm16FromFloat(List<double> samples) => Int16List.fromList([
  for (final s in samples) (s.clamp(-1.0, 1.0) * 32767).round(),
]);

/// A mono 16-bit PCM WAV file.
Uint8List wavFromPcm16(Int16List samples, {required int sampleRate}) {
  const headerLength = 44;
  final dataLength = samples.length * 2;
  final out = ByteData(headerLength + dataLength);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      out.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  const le = Endian.little;
  ascii(0, 'RIFF');
  out.setUint32(4, 36 + dataLength, le);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out
    ..setUint32(16, 16, le)
    ..setUint16(20, 1, le)
    ..setUint16(22, 1, le)
    ..setUint32(24, sampleRate, le)
    ..setUint32(28, sampleRate * 2, le)
    ..setUint16(32, 2, le)
    ..setUint16(34, 16, le);
  ascii(36, 'data');
  out.setUint32(40, dataLength, le);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(headerLength + 2 * i, samples[i], le);
  }
  return out.buffer.asUint8List();
}
