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
| Base URL | `--dart-define=ASSISTANT_MODEL_BASE=…` (docs/DEVELOPMENT.md) |
| Engine | `flutter_gemma` with `LiteRtLmEngine` |
| Backend | NPU on Snapdragon, CPU elsewhere (`lib/core/backend.dart`) |

`lib/core/model_catalog.dart` holds the requirement: 3 GB RAM and 4 GB free
disk, the 4 GB covering the file plus the ~780 MB compiled-graph cache.
`checkCapability` (`lib/core/capability.dart`) refuses simulators and phones
below those numbers, and the setup screen says which check failed rather than
offering a download that cannot work.

## Getting the model onto the phone

Two routes, both started by the reader, never automatically:

1. **Download** — `Assistant.install()` fetches the file with progress. A
   one-time 2.4 GB download over Wi-Fi.
2. **Adopt a file already on the phone** — `Assistant.adoptModelFile(path)`
   registers an existing `.litertlm` **in place**: no copy, no second 2.4 GB.
   This is the route for a model another app on the same phone has already
   downloaded.

   Registering in place means the file belongs to whoever put it there. If that
   app deletes or moves it, the assistant stops working until it is installed
   again, and the app has to say so rather than fail silently.

   **Open:** how the other app hands over the path. On Android that is a
   content URI from the system file picker or a shared-storage path the app
   publishes; either way the reader picks the file, and the app needs a real
   filesystem path to hand to `fromFile`. The UI text is in place; the picker
   is not wired until that handover is settled.

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

## Translation

`lib/ai/translation.dart`. The model is given one verse and returns prose in
one language. It never writes scripture:

- the rules live in the system instruction, ordered least to most important;
- the verse is fenced between `<<<` and `>>>`, and any such marker inside the
  text is broken up, so content cannot close its own fence or issue
  instructions;
- the answer is checked before it is stored — right script for the language,
  not empty, not just the verse echoed back. A rejected answer is discarded and
  the reader is told.

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
