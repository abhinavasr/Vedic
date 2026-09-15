// SQLite schema of a pack database: docs/CONTENT_PACKS.md §5.

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

CREATE TABLE sections (
  id        INTEGER PRIMARY KEY,
  work_id   INTEGER NOT NULL REFERENCES works(id),
  parent_id INTEGER REFERENCES sections(id),
  ordinal   INTEGER NOT NULL,
  kind      TEXT NOT NULL,
  number    TEXT,
  title     TEXT
);

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
  text       TEXT NOT NULL
);

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
