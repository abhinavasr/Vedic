import 'dart:convert';
import 'dart:io';

import 'package:vedic/packs/content.dart';

const _usage = '''
Keeps only the sūktas whose every verse has audio.

  dart run tool/limit_to_audio.dart <content.json> [--out <path>]

A scripture app that offers a verse and then cannot say it is worse than one
that does not offer it: the reader taps play, nothing happens, and there is
nothing on the screen to explain why. So a release ships the part of the book
that is finished rather than all of it half-done.

Whole sūktas, not whole verses. A sūkta with verses 2, 5 and 9 in it is not a
hymn, it is the wreckage of one, and the numbering would tell the reader
something is missing without telling them what.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first == '-h') {
    stdout.writeln(_usage);
    exit(arguments.isEmpty ? 64 : 0);
  }
  final file = File(arguments.first);
  final content = PackContent.fromJson(jsonDecode(await file.readAsString()));
  final outPath = arguments.contains('--out')
      ? arguments[arguments.indexOf('--out') + 1]
      : file.path;

  var keptSections = 0, keptVerses = 0, dropped = 0, partial = 0;
  // A maṇḍala with nothing finished in it drops out altogether rather than
  // shipping as an empty book. The pack format refuses a work with no text,
  // which is the right answer: a title on a shelf that opens onto nothing is
  // worse than a title that is not there yet.
  final works = [
    for (final work in content.works)
      if (work.passages.any((p) => _keep(work, p)))
        WorkSource(
          slug: work.slug,
          kind: work.kind,
          title: work.title,
          titleNative: work.titleNative,
          titles: work.titles,
          language: work.language,
          script: work.script,
          edition: work.edition,
          licenceId: work.licenceId,
          sourceNote: work.sourceNote,
          coverUrl: work.coverUrl,
          passages: [
            for (final passage in work.passages)
              if (_keep(work, passage)) passage,
          ],
        ),
  ];

  // Counting is done over the result rather than guessed at during it.
  for (final work in content.works) {
    final bySection = <String?, List<PassageSource>>{};
    for (final passage in work.passages) {
      bySection.putIfAbsent(_sectionKey(passage), () => []).add(passage);
    }
    for (final entry in bySection.entries) {
      final verses = entry.value.where((p) => p.kind == PassageKind.verse);
      if (verses.isEmpty) continue;
      final withAudio = verses.where((p) => p.audio.isNotEmpty).length;
      if (withAudio == verses.length) {
        keptSections++;
        keptVerses += verses.length;
      } else {
        dropped++;
        if (withAudio > 0) partial++;
      }
    }
  }

  await File(outPath).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(PackContent(packId: content.packId, revision: content.revision, languages: content.languages, licences: content.licences, voices: content.voices, works: works).toJson())}\n',
  );
  stdout.writeln(
    'kept $keptSections sūktas, $keptVerses verses · dropped $dropped '
    '($partial of them part-recorded) → $outPath',
  );
}

String? _sectionKey(PassageSource passage) =>
    passage.section?.number ?? passage.ref.split('.').take(2).join('.');

/// Whether this passage survives: its sūkta must be recorded right through.
bool _keep(WorkSource work, PassageSource passage) {
  final key = _sectionKey(passage);
  final verses = work.passages.where(
    (p) => _sectionKey(p) == key && p.kind == PassageKind.verse,
  );
  if (verses.isEmpty) return false;
  return verses.every((p) => p.audio.isNotEmpty);
}
