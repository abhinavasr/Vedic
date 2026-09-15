import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:vedic/packs/build/pack_builder.dart';
import 'package:vedic/packs/build/text_sources.dart';
import 'package:vedic/packs/build/verse_text.dart';
import 'package:vedic/packs/manifest.dart' show JsonReader, PackFormatException;
import 'package:yaml/yaml.dart';

const _usage = '''
Builds a content pack from a content directory (docs/CONTENT_PACKS.md §9).

  dart run tool/build_pack.dart <content-dir> [options]

<content-dir> holds pack.yaml and the .txt / .pdf sources it lists.
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'out',
      defaultsTo: 'build/packs',
      help: 'Where the publishable pack tree is written.',
    )
    ..addFlag(
      'bundle',
      negatable: false,
      help: 'Also copy the pack into assets/packs/ so the app ships it.',
    )
    ..addFlag(
      'encrypt',
      negatable: false,
      help: 'Encrypt for download with a fresh content key.',
    )
    ..addOption(
      'key-vault',
      defaultsTo: 'build/key-vault',
      help: 'Where content keys are written. Never publish this directory.',
    )
    ..addOption(
      'signing-seed',
      defaultsTo: 'tool/keys/dev-publisher.seed',
      help: '32-byte Ed25519 seed file.',
    )
    ..addOption('key-id', defaultsTo: 'dev-publisher-1')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    _fail('${e.message}\n\n$_usage\n${parser.usage}');
  }
  if (args.flag('help') || args.rest.length != 1) {
    stdout.writeln('$_usage\n${parser.usage}');
    exit(args.flag('help') ? 0 : 64);
  }
  if (args.flag('bundle') && args.flag('encrypt')) {
    _fail(
      '--bundle and --encrypt cannot be combined: any key in the app is public.',
    );
  }

  final contentDir = Directory(args.rest.single);
  final configFile = File(p.join(contentDir.path, 'pack.yaml'));
  if (!configFile.existsSync()) _fail('no pack.yaml in ${contentDir.path}');
  final config = jsonDecode(
    jsonEncode(loadYaml(configFile.readAsStringSync())),
  ) as Map<String, Object?>;

  try {
    final passages = <String, List<PassageSource>>{};
    for (final work in JsonReader(config, 'pack.yaml').objects('works')) {
      final slug = work.string('slug');
      final source = work.string('source');
      passages[slug] = await _extract(
        contentDir,
        source,
        format: work.optionalString('format'),
      );
      stdout.writeln(
        '  $slug: ${passages[slug]!.length} passages from $source',
      );
    }
    final source = PackSource.fromConfig(config, passagesBySlug: passages);

    final seed = File(args.option('signing-seed')!).readAsBytesSync();
    if (seed.length != 32) _fail('signing seed must be exactly 32 bytes');

    List<int>? contentKey;
    File? keyFile;
    if (args.flag('encrypt')) {
      keyFile = File(
        p.join(
          args.option('key-vault')!,
          source.packId,
          '${source.revision}.cek',
        ),
      );
      if (keyFile.existsSync()) {
        _fail('a content key already exists: ${keyFile.path}');
      }
      final rng = Random.secure();
      contentKey = List<int>.generate(32, (_) => rng.nextInt(256));
    }

    final built = await buildPack(
      source,
      outputRoot: Directory(args.option('out')!),
      signer: PackSigner(keyId: args.option('key-id')!, seed: seed),
      contentKey: contentKey,
    );
    if (keyFile != null) {
      await keyFile.parent.create(recursive: true);
      await keyFile.writeAsBytes(contentKey!);
      stdout.writeln('Content key: ${keyFile.path} (keep private)');
    }

    final payload = built.manifest.payload;
    stdout.writeln(
      'Built ${built.directory.path}: ${payload.size} bytes '
      '(${payload.plaintextSize} uncompressed)',
    );
    if (args.flag('bundle')) {
      await copyToBundledAssets(built, Directory('assets/packs'));
      stdout.writeln('Bundled into assets/packs/');
    }
  } on PackFormatException catch (e) {
    _fail(e.message);
  }
}

/// Reads a work's source. [format] is null for plain documents, or `verses`
/// for chapter-and-verse scripture text (see verse_text.dart).
Future<List<PassageSource>> _extract(
  Directory contentDir,
  String source, {
  String? format,
}) async {
  if (p.isAbsolute(source) || p.split(p.normalize(source)).contains('..')) {
    throw PackFormatException(
      'source "$source" must be inside the content directory',
    );
  }
  if (format != null && format != 'verses') {
    throw PackFormatException('unknown format "$format" for $source');
  }
  final file = File(p.join(contentDir.path, source));
  switch (p.extension(source).toLowerCase()) {
    case '.txt':
      final String text;
      try {
        text = await file.readAsString();
      } on FileSystemException catch (e) {
        throw PackFormatException('$source: ${e.message} (text must be UTF-8)');
      }
      if (format != 'verses') return passagesFromPlainText(text);
      try {
        return passagesFromVerseText(text);
      } on FormatException catch (e) {
        throw PackFormatException('$source: ${e.message}');
      }
    case '.pdf' when format == 'verses':
      throw PackFormatException('$source: verse format needs a .txt source');
    case '.pdf':
      await pdfrxInitialize();
      final document = await PdfDocument.openFile(file.path);
      try {
        final pages = [
          for (final page in document.pages)
            (await page.loadStructuredText()).fullText,
        ];
        final passages = passagesFromPages(pages);
        if (passages.isEmpty) {
          throw PackFormatException(
            '$source has no text layer. Scanned PDFs need a checked text '
            'file instead (docs/CONTENT_PACKS.md §9).',
          );
        }
        final blank = pages.length - passages.length;
        if (blank > 0) {
          stdout.writeln(
            '  warning: $blank of ${pages.length} pages in $source have no text',
          );
        }
        return passages;
      } finally {
        await document.dispose();
      }
    default:
      throw PackFormatException(
        'unsupported source "$source": use .txt or .pdf',
      );
  }
}

Never _fail(String message) {
  stderr.writeln('error: $message');
  exit(1);
}
