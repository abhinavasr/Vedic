// SQLite schema of the local pack database built on install from a pack's
// content JSON: docs/CONTENT_PACKS.md §5, docs/PACK_CONTENT_JSON.md.

/// `PRAGMA application_id` of every pack database: "VPK1".
const int packApplicationId = 0x56504B31;

/// `PRAGMA user_version` of databases built with [packSchemaSql].
const int packSchemaVersion = 1;

const String packSchemaSql = '''
CREATE TABLE pack_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE licences (
  id                        TEXT PRIMARY KEY,
  name                      TEXT NOT NULL,
  commercial_redistribution INTEGER NOT NULL CHECK (commercial_redistribution IN (0, 1)),
  grant_reference           TEXT,
  attribution               TEXT NOT NULL,
  notice                    TEXT
);

CREATE TABLE voices (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  language   TEXT NOT NULL,
  style      TEXT NOT NULL CHECK (style IN ('chant', 'read')),
  engine     TEXT NOT NULL,
  licence_id TEXT NOT NULL REFERENCES licences(id)
);

CREATE TABLE works (
  id           INTEGER PRIMARY KEY,
  slug         TEXT NOT NULL UNIQUE,
  kind         TEXT NOT NULL CHECK (kind IN ('scripture', 'commentary', 'document')),
  title        TEXT NOT NULL,
  title_native TEXT,
  language     TEXT NOT NULL,
  script       TEXT,
  edition      TEXT,
  licence_id   TEXT NOT NULL REFERENCES licences(id),
  source_note  TEXT
);

CREATE TABLE work_titles (
  work_id  INTEGER NOT NULL REFERENCES works(id),
  language TEXT NOT NULL,
  title    TEXT NOT NULL,
  PRIMARY KEY (work_id, language)
) WITHOUT ROWID;

CREATE TABLE sections (
  id        INTEGER PRIMARY KEY,
  work_id   INTEGER NOT NULL REFERENCES works(id),
  parent_id INTEGER REFERENCES sections(id),
  ordinal   INTEGER NOT NULL,
  kind      TEXT NOT NULL,
  number    TEXT,
  title     TEXT
);

CREATE TABLE section_titles (
  section_id INTEGER NOT NULL REFERENCES sections(id),
  language   TEXT NOT NULL,
  title      TEXT NOT NULL,
  PRIMARY KEY (section_id, language)
) WITHOUT ROWID;

CREATE TABLE passages (
  id         INTEGER PRIMARY KEY,
  work_id    INTEGER NOT NULL REFERENCES works(id),
  section_id INTEGER REFERENCES sections(id),
  ordinal    INTEGER NOT NULL,
  kind       TEXT NOT NULL CHECK (kind IN ('verse', 'prose', 'heading', 'page')),
  ref        TEXT NOT NULL,
  label      TEXT,
  text       TEXT NOT NULL,
  meter      TEXT,
  UNIQUE (work_id, ref),
  UNIQUE (work_id, ordinal)
);

CREATE TABLE renderings (
  id         INTEGER PRIMARY KEY,
  passage_id INTEGER NOT NULL REFERENCES passages(id),
  kind       TEXT NOT NULL CHECK (kind IN ('transliteration', 'translation', 'commentary', 'variant')),
  language   TEXT NOT NULL,
  script     TEXT,
  scheme     TEXT,
  author     TEXT,
  licence_id TEXT NOT NULL REFERENCES licences(id),
  origin     TEXT NOT NULL DEFAULT 'human' CHECK (origin IN ('human', 'machine')),
  text       TEXT NOT NULL
);

CREATE TABLE audio (
  passage_id  INTEGER NOT NULL REFERENCES passages(id),
  voice_id    TEXT NOT NULL REFERENCES voices(id),
  file        TEXT NOT NULL,
  mime        TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  size        INTEGER NOT NULL,
  sha256      TEXT NOT NULL,
  PRIMARY KEY (passage_id, voice_id)
) WITHOUT ROWID;

CREATE TABLE chunks (
  id               INTEGER PRIMARY KEY,
  work_id          INTEGER NOT NULL REFERENCES works(id),
  first_passage_id INTEGER NOT NULL REFERENCES passages(id),
  last_passage_id  INTEGER NOT NULL REFERENCES passages(id),
  ordinal          INTEGER NOT NULL,
  text             TEXT NOT NULL
);

CREATE TABLE embeddings (
  chunk_id    INTEGER NOT NULL REFERENCES chunks(id),
  embedder_id TEXT NOT NULL,
  vector      BLOB NOT NULL,
  PRIMARY KEY (chunk_id, embedder_id)
) WITHOUT ROWID;

CREATE INDEX passages_by_section ON passages(section_id, ordinal);
CREATE INDEX renderings_by_passage ON renderings(passage_id, kind, language);
CREATE INDEX chunks_by_work ON chunks(work_id, ordinal);
''';
