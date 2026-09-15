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
  });

  final InstalledPack pack;
  final int id;
  final String slug;
  final String title;
  final String? titleNative;
  final int verseCount;
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

class PassageView {
  const PassageView({
    required this.ref,
    required this.label,
    required this.type,
    required this.text,
    required this.variants,
  });

  final String ref;
  final String? label;
  final PassageType type;

  /// Always the text stored in the pack. Nothing here is model-generated.
  final String text;
  final List<String> variants;
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
  VerseOfTheDay? verseOfTheDay(DateTime day) {
    final candidates = works().where((w) => w.verseCount > 0).toList();
    final total = candidates.fold(0, (n, w) => n + w.verseCount);
    if (total == 0) return null;

    var index = math.Random(day.year * 10000 + day.month * 100 + day.day)
        .nextInt(total);
    for (final work in candidates) {
      if (index >= work.verseCount) {
        index -= work.verseCount;
        continue;
      }
      return _read(work.pack, (db) {
        final row = db.select(
          'SELECT section_id, ref, label, text FROM passages '
          "WHERE work_id = ? AND kind = 'verse' ORDER BY ordinal LIMIT 1 OFFSET ?",
          [work.id, index],
        ).first;
        return _verse(work, row);
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
      _read<void>(work.pack, (db) {
        for (final row in db.select(
          'SELECT section_id, ref, label, text FROM passages '
          "WHERE work_id = ? AND kind = 'verse' ORDER BY ordinal",
          [work.id],
        )) {
          final text = row['text'] as String;
          final haystack = latin ? foldIast(devanagariToIast(text)) : text;
          if (!haystack.contains(needle)) continue;
          hits.add(_verse(work, row));
          if (hits.length == limit) return;
        }
      });
      if (hits.length == limit) break;
    }
    return hits;
  }

  VerseOfTheDay _verse(WorkSummary work, Row row) => VerseOfTheDay(
    work: work,
    sectionId: row['section_id'] as int?,
    verse: PassageView(
      ref: row['ref'] as String,
      label: row['label'] as String?,
      type: PassageType.verse,
      text: row['text'] as String,
      variants: const [],
    ),
  );

  List<WorkSummary> works() => [
    for (final pack in store.installed())
      ..._read(
        pack,
        (db) => [
          for (final row in db.select(
            'SELECT w.id, w.slug, w.title, w.title_native, '
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

  List<PassageView> passages(WorkSummary work, SectionSummary section) =>
      _read(work.pack, (db) {
        final where = section.id == null
            ? 'p.work_id = ? AND p.section_id IS NULL'
            : 'p.section_id = ?';
        final argument = section.id ?? work.id;

        final variants = <int, List<String>>{};
        for (final row in db.select(
          'SELECT r.passage_id, r.text FROM renderings r '
          'JOIN passages p ON p.id = r.passage_id '
          "WHERE r.kind = 'variant' AND $where ORDER BY r.id",
          [argument],
        )) {
          variants
              .putIfAbsent(row['passage_id'] as int, () => [])
              .add(row['text'] as String);
        }

        return [
          for (final row in db.select(
            'SELECT p.id, p.ref, p.label, p.kind, p.text FROM passages p '
            'WHERE $where ORDER BY p.ordinal',
            [argument],
          ))
            PassageView(
              ref: row['ref'] as String,
              label: row['label'] as String?,
              type: _typeOf(row['kind'] as String, row['ref'] as String),
              text: row['text'] as String,
              variants: variants[row['id']] ?? const [],
            ),
        ];
      });

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
