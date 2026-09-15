# Content packs: format, encryption and delivery

**Status:** specification, v1 draft (2026-09-15). The bundled (unencrypted) path is being built
first; the encrypted download path is specified here so the bundled format never has to change
to support it.

A **content pack** is the single unit of scripture and reference content the app installs. The
same format serves both deliveries:

| Delivery | Where it comes from | Encrypted | Key |
|---|---|---|---|
| **Bundled** (base data) | `assets/packs/` inside the APK/IPA | No: any key in the app binary is readable by anyone who has the binary | none |
| **Downloaded** | Static file host / CDN | Yes | Per-pack content key, delivered wrapped to the user's device key |

One installer handles both. A bundled pack is a downloaded pack that skips the download and
key-unwrap steps.

---

## 1. Goals, non-goals and what encryption actually buys

**Goals**

1. One format for bundled and downloaded content. Converting source PDFs and text files
   happens once, at build time, on our machines.
2. Works fully offline once installed (ground rule 3). No licence check-in, no expiry.
3. Static hosting for every large file: immutable URLs, `Range` resume, strong `ETag`,
   CDN-cacheable (playbook §4.2 hosting contract).
4. Only a user whose device holds an entitled key can decrypt a downloaded pack.
5. Tamper-evident: the app installs only packs we signed.
6. Updates replace a pack atomically; bookmarks and notes survive the update.

**Non-goals**

- **This is not DRM.** Encryption stops pack files being copied between users or scraped from
  the CDN. It does not stop a determined user on a rooted or jailbroken phone from reading text
  the app has decrypted to show them. No offline scheme can: the app must hold the plaintext to
  display it.
- **No revocation after install.** Offline-first means a pack that has been installed stays
  readable. We can refuse future revisions, not recall past ones.
- **No per-user payloads.** Every user downloads identical ciphertext for a given revision; only
  the tiny key envelope is per device. Per-user ciphertext would defeat CDN caching and cost
  storage per user, and it buys nothing given the point above.

### Threat model

| Threat | Mitigated by |
|---|---|
| Someone downloads `payload.bin` from the CDN without entitlement | AES-256-GCM encryption; the content key never appears in plaintext on any host |
| User A copies their pack files to user B | Content key is wrapped to A's hardware-bound device key, which cannot be exported |
| Compromised or spoofed host serves altered content | Ed25519 signature on the manifest, verified against keys pinned in the app; manifest pins the payload's SHA-256 |
| Truncated, reordered or corrupted download | SHA-256 of the ciphertext, plus per-segment AEAD with index and final-segment flag |
| Old revision replayed to block an update | Signed catalogue lists current revisions; app never installs a revision lower than one it has |
| One leaked content key | Exposes one revision of one pack, not the catalogue: keys are per pack **and** per revision |
| Rooted device reads installed plaintext | **Not mitigated.** Out of scope; see non-goals |

---

## 2. Hosting layout

Everything is under a versioned root, so a v2 format can coexist on the same host.

```
/v1/catalog.json                                     mutable: the only file that changes
/v1/catalog.json.sig
/v1/packs/<pack_id>/<revision>/manifest.json         immutable
/v1/packs/<pack_id>/<revision>/manifest.json.sig     immutable
/v1/packs/<pack_id>/<revision>/payload.bin           immutable, large
/v1/packs/<pack_id>/<revision>/payload.bin.sha256    immutable
/v1/keys/<device_key_id>/<pack_id>/<revision>.json   per-device key envelopes
```

- **Immutable means never overwritten and never deleted.** A new revision is a new directory. An
  installer mid-resume must never find the bytes under it changed.
- **Host requirements** for everything except `catalog.json`: honest `Content-Length`, `Range`
  support, a strong `ETag`, `HEAD`, no authentication, long cache lifetime.
  `catalog.json` gets a short cache lifetime (minutes).
- **Key envelopes can be public.** An envelope is useless without the device's private key,
  which never leaves that device's secure hardware. `device_key_id` is the SHA-256 of the
  device's public key, so envelope URLs can't be guessed or enumerated without that key.
  This keeps key delivery on the static host too.

`pack_id` matches `^[a-z0-9]+(?:[.-][a-z0-9]+)*$`, e.g. `bhagavad-gita.sa-en`. `revision` is a
positive integer that increases by one per release of that pack.

---

## 3. Catalogue

`catalog.json` lists what can be installed. The app fetches it, verifies `catalog.json.sig`, and
never installs anything the catalogue doesn't list.

```json
{
  "format": "vedic-catalog",
  "format_version": 1,
  "generated_at": "2026-09-15T00:00:00Z",
  "sequence": 42,
  "packs": [
    {
      "pack_id": "bhagavad-gita.sa-en",
      "revision": 3,
      "kind": "text",
      "title": { "en": "Bhagavad Gītā", "sa": "भगवद्गीता" },
      "summary": { "en": "700 verses with IAST transliteration and English translation." },
      "languages": ["sa", "en"],
      "download_bytes": 3145728,
      "installed_bytes": 9437184,
      "requires_entitlement": true,
      "min_app_build": 12,
      "manifest": "packs/bhagavad-gita.sa-en/3/manifest.json"
    }
  ]
}
```

`sequence` increases with every publish. The app rejects a catalogue whose `sequence` is lower
than the last one it accepted. This blocks rollback to a stale catalogue.

---

## 4. Manifest

One per pack revision. Everything the installer needs to decide, verify and decrypt.

```json
{
  "format": "vedic-pack",
  "format_version": 1,
  "pack_id": "bhagavad-gita.sa-en",
  "revision": 3,
  "kind": "text",
  "schema_version": 1,
  "min_app_build": 12,
  "created_at": "2026-09-15T00:00:00Z",
  "title": { "en": "Bhagavad Gītā", "sa": "भगवद्गीता" },
  "languages": ["sa", "en"],
  "payload": {
    "file": "payload.bin",
    "size": 3145728,
    "sha256": "<hex SHA-256 of payload.bin exactly as served>",
    "compression": "deflate",
    "encryption": "vpk1-aes256gcm-stream",
    "key_delivery": "hpke-device-envelope",
    "plaintext_size": 9437184,
    "plaintext_sha256": "<hex SHA-256 of the decrypted, decompressed SQLite file>"
  },
  "embeddings": [
    {
      "embedder_id": "gecko-110m",
      "embedder_revision": "<hash of the .tflite file used>",
      "dimensions": 768,
      "quantisation": "int8-symmetric-per-vector"
    }
  ],
  "licences": [
    {
      "id": "gita-translation-2026",
      "commercial_redistribution": true,
      "grant_reference": "LIC-2026-004"
    }
  ]
}
```

Field rules:

- `encryption` is `"none"` or `"vpk1-aes256gcm-stream"`. `key_delivery` is `"none"` or
  `"hpke-device-envelope"`. They go together: both `none` (bundled) or both set (downloaded).
- **The installer refuses** unknown `format_version`, a `schema_version` newer than the app
  supports, or `min_app_build` above its own build. The last two show *"Update the app to
  install this pack."*
- `embeddings` is optional. Vectors are used only if `embedder_id` **and** `embedder_revision`
  match the embedder installed on the phone. Otherwise the app embeds the pack's chunks on the
  device, in the background, into its own database (§8).
- **Every licence in the pack database must appear here with
  `commercial_redistribution: true`.** The build tool refuses to publish otherwise
  (LICENSING.md §3).

### Signatures

`manifest.json.sig` and `catalog.json.sig` are detached Ed25519 signatures over the **exact bytes
served**. No JSON canonicalisation: the verifier signs and checks bytes, not parsed objects.

```json
{ "alg": "ed25519", "key_id": "publisher-2026-a", "signature": "<base64url, 64 bytes>" }
```

The app pins a small list of publisher public keys, each with a `key_id` and a validity window,
so a key can be rotated by shipping an app update before it is needed. The signing key lives
offline, on a hardware token or in a KMS, and never on the build machine's disk. Development
builds pin a separate dev key that production builds do not trust.

---

## 5. Payload: the pack database

The plaintext payload is the **content JSON** defined in
[PACK_CONTENT_JSON.md](PACK_CONTENT_JSON.md), deflate-compressed (RFC 1950 zlib stream) and then,
for downloads, encrypted. `plaintext_sha256` is the SHA-256 of that JSON. JSON is what the
content server and editors produce, so it is also what ships. On install the app validates it and
builds the local **SQLite database** below from it. Audio files are not in the payload: they sit
next to it under `audio/` and are fetched per verse.

- `PRAGMA application_id = 0x56504B31` ("VPK1"), so a stray SQLite file is never mistaken for a
  pack.
- `PRAGMA user_version` = `schema_version`.
- Built with `VACUUM` last, `journal_mode=DELETE`, and no WAL or journal files alongside.
- All text in Unicode **NFC**. ZWJ and ZWNJ are preserved; they change how Indic conjuncts render.
- Opened **read-only** on the device. The app never writes into a pack.

### Schema v1

```sql
CREATE TABLE pack_meta (            -- must match the manifest: pack_id, revision, schema_version
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE licences (
  id                        TEXT PRIMARY KEY,
  name                      TEXT NOT NULL,
  commercial_redistribution INTEGER NOT NULL CHECK (commercial_redistribution IN (0, 1)),
  grant_reference           TEXT,   -- our record of the grant
  attribution               TEXT NOT NULL,  -- shown in the reader
  notice                    TEXT    -- full text, where the licence requires reproducing it
);

CREATE TABLE works (
  id           INTEGER PRIMARY KEY,
  slug         TEXT NOT NULL UNIQUE,   -- stable across revisions: 'bhagavad-gita'
  kind         TEXT NOT NULL CHECK (kind IN ('scripture', 'commentary', 'document')),
  title        TEXT NOT NULL,
  title_native TEXT,
  language     TEXT NOT NULL,          -- BCP 47: 'sa', 'hi', 'kn', 'en'
  script       TEXT,                   -- ISO 15924: 'Deva', 'Knda', 'Latn'
  edition      TEXT,                   -- recension or edition; verse numbering depends on it
  licence_id   TEXT NOT NULL REFERENCES licences(id),
  source_note  TEXT                    -- where the text came from
);

CREATE TABLE sections (               -- chapter / canto / sūkta / page hierarchy
  id        INTEGER PRIMARY KEY,
  work_id   INTEGER NOT NULL REFERENCES works(id),
  parent_id INTEGER REFERENCES sections(id),
  ordinal   INTEGER NOT NULL,
  kind      TEXT NOT NULL,              -- 'chapter', 'canto', 'sukta', 'page', ...
  number    TEXT,                       -- as printed: '2', 'II'
  title     TEXT
);

CREATE TABLE passages (               -- the unit the reader shows and citations point at
  id         INTEGER PRIMARY KEY,
  work_id    INTEGER NOT NULL REFERENCES works(id),
  section_id INTEGER REFERENCES sections(id),
  ordinal    INTEGER NOT NULL,          -- reading order within the work
  kind       TEXT NOT NULL CHECK (kind IN ('verse', 'prose', 'heading', 'page')),
  ref        TEXT NOT NULL,             -- stable citation key: '2.47', 'p12'
  label      TEXT,                      -- display form: '2.47', 'p. 12'
  text       TEXT NOT NULL,             -- in the source script
  meter      TEXT,
  UNIQUE (work_id, ref),
  UNIQUE (work_id, ordinal)
);

CREATE TABLE renderings (             -- transliterations, translations, commentary
  id         INTEGER PRIMARY KEY,
  passage_id INTEGER NOT NULL REFERENCES passages(id),
  kind       TEXT NOT NULL CHECK (kind IN ('transliteration', 'translation', 'commentary', 'variant')),
  language   TEXT NOT NULL,
  script     TEXT,
  scheme     TEXT,                      -- transliteration scheme: 'IAST', 'ISO15919'
  author     TEXT,
  licence_id TEXT NOT NULL REFERENCES licences(id),
  text       TEXT NOT NULL
);

CREATE TABLE chunks (                 -- retrieval units for the assistant
  id               INTEGER PRIMARY KEY,
  work_id          INTEGER NOT NULL REFERENCES works(id),
  first_passage_id INTEGER NOT NULL REFERENCES passages(id),
  last_passage_id  INTEGER NOT NULL REFERENCES passages(id),
  ordinal          INTEGER NOT NULL,
  text             TEXT NOT NULL
);

CREATE TABLE embeddings (             -- optional; see manifest.embeddings
  chunk_id    INTEGER NOT NULL REFERENCES chunks(id),
  embedder_id TEXT NOT NULL,
  vector      BLOB NOT NULL,            -- int8, one byte per dimension
  PRIMARY KEY (chunk_id, embedder_id)
) WITHOUT ROWID;

CREATE INDEX passages_by_section ON passages(section_id, ordinal);
CREATE INDEX renderings_by_passage ON renderings(passage_id, kind, language);
CREATE INDEX chunks_by_work ON chunks(work_id, ordinal);
```

**Row ids are local to one revision.** Anything the user keeps (bookmarks, notes, reading
position, cached embeddings) references content by **`(pack_id, work slug, passage ref)`**, which
stays stable across revisions. The build tool fails if a new revision drops a `ref` that the
previous revision had, unless the change is listed explicitly in the pack's `ref_changes`.

**No full-text index in the pack.** The app builds FTS on the device when a pack is installed.
Tokenizer behaviour on Devanagari varies by SQLite build, so an index built on our build machine
may not match what the phone's SQLite does with queries.

---

## 6. Encryption

### 6.1 Key hierarchy

```
Publisher signing key (Ed25519, offline) ── signs catalogue and manifests

Content key, CEK (32 random bytes) ─ one per (pack_id, revision), held in the server key vault
  └─ HKDF ─> payload key ─ encrypts payload.bin

Device key (P-256, generated in Secure Enclave / Android Keystore, non-exportable)
  └─ HPKE ─> key envelope = CEK wrapped to this device's public key
```

**P-256, not X25519.** P-256 is the only curve iOS Secure Enclave supports, and it is supported
by Android Keystore / StrongBox. Using it lets the private key live in secure hardware on both
platforms rather than in app memory.

### 6.2 `payload.bin` byte layout (`vpk1-aes256gcm-stream`)

Online authenticated encryption in segments (the STREAM construction, as used by Tink's
streaming AEAD). The installer decrypts with bounded memory, and truncation, reordering or
bit-flips are detected per segment.

```
Header (56 bytes)
  0   4  magic           "VPK1" (0x56 0x50 0x4B 0x31)
  4   1  format version  0x01
  5   1  suite           0x01 = AES-256-GCM, HKDF-SHA256
  6   2  reserved        0x0000
  8   4  segment size    uint32 big-endian, plaintext bytes per segment (1,048,576)
  12 32  salt            random, per payload
  44  7  nonce prefix    random, per payload
  51  5  reserved        zeros

Segments i = 0 … n-1, immediately after the header
  ciphertext_i = AES-256-GCM(
      key   = payload key,
      nonce = nonce_prefix(7) || uint32_be(i)(4) || last(1),   last = 0x01 on the final segment, else 0x00
      aad   = header(56),
      plaintext = compressed bytes [i × segment_size, (i+1) × segment_size) )
  → segment_size bytes + 16-byte tag; the final segment holds 0 … segment_size bytes + 16-byte tag.
  An empty plaintext is one final segment of just a tag.

payload key = HKDF-SHA256(
    ikm  = CEK,
    salt = header.salt,
    info = "vedic/pack/v1" || 0x00 || pack_id (UTF-8) || 0x00 || uint32_be(revision),
    L    = 32)
```

Binding `pack_id` and `revision` into key derivation means a CEK or ciphertext cannot be
transplanted onto another pack or revision. Binding the header as AAD means it can't be edited.
Segment count follows from `payload.size`, so there is no length field to trust.

For `encryption: "none"`, `payload.bin` is the deflate stream itself, with no header. Integrity
then rests on the signed manifest's `sha256`.

### 6.3 Key envelope (`hpke-device-envelope`)

HPKE (RFC 9180), Base mode, suite **DHKEM(P-256, HKDF-SHA256) / HKDF-SHA256 / AES-256-GCM**
(KEM 0x0010, KDF 0x0001, AEAD 0x0002).

```json
{
  "format": "vedic-pack-key",
  "format_version": 1,
  "pack_id": "bhagavad-gita.sa-en",
  "revision": 3,
  "device_key_id": "<hex SHA-256 of the device's uncompressed P-256 public key>",
  "suite": { "kem": 16, "kdf": 1, "aead": 2 },
  "enc": "<base64url, 65 bytes: encapsulated ephemeral public key>",
  "ciphertext": "<base64url, 48 bytes: 32-byte CEK + 16-byte tag>"
}
```

- HPKE `info` = `"vedic/pack-key/v1" || 0x00 || pack_id || 0x00 || uint32_be(revision) || 0x00 || device_key_id`,
  so an envelope opens only for the pack, revision and device it names. `aad` is empty.
- **Base mode is sufficient.** A forged envelope yields a wrong CEK, which fails AEAD on the
  first segment. That is at worst a denial of service, and the signed manifest has already
  pinned the ciphertext.
- On device: iOS uses CryptoKit (`HPKE` on iOS 17+; DHKEM is assembled from
  `SecureEnclave.P256.KeyAgreement` on iOS 16). Android does ECDH with the Keystore-held key and
  runs the HPKE key schedule in app code. Only the ECDH step touches the private key, and it
  runs in secure hardware on both platforms.

### 6.4 Device keys and entitlement

1. **First time the user needs a downloaded pack:** the app generates a P-256 key pair in secure
   hardware (StrongBox if present, else TEE; Secure Enclave on iOS), marked non-exportable and
   available after first unlock.
2. **Registration:** the app sends the public key, plus proof of entitlement (store receipt or
   account token), to the entitlement service. **This is the one call that is not a static file
   fetch** (see §10, decision 1). It carries no user content and nothing AI-related.
3. **Issuing:** for every pack revision the user is entitled to, the service wraps that
   revision's CEK to the device key and publishes the envelope under `/v1/keys/<device_key_id>/`.
   New revisions get envelopes at publish time.
4. **More devices:** each device registers its own key; there is no user-level private key to
   sync. The service caps devices per user.
5. **Lost device or reinstall:** Android deletes Keystore keys on uninstall, so a reinstall
   registers a new key. On iOS, Secure Enclave key items can survive a reinstall. The app checks
   for an existing key before creating one.

---

## 7. Install flow

Downloaded and bundled packs share the flow; bundled packs skip the steps marked †.

```
 1  Fetch catalogue, verify signature and sequence                     †
 2  Fetch manifest + signature; verify against pinned publisher keys
 3  Refuse if format/schema/min_app_build unsupported, or revision ≤ installed
 4  Check free space ≥ size + plaintext_size + 10 % headroom
 5  Download payload.bin (resumable, If-Range on ETag, Wi-Fi by default) †
 6  Verify SHA-256 of payload.bin == manifest.payload.sha256
 7  Fetch key envelope; unwrap CEK with the device key                   †
 8  Stream: decrypt † → inflate → temp file in the app's private packs dir
 9  Verify SHA-256 of the temp file == plaintext_sha256
10  Open read-only: application_id, user_version, pack_meta match the manifest,
    PRAGMA integrity_check = ok, every licence has commercial_redistribution = 1
11  Activate in one app-database transaction: move the temp file to
    packs/<pack_id>/<revision>.sqlite, record it as the active revision
12  Post-install, in the background: build FTS; embed chunks if the pack
    lacks vectors for the installed embedder
13  Delete payload.bin, the envelope and the previous revision's database
    once nothing has it open
```

**Failure rules.** Every failure leaves the previous revision active and readable; installs
never delete what works. A SHA-256 or AEAD failure deletes the downloaded file, retries once
from scratch, then stops with a message. Temp files are deleted on every launch before new
installs start, since an install can be killed at any step. iOS gives no background time for
decryption, so steps 8–10 must resume safely after the app is killed: they restart from step 8
using the verified `payload.bin`.

**Storage.** Installed databases live in app-private storage and are excluded from iCloud and
Android backups. They are re-downloadable, and backups would copy licensed content off the
device. v1 relies on the OS's file-based encryption at rest (iOS Data Protection class
*complete until first user authentication*; Android FBE). SQLCipher is the upgrade path if
per-file at-rest encryption is ever required (§10, decision 3).

---

## 8. What the app keeps outside packs

The app's own database (drift) holds everything user-specific and anything derived on the device.
Packs stay read-only and replaceable.

| App table | Contents |
|---|---|
| `installed_packs` | pack_id, active revision, file path, installed_at, source (bundled / downloaded) |
| `pack_embeddings` | (pack_id, revision, chunk ordinal, embedder_id) → int8 vector, for packs without matching vectors |
| `bookmarks`, `notes`, `reading_position` | keyed by (pack_id, work slug, passage ref) |
| `device_keys` | device_key_id and platform key alias; never the private key |

Retrieval for the assistant searches the chunks of every installed pack plus the user's own
imported documents. Search is exact cosine over int8 vectors (FEASIBILITY_AND_ROADMAP.md §4).

---

## 8b. Chant audio: served, cached or generated

Audio for a passage comes from the first source that has it (`lib/audio/chant_audio.dart`):

1. **An installed audio pack** (`kind: audio`), e.g. pre-rendered Vāgdhenu chant.
2. **Server audio**, one file per passage on the static host. It is downloaded on first play and
   cached, so it is never downloaded twice. When offline, this step is skipped.
3. **Audio generated earlier on this phone**, replayed from the cache.
4. **Generate now** with the on-device Sanskrit speech model, then save it, so each passage is
   generated at most once per model and text.

The cache key is the pack, work, passage ref, the **exact text** and the **voice id**. A corrected
text in a new pack revision, or a new model revision, therefore never replays stale audio. Server
and on-device audio are cached separately, and server audio is preferred once it exists. The
cache is capped (300 MB by default) and evicts the least recently played audio first. Concurrent
requests for the same passage share one generation.

With no pack, no server audio and no model installed, there is no audio, and the Listen control
says so (ground rule 3).

## 9. Build pipeline: from your PDFs and text files to a pack

Runs on our machines, never on the phone. Input per pack:

```
content/<pack_id>/
  pack.yaml        pack_id, revision, titles, languages, licences, created_at (fixed, not
                   the clock), and one entry per work: slug, kind, source file, format,
                   language, script, edition, licence
  sources/         .pdf and .txt files
```

Build with `dart run tool/build_pack.dart content/<pack_id>`. `--bundle` also copies the pack
into `assets/packs/`; `--encrypt` produces a download pack with a fresh content key under
`build/key-vault/`. The first real pack is `content/bhagavad-gita.sa`.

Steps:

1. **Extract.** Digital PDFs: text per page via PDFium, the same engine the app uses. Scanned
   PDFs (no text layer) are **flagged, not guessed**: OCR on Sanskrit is unreliable (roadmap
   §3.6), so they need a human-checked text file. `.txt` is read as UTF-8 and rejected if not.
2. **Normalise.** NFC; fix line-break hyphenation; collapse whitespace; keep ZWJ and ZWNJ.
3. **Structure.** A PDF becomes one `page` passage per page (`ref` `p12`); a plain `.txt`
   becomes one `prose` passage per paragraph (`para3`). `format: verses` parses
   chapter-and-verse text laid out as on sanskritdocuments.org: chapter headings become
   sections, verses get refs from their numbers (`॥ २-४७॥` → `2.47`), speaker lines,
   chapter openings and colophons become their own passages, and parenthesised readings
   become `variant` renderings rather than verse text. The parser is strict: any line that
   doesn't fit fails the build with its line number.
4. **Chunk** with `lib/core/chunker.dart`, the same code the app uses on user documents, so
   pack and user retrieval behave alike.
5. **Embed (optional),** only if desktop output of the embedder is verified to match the phone
   within tolerance (cosine ≥ 0.999 on a sample). Otherwise leave vectors out; the phone computes
   them.
6. **Write** the SQLite database, check that every `ref` from the previous revision is still
   present, then `VACUUM`.
7. **Compress** (deflate) and, for downloads, **encrypt** with a fresh CEK sent to the key vault.
8. **Manifest, sign, publish** the immutable directory, then publish the new catalogue last.

**Reproducible.** The same inputs produce a byte-identical plaintext database. `created_at`
comes from `pack.yaml`, and row order is deterministic. A revision's changes can be reviewed as
a diff of the two databases before signing.

---

## 10. Open decisions

1. **The entitlement service breaks "static file hosts only".** Per-user keys require
   something that knows who is entitled and receives device public keys. Options:
   (a) accept one small authenticated endpoint for registration only, with no content, no AI
   and no user data beyond a public key and a receipt; or (b) drop per-user encryption and ship
   downloads under `encryption: none`. **Recommendation: (a).** CLAUDE.md ground rule 1 should
   be amended to name it explicitly if chosen.
2. **Entitlement source.** App Store / Play purchases, our own accounts, or free with
   registration. This drives what "proof of entitlement" means in §6.4.
3. **At-rest encryption beyond the OS.** v1 decrypts to app-private storage. SQLCipher (BSD
   licence) would keep packs encrypted on disk under a key wrapped by the device key, at some
   read cost. It protects only against extraction from an unlocked, compromised device, which
   is out of scope (§1).
4. **Devices per user**, and whether to reissue envelopes automatically on reinstall.
5. **Seed pack contents.** Awaiting the source files, plus a recorded commercial grant for each
   (LICENSING.md §5).
6. **Pre-computed embeddings.** Only if the desktop-vs-phone parity check in §9 step 5 passes.

## 11. Before encrypted downloads ship

- [ ] Test vectors: a fixed CEK, salt and nonce prefix, a small plaintext and the expected
      `payload.bin`; a fixed device key and the expected envelope. The builder, the Dart
      reference decryptor and both native unwrap paths must reproduce them.
- [ ] Tampering tests: flipped bit in the header, in a middle segment and in the final tag;
      truncated final segment; swapped segments; an envelope for a different revision.
- [ ] Kill-at-every-step install tests on a real device (§7).
- [ ] External review of §6 before production keys are generated.
