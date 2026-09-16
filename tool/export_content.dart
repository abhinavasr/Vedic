import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:vedic/packs/content.dart';
import 'package:vedic/packs/manifest.dart';

const _usage = '''
Exports a built pack's content as readable JSON, and as one translation
request per chapter for sending to a translation service.

  dart run tool/export_content.dart <pack-revision-dir> [options]

<pack-revision-dir> is a directory built by tool/build_pack.dart, e.g.
build/packs/bhagavad-gita.sa/1.
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('out', defaultsTo: 'build/export', help: 'Output directory.')
    ..addFlag(
      'requests',
      defaultsTo: true,
      help: 'Also write one translation request file per chapter.',
    )
    ..addOption(
      'batch',
      help: 'Split each chapter into files of at most this many verses.',
    )
    ..addFlag(
      'single',
      negatable: false,
      help: 'Write one compact request file holding every verse.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  if (args.flag('help') || args.rest.length != 1) {
    stdout.writeln('$_usage\n${parser.usage}');
    exit(args.flag('help') ? 0 : 64);
  }

  final dir = Directory(args.rest.single);
  final manifest = PackManifest.parse(
    await File(p.join(dir.path, 'manifest.json')).readAsBytes(),
  );
  if (manifest.payload.isEncrypted) {
    stderr.writeln(
      'error: ${dir.path} is encrypted; export from an '
      'unencrypted build instead.',
    );
    exit(1);
  }

  final payload = await File(p.join(dir.path, manifest.payload.file))
      .readAsBytes();
  final plain = manifest.payload.compression == PayloadCompression.deflate
      ? ZLibCodec().decode(payload)
      : payload;
  final content = PackContent.fromJson(jsonDecode(utf8.decode(plain)));

  final out = Directory(args.option('out')!);
  await out.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');

  final full = File(p.join(out.path, '${content.packId}.content.json'));
  await full.writeAsString('${encoder.convert(content.toJson())}\n');
  stdout.writeln('${full.path}  (${await full.length()} bytes)');

  if (args.flag('single')) {
    for (final work in content.works) {
      final file = File(
        p.join(out.path, '${content.packId}.${work.slug}.request.json'),
      );
      await file.writeAsString(jsonEncode(_singleRequest(content, work)));
      stdout.writeln('${file.path}  (${await file.length()} bytes)');
    }
    return;
  }

  if (!args.flag('requests')) return;
  for (final work in content.works) {
    final requests = Directory(p.join(out.path, content.packId, work.slug));
    await requests.create(recursive: true);
    for (final section in _sectionsOf(work)) {
      final verses = [
        for (final passage in work.passages)
          if (passage.section?.path == section.path &&
              passage.kind == PassageKind.verse)
            passage,
      ];
      if (verses.isEmpty) continue;
      final batch = int.tryParse(args.option('batch') ?? '') ?? verses.length;
      final parts = (verses.length / batch).ceil();
      for (var part = 0; part < parts; part++) {
        final slice = verses.skip(part * batch).take(batch).toList();
        final suffix = parts == 1 ? '' : '-part${part + 1}';
        final file = File(
          p.join(requests.path, '${_fileName(section)}$suffix.json'),
        );
        await file.writeAsString(
          '${encoder.convert(_request(content, work, section, slice, part: part + 1, of: parts))}\n',
        );
        stdout.writeln('${file.path}  (${slice.length} verses)');
      }
    }
  }
}

/// Every verse of a work in one compact request: the Sanskrit only, with the
/// fields to return described once rather than repeated per verse.
Map<String, Object?> _singleRequest(PackContent content, WorkSource work) => {
  'format': 'vedic-translation-request',
  'format_version': 1,
  'pack_id': content.packId,
  'work': work.slug,
  'instructions': [
    'For every verse below, produce transliteration, translations and notes.',
    'Return JSON only, shaped exactly as "output_example", with one entry per '
        '"ref". Do not repeat the Sanskrit. Do not change any "ref".',
    'If your reply cannot hold every verse, return whole chapters at a time '
        'and say which chapter you stopped after. Never summarise, never skip '
        'verses silently, never invent a verse.',
    'Leave a field as "" or [] if you cannot produce it.',
    '"iast" has one entry per Sanskrit line of that verse.',
    '"hi" and "en" translate that verse alone, faithfully.',
    '"explanation_en" and "explanation_hi" are one short paragraph each.',
    '"takeaways_en" is 2-4 short lines.',
  ],
  'output_example': {
    'verses': {
      '2.47': {
        'iast': ['<IAST line 1>', '<IAST line 2>'],
        'hi': '<हिन्दी अनुवाद>',
        'en': '<English translation>',
        'explanation_en': '<one short paragraph>',
        'explanation_hi': '<एक संक्षिप्त अनुच्छेद>',
        'takeaways_en': ['<takeaway>', '<takeaway>'],
      },
    },
  },
  'chapters': [
    for (final section in _sectionsOf(work))
      {
        'number': section.number,
        'title_sa': section.title,
        'verses': {
          for (final passage in work.passages)
            if (passage.section?.path == section.path &&
                passage.kind == PassageKind.verse)
              passage.ref: passage.text.split('\n'),
        },
      },
  ],
};

Iterable<SectionSource> _sectionsOf(WorkSource work) {
  final seen = <String, SectionSource>{};
  for (final passage in work.passages) {
    final section = passage.section;
    if (section != null) seen.putIfAbsent(section.path, () => section);
  }
  return seen.values;
}

String _fileName(SectionSource section) {
  final number = section.number.padLeft(2, '0');
  return '${section.kind}-$number';
}

/// One chapter's verses with empty fields for a translation service to fill.
Map<String, Object?> _request(
  PackContent content,
  WorkSource work,
  SectionSource section,
  List<PassageSource> verses, {
  required int part,
  required int of,
}) => {
  'format': 'vedic-translation-request',
  'format_version': 1,
  'pack_id': content.packId,
  'work': work.slug,
  if (of > 1) 'part': part,
  if (of > 1) 'of': of,
  'section': {
    'kind': section.kind,
    'number': section.number,
    'title': sectionTitles(section, work.language),
  },
  'instructions': [
    'Fill every empty field below and return this same JSON, unchanged otherwise.',
    'Never alter "ref" or "sanskrit": they identify and carry the source text.',
    '"transliteration_iast" is the Sanskrit in IAST, one entry per Sanskrit line.',
    '"hi" and "en" are faithful translations of that verse alone.',
    '"explanation_en" and "explanation_hi" are one short paragraph each.',
    '"takeaways_en" is 2-4 short lines.',
    'Leave a field as "" or [] if you cannot produce it; do not guess.',
    'Return valid JSON only, with no commentary outside the JSON.',
  ],
  'section_summary_en': '',
  'verses': [
    for (final verse in verses)
      {
        'ref': verse.ref,
        'label': verse.label,
        if (verse.meter != null) 'meter': verse.meter,
        'sanskrit': verse.text.split('\n'),
        'transliteration_iast': <String>[],
        'hi': '',
        'en': '',
        'explanation_en': '',
        'explanation_hi': '',
        'takeaways_en': <String>[],
      },
  ],
};
