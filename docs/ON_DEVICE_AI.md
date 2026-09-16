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

## What the model can actually do — measured

Gemma 4 E2B, the real 2.4 GB file, on an iOS simulator, 2026-09-16. Weights,
prompt and seed decide the words, so **quality here is the quality anywhere**.
Speed is not: the simulator runs on the Mac's CPU.

Bhagavad Gītā 2.1, with full context supplied (1.47 and its published English
translation, the speaker line, the transliteration):

| | |
| --- | --- |
| English, 23 s | "That, likewise, the most compassionate and tearful eye of the charioteer, this poisonous sentence, he said Madhusūdana." |
| Hindi, 22 s | "मधुसूदन ने कहा कि वह तथा दया से भरा हुआ, आँसुओं से भरा हुआ, उल्लू की आँख वाला, विषदंत वाला वाक्य है।" |

The verse says: *to him, thus overcome by pity, his eyes brimming with tears,
despondent, Madhusūdana spoke these words.*

Both readings make the same mistake — विषीदन्तम्, "despondent", read as विष,
"poison" — and both invent what is not there: a charioteer, an owl's eye. The
error is systematic rather than unlucky: the model does not parse the word,
and reaches for the one it knows.

### Which language to translate out of

Bhagavad Gītā 1.2, same model, same day, against the pack's own rendering.
`integration_test/translation_quality_test.dart` reruns this anywhere.

| From → into | Time | What came back |
| --- | --- | --- |
| **English → Hindi** | 20 s | संजय ने कहा: हे राजा, पांडु के पुत्रों द्वारा सैन्य गठन में व्यवस्थित सेना को देखकर, राजा दुर्योधन अपने गुरु के पास गया और निम्नलिखित शब्द बोले। |
| **Hindi → English** | 18 s | "Sanjay said that at that time, King Duryodhana, seeing the Pandavas' army was strategically arranged, went to Dronacharya and said this *promise*." |
| **Sanskrit → English** | 23 s | "Having seen the Pandava army formed, Duryodhana then, meeting the teacher, the king spoke his words." |
| **Sanskrit → Hindi** | 16 s | जब उसने **पांडवानीकं** को व्यूढ रूप में देखा, तब दुर्योधन ने आचार्य से मिलकर वचन कहे। |

English into Hindi is the best of the four and reads naturally. Hindi into
English is close behind, with one word off: वचन becomes "promise" rather than
"words", a meaning it can carry but not here. The two out of Sanskrit are the
weakest — the English is stiff but right, and the Hindi gives up on
पाण्डवानीकं and copies it across untranslated, which is the same kind of
failure as 2.1 in a milder form.

So `chooseSource` prefers, in order:

1. **Hindi**, for a target written in Devanagari and steeped in the same
   vocabulary, where a compound often survives almost unchanged.
2. **English**, otherwise, because it is what packs most often carry.
3. **The Sanskrit**, last.

Only the pack's own renderings are eligible. A translation this phone made is
not: it was never vetted, and translating from it would compound one guess
into another. The stored row records the route (`…litertlm via en`) so
anything that came the long way round can be found and redone later.

Caveats worth keeping in view: the ordering between Hindi and English as
*sources* rests on one verse in each direction, and the preference for Hindi
into other Indic languages is reasoning about shared vocabulary rather than a
measurement — no Marathi or Gujarati target has been tested. And a pivot
inherits its source's mistakes: "promise" would travel onward intact.

### What follows

The pipeline is sound and **this model's Sanskrit is not**. What follows
from that:

- Where a published translation exists in *another* language, translating from
  that is a different and much easier task — English to Hindi is work this
  model does well. The pivot is not a nicety; on this evidence it is most of
  the quality.
- Where nothing is published, Sanskrit to anything is unreliable, and calling
  the result a translation of scripture overstates it.
- The guards cannot help here. An answer this wrong is fluent, in the right
  script, and not an echo — every check passes it. Only a better source or a
  better model fixes it.

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
**the verse before this one**, and any published translations of either verse.

Everything in it is optional, and that is the point: most of a work is
untranslated while it is being worked through, so the context has to be
useful when it is nothing but Sanskrit. The transliteration is always there,
because the app can produce it mechanically.

**Continuity.** The previous verse is fetched with `verseBefore`, which walks
by ordinal across the whole work rather than within the open chapter — a
dialogue does not stop at a chapter end, and the first verse of one is usually
an answer to the last verse of the one before. It carries its own speaker
line, so the model can see whether the voice has changed.

When that verse has no translation, the prompt says so outright — otherwise
the silence reads as "nothing came before this verse".

A machine translation is never included, for this verse or the one before.
One phone's guess is not a source, and translating from it would launder a
guess into a second language.

References such as "1.47" are the one piece written into the prompt's own
prose rather than fenced, so they are cut back to what a reference can be: the
first word, letters and digits and punctuation only, sixteen characters.

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
