# Pack content JSON (what the server provides)

**Status:** v1 specification (2026-09-15). Machine-checkable schema:
[`schemas/pack-content.v1.schema.json`](schemas/pack-content.v1.schema.json).

This is the document a content pack carries: every verse's **Sanskrit text, translations (e.g.
Hindi and English), transliteration and chant audio**. The server team and content editors
produce it. The app never edits it.

It travels inside the signed pack envelope described in [CONTENT_PACKS.md](CONTENT_PACKS.md):
`payload.bin` is this JSON, deflate-compressed, and encrypted for download packs. Audio files
sit next to the payload on the static host and are fetched per verse. On install the app
converts the JSON into its local SQLite database.

---

## 1. What the app does when something is missing

| The pack has… | The app… |
|---|---|
| a translation in the reader's language | shows it, with translator and attribution |
| no translation in that language | offers **"Translate on this phone"**. The first time, it explains that this needs a **one-time download of the on-device AI model (about 2.4 GB, Wi-Fi recommended)** and asks before downloading. The result is saved on the phone and always labelled **Machine translation**, shown next to the Sanskrit, never instead of it |
| audio for the verse | streams nothing: downloads the file once, verifies its SHA-256, caches it, replays from cache |
| no audio for the verse | offers **"Generate chant on this phone"**, after its own one-time voice model download. Generated audio is saved and replayed, never regenerated for the same text and model |

The Sanskrit text itself always comes from the pack. The AI is never asked to produce it.

---

## 2. Top level

```json
{
  "format": "vedic-pack-content",
  "format_version": 1,
  "pack_id": "bhagavad-gita",
  "revision": 3,
  "languages": ["sa", "hi", "en"],
  "licences": [ … ],
  "voices": [ … ],
  "works": [ … ]
}
```

| Field | Type | Rules |
|---|---|---|
| `format` | string | Exactly `"vedic-pack-content"` |
| `format_version` | integer | `1`. The app refuses versions it does not know |
| `pack_id` | string | `^[a-z0-9]+(?:[.-][a-z0-9]+)*$`. Must equal the manifest's `pack_id` |
| `revision` | integer ≥ 1 | Must equal the manifest's `revision` |
| `languages` | string[] | BCP 47 tags of every language with text in this pack, original first |
| `licences` | object[] | Every licence referenced anywhere below |
| `voices` | object[] | Every voice referenced by audio below. Empty if the pack has no audio |
| `works` | object[] | At least one |

### Licence

```json
{ "id": "gita-hi-2026", "name": "Hindi translation", "attribution": "Translated by …", "notice": null }
```

`id` is unique in the pack. `attribution` is shown in the reader. `notice` is the full text,
where it must be reproduced.

### Voice

```json
{
  "id": "vagdhenu-m1",
  "name": "Vāgdhenu",
  "language": "sa",
  "style": "chant",
  "engine": "vagdhenu@2026-06-17",
  "licence": "vagdhenu"
}
```

`style` is `chant` or `read`. `engine` names the model and revision that rendered the audio.

---

## 3. Work

```json
{
  "slug": "bhagavad-gita",
  "kind": "scripture",
  "title": { "sa": "श्रीमद्भगवद्गीता", "hi": "श्रीमद्भगवद्गीता", "en": "Bhagavad Gītā" },
  "original_language": "sa",
  "script": "Deva",
  "edition": "Critical edition, 700 verses plus 13.0",
  "licence": "gita-sa",
  "front_matter": [ /* passages before the first section, e.g. an invocation */ ],
  "sections": [ /* chapters */ ],
  "back_matter": [ /* passages after the last section */ ]
}
```

| Field | Type | Rules |
|---|---|---|
| `slug` | string | Stable across revisions. Unique in the pack |
| `kind` | string | `scripture`, `commentary` or `document` |
| `title` | object | Language tag → title. Must include `original_language` |
| `original_language` | string | BCP 47, e.g. `sa` |
| `script` | string | ISO 15924 of the original text, e.g. `Deva` |
| `edition` | string? | Recension or edition. Verse numbering depends on it |
| `licence` | string | Licence of the original text |
| `source_note` | string? | Editorial record of where the text came from |
| `front_matter`, `back_matter` | passage[] | Optional |
| `sections` | section[] | Optional; a work may be passages only (put them in `front_matter`) |

## 4. Section

```json
{
  "kind": "chapter",
  "number": "2",
  "title": { "sa": "साङ्ख्ययोगः", "en": "The Yoga of Knowledge" },
  "passages": [ … ],
  "sections": [ … ]
}
```

Sections nest (e.g. skandha → chapter for the Bhāgavatam). A section has `passages`, `sections`,
or both. `number` is as printed and unique among its siblings. `summary` is an optional
language → text object, shown under the chapter title in the reader.

**A filled-in example to hand to the content server:**
[`examples/bhagavad-gita.sample.json`](examples/bhagavad-gita.sample.json).

## 5. Passage

The unit the reader shows, a citation points to, and audio is recorded for.

```json
{
  "ref": "2.47",
  "kind": "verse",
  "label": "2.47",
  "speaker": { "sa": "श्रीभगवानुवाच", "en": "The Blessed Lord said" },
  "lines": [
    "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।",
    "मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥"
  ],
  "meter": "anuṣṭubh",
  "transliterations": [
    { "scheme": "IAST", "lines": ["karmaṇy evādhikāras te mā phaleṣu kadācana |", "mā karma-phala-hetur bhūr mā te saṅgo 'stv akarmaṇi ||"] }
  ],
  "translations": [
    { "language": "hi", "text": "…", "translator": "…", "licence": "gita-hi-2026", "origin": "human" },
    { "language": "en", "text": "…", "translator": "…", "licence": "gita-en-2026", "origin": "human" }
  ],
  "variants": ["सङ्गोऽस्त्वकर्मणि"],
  "audio": [
    {
      "voice": "vagdhenu-m1",
      "file": "audio/vagdhenu-m1/2/2.47.m4a",
      "mime": "audio/mp4",
      "duration_ms": 11840,
      "size": 95123,
      "sha256": "9f2c…"
    }
  ]
}
```

| Field | Type | Rules |
|---|---|---|
| `ref` | string | Stable citation key, unique within the work. Verses use `chapter.verse`; framing text uses names like `2.opening`, `2.colophon`, `invocation`. Never renumbered between revisions |
| `kind` | string | `verse`, `prose`, `heading` or `page` |
| `label` | string? | Display form, e.g. `2.47` |
| `speaker` | object? | Language → "X said" line shown before the verse. A speaker change *inside* a verse stays in `lines`, because it is recited there |
| `lines` | string[] | The original text as printed, one pāda or half-verse per line, in `script`, Unicode NFC, verse numbers removed. At least one non-empty line |
| `meter` | string? | e.g. `anuṣṭubh`, `triṣṭubh` |
| `transliterations` | object[]? | `scheme` (`IAST`, `ISO15919`) and `lines`. If absent, the app transliterates to IAST itself (deterministic, not AI) |
| `translations` | object[]? | One per language at most. `language` BCP 47; `text` may contain paragraph breaks; `translator` optional; `licence` must be listed; `origin` is `human` (default) or `machine`. The app labels `machine` translations visibly |
| `notes` | object[]? | The **Explanation** paragraphs and **Key Takeaways** under the verse. Each has `kind` (`explanation` or `takeaway`), `language`, `text`, optional `author`, and a listed `licence`. Order is kept; takeaways render as bullets |
| `variants` | string[]? | Alternative readings. Never recited, never shown as the verse |
| `audio` | object[]? | One per voice at most. See below |

### Audio file

| Field | Type | Rules |
|---|---|---|
| `voice` | string | A `voices[].id` |
| `file` | string | Path relative to the pack revision directory on the host, under `audio/` — letters, digits, `.`, `_`, `-`, `/` only, no `..`. May instead be an absolute `https://` URL, for a publisher serving audio from somewhere other than the pack host |
| `mime` | string | `audio/mp4` (AAC-LC, 64 kbps mono recommended), `audio/ogg` (Opus, 32 kbps) or `audio/wav` (uncompressed — about five times the size for the same recording) |
| `duration_ms` | integer | Used for progress and verse highlighting |
| `size` | integer | Bytes as served |
| `sha256` | string | Lowercase hex of the file as served. The app rejects a mismatch |

Audio is served from `/v1/packs/<pack_id>/<revision>/<file>`, immutable like everything else
in a revision. In an encrypted pack each audio file is encrypted with the pack's content key in
the same VPK1 format as the payload, and `size` / `sha256` describe the encrypted file.

---

## 6. Validation the app performs

Installation fails, and leaves the previous revision in place, if any of these fail:

- `format`, `format_version`, `pack_id` and `revision` match the signed manifest
- every `licence` and `voice` reference resolves
- work `slug`s are unique; `ref`s are unique within their work; sibling section `number`s are unique
- every passage has at least one non-empty line; all text is valid UTF-8
- translations: at most one per language per passage; `origin` is `human` or `machine`
- audio: at most one per voice per passage; `file` paths are safe; `sha256` is 64 lowercase hex

Unknown fields are ignored, so fields can be added in a later `format_version` without breaking
older apps, as long as their absence stays meaningful.

---

## 7. How this supports RAG (search and Q&A)

JSON is the **transport**: what the server serves and editors produce. It is never queried
directly. On install the app builds a local **SQLite** database from it, and that database is
what retrieval runs on:

- `passages` and `renderings` hold every verse and translation, addressable by ref, so every
  answer can cite and link the exact verse it drew on.
- `chunks` holds retrieval units built deterministically from the passages. Each chunk records
  the first and last passage it covers.
- Embeddings for those chunks go into flutter_gemma's vector store, which is SQLite too
  (`flutter_gemma_rag_sqlite`, `sqlite-vec` KNN). Each document's id is
  `<pack_id>/<work slug>/<chunk ordinal>`, and its metadata holds the passage refs.
  `searchSimilar` returns ids, and the app resolves them to verses in the pack database. The
  model receives only those retrieved passages.
- Chunks are embedded on the phone after install. A later format version may add an optional
  binary sidecar of precomputed vectors per embedder, `embeddings/<embedder-id>.bin`, rather
  than putting 768 floats per chunk into the JSON.

This keeps the transport simple and diffable while the phone gets indexed, queryable storage.

## 8. Machine translation on the phone

When a reader asks for a language the pack doesn't have:

1. If the assistant model isn't installed, the app explains what it is, its size, that it runs
   entirely on the phone, and that the download happens once. It downloads only if the reader
   agrees, and only after the device capability check passes.
2. The model gets the Sanskrit lines plus any human translation in the pack as context, and is
   asked for a faithful translation into the target language.
3. The result is stored on the phone per `(pack_id, work slug, ref, language, model revision)`
   and shown under a **Machine translation** label, below the original. A newer pack revision
   that adds a human translation replaces it in the display automatically.
4. A 2-billion-parameter model can mistranslate Sanskrit. The label says so, and the original
   is always one line above.

---

## 9. Complete minimal example

```json
{
  "format": "vedic-pack-content",
  "format_version": 1,
  "pack_id": "bhagavad-gita",
  "revision": 1,
  "languages": ["sa", "en"],
  "licences": [
    { "id": "gita-sa", "name": "Bhagavad Gītā, Sanskrit text", "attribution": "Sanskrit text." },
    { "id": "gita-en", "name": "English translation", "attribution": "Translated by …" }
  ],
  "voices": [
    { "id": "vagdhenu-m1", "name": "Vāgdhenu", "language": "sa", "style": "chant", "engine": "vagdhenu@2026-06-17", "licence": "gita-sa" }
  ],
  "works": [
    {
      "slug": "bhagavad-gita",
      "kind": "scripture",
      "title": { "sa": "श्रीमद्भगवद्गीता", "en": "Bhagavad Gītā" },
      "original_language": "sa",
      "script": "Deva",
      "licence": "gita-sa",
      "sections": [
        {
          "kind": "chapter",
          "number": "2",
          "title": { "sa": "साङ्ख्ययोगः", "en": "The Yoga of Knowledge" },
          "passages": [
            {
              "ref": "2.47",
              "kind": "verse",
              "label": "2.47",
              "speaker": { "sa": "श्रीभगवानुवाच", "en": "The Blessed Lord said" },
              "lines": [
                "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।",
                "मा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि ॥"
              ],
              "translations": [
                { "language": "en", "text": "…", "licence": "gita-en" }
              ],
              "audio": [
                { "voice": "vagdhenu-m1", "file": "audio/vagdhenu-m1/2/2.47.m4a", "mime": "audio/mp4", "duration_ms": 11840, "size": 95123, "sha256": "0000000000000000000000000000000000000000000000000000000000000000" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```
