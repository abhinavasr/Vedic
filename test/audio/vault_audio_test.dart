import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/audio/chant_audio.dart';
import 'package:vedic/audio/vault_audio.dart';

const _request = ChantRequest(
  packId: 'bhagavad-gita.sa',
  workSlug: 'bhagavad-gita',
  ref: '2.47',
  text: 'कर्मण्येवाधिकारस्ते',
);

final _audio = utf8.encode('pretend this is a wav');
final _digest = crypto.sha256.convert(_audio).toString();

class _Vault implements AudioFetcher {
  _Vault({this.body, this.missing = false});

  final List<int>? body;
  final bool missing;
  final headers = <String, String>{};
  var calls = 0;

  @override
  Future<List<int>?> get(Uri url, Map<String, String> headers) async {
    calls++;
    this.headers.addAll(headers);
    return missing ? null : body;
  }
}

VaultAudioLookup _published({String? sha, int bytes = 0}) =>
    (request) => VaultAudioFile(
      url: 'https://ai.abhinava.xyz/audio-vault/files/abc123',
      sha256: sha ?? _digest,
      bytes: bytes,
    );

void main() {
  test('fetches the published file and sends the key', () async {
    final vault = _Vault(body: _audio);
    final source = VaultAudioSource(
      voiceId: 'vagdhenu-m1',
      lookup: _published(),
      apiKey: 'the-key',
      fetcher: vault,
    );

    expect(await source.fetch(_request), _audio);
    expect(vault.headers['X-API-Key'], 'the-key');
  });

  test('a build with no key behaves as though there were no vault', () async {
    // Rule 3: every feature degrades to absent. A build that was never given
    // a key has no server audio, and asks the vault nothing.
    final vault = _Vault(body: _audio);
    final source = VaultAudioSource(
      voiceId: 'vagdhenu-m1',
      lookup: _published(),
      apiKey: '',
      fetcher: vault,
    );

    expect(source.available, isFalse);
    expect(await source.fetch(_request), isNull);
    expect(vault.calls, 0, reason: 'nothing to ask, so nothing is asked');
  });

  test('a verse the pack has no recording for is not asked about', () async {
    final vault = _Vault(body: _audio);
    final source = VaultAudioSource(
      voiceId: 'vagdhenu-m1',
      lookup: (_) => null,
      apiKey: 'the-key',
      fetcher: vault,
    );

    expect(await source.fetch(_request), isNull);
    expect(vault.calls, 0);
  });

  test('a verse the vault has lost is no chant, not an error', () async {
    final source = VaultAudioSource(
      voiceId: 'vagdhenu-m1',
      lookup: _published(),
      apiKey: 'the-key',
      fetcher: _Vault(missing: true),
    );

    expect(await source.fetch(_request), isNull);
  });

  test('a file that does not match its checksum is refused', () async {
    // An error page, the wrong verse, or a truncated download. Playing it
    // would be worse than having no chant.
    final source = VaultAudioSource(
      voiceId: 'vagdhenu-m1',
      lookup: _published(sha: 'not-the-digest'),
      apiKey: 'the-key',
      fetcher: _Vault(body: _audio),
    );

    expect(
      () => source.fetch(_request),
      throwsA(isA<AudioNotAsPublished>()),
    );
  });

  test('a file of the wrong length is refused before it is hashed', () async {
    final source = VaultAudioSource(
      voiceId: 'vagdhenu-m1',
      lookup: _published(bytes: _audio.length + 1),
      apiKey: 'the-key',
      fetcher: _Vault(body: _audio),
    );

    expect(
      () => source.fetch(_request),
      throwsA(isA<AudioNotAsPublished>()),
    );
  });

  test('only https is fetched', () async {
    final vault = _Vault(body: _audio);
    final source = VaultAudioSource(
      voiceId: 'vagdhenu-m1',
      lookup: (_) => VaultAudioFile(
        url: 'http://ai.abhinava.xyz/audio-vault/files/abc123',
        sha256: _digest,
        bytes: 0,
      ),
      apiKey: 'the-key',
      fetcher: vault,
    );

    expect(await source.fetch(_request), isNull);
    expect(vault.calls, 0, reason: 'the key is not sent in clear');
  });
}
