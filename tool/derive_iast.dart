import 'dart:convert';
import 'dart:io';

import 'package:vedic/core/transliteration.dart';
import 'package:vedic/packs/content.dart';

const _usage = '''
Fills in the IAST transliteration of every verse from its Devanagari.

  dart run tool/derive_iast.dart <content.json> [--out <path>]

A transliteration is not a translation: it is the same text in another
script, and the mapping is mechanical. Deriving it from the Devanagari is
both free and exact, where asking a model for it is asking it to retype
scripture from memory — which it does well until it drops a vowel length,
and "ratnadhatamam" for "ratnadhātamam" is a different word.

A transliteration that was supplied with the text is kept when it reduces to
the same letters as the Devanagari, because those carry the Vedic accents as
acutes and split the sandhi into words, which is more than this can do. One
that does not reduce to the same letters is replaced.
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

  var kept = 0, derived = 0, replaced = 0;
  final works = [
    for (final work in content.works)
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
            () {
              final lines = passage.text.split('\n');
              final iast = lines.map(devanagariToIast).join('\n');
              final existing = passage.renderings.where(
                (r) => r.kind == RenderingKind.transliteration,
              );
              if (existing.isNotEmpty && iastSkeleton(existing.first.text) == iastSkeleton(iast)) {
                kept++;
                return passage;
              }
              existing.isEmpty ? derived++ : replaced++;
              return PassageSource(
                ref: passage.ref,
                kind: passage.kind,
                text: passage.text,
                label: passage.label,
                section: passage.section,
                meter: passage.meter,
                audio: passage.audio,
                renderings: [
                  ...passage.renderings.where(
                    (r) => r.kind != RenderingKind.transliteration,
                  ),
                  RenderingSource(
                    kind: RenderingKind.transliteration,
                    language: work.language,
                    script: 'Latn',
                    scheme: 'IAST',
                    text: iast,
                    // Mechanically derived from the text, so it carries the
                    // text's own licence and is not machine-generated prose.
                    licenceId: work.licenceId,
                    origin: TextOrigin.human,
                  ),
                ],
              );
            }(),
        ],
      ),
  ];

  await File(outPath).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(PackContent(
      packId: content.packId,
      revision: content.revision,
      languages: content.languages,
      licences: content.licences,
      voices: content.voices,
      works: works,
    ).toJson())}\n',
  );
  stdout.writeln(
    'kept $kept verified · derived $derived · replaced $replaced  →  $outPath',
  );
}
