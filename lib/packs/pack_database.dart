import 'package:sqlite3/sqlite3.dart';

import '../core/chunker.dart';
import 'content.dart';
import 'pack_schema.dart';

/// Writes [content] as a pack database at [path] (docs/CONTENT_PACKS.md §5).
///
/// Runs on the phone at install time, and on the build machine to prove a
/// pack will install. Throws [SqliteException] if content breaks a
/// constraint.
void writePackDatabase(
  String path,
  PackContent content, {
  required DateTime createdAt,
  int maxChunkChars = 1000,
  int chunkOverlapChars = 150,
}) {
  final db = sqlite3.open(path);
  try {
    db
      ..execute('PRAGMA application_id = $packApplicationId')
      ..execute('PRAGMA user_version = $packSchemaVersion')
      ..execute(packSchemaSql)
      ..execute('BEGIN');

    for (final MapEntry(:key, :value) in {
      'pack_id': content.packId,
      'revision': '${content.revision}',
      'schema_version': '$packSchemaVersion',
      'created_at': createdAt.toUtc().toIso8601String(),
      'languages': content.languages.join(','),
    }.entries) {
      db.execute('INSERT INTO pack_meta (key, value) VALUES (?, ?)', [
        key,
        value,
      ]);
    }

    for (final l in content.licences) {
      db.execute(
        'INSERT INTO licences (id, name, commercial_redistribution, '
        'grant_reference, attribution, notice) VALUES (?, ?, ?, ?, ?, ?)',
        [
          l.id,
          l.name,
          l.commercialRedistribution ? 1 : 0,
          l.grantReference,
          l.attribution,
          l.notice,
        ],
      );
    }

    for (final v in content.voices) {
      db.execute(
        'INSERT INTO voices (id, name, language, style, engine, licence_id) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [v.id, v.name, v.language, v.style, v.engine, v.licenceId],
      );
    }

    for (final w in content.works) {
      _writeWork(db, w, maxChunkChars, chunkOverlapChars);
    }

    db
      ..execute('COMMIT')
      ..execute('VACUUM');
  } finally {
    db.close();
  }
}

void _writeWork(
  Database db,
  WorkSource w,
  int maxChunkChars,
  int chunkOverlapChars,
) {
  db.execute(
    'INSERT INTO works (slug, kind, title, title_native, language, '
    'script, edition, licence_id, source_note) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      w.slug,
      w.kind.name,
      w.title,
      w.titleNative,
      w.language,
      w.script,
      w.edition,
      w.licenceId,
      w.sourceNote,
    ],
  );
  final workId = db.lastInsertRowId;
  for (final MapEntry(:key, :value) in workTitles(w).entries) {
    db.execute(
      'INSERT INTO work_titles (work_id, language, title) VALUES (?, ?, ?)',
      [workId, key, value],
    );
  }

  final sectionIds = <String, int>{};
  final childCounts = <String, int>{};
  int sectionId(SectionSource section) {
    final known = sectionIds[section.path];
    if (known != null) return known;
    final parent = section.parent;
    final parentId = parent == null ? null : sectionId(parent);
    final siblings = parent?.path ?? '';
    final ordinal = childCounts[siblings] = (childCounts[siblings] ?? 0) + 1;
    db.execute(
      'INSERT INTO sections (work_id, parent_id, ordinal, kind, number, title) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [workId, parentId, ordinal, section.kind, section.number, section.title],
    );
    final id = db.lastInsertRowId;
    for (final MapEntry(:key, :value) in sectionTitles(
      section,
      w.language,
    ).entries) {
      db.execute(
        'INSERT INTO section_titles (section_id, language, title) '
        'VALUES (?, ?, ?)',
        [id, key, value],
      );
    }
    return sectionIds[section.path] = id;
  }

  final passageIds = <int>[];
  for (var i = 0; i < w.passages.length; i++) {
    final passage = w.passages[i];
    final section = passage.section;
    db.execute(
      'INSERT INTO passages '
      '(work_id, section_id, ordinal, kind, ref, label, text, meter) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        workId,
        section == null ? null : sectionId(section),
        i + 1,
        passage.kind.name,
        passage.ref,
        passage.label,
        passage.text,
        passage.meter,
      ],
    );
    final passageId = db.lastInsertRowId;
    passageIds.add(passageId);

    for (final r in passage.renderings) {
      db.execute(
        'INSERT INTO renderings (passage_id, kind, language, script, scheme, '
        'author, licence_id, origin, text) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          passageId,
          r.kind.name,
          r.language,
          r.script,
          r.scheme,
          r.author,
          r.licenceId ?? w.licenceId,
          r.origin.name,
          r.text,
        ],
      );
    }

    for (final a in passage.audio) {
      db.execute(
        'INSERT INTO audio (passage_id, voice_id, file, mime, duration_ms, '
        'size, sha256) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [passageId, a.voice, a.file, a.mime, a.durationMs, a.size, a.sha256],
      );
    }
  }

  _writeChunks(
    db,
    workId,
    w.passages,
    passageIds,
    maxChunkChars,
    chunkOverlapChars,
  );
}

/// Chunks a work's passages as one text, so retrieval units can span passage
/// boundaries, and records the first and last passage each chunk covers.
void _writeChunks(
  Database db,
  int workId,
  List<PassageSource> passages,
  List<int> passageIds,
  int maxChars,
  int overlapChars,
) {
  final joined = StringBuffer();
  final starts = <int>[];
  for (final passage in passages) {
    if (joined.isNotEmpty) joined.write('\n\n');
    starts.add(joined.length);
    joined.write(passage.text);
  }
  var ordinal = 0;
  for (final chunk in chunkText(
    joined.toString(),
    maxChars: maxChars,
    overlapChars: overlapChars,
  )) {
    db.execute(
      'INSERT INTO chunks (work_id, first_passage_id, last_passage_id, '
      'ordinal, text) VALUES (?, ?, ?, ?, ?)',
      [
        workId,
        passageIds[_passageAt(starts, chunk.start)],
        passageIds[_passageAt(starts, chunk.end - 1)],
        ++ordinal,
        chunk.text,
      ],
    );
  }
}

/// Index of the passage whose text contains [offset] in the joined text.
int _passageAt(List<int> starts, int offset) {
  var lo = 0;
  var hi = starts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (starts[mid] <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}
