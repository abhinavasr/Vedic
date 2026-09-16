import 'dart:io';

import 'package:path/path.dart' as p;

import '../ui/listen_meaning.dart';
import 'chant_audio.dart';
import 'vault_audio.dart';

// Joining the three parts of a chant: what the pack says exists, where it is
// fetched from, and where it is kept once fetched. They live apart so that
// none of them has to know about the others — the reader asks for a recording
// and gets one, or gets nothing.

/// Wires chant playback, caching downloads under [directory].
///
/// Returns null when nothing can supply a chant — a build with no vault key —
/// and the reader then simply has no chant, which it already handles.
ChantSource? chantSource({required Directory directory}) {
  // What the verse being asked about publishes, remembered just long enough
  // for the fetch below to read it. The passage carries its own audio, so
  // there is nothing to look up: it is handed across rather than searched for.
  final published = <String, VaultAudioFile>{};
  String keyOf(ChantRequest request) => '${request.ref}|${request.text}';

  final vault = VaultAudioSource(
    // The pack's voice. Recordings are cached under it, so a pack that moves
    // to a better voice never replays the old one.
    voiceId: 'vagdhenu-m1',
    lookup: (request) => published[keyOf(request)],
  );
  if (!vault.available) return null;

  final service = ChantAudioService(
    cache: ChantCache(Directory(p.join(directory.path, 'chants'))),
    server: vault,
  );

  return ChantSource(
    find: (verse) async {
      final audio = verse.audio.firstOrNull;
      if (audio == null) return null;
      final request = ChantRequest(
        packId: '',
        workSlug: '',
        ref: verse.ref,
        // Part of the cache key: a verse corrected in a later revision must
        // never replay the recording made from the old wording.
        text: verse.text,
      );
      published[keyOf(request)] = VaultAudioFile(
        url: audio.file,
        sha256: audio.sha256,
        bytes: audio.size,
      );
      try {
        final chant = await service.resolve(request);
        return chant?.file;
      } on Object {
        // Offline, or a download that did not match what the pack published.
        // Either way this verse has no chant right now.
        return null;
      }
    },
  );
}
