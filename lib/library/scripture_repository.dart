import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import '../core/transliteration.dart';
import '../packs/pack_store.dart';

// Read-only queries over installed packs for the reader UI.

class WorkSummary {
  const WorkSummary({
    required this.pack,
    required this.id,
    required this.slug,
    required this.title,
    required this.titleNative,
    required this.verseCount,
    this.coverUrl,
  });

  final InstalledPack pack;
  final int id;
  final String slug;
  final String title;
  final String? titleNative;
  final int verseCount;

  /// A picture of the book, supplied by whoever published the pack. Null is
  /// normal; the library shows a plain card instead.
  final String? coverUrl;
}

class SectionSummary {
  const SectionSummary({
    required this.id,
    required this.number,
    required this.title,
    required this.passageCount,
    required this.verseCount,
  });

  /// Null for the passages outside any section, such as an invocation.
  final int? id;
  final String? number;
  final String? title;
  final int passageCount;
  final int verseCount;
}

enum PassageType { verse, speaker, heading, prose, page }

/// A translation of a passage, as shipped in a pack.
class TranslationView {
  const TranslationView({
    required this.language,
    required this.text,
    required this.translator,
    required this.machine,
    this.onThisPhone = false,
  });

  final String language;
  final String text;
  final String? translator;

  /// Machine-translated, and labelled as such wherever it is shown.
  final bool machine;

  /// Produced by this phone rather than shipped in the pack.
  ///
  /// A pack's own machine translation was vetted by whoever published it; this
  /// one was not, so it is never used as the source for another translation.
  final bool onThisPhone;
}

/// A note the pack carries about a passage: an explanation, or a takeaway.
///
/// It keeps its language, because a pack carries the same note in several and
/// the reader wants theirs rather than all of them at once.
class NoteView {
  const NoteView({
    required this.language,
    required this.text,
    this.onThisPhone = false,
  });

  final String language;
  final String text;

  /// Written by this phone rather than shipped in the pack.
  final bool onThisPhone;
}

/// A recording the pack publishes for a passage.
class AudioView {
  const AudioView({
    required this.voice,
    required this.file,
    required this.mime,
    required this.durationMs,
    required this.size,
    required this.sha256,
  });

  final String voice;

  /// Where it is: a path under the pack host, or an absolute https URL.
  final String file;
  final String mime;
  final int durationMs;
  final int size;
  final String sha256;
}

class PassageView {
  const PassageView({
    required this.ref,
    required this.label,
    required this.type,
    required this.text,
    required this.variants,
    this.speaker,
    this.meter,
    this.transliteration,
    this.translations = const [],
    this.explanations = const [],
    this.takeaways = const [],
    this.audio = const [],
  });

  final String ref;
  final String? label;
  final PassageType type;

  /// Always the text stored in the pack. Nothing here is model-generated.
  final String text;
  final List<String> variants;

  /// The "X said" line introducing this verse, if it has one.
  final String? speaker;
  final String? meter;

  /// Transliteration shipped with the pack. Without one the app transliterates
  /// the Devanagari itself.
  final String? transliteration;
  final List<TranslationView> translations;

  /// Explanation paragraphs shipped with the verse, in every language the
  /// pack carries.
  final List<NoteView> explanations;

  /// Key takeaway lines shipped with the verse, in every language.
  final List<NoteView> takeaways;

  /// Recordings published for this passage. Empty for most passages in most
  /// packs, which is why nothing above here depends on there being one.
  final List<AudioView> audio;

  PassageView withSpeaker(String? speaker) => PassageView(
    ref: ref,
    label: label,
    type: type,
    text: text,
    variants: variants,
    speaker: speaker,
    meter: meter,
    transliteration: transliteration,
    translations: translations,
    explanations: explanations,
    takeaways: takeaways,
    audio: audio,
  );

  /// The translation to show, preferring [languages] in order. Published
  /// translations come first, so one is never shadowed by a machine one.
  TranslationView? translationFor(List<String> languages) {
    for (final language in languages) {
      for (final translation in translations) {
        if (translation.language == language) return translation;
      }
    }
    return translations.isEmpty ? null : translations.first;
  }

  bool hasTranslationIn(String language) =>
      translations.any((t) => t.language == language);

  /// The notes to show, in the first of [languages] the pack has them in.
  ///
  /// One language at a time: showing a reader the same explanation twice, in
  /// two languages, is worse than showing it once in the wrong one.
  List<String> notesFor(List<NoteView> notes, List<String> languages) {
    for (final language in languages) {
      final matching = [
        for (final note in notes)
          if (note.language == language) note.text,
      ];
      if (matching.isNotEmpty) return matching;
    }
    // Nothing in any language asked for. Fall back to one language — the
    // first the pack carries — and not to all of them at once. Returning
    // every language is how a verse came to be read aloud in English and
    // then again in Hindi: two voices, two languages, one explanation.
    final fallback = notes.isEmpty ? null : notes.first.language;
    return [
      for (final note in notes)
        if (note.language == fallback) note.text,
    ];
  }

  /// The language [notesFor] settles on, so the reader can be told when it is
  /// not the one they asked for.
  String? noteLanguageOf(List<NoteView> notes, List<String> languages) {
    for (final language in languages) {
      if (notes.any((note) => note.language == language)) return language;
    }
    return notes.isEmpty ? null : notes.first.language;
  }

  /// Which languages this passage has notes in.
  Set<String> noteLanguages(List<NoteView> notes) => {
    for (final note in notes) note.language,
  };
}

/// When the day's verse turns over: five in the morning, the device's own
/// local time.
///
/// Not midnight. Someone still reading at one in the morning is having last
/// night, not this morning, and a verse that changes under them mid-sitting
/// reads as a bug. Five is before anyone is up for it.
const dayStartsAtHour = 5;

/// Which day's verse to show at [when], in local time.
DateTime scriptureDay(DateTime when) {
  final local = when.isUtc ? when.toLocal() : when;
  final day = DateTime(local.year, local.month, local.day);
  return local.hour < dayStartsAtHour
      ? day.subtract(const Duration(days: 1))
      : day;
}

/// When the verse next changes, so a phone left open overnight turns the page
/// itself rather than showing yesterday's until it is reopened.
DateTime nextScriptureDay(DateTime when) {
  final local = when.isUtc ? when.toLocal() : when;
  final today = DateTime(local.year, local.month, local.day, dayStartsAtHour);
  // DateTime arithmetic over a day boundary, so the hour survives a clock
  // change: adding 24 hours to a DST morning would not.
  return today.isAfter(local)
      ? today
      : DateTime(local.year, local.month, local.day + 1, dayStartsAtHour);
}

/// A verse with the work and section it belongs to.
class VerseOfTheDay {
  const VerseOfTheDay({
    required this.work,
    required this.sectionId,
    required this.verse,
  });

  final WorkSummary work;
  final int? sectionId;
  final PassageView verse;
}

class ScriptureRepository {
  const ScriptureRepository(this.store);

  final PackStore store;

  /// A verse picked at random from every installed work, the same all day.
  ///
  /// [when] is the device's own local time; the day it belongs to is decided
  /// by [scriptureDay]. Random rather than sequential: the point is to be
  /// handed a verse, not to be walked through the book.
  ///
  /// [skip] rules a verse out — used for the ones already found to say nothing
  /// on their own. It is asked about each candidate in turn, and the day gets
  /// the first that survives, so a phone that has judged nothing yet behaves
  /// exactly as it did before.
  VerseOfTheDay? verseOfTheDay(
    DateTime when, {
    bool Function(VerseOfTheDay verse)? skip,
  }) {
    for (final verse in versesForDay(when)) {
      if (skip == null || !skip(verse)) return verse;
    }
    return null;
  }

  /// How many verses a day has in reserve behind the one it shows.
  ///
  /// Enough that a run of unsuitable verses still leaves one to show, few
  /// enough that judging them all is a handful of questions rather than a job.
  static const dayCandidates = 5;

  /// The day's verse and its reserves, in the order they would be taken.
  List<VerseOfTheDay> versesForDay(DateTime when) {
    final day = scriptureDay(when);
    final seed = math.Random(day.year * 10000 + day.month * 100 + day.day);
    final picked = <VerseOfTheDay>[];
    final seen = <String>{};
    for (var i = 0; i < dayCandidates; i++) {
      final verse = _nthVerse(seed);
      if (verse == null) break;
      if (seen.add('${verse.work.slug}/${verse.verse.ref}')) picked.add(verse);
    }
    return picked;
  }

  /// One verse drawn from everything installed, by the day's own dice.
  VerseOfTheDay? _nthVerse(math.Random seed) {
    final candidates = works().where((w) => w.verseCount > 0).toList();
    final total = candidates.fold(0, (n, w) => n + w.verseCount);
    if (total == 0) return null;

    var index = seed.nextInt(total);
    for (final work in candidates) {
      if (index >= work.verseCount) {
        index -= work.verseCount;
        continue;
      }
      return _read(work.pack, (db) {
        final row = db.select(
          'SELECT id, section_id, ref, label, text, meter FROM passages '
          "WHERE work_id = ? AND kind = 'verse' ORDER BY ordinal "
          'LIMIT 1 OFFSET ?',
          [work.id, index],
        ).first;
        return VerseOfTheDay(
          work: work,
          sectionId: row['section_id'] as int?,
          verse: _passage(
            db,
            row,
            PassageType.verse,
            local: _localTranslations(work),
          ),
        );
      });
    }
    return null;
  }

  /// Verses containing [query]: a Devanagari substring, or Latin text matched
  /// against the IAST transliteration without diacritics.
  List<VerseOfTheDay> searchVerses(String query, {int limit = 50}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final latin = !RegExp('[\u0900-\u097F]').hasMatch(q);
    final needle = latin ? foldIast(q) : q;
    if (needle.isEmpty) return const [];

    final hits = <VerseOfTheDay>[];
    for (final work in works()) {
      final local = _localTranslations(work);
      _read<void>(work.pack, (db) {
        for (final row in db.select(
          'SELECT id, section_id, ref, label, text, meter FROM passages '
          "WHERE work_id = ? AND kind = 'verse' ORDER BY ordinal",
          [work.id],
        )) {
          final text = row['text'] as String;
          final haystack = latin ? foldIast(devanagariToIast(text)) : text;
          if (!haystack.contains(needle)) continue;
          hits.add(
            VerseOfTheDay(
              work: work,
              sectionId: row['section_id'] as int?,
              verse: _passage(db, row, PassageType.verse, local: local),
            ),
          );
          if (hits.length == limit) return;
        }
      });
      if (hits.length == limit) break;
    }
    return hits;
  }

  List<WorkSummary> works() => [
    for (final pack in store.installed())
      ..._read(
        pack,
        (db) => [
          for (final row in db.select(
            'SELECT w.id, w.slug, w.title, w.title_native, w.cover_url, '
            '(SELECT count(*) FROM passages p '
            "WHERE p.work_id = w.id AND p.kind = 'verse') AS verses "
            'FROM works w ORDER BY w.id',
          ))
            WorkSummary(
              pack: pack,
              id: row['id'] as int,
              slug: row['slug'] as String,
              title: row['title'] as String,
              titleNative: row['title_native'] as String?,
              verseCount: row['verses'] as int,
              coverUrl: row['cover_url'] as String?,
            ),
        ],
      ),
  ];

  /// Top-level sections in reading order, followed by one entry with a null
  /// id for passages outside any section, if there are any.
  List<SectionSummary> sections(WorkSummary work) => _read(work.pack, (db) {
    final sections = [
      for (final row in db.select(
        'SELECT s.id, s.number, s.title, '
        '(SELECT count(*) FROM passages p WHERE p.section_id = s.id) AS passages, '
        '(SELECT count(*) FROM passages p '
        "WHERE p.section_id = s.id AND p.kind = 'verse') AS verses "
        'FROM sections s WHERE s.work_id = ? AND s.parent_id IS NULL '
        'ORDER BY s.ordinal',
        [work.id],
      ))
        SectionSummary(
          id: row['id'] as int,
          number: row['number'] as String?,
          title: row['title'] as String?,
          passageCount: row['passages'] as int,
          verseCount: row['verses'] as int,
        ),
    ];
    final other = db.select(
      'SELECT count(*) AS passages, '
      "count(*) FILTER (WHERE kind = 'verse') AS verses "
      'FROM passages WHERE work_id = ? AND section_id IS NULL',
      [work.id],
    ).first;
    return [
      ...sections,
      if (other['passages'] as int > 0)
        SectionSummary(
          id: null,
          number: null,
          title: null,
          passageCount: other['passages'] as int,
          verseCount: other['verses'] as int,
        ),
    ];
  });

  List<PassageView> passages(WorkSummary work, SectionSummary section) {
    final local = _localTranslations(work);
    final notes = _localNotes(work);
    return _read(work.pack, (db) {
      final where = section.id == null
          ? 'work_id = ? AND section_id IS NULL'
          : 'section_id = ?';
      return [
        for (final row in db.select(
          'SELECT id, ref, label, kind, text, meter FROM passages '
          'WHERE $where ORDER BY ordinal',
          [section.id ?? work.id],
        ))
          _passage(
            db,
            row,
            _typeOf(row['kind'] as String, row['ref'] as String),
            local: local,
            localNotes: notes,
          ),
      ];
    });
  }

  /// The verses of a section in reading order, each carrying the speaker line
  /// that introduces it.
  List<PassageView> verses(WorkSummary work, SectionSummary section) {
    final result = <PassageView>[];
    String? speaker;
    for (final passage in passages(work, section)) {
      switch (passage.type) {
        case PassageType.speaker:
          speaker = passage.text;
        case PassageType.verse:
          result.add(passage.withSpeaker(speaker));
          speaker = null;
        case PassageType.heading:
        case PassageType.prose:
        case PassageType.page:
          break;
      }
    }
    return result;
  }

  /// The verse immediately before [ref] in this work, with the speaker line
  /// that introduces it.
  ///
  /// Crosses a chapter boundary when it has to: a dialogue does not stop at
  /// the end of a chapter, and the first verse of one is often an answer to
  /// the last verse of the one before.
  PassageView? verseBefore(WorkSummary work, String ref) {
    final local = _localTranslations(work);
    return _read(work.pack, (db) {
      final at = db.select(
        'SELECT ordinal FROM passages WHERE work_id = ? AND ref = ?',
        [work.id, ref],
      );
      if (at.isEmpty) return null;
      final ordinal = at.first['ordinal'] as int;

      final rows = db.select(
        'SELECT id, ref, label, text, meter, ordinal FROM passages '
        "WHERE work_id = ? AND kind = 'verse' AND ordinal < ? "
        'ORDER BY ordinal DESC LIMIT 1',
        [work.id, ordinal],
      );
      if (rows.isEmpty) return null;

      final previous = _passage(
        db,
        rows.first,
        PassageType.verse,
        local: local,
      );
      return previous.withSpeaker(
        _speakerBefore(db, work.id, rows.first['ordinal'] as int),
      );
    });
  }

  /// The "X said" line directly above a passage, if that is what is there.
  String? _speakerBefore(Database db, int workId, int ordinal) {
    final rows = db.select(
      'SELECT ref, kind, text FROM passages '
      'WHERE work_id = ? AND ordinal < ? ORDER BY ordinal DESC LIMIT 1',
      [workId, ordinal],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final type = _typeOf(row['kind'] as String, row['ref'] as String);
    return type == PassageType.speaker ? row['text'] as String : null;
  }

  /// The section with this id, for opening the reader where a verse lives.
  SectionSummary? sectionOf(WorkSummary work, int? sectionId) {
    for (final section in sections(work)) {
      if (section.id == sectionId) return section;
    }
    return null;
  }

  /// Explanations this phone wrote, by ref.
  Map<String, List<NoteView>> _localNotes(WorkSummary work) => {
    for (final entry in store.localNotes(work.pack.packId, work.slug).entries)
      entry.key: [
        for (final note in entry.value)
          NoteView(language: note.language, text: note.text, onThisPhone: true),
      ],
  };

  /// Translations this phone produced, by ref, for merging into [_passage].
  Map<String, List<TranslationView>> _localTranslations(WorkSummary work) {
    final byRef = <String, List<TranslationView>>{};
    for (final local in store.localTranslations(work.pack.packId, work.slug)) {
      (byRef[local.ref] ??= []).add(
        TranslationView(
          language: local.language,
          text: local.text,
          translator: null,
          machine: true,
          onThisPhone: true,
        ),
      );
    }
    return byRef;
  }

  PassageView _passage(
    Database db,
    Row row,
    PassageType type, {
    Map<String, List<TranslationView>> local = const {},
    Map<String, List<NoteView>> localNotes = const {},
  }) {
    final audio = [
      for (final row in db.select(
        'SELECT voice_id, file, mime, duration_ms, size, sha256 FROM audio '
        'WHERE passage_id = ?',
        [row['id'] as int],
      ))
        AudioView(
          voice: row['voice_id'] as String,
          file: row['file'] as String,
          mime: row['mime'] as String,
          durationMs: row['duration_ms'] as int,
          size: row['size'] as int,
          sha256: row['sha256'] as String,
        ),
    ];
    final variants = <String>[];
    final translations = <TranslationView>[];
    final explanations = <NoteView>[];
    final takeaways = <NoteView>[];
    String? transliteration;
    for (final rendering in db.select(
      'SELECT kind, language, author, origin, scheme, text FROM renderings '
      'WHERE passage_id = ? ORDER BY id',
      [row['id'] as int],
    )) {
      final text = rendering['text'] as String;
      switch (rendering['kind'] as String) {
        case 'variant':
          variants.add(text);
        case 'translation':
          translations.add(
            TranslationView(
              language: rendering['language'] as String,
              text: text,
              translator: rendering['author'] as String?,
              machine: rendering['origin'] == 'machine',
            ),
          );
        case 'commentary':
          (rendering['scheme'] == 'takeaway' ? takeaways : explanations).add(
            NoteView(language: rendering['language'] as String, text: text),
          );
        case 'transliteration':
          transliteration ??= text;
      }
    }
    // After the pack's own, so a published translation always wins.
    translations.addAll(local[row['ref'] as String] ?? const []);
    explanations.addAll(localNotes[row['ref'] as String] ?? const []);
    return PassageView(
      ref: row['ref'] as String,
      label: row['label'] as String?,
      type: type,
      text: row['text'] as String,
      meter: row['meter'] as String?,
      variants: variants,
      transliteration: transliteration,
      translations: translations,
      explanations: explanations,
      takeaways: takeaways,
      audio: audio,
    );
  }

  T _read<T>(InstalledPack pack, T Function(Database db) body) {
    final db = store.openReadOnly(pack);
    try {
      return body(db);
    } finally {
      db.close();
    }
  }
}

PassageType _typeOf(String kind, String ref) => switch (kind) {
  'heading' when ref.endsWith('.speaker') => PassageType.speaker,
  'heading' => PassageType.heading,
  'verse' => PassageType.verse,
  'page' => PassageType.page,
  _ => PassageType.prose,
};
