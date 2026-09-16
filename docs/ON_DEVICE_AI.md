# On-device AI

The assistant runs on the phone. No verse, question or translation leaves the
device, and the app works fully without it: everything here is an extra that
the reader switches on.

## The model

| | |
| --- | --- |
| Model | Gemma 4 E2B IT, LiteRT-LM build |
| File | `gemma-4-E2B-it.litertlm`, 2.4 GB |
| Source | `litert-community/gemma-4-E2B-it-litert-lm` on Hugging Face, no token |
| Mirror | `https://batiyao.com/models/` — same file, same 2,588,147,712 bytes |
| Base URLs | `--dart-define=ASSISTANT_MODEL_BASE=…` and `ASSISTANT_MODEL_FALLBACK_BASE=…` |
| Engine | `flutter_gemma` with `LiteRtLmEngine` |
| Backend | NPU on Snapdragon, CPU elsewhere (`lib/core/backend.dart`) |

`lib/core/model_catalog.dart` holds the requirement: 3 GB RAM and 4 GB free
disk, the 4 GB covering the file plus the ~780 MB compiled-graph cache.
`checkCapability` (`lib/core/capability.dart`) refuses simulators and phones
below those numbers, and the setup screen says which check failed rather than
offering a download that cannot work.

## Where it is downloaded from

Two hosts, both serving the identical file, verified byte-for-byte:

| | Hugging Face | Mirror |
| --- | --- | --- |
| Cost to us | nothing | ours to run |
| `ETag` | weak, CDN-issued | strong |
| Resumable | **no** | yes |

Hugging Face is the default and stays the default. The mirror exists so a
rename, a rate limit or a licence gate on their side is an inconvenience rather
than the end of the feature — and it is also **offered outright** in Settings,
because Hugging Face is far away from some people and a 2.4 GB download that
crawls is the kind of thing somebody gives up on. Whoever is watching the bar
knows more about their connection than one speed test would.

Hugging Face is marked unresumable deliberately: it serves weak ETags, and a
resumed transfer there can produce a file that is corrupt in a way only the
engine notices, an hour later. The mirror must keep strong ETags and `Range`
support for the resumable route to stay honest.

Both hosts serve `gemma-4-E2B-it.litertlm`, and the installed model's identity
is its file name — so switching hosts must never change the file name, or the
app would treat the same model as a new one and download it again.

### What the download does

1. **A reachability check first** (`HostProbe`, one `HEAD`). Without it a moved
   file shows up as a bar that climbs for a while and then dies, which tells
   the reader nothing and invites them to retry something that cannot work.
   401 and 403 are classed as *missing* rather than *unavailable*: a model that
   used to be public and now needs a token is, from the app's side, gone.
2. **A stall watchdog** — 90 s with no movement cancels the transfer and says
   so. Re-armed only when the percentage actually rises, so a transfer that
   reports the same number forever is still caught.
3. **A cancel control**, because 2.4 GB is a decision people change their mind
   about halfway through.
4. **Validation on completion** (`validateModel`) before the file is used.
   Trust the file, not the fact that the stream ended.

## Getting the model onto the phone

Two routes, both started by the reader, never automatically:

1. **Download** — `Assistant.install()`, as above. A one-time 2.4 GB download
   over Wi-Fi.
2. **Adopt a file already on the phone** — `Assistant.adoptModelFile(path)`
   registers an existing `.litertlm` **in place**: no copy, no second 2.4 GB.
   This is the route for a model another app on the same phone has already
   downloaded.

   Registering in place means the file belongs to whoever put it there. If that
   app deletes or moves it, the assistant stops working until it is installed
   again, and the app has to say so rather than fail silently.

   **Open:** how the other app hands over the path. An app's own model lives
   in its private `applicationSupport` directory, which no other app can read —
   so an app that has already downloaded this file cannot simply share it.
   Genuine reuse needs that app to export the file (a `FileProvider` URI, or a
   copy into shared storage) and Sadhana to be handed a real filesystem path,
   because `fromFile` takes a path, not a `content://` URI. The UI text is in
   place; the picker is not wired until that handover is settled.

   What *is* settled is that both apps fetch the identical file, by the same
   name, from the same two hosts — so nothing is downloaded twice
   unnecessarily within an app, and a shared file would drop straight in.

`Assistant.remove()` deletes the model and gives the storage back. Translations
already made stay: they live outside the model.

## Running it

`lib/ai/assistant.dart` is the whole surface:

- one model per process, kept loaded (the first load takes about a minute);
- one request at a time, queued — concurrent inference overheats the phone or
  gets the app killed;
- `detectRunaway` cuts a repeating generation short, and `cleanOutput` strips
  the model's framing before anything is shown;
- `topK: 40`, never pure argmax, which made a phone repeat one character
  forever.

State is a `ValueNotifier<AssistantState>`: `unknown`, `unsupported`,
`notInstalled`, `downloading(percent)`, `loading`, `ready`, `working`,
`failed`. The setup screen (`lib/ui/ai/assistant_screen.dart`) renders exactly
those.

## Answering as it is written

`Assistant.stream` returns a `Stream<AssistantChunk>` at once and starts the
work when its turn in the queue comes, so a caller can show "waiting" without
holding a future that looks identical to a stalled one. Each chunk carries the
**whole** answer so far, not a delta.

Reasoning is on by default for translation. Two things follow from that, and
both are easy to get wrong:

- **The token ceiling has to cover both.** Reasoning and answer come out of
  the same budget, so `translationTokenCap` triples when thinking is on
  (12× the verse, floor 768) rather than nudging up.
- **The runaway guard is measured against the answer only.** Reasoning
  legitimately repeats itself; a guard run over the raw stream cuts the model
  off mid-deliberation, before it has written a word of the translation.

`lib/core/thinking.dart` splits the two. The markers are Gemma 4's
`<|channel>thought` … `<channel|>`, taken from the runtime's own filter rather
than guessed, and the splitter runs even when thinking was switched off: the
runtime only filters models it knows can think, and Gemma 4 is not on that
list when the flag is off. It also handles a thought that never closed because
generation hit its ceiling part-way through one — without that, the whole run
reads as reasoning and nothing is shown.

While there is no answer yet the reader sees the reasoning instead. Honest,
and better than watching it think in silence.

## Translation

`lib/ai/translation.dart`. The model is given one verse **in its context** and
returns prose in one language. It never writes scripture:

- the rules live in the system instruction, ordered least to most important;
- everything from the pack is fenced between `<<<` and `>>>`, and any such
  marker inside the text is broken up, so content cannot close its own fence
  or issue instructions;
- the answer is checked before it is stored — right script for the language,
  not empty, not just the verse echoed back. A rejected answer is discarded and
  the reader is told.

### The context

`verseContext` (`lib/ai/verse_context.dart`) gathers what the installed pack
already knows: the work and chapter, the speaker line, the transliteration,
the verse before this one, and **published translations of the same verse in
other languages**. That last one does most of the work — rendering Hindi from
the Sanskrit plus a published English translation is a far better bet, on a 2B
model, than the Sanskrit alone.

A machine translation is never included. One phone's guess is not a source,
and translating from it would launder a guess into a second language.

The target language is named twice, with its endonym and its script —
"Hindi (हिन्दी), in the Devanagari script" — and stated again at the end of
the prompt, because on a model this size the instruction nearest the end is
the one that gets followed. Asked for a language by its English name alone,
these models answer in a neighbour that shares the script.

Results go to `local_translations` in the store's registry database
(`lib/packs/pack_store.dart`), keyed by pack, work, ref and language, with the
model that wrote them. They are kept out of the pack database, which is
replaced whole on every pack update and holds published text only.

`ScriptureRepository` merges them **after** the pack's own translations, so a
published translation is never shadowed by a machine one, and every one of them
is shown with the "Machine translation" label the reader already sees for
machine-translated pack content.

## Next

RAG for question answering, over the `chunks` and `embeddings` tables the pack
database already carries (docs/PACK_CONTENT_JSON.md §7).
