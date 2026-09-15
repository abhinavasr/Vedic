# Vedic App — Feasibility Assessment & Phased Roadmap

**Status:** pre-implementation. No app code has been written yet.
**Date:** 2026-09-15
**Purpose:** establish what is actually buildable before committing to an architecture.

This document is deliberately blunt. The original spec is a good product vision, but three
of its assumptions do not survive contact with reality, and one of them (on-device Vāgdhenu)
would have burned months if we had started coding against it.

---

## 0. The one-paragraph summary

Everything in the spec is achievable **except running Vāgdhenu TTS on the phone**, which is
today a research project, not an engineering task. The astronomy is solid and cheap. The
on-device LLM is solved and proven. The document-ingestion feature (share a PDF, ask
questions about it) is achievable now and is the fastest path to a genuinely useful v1,
because it is the one major feature whose content the *user* supplies — so it is not
blocked on the project's real long pole, which is **licensed scripture text**, an
editorial and legal problem rather than a coding one.

---

## 1. Verified findings

Each row was checked against the actual source, not recalled. Verification date 2026-09-15.

| Spec assumption | Verdict | Evidence |
|---|---|---|
| Gemma 4 E2B-it runs on-device via LiteRT-LM | ✅ **Confirmed** | `flutter_gemma` 1.8.3 + `flutter_gemma_litertlm` 1.6.4 live on pub.dev; the attached playbook measured it on real hardware (62 s cold load, ~25 chars/s, CPU) |
| On-device embeddings for RAG over user PDFs | ✅ **Confirmed, better than expected** | `flutter_gemma_embeddings` ships EmbeddingGemma (300M, 768-dim) and Gecko (110M) as `.tflite` via the same LiteRT FFI. Gecko ≈109 ms/doc, EmbeddingGemma ≈286 ms/doc |
| Swiss Ephemeris compiled for mobile via FFI | ✅ **Confirmed, already done for us** | `sweph` 4.1.0+2.10.3 on pub.dev — cross-platform Flutter bindings, wraps Swiss Ephemeris 2.10.3. No JNI work needed |
| Share PDFs/text into the app | ✅ **Confirmed** | `receive_sharing_intent` 1.9.0; PDF text via `syncfusion_flutter_pdf` / `pdfrx`; OCR fallback via `google_mlkit_text_recognition` 0.17.1 |
| Vāgdhenu exists as a real Sanskrit chant TTS | ✅ **Confirmed** | Apache-2.0. IndicF5/F5-TTS flow-matching DiT, ~337M params, fine-tuned BigVGAN-v2 vocoder. MOS ~4.6 from expert listeners. Genuinely excellent work |
| **Vāgdhenu can be quantized to INT8 and run on-device** | ❌ **False today** | See §2. It is CUDA-only PyTorch, has no ONNX or mobile export, and is architecturally the worst-case shape for a phone |

---

## 2. The one thing that does not work: on-device Vāgdhenu

The spec's Phase 3 says "integrate ONNX Runtime, port the normalizer to Dart, wire
Transformer → BigVGAN → audio player." That reads like a week of plumbing. It is not.

**What the upstream project actually ships:**

- Python 3.10 with a **CUDA 12.1 GPU** as a stated requirement.
- **No ONNX export. No quantized export. No mobile target.** Nobody has done this conversion.
- The architecture is a **flow-matching DiT**: unlike a normal TTS model, generating audio
  requires running the full 337M-parameter transformer **N times over** (typically 16–32
  sampling steps), not once. A phone pays the whole model cost on every step.
- **BigVGAN-v2** is a deliberately heavy, high-fidelity vocoder — it is what buys the MOS 4.6,
  and it is far more expensive than the HiFiGAN/Vocos-class vocoders that ship on phones.
- It is a **voice-cloning architecture** (OT-CFM mel-infilling). It needs a *reference audio
  clip plus its reference text* on every call. The app would have to ship reference chants,
  and prosody is steered by which reference is chosen — this is a product design surface the
  spec does not account for.

**The analogy:** the spec treats this like moving a piano into a smaller room. It is closer
to shipping a pipe organ by post. It can be done, but you disassemble it first, and some of
what makes it sound good does not survive the journey.

**What on-device would actually require** (each item is real work, and item 2 is research):

1. Export DiT + BigVGAN to ONNX/LiteRT — the playbook's §7 documents how badly this goes on
   transformer and conv-heavy models (`enable_hlfb=False`, builtin op 206, runtime segfaults).
2. **Step distillation** — cutting 32 sampling steps to 2–4 without losing the meter fidelity
   that is the entire point of the model. This is a research result, not a config flag.
3. Replace or distil BigVGAN-v2 into something phone-sized, and prove the sibilant and
   aspiration contrasts survive — precisely the things the paper measures.
4. INT8 calibration on real chant, judged by ear against the float model (playbook §7.3:
   cosine similarity of 0.9997 still produced visibly wrong output).

Estimate: **months, with a real chance of failure**, and it must not sit on the critical path.

### The way to get Vāgdhenu quality anyway: pre-render it

The authors' own two deployments were **a 5,183-verse video corpus and an audio app of
~18,000 verses** — i.e. they rendered the audio ahead of time and shipped the files. We
should do the same.

Run Vāgdhenu on a workstation/rented GPU, render each verse once, ship the audio in the
content packs. The phone plays a file.

This **honours the no-cloud constraint completely** — there is no network call at runtime and
no user data leaves the device. Rendering is a build step, like compiling. It also gives
better audio than any on-device model would, sooner, and at zero battery cost. The only
prices are storage and losing per-user voice choice.

On-device TTS stays on the roadmap as Tier C, for arbitrary text the packs don't cover.

---

## 3. The other constraints the spec does not mention

### 3.1 The real long pole is text, not code

Sanskrit source text with reliable translations is the bottleneck. Sources (GRETIL,
sanskritdocuments.org, archive.org, individual translations) carry **wildly different
licences**, and many well-known English translations are still in copyright. Verse text is
also not uniform — recensions differ, and verse numbering differs between editions, which
breaks any cross-reference scheme that assumes one canonical numbering.

This is editorial and legal work. It parallelises with engineering but does not go faster
with more engineers. **Start it in week 1 of Phase 1, not in Phase 2.**

**Mitigation (agreed):** ship a small, licence-clean **seed pack bundled in the app** so the
app is useful on first launch with no download, and deliver everything else as
**downloadable content packs**. See §5.

### 3.2 A 2B model will confidently invent scripture

This is the most serious risk in the project and it is not a technical one.

A ~2B parameter model asked "what does Gita 2.47 mean" will produce fluent, plausible,
*sometimes fabricated* verses, citations and commentary — and users will not be able to tell.
For a spiritual text, a hallucinated verse is not a bug report, it is a harm.

Non-negotiable rules, enforced in code rather than in the prompt:

- The model **never generates scripture text**. Verse text is always retrieved from the
  database and rendered by the UI, never passed through the model as output.
- All Q&A is **RAG-grounded and cited**: the answer names the verses it drew on, and those
  citations are rendered as links the user can tap to read the actual source.
- If retrieval returns nothing above a similarity threshold, the app says it does not know.
  It does not fall back to the model's own memory.
- Every AI answer is **visibly labelled as machine-generated**, alongside the human
  translation, never replacing it.

### 3.3 Festivals are not astronomy

The spec says "calculate upcoming festivals based on the alignment of sun, moon and planets."
Half of that is true. Tithi, nakṣatra, yoga, karaṇa, sunrise and sunset are pure astronomy and
`sweph` gives them to arcsecond accuracy offline.

**Festival dates are convention, not computation.** Whether Ekādaśī is observed on a given day
differs between Smārta and Vaiṣṇava tradition; Amānta and Pūrṇimānta month reckoning shift a
festival by a fortnight between regions; Diwali, Janmāṣṭamī and Mahāśivarātri each have their
own rules about which tithi must be current at which time of day. Two accurate panchangs
legitimately disagree.

So festivals are a **rule engine layered on top of the astronomy**, with an explicit
tradition/region setting, and the app must show *which* convention produced a date.
Budget for this separately — it is more work than the ephemeris integration itself.

### 3.4 Swiss Ephemeris licensing — a decision, not a detail

Swiss Ephemeris is dual-licensed: **AGPL-3.0, or a paid commercial licence** (order of a few
hundred CHF). AGPL on a mobile app is workable only if we open-source the app. If this is ever
a closed-source or paid app, the commercial licence must be bought.

*Decision needed from you before Phase 3.* The alternative is writing our own Moshier-based
ephemeris, which is weeks of work and worse.

### 3.5 Reach: the AI excludes a large part of the audience

Gemma 4 E2B is a **2.4 GB download** needing ~3 GB RAM and 4 GB free disk, plus ~300 MB for
the embedder. A large share of the likely Indian Android install base will fail that gate
(playbook §5). Cold load is ~62 s per process start. NPU acceleration is **Qualcomm-only**.

Consequence: **the reader, the panchang and the audio must be fully functional with no model
installed.** The AI is a power feature, not the floor. Concretely — the app is a temple; the
AI is the electric lighting. It must still work by lamplight.

### 3.6 Platform details that bite late

- **iOS share extensions run in a ~120 MB memory jail.** Never run AI — or even PDF parsing —
  inside the extension. The extension's only job is to copy the file into the shared App Group
  container and hand off. All processing happens in the main app.
- **iOS has no background inference.** Ingesting a 300-page PDF cannot complete while
  backgrounded; it must be resumable and survive being killed mid-way.
- **OCR of Sanskrit is materially worse than OCR of Hindi.** ML Kit's Devanagari recognizer is
  trained on modern Hindi; Sanskrit conjuncts, avagraha and vedic accent marks degrade badly.
  Scanned scripture PDFs will need user review. Digital-text PDFs are fine.
- **Never run two large models at once** (playbook §4): unload the LLM before the embedder
  batch-runs, or the OS kills the app.

### 3.7 Build environment

This container has **no Flutter SDK** and cannot reach huggingface.co. Code can be written
here, but it cannot be compiled or run. We need either CI (GitHub Actions with Flutter) or
your local machine for every build. **Recommend setting up CI as the first commit of Phase 1**,
so nothing is merged unverified.

---

## 4. Architecture

Directly reusing the attached playbook's hard-won patterns — singleton service, serialised
queue, capability gate, download manager, cache-invalidation trap, runaway guard. That
document is worth more than any design I could write from scratch; it is measured, not guessed.

```
┌─────────────────────────────────────────────────────────────────┐
│  UI (Flutter, Material 3)                                       │
│  Reader · Library · Ask · Panchang · Settings                   │
└─────────────────────────────────────────────────────────────────┘
        │              │              │             │
┌───────▼──────┐ ┌─────▼──────┐ ┌─────▼──────┐ ┌────▼─────────┐
│ CorpusRepo   │ │ IngestSvc  │ │ AiService  │ │ PanchangSvc  │
│ (drift/      │ │ share →    │ │ singleton, │ │ sweph FFI    │
│  SQLite)     │ │ extract →  │ │ serialised │ │ + convention │
│ seed pack +  │ │ chunk →    │ │ queue      │ │   rule engine│
│ downloaded   │ │ embed      │ │            │ │              │
│ packs        │ │            │ │            │ │              │
└──────┬───────┘ └─────┬──────┘ └─────┬──────┘ └──────────────┘
       │               │              │
       └───────┬───────┘        ┌─────┴──────────────┐
               │                │ Gemma 4 E2B-it     │
       ┌───────▼────────┐       │ (LiteRT-LM)        │
       │ VectorStore    │◄──────┤ EmbeddingGemma/    │
       │ ObjectBox HNSW │       │ Gecko (.tflite)    │
       └────────────────┘       └────────────────────┘
               │
       ┌───────▼────────────────────────────────────┐
       │ ModelManager + PackManager                 │
       │ shared download queue, capability gate,    │
       │ Wi-Fi only, resumable, SHA-256 verified    │
       └────────────────────────────────────────────┘
```

**Key decision — one download system, two kinds of payload.** Model weights and content packs
use the same queue, the same capability gate, the same hosting contract (playbook §4.2:
honest `Content-Length`, `Range`, strong `ETag`, `HEAD`, no auth, never delete a published
file, publish a `.sha256`). Content packs are far smaller and far more likely to change, so
they additionally carry a version and a manifest.

**Vector store:** ObjectBox 5.3.2 (stable HNSW vector search) over `sqlite_vec` 0.1.7-**alpha**.
Alpha is not acceptable for the store that holds the user's imported documents.

---

## 5. Content packaging (bundled seed + downloadable packs)

| Tier | Contents | Size (est.) | Delivery |
|---|---|---|---|
| **Seed** | 1–2 complete, licence-clean works (proposal: Bhagavad Gītā, 700 verses, Sanskrit + transliteration + one public-domain translation) + panchang needs nothing | ~2–4 MB text | **Bundled in the app.** Useful on first launch, offline, no download, no AI |
| **Text packs** | Per-scripture: verses, transliterations, translations per language | 1–30 MB each | Downloadable, versioned manifest |
| **Audio packs** | Pre-rendered Vāgdhenu chant, per scripture, Opus ~24–32 kbps | ~50–150 MB per major work (est.) | Downloadable, Wi-Fi default, per-chapter granularity |
| **AI models** | Gemma 4 E2B-it (2.4 GB), embedder (~110–300 MB) | 2.6 GB total | Downloadable, behind capability gate |

Users pick what they want. Someone who only wants the Gītā and the panchang installs ~4 MB.

Ephemeris data: `sweph` can use the built-in Moshier ephemeris (no data files, accuracy far
beyond what tithi calculation needs) — so **no ephemeris download is required**. Optional
higher-precision SE files can be a pack later if we ever need them.

---

## 6. Phased roadmap

Ordering principle, per your instruction: **the AI spine comes first**, because ingestion,
search, translation and Q&A all hang off it, and retrofitting an inference runtime into a
finished app is far more expensive than building on it. The constraint from §3.5 stands
alongside it: every phase must remain fully usable with no model installed.

All effort figures are **rough estimates** for one experienced Flutter developer.

### Phase 1 — AI spine + document ingestion  ·  *the shippable core*
> **This phase alone is a useful product**, because its content comes from the user.

- Flutter scaffold, Android + iOS, CI that actually builds both (§3.7)
- `AiService` singleton: serialised queue, one model per process, warm at launch, unload on
  memory pressure, `ValueNotifier` status — straight from the playbook
- `FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()])`, generic
  `gemma-4-E2B-it.litertlm`, backend by SoC, the create-before-activate cache trap
- Device capability gate **before** any download prompt; every refusal gives an actionable reason
- Download manager: one transfer at a time, resumable, Wi-Fi default, SHA-256
- Embeddings via `flutter_gemma_embeddings` (start with Gecko for speed; measure both)
- **Share-to-app**: Android intent filters + iOS share extension (thin — copy only, §3.6)
- PDF text extraction, OCR fallback, resumable chunked ingestion with visible progress
- Chunk → embed → ObjectBox HNSW; **Ask** screen: retrieve → cite → grounded answer, streamed
- Output hygiene: runaway guard, thinking splitter, output cleaner, script verifier
- Grounding rules of §3.2 enforced in code, with unit tests
- Bundled seed pack (Gītā) so the app is useful before any download
- **In parallel from day 1: corpus licensing and sourcing work** (§3.1)

*Estimate: 6–9 weeks.* Risk: low. Every dependency is verified and the playbook de-risks the hard parts.

### Phase 2 — Scripture reader + content packs
- drift/SQLite schema: Scriptures / Chapters / Verses / Translations / Packs
- Reader UI: Sanskrit with per-verse translation toggle, script and font-size settings, bookmarks
- **Devanagari → Kannada transliteration** — this is deterministic rule-based code
  (Devanagari→SLP1→Kannada), *not* ML. Portable to Dart from upstream `prep_text.py`, and
  unit-testable against known verses. Needed for audio alignment and useful on its own
- **Meter (vṛtta) detection** — algorithmic from syllable weights; ~80% of verses are Anuṣṭubh
  and fall out easily, the rest need a gaṇa matcher. Moderate
- Pack manager UI: browse, install, update, delete content packs
- Wire the AI to the corpus: per-verse "explain this", translation into languages ML Kit lacks

*Estimate: 5–7 weeks engineering.* Risk: **low technically, high on content availability** (§3.1).

### Phase 3 — Panchang & astronomy
- `sweph` integration, Moshier ephemeris, location (GPS + manual city)
- Tithi, nakṣatra, yoga, karaṇa, vāra, sunrise/sunset/moonrise, rāhu kāla — **high confidence**
- Month/year reckoning with an explicit **Amānta / Pūrṇimānta** setting
- **Festival rule engine** with a tradition/region selector, showing which convention gave the
  date (§3.3) — the expensive half of this phase
- Panchang UI + `flutter_local_notifications` for muhūrta reminders
- **Blocker to resolve first: Swiss Ephemeris licence (§3.4)**

*Estimate: 4 weeks for the astronomy, 4–6 more for festival rules and validation against
published panchangs.* Risk: low for math, medium for conventions.

### Phase 4 — Chant audio (tiered, honest)
- **Tier A — pre-rendered Vāgdhenu audio packs.** The recommendation. Render offline on GPU,
  ship as content packs, phone plays files with verse-synchronised highlighting. Gives the
  MOS 4.6 quality immediately, zero runtime cost, zero cloud. *3–4 weeks, mostly pipeline
  and player work.*
- **Tier B — a light on-device TTS for arbitrary text** (`sherpa_onnx` 1.13.8 runs
  VITS/Matcha/Piper on phones). No Sanskrit chant voice exists off the shelf; we would need to
  train one. Covers user-imported text the packs don't include. *Optional, research-flavoured.*
- **Tier C — Vāgdhenu on-device.** Per §2: export, distil, quantize, validate by ear. Track it,
  do not schedule it, and never put it on the critical path.

### Phase 5 — Depth
Cross-scripture semantic search, conversation memory, verse-of-the-day, practice tracking,
widgets, per-user reading plans.

---

## 7. Open decisions for you

1. **Swiss Ephemeris licence** — AGPL (app must be open source) or buy the commercial licence?
   Blocks Phase 3.
2. **Which scripture is the bundled seed pack?** Proposal: Bhagavad Gītā. Needs a
   licence-clean translation chosen and verified.
3. **Where are packs and models hosted?** Needs to meet the playbook §4.2 contract. HuggingFace
   works for the Gemma weights but serves weak ETags (so resume is unsafe there — mark it
   non-pausable and offer a mirror).
4. **Which languages ship first** for translations, and which are AI-only (§3.5 route logic)?
5. **Open source or commercial?** Determines (1), and determines whether SEA-LION-class
   non-commercial models are even an option.

---

## 8. What this document deliberately does not claim

- No number here was measured on this project's hardware. The performance figures are the
  playbook's, from a Pixel 10 Pro XL and iPhones — **no Snapdragon device was ever measured**,
  and Snapdragon is most of the Android market and the only NPU path.
- Effort estimates are estimates. The corpus work in §3.1 is the one I would trust least,
  because it depends on other people's licences.
- Nothing in this repo has been compiled (§3.7).
