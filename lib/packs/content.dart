import 'manifest.dart' show JsonReader, PackFormatException, PackManifest;

// What a pack contains: works, sections and passages with their translations,
// transliterations and audio. Serialised as docs/PACK_CONTENT_JSON.md, and
// written into the local SQLite database on install.

enum WorkKind { scripture, commentary, document }

enum PassageKind { verse, prose, heading, page }

enum RenderingKind { transliteration, translation, commentary, variant }

enum TextOrigin { human, machine }

class LicenceSource {
  const LicenceSource({
    required this.id,
    required this.name,
    required this.commercialRedistribution,
    required this.attribution,
    this.grantReference,
    this.notice,
  });

  final String id;
  final String name;
  final bool commercialRedistribution;
  final String attribution;
  final String? grantReference;
  final String? notice;
}

class VoiceSource {
  const VoiceSource({
    required this.id,
    required this.name,
    required this.language,
    required this.style,
    required this.engine,
    required this.licenceId,
  });

  final String id;
  final String name;
  final String language;

  /// "chant" or "read".
  final String style;

  /// Model and revision that rendered the audio.
  final String engine;
  final String licenceId;
}

class SectionSource {
  const SectionSource({
    required this.kind,
    required this.number,
    this.title,
    this.titles = const {},
    this.parent,
  });

  /// e.g. "chapter".
  final String kind;

  /// As printed, e.g. "2". Unique among siblings.
  final String number;

  /// Title in the work's original language.
  final String? title;

  /// Title by language. Empty when only [title] is known.
  final Map<String, String> titles;
  final SectionSource? parent;

  /// Identifies the section within its work: passages whose sections have
  /// the same path belong to the same section.
  String get path {
    final parent = this.parent;
    return parent == null ? '$kind:$number' : '${parent.path}/$kind:$number';
  }
}

class RenderingSource {
  const RenderingSource({
    required this.kind,
    required this.language,
    required this.text,
    this.script,
    this.scheme,
    this.author,
    this.licenceId,
    this.origin = TextOrigin.human,
  });

  final RenderingKind kind;
  final String language;
  final String text;
  final String? script;

  /// Transliteration scheme, e.g. "IAST".
  final String? scheme;
  final String? author;

  /// Null means the work's licence.
  final String? licenceId;
  final TextOrigin origin;
}

class AudioFileSource {
  const AudioFileSource({
    required this.voice,
    required this.file,
    required this.mime,
    required this.durationMs,
    required this.size,
    required this.sha256,
  });

  final String voice;

  /// Relative to the pack revision directory on the host, under `audio/`.
  final String file;
  final String mime;
  final int durationMs;
  final int size;
  final String sha256;
}

class PassageSource {
  const PassageSource({
    required this.ref,
    required this.kind,
    required this.text,
    this.label,
    this.section,
    this.meter,
    this.renderings = const [],
    this.audio = const [],
  });

  /// Stable citation key within the work, e.g. "2.47" or "p12".
  final String ref;
  final PassageKind kind;

  /// Original text; lines separated by "\n".
  final String text;
  final String? label;
  final SectionSource? section;
  final String? meter;
  final List<RenderingSource> renderings;
  final List<AudioFileSource> audio;
}

class WorkSource {
  const WorkSource({
    required this.slug,
    required this.kind,
    required this.title,
    required this.language,
    required this.licenceId,
    required this.passages,
    this.titleNative,
    this.titles = const {},
    this.script,
    this.edition,
    this.sourceNote,
    this.coverUrl,
  });

  final String slug;
  final WorkKind kind;

  /// Display title, English where there is one.
  final String title;

  /// Title in the original language.
  final String? titleNative;

  /// Title by language. Empty when only [title] and [titleNative] are known.
  final Map<String, String> titles;

  /// Original language, BCP 47.
  final String language;
  final String? script;
  final String? edition;
  final String licenceId;
  final String? sourceNote;

  /// A picture of the book, for the library. Supplied by whoever publishes
  /// the pack, so a partner can give their own edition its own cover.
  ///
  /// An `https:` URL, or an asset path inside the app. Absent is normal: the
  /// library falls back to a plain card.
  final String? coverUrl;

  /// Reading order: front matter, sections depth-first, back matter.
  final List<PassageSource> passages;
}

/// Titles by language for [work], falling back to its title fields.
Map<String, String> workTitles(WorkSource work) => work.titles.isNotEmpty
    ? work.titles
    : {
        work.language: work.titleNative ?? work.title,
        if (work.titleNative != null && work.titleNative != work.title)
          'en': work.title,
      };

/// Titles by language for [section], falling back to its original title.
Map<String, String> sectionTitles(SectionSource section, String original) =>
    section.titles.isNotEmpty ? section.titles : {original: ?section.title};

class PackContent {
  const PackContent({
    required this.packId,
    required this.revision,
    required this.languages,
    required this.licences,
    required this.voices,
    required this.works,
  });

  /// Parses and validates a decoded content JSON document.
  factory PackContent.fromJson(Object? json) {
    final c = JsonReader(json, 'content');
    if (c.string('format') != 'vedic-pack-content') {
      throw const PackFormatException(
        'content.format must be "vedic-pack-content"',
      );
    }
    final version = c.integer('format_version', min: 1);
    if (version != 1) {
      throw PackFormatException('unsupported content format_version $version');
    }
    final content = PackContent(
      packId: c.string('pack_id'),
      revision: c.integer('revision', min: 1),
      languages: c.strings('languages'),
      licences: [
        for (final l in c.objects('licences'))
          LicenceSource(
            id: l.string('id'),
            name: l.string('name'),
            commercialRedistribution: true,
            attribution: l.string('attribution'),
            notice: l.optionalString('notice'),
          ),
      ],
      voices: [
        for (final v in c.objects('voices', optional: true))
          VoiceSource(
            id: v.string('id'),
            name: v.string('name'),
            language: v.string('language'),
            style: v.oneOf('style', const {'chant': 'chant', 'read': 'read'}),
            engine: v.string('engine'),
            licenceId: v.string('licence'),
          ),
      ],
      works: [for (final w in c.objects('works')) _parseWork(w)],
    );
    validatePackContent(content);
    return content;
  }

  final String packId;
  final int revision;
  final List<String> languages;
  final List<LicenceSource> licences;
  final List<VoiceSource> voices;
  final List<WorkSource> works;

  Map<String, Object?> toJson() {
    validatePackContent(this);
    return {
      'format': 'vedic-pack-content',
      'format_version': 1,
      'pack_id': packId,
      'revision': revision,
      'languages': languages,
      'licences': [
        for (final l in licences)
          {
            'id': l.id,
            'name': l.name,
            'attribution': l.attribution,
            if (l.notice != null) 'notice': l.notice,
          },
      ],
      'voices': [
        for (final v in voices)
          {
            'id': v.id,
            'name': v.name,
            'language': v.language,
            'style': v.style,
            'engine': v.engine,
            'licence': v.licenceId,
          },
      ],
      'works': [for (final w in works) _workToJson(w)],
    };
  }
}

final _audioFile = RegExp(
  r'^audio/(?:[A-Za-z0-9_-][A-Za-z0-9._-]*/)*[A-Za-z0-9_-][A-Za-z0-9._-]*$',
);

/// Throws [PackFormatException] for content the app must not install.
void validatePackContent(PackContent c) {
  if (!PackManifest.packIdPattern.hasMatch(c.packId)) {
    throw PackFormatException('invalid pack_id "${c.packId}"');
  }

  final licences = <String>{};
  for (final l in c.licences) {
    if (!licences.add(l.id)) {
      throw PackFormatException('licence "${l.id}" is listed twice');
    }
    if (!l.commercialRedistribution) {
      throw PackFormatException(
        'licence "${l.id}" is not cleared for commercial redistribution',
      );
    }
  }

  final voices = <String>{};
  for (final v in c.voices) {
    if (!voices.add(v.id)) {
      throw PackFormatException('voice "${v.id}" is listed twice');
    }
    if (!licences.contains(v.licenceId)) {
      throw PackFormatException(
        'voice "${v.id}" uses unknown licence "${v.licenceId}"',
      );
    }
  }

  if (c.works.isEmpty) {
    throw const PackFormatException('a pack needs at least one work');
  }
  final slugs = <String>{};
  for (final w in c.works) {
    if (!slugs.add(w.slug)) {
      throw PackFormatException('work "${w.slug}" is listed twice');
    }
    if (!licences.contains(w.licenceId)) {
      throw PackFormatException(
        'work "${w.slug}" uses unknown licence "${w.licenceId}"',
      );
    }
    if (w.passages.isEmpty) {
      throw PackFormatException('work "${w.slug}" has no text');
    }

    final refs = <String>{};
    for (final passage in w.passages) {
      if (!refs.add(passage.ref)) {
        throw PackFormatException(
          'work "${w.slug}" has two passages with ref "${passage.ref}"',
        );
      }
      final at = 'work "${w.slug}" passage "${passage.ref}"';
      if (passage.text.trim().isEmpty) {
        throw PackFormatException('$at has empty text');
      }

      final translations = <String>{};
      final schemes = <String>{};
      for (final r in passage.renderings) {
        if (r.text.trim().isEmpty) {
          throw PackFormatException('$at has an empty ${r.kind.name}');
        }
        final licence = r.licenceId;
        if (licence != null && !licences.contains(licence)) {
          throw PackFormatException('$at uses unknown licence "$licence"');
        }
        if (r.kind == RenderingKind.translation &&
            !translations.add(r.language)) {
          throw PackFormatException('$at has two "${r.language}" translations');
        }
        if (r.kind == RenderingKind.commentary &&
            r.scheme != 'explanation' &&
            r.scheme != 'takeaway') {
          throw PackFormatException(
            '$at has a note that is neither an explanation nor a takeaway',
          );
        }
        if (r.kind == RenderingKind.transliteration &&
            !schemes.add(r.scheme ?? '')) {
          throw PackFormatException(
            '$at has two "${r.scheme}" transliterations',
          );
        }
      }

      final audioVoices = <String>{};
      for (final a in passage.audio) {
        if (!voices.contains(a.voice)) {
          throw PackFormatException('$at uses unknown voice "${a.voice}"');
        }
        if (!audioVoices.add(a.voice)) {
          throw PackFormatException('$at has two audio files for "${a.voice}"');
        }
        if (!_audioFile.hasMatch(a.file)) {
          throw PackFormatException('$at has an unsafe audio path "${a.file}"');
        }
      }
    }
  }
}

Map<T, String> _names<T extends Enum>(List<T> values) => {
  for (final v in values) v: v.name,
};

WorkSource _parseWork(JsonReader w) {
  final original = w.string('original_language');
  final script = w.string('script');
  final titles = w.stringMap('title');
  final nativeTitle = titles[original];
  if (nativeTitle == null) {
    throw PackFormatException('${w.path}.title has no "$original" title');
  }

  final passages = <PassageSource>[];
  void addPassages(JsonReader parent, String key, SectionSource? section) {
    if (!parent.has(key)) return;
    for (final p in parent.objects(key)) {
      passages.addAll(_parsePassage(p, section, original, script));
    }
  }

  void addSections(JsonReader parent, SectionSource? parentSection) {
    if (!parent.has('sections')) return;
    final numbers = <String>{};
    for (final s in parent.objects('sections')) {
      final number = s.string('number');
      if (!numbers.add(number)) {
        throw PackFormatException('${s.path}.number "$number" repeats');
      }
      if (!s.has('passages') && !s.has('sections')) {
        throw PackFormatException('${s.path} has no passages or sections');
      }
      final sectionTitles = s.has('title')
          ? s.stringMap('title')
          : const <String, String>{};
      final section = SectionSource(
        kind: s.string('kind'),
        number: number,
        title: sectionTitles[original],
        titles: sectionTitles,
        parent: parentSection,
      );
      addPassages(s, 'passages', section);
      addSections(s, section);
    }
  }

  addPassages(w, 'front_matter', null);
  addSections(w, null);
  addPassages(w, 'back_matter', null);

  return WorkSource(
    slug: w.string('slug'),
    kind: w.oneOf('kind', _names(WorkKind.values)),
    title: titles['en'] ?? nativeTitle,
    titleNative: nativeTitle,
    titles: titles,
    language: original,
    script: script,
    edition: w.optionalString('edition'),
    licenceId: w.string('licence'),
    sourceNote: w.optionalString('source_note'),
    coverUrl: w.optionalString('cover_url'),
    passages: passages,
  );
}

/// A JSON passage, preceded by its speaker line as a heading passage
/// `<ref>.speaker` if it has one.
List<PassageSource> _parsePassage(
  JsonReader p,
  SectionSource? section,
  String original,
  String script,
) {
  final ref = p.string('ref');
  final result = <PassageSource>[];

  if (p.has('speaker')) {
    final speaker = p.stringMap('speaker');
    final line = speaker[original];
    if (line == null) {
      throw PackFormatException('${p.path}.speaker has no "$original" line');
    }
    result.add(
      PassageSource(
        ref: '$ref.speaker',
        kind: PassageKind.heading,
        text: line,
        section: section,
        renderings: [
          for (final MapEntry(:key, :value) in speaker.entries)
            if (key != original)
              RenderingSource(
                kind: RenderingKind.translation,
                language: key,
                text: value,
              ),
        ],
      ),
    );
  }

  result.add(
    PassageSource(
      ref: ref,
      kind: p.oneOf('kind', _names(PassageKind.values)),
      label: p.optionalString('label'),
      text: _lines(p, 'lines').join('\n'),
      section: section,
      meter: p.optionalString('meter'),
      renderings: [
        for (final t in p.objects('transliterations', optional: true))
          RenderingSource(
            kind: RenderingKind.transliteration,
            language: original,
            script: 'Latn',
            scheme: t.oneOf('scheme', const {
              'IAST': 'IAST',
              'ISO15919': 'ISO15919',
            }),
            text: _lines(t, 'lines').join('\n'),
          ),
        for (final t in p.objects('translations', optional: true))
          RenderingSource(
            kind: RenderingKind.translation,
            language: t.string('language'),
            text: t.string('text'),
            author: t.optionalString('translator'),
            licenceId: t.string('licence'),
            origin: t.has('origin')
                ? t.oneOf('origin', _names(TextOrigin.values))
                : TextOrigin.human,
          ),
        for (final note in p.objects('notes', optional: true))
          RenderingSource(
            kind: RenderingKind.commentary,
            language: note.string('language'),
            scheme: note.oneOf('kind', const {
              'explanation': 'explanation',
              'takeaway': 'takeaway',
            }),
            text: note.string('text'),
            author: note.optionalString('author'),
            licenceId: note.string('licence'),
          ),
        if (p.has('variants'))
          for (final variant in p.strings('variants'))
            RenderingSource(
              kind: RenderingKind.variant,
              language: original,
              script: script,
              text: variant,
            ),
      ],
      audio: [
        for (final a in p.objects('audio', optional: true))
          AudioFileSource(
            voice: a.string('voice'),
            file: a.string('file'),
            mime: a.oneOf('mime', const {
              'audio/mp4': 'audio/mp4',
              'audio/ogg': 'audio/ogg',
            }),
            durationMs: a.integer('duration_ms', min: 1),
            size: a.integer('size', min: 1),
            sha256: a.hex('sha256'),
          ),
      ],
    ),
  );
  return result;
}

/// Lines may be blank (a paragraph break on a page), but not all of them.
List<String> _lines(JsonReader r, String key) {
  final value = r.map[key];
  if (value is List &&
      value.every((line) => line is String) &&
      value.any((line) => (line as String).trim().isNotEmpty)) {
    return List.unmodifiable(value.cast<String>());
  }
  throw PackFormatException(
    '${r.path}.$key must be a list of strings with a non-empty line',
  );
}

Map<String, Object?> _workToJson(WorkSource w) {
  final front = <Object?>[];
  final back = <Object?>[];
  final roots = <_SectionNode>[];
  final nodes = <String, _SectionNode>{};
  var sectionsStarted = false;

  final all = w.passages;
  for (var i = 0; i < all.length; i++) {
    final passage = all[i];
    final next = i + 1 < all.length ? all[i + 1] : null;
    if (next != null && _introduces(passage, next)) continue;
    final previous = i > 0 ? all[i - 1] : null;
    final json = _passageToJson(
      passage,
      w,
      speaker: previous != null && _introduces(previous, passage)
          ? previous
          : null,
    );

    final section = passage.section;
    if (section == null) {
      (sectionsStarted ? back : front).add(json);
    } else {
      sectionsStarted = true;
      _nodeFor(section, nodes, roots).passages.add(json);
    }
  }

  return {
    'slug': w.slug,
    'kind': w.kind.name,
    'title': workTitles(w),
    'original_language': w.language,
    'script': w.script ?? 'Zyyy',
    if (w.edition != null) 'edition': w.edition,
    'licence': w.licenceId,
    if (w.sourceNote != null) 'source_note': w.sourceNote,
    if (w.coverUrl != null) 'cover_url': w.coverUrl,
    if (front.isNotEmpty) 'front_matter': front,
    if (roots.isNotEmpty)
      'sections': [for (final r in roots) r.toJson(w.language)],
    if (back.isNotEmpty) 'back_matter': back,
  };
}

bool _introduces(PassageSource speaker, PassageSource passage) =>
    speaker.kind == PassageKind.heading &&
    speaker.ref == '${passage.ref}.speaker' &&
    speaker.section?.path == passage.section?.path;

Map<String, Object?> _passageToJson(
  PassageSource p,
  WorkSource w, {
  PassageSource? speaker,
}) {
  List<RenderingSource> of(RenderingKind kind) => [
    for (final r in p.renderings)
      if (r.kind == kind) r,
  ];
  final transliterations = of(RenderingKind.transliteration);
  final translations = of(RenderingKind.translation);
  final notes = of(RenderingKind.commentary);
  final variants = of(RenderingKind.variant);

  return {
    'ref': p.ref,
    'kind': p.kind.name,
    if (p.label != null) 'label': p.label,
    if (speaker != null)
      'speaker': {
        w.language: speaker.text,
        for (final r in speaker.renderings)
          if (r.kind == RenderingKind.translation) r.language: r.text,
      },
    'lines': p.text.split('\n'),
    if (p.meter != null) 'meter': p.meter,
    if (transliterations.isNotEmpty)
      'transliterations': [
        for (final r in transliterations)
          {'scheme': r.scheme ?? 'IAST', 'lines': r.text.split('\n')},
      ],
    if (translations.isNotEmpty)
      'translations': [
        for (final r in translations)
          {
            'language': r.language,
            'text': r.text,
            if (r.author != null) 'translator': r.author,
            'licence': r.licenceId ?? w.licenceId,
            if (r.origin == TextOrigin.machine) 'origin': 'machine',
          },
      ],
    if (notes.isNotEmpty)
      'notes': [
        for (final r in notes)
          {
            'kind': r.scheme ?? 'explanation',
            'language': r.language,
            'text': r.text,
            if (r.author != null) 'author': r.author,
            'licence': r.licenceId ?? w.licenceId,
          },
      ],
    if (variants.isNotEmpty) 'variants': [for (final r in variants) r.text],
    if (p.audio.isNotEmpty)
      'audio': [
        for (final a in p.audio)
          {
            'voice': a.voice,
            'file': a.file,
            'mime': a.mime,
            'duration_ms': a.durationMs,
            'size': a.size,
            'sha256': a.sha256,
          },
      ],
  };
}

class _SectionNode {
  _SectionNode(this.section);

  final SectionSource section;
  final passages = <Object?>[];
  final children = <_SectionNode>[];

  Map<String, Object?> toJson(String original) {
    final titles = sectionTitles(section, original);
    return {
      'kind': section.kind,
      'number': section.number,
      if (titles.isNotEmpty) 'title': titles,
      if (passages.isNotEmpty) 'passages': passages,
      if (children.isNotEmpty)
        'sections': [for (final c in children) c.toJson(original)],
    };
  }
}

_SectionNode _nodeFor(
  SectionSource section,
  Map<String, _SectionNode> nodes,
  List<_SectionNode> roots,
) {
  final existing = nodes[section.path];
  if (existing != null) return existing;
  final node = nodes[section.path] = _SectionNode(section);
  final parent = section.parent;
  if (parent == null) {
    roots.add(node);
  } else {
    _nodeFor(parent, nodes, roots).children.add(node);
  }
  return node;
}
