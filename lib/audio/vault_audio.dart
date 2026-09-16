import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'chant_audio.dart';

// Chant audio published in the audio vault.
//
// The vault answers only with a key, and that key ships inside the app, so it
// is not a secret: anyone can read it out of an installed build. It is a
// throttle on casual traffic, not a lock — nothing may be kept in that vault
// which would matter if it were public. The key is supplied at build time
// (`--dart-define=VAULT_API_KEY=…`) so that it never enters the repository,
// and a build without it simply has no server audio, which the reader sees as
// a verse with no chant rather than as an error.

/// Where a passage's audio lives, and what it should turn out to be.
typedef VaultAudioLookup = VaultAudioFile? Function(ChantRequest request);

class VaultAudioFile {
  const VaultAudioFile({
    required this.url,
    required this.sha256,
    required this.bytes,
  });

  final String url;

  /// From the pack. The download is checked against it before it is kept.
  final String sha256;

  /// Expected size, used to reject an answer that is obviously not the file
  /// before its bytes are hashed.
  final int bytes;
}

/// Fetches a URL. A seam, so the source is testable without a network.
abstract interface class AudioFetcher {
  /// The body, or null when the server does not have it (404).
  Future<List<int>?> get(Uri url, Map<String, String> headers);
}

/// The real one.
class HttpAudioFetcher implements AudioFetcher {
  HttpAudioFetcher({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<List<int>?> get(Uri url, Map<String, String> headers) async {
    final request = await _client.getUrl(url);
    headers.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode == HttpStatus.notFound) {
      // Nothing published for this verse. Not a failure: most verses in most
      // packs have no recording, and the reader is shown that honestly.
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('${response.statusCode} from $url');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return bytes;
  }
}

/// Audio the vault holds, for [ChantAudioService] to cache and replay.
class VaultAudioSource implements ServerAudioSource {
  VaultAudioSource({
    required this.voiceId,
    required this.lookup,
    String? apiKey,
    AudioFetcher? fetcher,
  }) : _apiKey = apiKey ?? _keyFromBuild,
       _fetcher = fetcher ?? HttpAudioFetcher();

  /// Supplied at build time so it never enters the repository.
  static const _keyFromBuild = String.fromEnvironment('VAULT_API_KEY');

  /// Identifies the voice, so what the vault sent is cached apart from
  /// anything this phone made for itself.
  @override
  final String voiceId;

  /// Where to find the file for a passage, from the installed pack.
  final VaultAudioLookup lookup;
  final String _apiKey;
  final AudioFetcher _fetcher;

  /// Whether this source can be used at all. False in a build that was given
  /// no key, which then behaves as though the vault did not exist.
  bool get available => _apiKey.isNotEmpty;

  @override
  Future<List<int>?> fetch(ChantRequest request) async {
    if (!available) return null;
    final file = lookup(request);
    if (file == null) return null;
    final url = Uri.tryParse(file.url);
    if (url == null || !url.isScheme('https')) return null;

    final bytes = await _fetcher.get(url, {'X-API-Key': _apiKey});
    if (bytes == null) return null;

    // The pack says how long the file is and what it hashes to. A body that
    // fails either is something other than the recording — an error page, a
    // truncated download, the wrong verse — and playing it would be worse
    // than having no chant at all.
    if (file.bytes > 0 && bytes.length != file.bytes) {
      throw const AudioNotAsPublished('the file was not the size the pack expects');
    }
    final digest = crypto.sha256.convert(bytes).toString();
    if (digest != file.sha256.toLowerCase()) {
      throw const AudioNotAsPublished('the file did not match its checksum');
    }
    return bytes;
  }
}

/// The download was not what the pack described, so it is not kept.
class AudioNotAsPublished implements Exception {
  const AudioNotAsPublished(this.message);

  final String message;

  @override
  String toString() => 'AudioNotAsPublished: $message';
}
