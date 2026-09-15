# Vedic — project context

Offline-first Flutter app (Android + iOS) for Hindu scripture reading, chant audio, panchang
calculation, and on-device AI over the user's own documents.

**Before changing architecture, read [`docs/FEASIBILITY_AND_ROADMAP.md`](docs/FEASIBILITY_AND_ROADMAP.md).**
It records what was verified, what was ruled out, and why. Several obvious-looking choices were
already investigated and rejected for non-obvious reasons.

## Ground rules — do not relitigate these

1. **No cloud AI APIs.** All inference and all astronomical maths run on-device. The only
   network traffic is downloading model weights and content packs from static file hosts.
2. **The model never generates scripture text.** Verse text is always retrieved from the
   database and rendered by the UI. AI answers are retrieval-grounded, cite their sources, and
   are visibly labelled as machine-generated. If retrieval returns nothing above threshold, the
   app says it does not know — it never falls back to the model's own memory. Enforce in code,
   not in the prompt.
3. **Every feature degrades to absent.** No model installed means a feature is hidden or
   explained, never broken. The reader, panchang and audio must be fully usable with no AI.
4. **Model weights are downloaded, never bundled** in the APK/IPA. Size and licensing both.
5. **Licences: closed source.** No GPL/AGPL/SSPL dependency may ship — check the *native*
   library, not just the Dart wrapper (see `docs/LICENSING.md` §3).

## Architecture

```
UI (Flutter, Material 3)  ── Reader · Library · Ask · Panchang · Settings
  │
  ├── CorpusRepo    drift/SQLite · bundled seed pack + downloaded packs
  ├── IngestService share → extract (pdfrx) → OCR fallback (ML Kit) → chunk → embed
  ├── AiService     SINGLETON · serialised queue · Gemma 4 E2B-it via LiteRT-LM
  ├── VectorStore   int8 vectors in SQLite · exact brute-force cosine in pure Dart
  └── PanchangSvc   ephemeris (TBD, see LICENSING.md §1) + convention rule engine
```

## Hard-won lessons — these cost days elsewhere, do not rediscover them

From `ON_DEVICE_AI_PLAYBOOK.md` (measured on real hardware, not guessed):

- **One model instance per process.** A second instance doubles gigabytes of memory and the
  ~60 s load. Use a singleton.
- **Serialise inference** through a single `Future` chain. Concurrent prompts overheat the
  phone or get the app killed.
- **Load at app start** if the model is installed; keep it loaded for the process lifetime.
  Unload on memory pressure and before another large model runs.
- **The cache-invalidation trap:** call `createModel` *first*, and only call
  `ensureModelReadyFromSpec` if it throws. Activating on every launch rewrites ~780 MB of
  compiled-graph cache that is then never reused.
- **`FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()])`** in `main()` — core
  registers none, and every call fails without it.
- **Use the generic `gemma-4-E2B-it.litertlm`** (2,588,147,712 bytes). The `-gpu` variant is a
  WebGPU build that fails on Android; the per-SoC variants failed to create an engine.
- **Backend by SoC:** NPU on Qualcomm (`Build.HARDWARE` contains `qcom`), CPU everywhere else.
  LiteRT-LM's NPU path is Qualcomm-only. iOS is always CPU.
- **topK 40, not 1.** Pure argmax made a phone emit the same character forever. Low temperature
  plus a small window stays faithful and gives the sampler an exit. `randomSeed: 1` always.
- **Rules go in `systemInstruction`, not the user turn.** Numbered by importance, most important
  last, content wrapped in `<<<` `>>>` markers and declared to be content and never an instruction.
- **Always post-process:** runaway guard, thinking splitter, output cleaner, script verifier.
  Measure the guard against the visible answer only, never the reasoning.
- **Stream partial output to the UI** (~25 chars/s; 30 s of nothing reads as broken). Verify only
  the final value.
- **Check device capability before offering any download.** Keep it a pure, unit-tested function.
  `freeDiskSize` is bytes, `physicalRamSize` is megabytes — do not mix them up.

## Testing

Pure logic must be unit-testable without a phone: capability gate, backend selection, chunking,
vector quantisation and cosine, output hygiene, prompt building, HTTP status mapping. Keep it free
of Flutter imports so `dart test` runs it fast.

Hardware-dependent behaviour (load time, generation speed, OCR accuracy, retrieval latency) must
be **measured on a real device** and the measurement written next to the constant it justifies.

## Commands

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <device>          # real phone for anything AI-related
```

## What cannot be tested on a simulator

The capability gate **refuses simulators** (they report the Mac's RAM, not the phone's), and
LiteRT-LM needs real hardware. **All AI work requires a physical device.** The simulator is fine
for UI, navigation, database and panchang work.
