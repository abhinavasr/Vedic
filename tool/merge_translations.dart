import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:vedic/packs/content.dart';
import 'package:vedic/packs/manifest.dart' show JsonReader;

const _usage = '''
Merges translation responses into a pack's content JSON, keyed by verse ref.

  dart run tool/merge_translations.dart <content.json> <response.json>... [options]

Each response holds {"verses": {"<ref>": {iast, hi, en, explanation_en,
explanation_hi, takeaways_en}}}. Missing fields are skipped, unknown refs are
reported, and existing text of the same kind and language is replaced.
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('out', help: 'Where to write the merged content JSON.')
    ..addOption('revision', help: 'Set the content revision, e.g. 2.')
    ..addOption(
      'licence',
      help: 'Licence id for the merged text. Defaults to the work licence.',
    )
    ..addOption(
      'licence-name',
      help: 'Creates the --licence entry with this name if it is missing.',
    )
    ..addOption(
      'licence-attribution',
      help: 'Credit shown in the reader for the merged text.',
    )
    ..addOption(
      'origin',
      allowed: ['machine', 'human'],
      defaultsTo: 'machine',
      help: 'How translations are labelled in the app.',
    )
    ..addOption('translator', help: 'Credit shown with the translations.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  if (args.flag('help') || args.rest.length < 2) {
    stdout.writeln('$_usage\n${parser.usage}');
    exit(args.flag('help') ? 0 : 64);
  }

  final contentFile = File(args.rest.first);
  final content = PackContent.fromJson(
    jsonDecode(await contentFile.readAsString()),
  );

  final answers = <String, JsonReader>{};
  for (final path in args.rest.skip(1)) {
    final decoded = jsonDecode(await File(path).readAsString());
    final verses = JsonReader(decoded, path).object('verses');
    for (final ref in verses.map.keys) {
      answers[ref] = verses.object(ref);
    }
  }
  stdout.writeln('${answers.length} verses in ${args.rest.length - 1} files');

  final origin = args.option('origin') == 'human'
      ? TextOrigin.human
      : TextOrigin.machine;
  final licenceOverride = args.option('licence');
  final licences = [...content.licences];
  if (licenceOverride != null &&
      !licences.any((l) => l.id == licenceOverride)) {
    final name = args.option('licence-name');
    if (name == null) {
      stderr.writeln(
        'error: no licence "$licenceOverride" in the content; pass '
        '--licence-name to create it',
      );
      exit(1);
    }
    licences.add(
      LicenceSource(
        id: licenceOverride,
        name: name,
        commercialRedistribution: true,
        attribution: args.option('licence-attribution') ?? name,
      ),
    );
  }

  final used = <String>{};
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
            _merge(
              passage,
              answers[passage.ref],
              used: used,
              licenceId: licenceOverride ?? work.licenceId,
              origin: origin,
              translator: args.option('translator'),
            ),
        ],
      ),
  ];

  final merged = PackContent(
    packId: content.packId,
    revision: int.tryParse(args.option('revision') ?? '') ?? content.revision,
    languages: _languages(content, works),
    licences: licences,
    voices: content.voices,
    works: works,
  );

  final unmatched = answers.keys.where((ref) => !used.contains(ref)).toList();
  if (unmatched.isNotEmpty) {
    stderr.writeln(
      'warning: ${unmatched.length} refs are not in this pack: '
      '${unmatched.take(10).join(', ')}',
    );
  }
  stdout.writeln('merged ${used.length} verses');

  final out = File(args.option('out') ?? contentFile.path);
  await out.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(merged.toJson())}\n',
  );
  stdout.writeln('${out.path}  (${await out.length()} bytes)');
}

PassageSource _merge(
  PassageSource passage,
  JsonReader? answer, {
  required Set<String> used,
  required String licenceId,
  required TextOrigin origin,
  required String? translator,
}) {
  if (answer == null) return passage;
  used.add(passage.ref);

  final added = <RenderingSource>[];
  final iast = _lines(answer, 'iast');
  if (iast.isNotEmpty) {
    added.add(
      RenderingSource(
        kind: RenderingKind.transliteration,
        language: 'sa',
        script: 'Latn',
        scheme: 'IAST',
        text: iast.join('\n'),
      ),
    );
  }
  for (final language in ['hi', 'en']) {
    final text = _text(answer, language);
    if (text == null) continue;
    added.add(
      RenderingSource(
        kind: RenderingKind.translation,
        language: language,
        text: text,
        author: translator,
        licenceId: licenceId,
        origin: origin,
      ),
    );
  }
  for (final language in ['en', 'hi']) {
    final text = _text(answer, 'explanation_$language');
    if (text == null) continue;
    added.add(
      RenderingSource(
        kind: RenderingKind.commentary,
        language: language,
        scheme: 'explanation',
        text: text,
        author: translator,
        licenceId: licenceId,
        origin: origin,
      ),
    );
  }
  for (final takeaway in _lines(answer, 'takeaways_en')) {
    added.add(
      RenderingSource(
        kind: RenderingKind.commentary,
        language: 'en',
        scheme: 'takeaway',
        text: takeaway,
        author: translator,
        licenceId: licenceId,
        origin: origin,
      ),
    );
  }
  if (added.isEmpty) return passage;

  // Replace anything of the same kind, language and scheme; keep the rest.
  bool replaced(RenderingSource existing) => added.any(
    (r) =>
        r.kind == existing.kind &&
        r.language == existing.language &&
        r.scheme == existing.scheme,
  );

  return PassageSource(
    ref: passage.ref,
    kind: passage.kind,
    text: passage.text,
    label: passage.label,
    section: passage.section,
    meter: passage.meter,
    renderings: [
      for (final existing in passage.renderings)
        if (!replaced(existing)) existing,
      ...added,
    ],
    audio: passage.audio,
  );
}

List<String> _lines(JsonReader answer, String key) {
  final value = answer.map[key];
  if (value is! List) return const [];
  return [
    for (final line in value)
      if (line is String && line.trim().isNotEmpty) line.trim(),
  ];
}

String? _text(JsonReader answer, String key) {
  final value = answer.map[key];
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

List<String> _languages(PackContent content, List<WorkSource> works) {
  final languages = [...content.languages];
  for (final work in works) {
    for (final passage in work.passages) {
      for (final rendering in passage.renderings) {
        if (rendering.kind == RenderingKind.transliteration) continue;
        if (!languages.contains(rendering.language)) {
          languages.add(rendering.language);
        }
      }
    }
  }
  return languages;
}
