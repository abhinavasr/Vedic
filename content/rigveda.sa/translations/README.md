# Translations written here

One JSON file per sūkta, named for it — `rv-1.51.json`:

```json
{ "verses": { "1.51.1": { "hi": "…", "en": "…" } } }
```

Only `hi` and `en`. **Do not put the Sanskrit in these files, in any script.**
The Devanagari comes from `../sources/` and the IAST is derived from it by
`tool/derive_iast.dart`, so a transliteration written here would be a model
retyping scripture from memory. When we did ask for one, 58 of 409 verses came
back misread — nearly always a dropped vowel length, which reads perfectly
well and is a different word. `tool/merge_translations.dart` now compares any
transliteration it is given against the Devanagari and reports what does not
reduce to the same letters.

Punctuation is not cosmetic here. The reader can listen to these, and the
speech synthesiser has nothing but the punctuation to tell it where to
breathe: a comma wherever a reader would pause, a full stop ending every
English sentence, and `।` ending every Hindi one.

`../responses/` holds what came back from Gemini before this. The two are kept
apart so the pack credits each line to whoever wrote it.

## Asking for the rest

```sh
python3 tool/translation_requests.py content/rigveda.sa --single --todo --out ~/ask
```

`--todo` leaves out every verse already translated. As of this writing that is
7,624 verses across 772 sūktas. Answers go in this folder, then:

```sh
./tool/rebuild_rigveda.sh
```

which rebuilds the whole pack from the sources and everything merged over it.
`content.json` is generated — never edit it by hand.

## What is not here

1.8, 1.9, 1.20–1.23, 1.26, 1.27 and 1.32–1.37 have no translation because they
have no source file, not because they were missed. 809 of the Saṃhitā's 1,028
sūktas are present; the other 219 have to be obtained before they can be
translated.
