# Vedic

An offline-first Flutter app (Android + iOS) for Hindu scripture reading, chant audio,
panchang calculation, and on-device AI over your own documents.

**Every inference runs on the phone.** There are no cloud AI APIs. The only network calls are
downloads of model weights and content packs from static file hosts.

## Status

**Pre-implementation.** No app code yet. The architecture and phasing are being agreed first.

👉 **Start here: [docs/FEASIBILITY_AND_ROADMAP.md](docs/FEASIBILITY_AND_ROADMAP.md)** — what is
actually buildable, what is not, and in what order. It includes an honest account of the one
spec assumption that does not hold (on-device Vāgdhenu TTS) and what we do instead.

📜 **[docs/LICENSING.md](docs/LICENSING.md)** — dependency licence review and the one open
decision that blocks Phase 3.

## Planned capabilities

| | Feature | Phase |
|---|---|---|
| 📥 | Share PDFs and text files into the app; they become a searchable, AI-queryable source | 1 |
| 🤖 | On-device LLM (Gemma 4 E2B-it via LiteRT-LM) + on-device embeddings for grounded, cited Q&A | 1 |
| 📖 | Scripture reader — Sanskrit with transliteration and translations | 2 |
| 🔊 | Chant audio with correct meter, from pre-rendered Vāgdhenu | 4 |
| 🗓️ | Panchang: tithi, nakṣatra, yoga, karaṇa, sunrise/sunset, festival reminders | 3 |

## Content model

A small, licence-clean **seed pack is bundled** in the app, so it is useful offline on first
launch with no download. Everything else — further scriptures, translations, chant audio, and
the AI models — is delivered as optional **downloadable packs** over one shared, resumable,
Wi-Fi-by-default download queue.

The app is fully functional with no AI model installed. The AI is a power feature, not the floor.

## Ground rules

- **No cloud APIs** for any feature. All ML and all astronomical maths run on-device.
- **The model never generates scripture text.** Verses are always retrieved from the database.
  AI answers are retrieval-grounded, cited, and labelled as machine-generated.
- **Every feature degrades to absent.** A missing model means a feature is hidden or explained,
  never broken.

## Licence

**Proprietary. All rights reserved.** See [`LICENSE`](LICENSE).

Third-party components ship under their own licences — reviewed in
[docs/LICENSING.md](docs/LICENSING.md). MIT, BSD and Apache-2.0 notices must be reproduced in
the app's "Open source licences" screen; being closed source does not exempt us from that.
