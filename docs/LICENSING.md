# Licensing

**Project licence: proprietary / closed source** (decided 2026-09-15). See [`LICENSE`](../LICENSE).

> **History.** AGPL-3.0 was briefly chosen and then reversed the same day. The reversal is a
> net simplification: it removes a hard blocker on iOS and re-opens two better dependencies.
> One cost survives both choices — see §1.

Closed source inverts the constraint. Under AGPL the question was *"may we combine this with
proprietary code?"*; the danger was proprietary dependencies. Closed source flips it to
*"does this force us to publish source?"*; the danger is now **copyleft** dependencies.

---

## 1. The one thing that did not change: Swiss Ephemeris costs you

Swiss Ephemeris is dual-licensed: **AGPL-3.0, or a paid Professional Licence** from Astrodienst.
There is no third option and no free closed-source path.

- Under **AGPL**, it was free — but AGPL binaries cannot ship on the iOS App Store (Apple's
  terms impose restrictions that GPLv3/AGPL §10 forbids; the FSF enforced exactly this against
  VLC). Blocked a stated product requirement.
- Under **closed source**, the iOS conflict disappears entirely — but the AGPL option is now
  unavailable to us, so `sweph` requires **buying the Professional Licence**.

Either way Swiss Ephemeris is not free for this project. That is worth knowing before Phase 3
rather than during it.

### Options

| # | Option | Cost | Notes |
|---|---|---|---|
| **A** | **Buy the Swiss Ephemeris Professional Licence** | one-off fee, order of several hundred CHF — confirm current pricing with Astrodienst directly | Mature, exhaustively validated, `sweph` binding already exists on pub.dev. Lowest engineering risk |
| **B** | **Use a permissively-licensed ephemeris** | ~2–4 weeks engineering (estimate), or possibly near-zero if an existing package fits | No fee. Closed-source-safe. Fewer moving parts |

### Recommendation: evaluate B first, fall back to A without hesitation

B is attractive because **our accuracy requirement is modest**. Swiss Ephemeris is built for
professional astrology across 8,000 years with asteroids and exotic reference frames. A panchang
needs the Sun, Moon, five visible planets and the lunar nodes over roughly 1900–2100, to about a
minute of time. Published theories (VSOP87 for planets, ELP2000-82B for the Moon) give
arcsecond-class accuracy there — and since a tithi is 12° of Moon–Sun elongation and the Moon
gains ~12°/day on the Sun, **one arcsecond is about a third of a second of time**, roughly a
hundredfold more precision than a panchang needs.

**Candidate to evaluate first:** the `ephemeris` package — **MPL-2.0**, JPL DE-based, ~0.001″,
covering roughly −3000 to +3000.

MPL-2.0 is **safe for closed source**: its copyleft is *file-level*, so linking it into a
proprietary app is fine, and the only obligation is publishing modifications to the MPL-licensed
files themselves. Don't fork it — consume it as a dependency and that obligation stays trivially
satisfied.

Two caveats to clear before adopting: it is `1.0.0-rc.1`, and **the licence of its underlying
Taiyin C library is not stated on pub.dev.** Verify that native licence — §3 explains why that
gap matters more than it looks.

If either caveat fails, buy the Professional Licence and move on. The fee is small against
2–4 weeks of engineering; A is the pragmatic answer, not the embarrassing one.

**Not needed until Phase 3.** Evaluate during Phase 2 so Phase 3 starts with the answer.

---

## 2. What closed source gives back

Three dependencies rejected under AGPL are now available, and two of them are genuinely better:

- **ML Kit** — proprietary Google binary, fine now. Its **Devanagari OCR is materially better
  than Tesseract's**, and OCR quality was already the weak point for Sanskrit. A real win.
- **ObjectBox** — proprietary native core, fine now (confirm its free-tier terms cover
  commercial distribution). Available if we ever outgrow brute-force search.
- **Syncfusion** — available, but it is a *paid* licence above a revenue threshold. `pdfrx`
  (MIT, wrapping BSD-licensed PDFium) does what we need for free. No reason to pay.

---

## 3. The trap that applies under any licence: pub.dev shows the wrapper, not the native library

Most Flutter packages are thin Dart bindings around a bundled native library, and **pub.dev
displays the licence of the Dart wrapper only.** The binary that actually ships can be under
something entirely different: `objectbox`'s binding is Apache-2.0 over a proprietary core;
`google_mlkit_*` wrappers are MIT over a proprietary Google blob.

Under closed source these are no longer disqualifying — but **always check the native library
separately** anyway, because a native library under GPL or AGPL *would* force disclosure of our
source, and it would not be visible on the package page.

### Dependency review

| Dependency | Wrapper | Native | Closed-source safe | Verdict |
|---|---|---|---|---|
| `sweph` | AGPL-3.0 | AGPL-3.0 (Astrodienst) | ❌ **not without the paid licence** | **§1 decision** |
| `ephemeris` | MPL-2.0 | **Taiyin — unstated, verify** | ✅ if native checks out | Evaluate first (§1) |
| `google_mlkit_*` | MIT | Google ML Kit (proprietary) | ✅ | **Adopt** for OCR |
| `pdfrx` | MIT | PDFium (BSD-3-Clause) | ✅ | **Adopt** for PDF text |
| `syncfusion_flutter_pdf` | Syncfusion commercial | — | ✅ but **costs money** | Skip — `pdfrx` is free |
| `objectbox` | Apache-2.0 | ObjectBox Binary Licence | ✅ (confirm free-tier terms) | Optional; not needed yet (§4) |
| `flutter_gemma` / `_litertlm` / `_embeddings` | MIT | LiteRT (Apache-2.0) | ✅ | Adopt |
| `sqlite3`, `drift` | MIT | SQLite (public domain) | ✅ | Adopt |
| `receive_sharing_intent` | Apache-2.0 | — | ✅ | Adopt |
| `background_downloader` | BSD | — | ✅ | Adopt |
| `device_info_plus` | BSD-3-Clause | — | ✅ | Adopt |
| `flutter_local_notifications` | BSD-3-Clause | — | ✅ | Adopt |
| `sherpa_onnx` | Apache-2.0 | ONNX Runtime (MIT) | ✅ | Adopt if Tier B TTS happens |

**The rule for CI:** fail the build on any new dependency under **GPL, AGPL, or SSPL**, at the
wrapper *or* native level. Permissive (MIT / BSD / Apache-2.0), file-level copyleft (MPL-2.0,
consumed unmodified), and commercial-with-a-paid-licence are all fine.

### Model and content licences

| Asset | Licence | Notes |
|---|---|---|
| **Gemma 4** weights | **Apache-2.0** | Google moved Gemma 4 to Apache-2.0, away from the restrictive "Gemma Terms of Use" that governed Gemma 1–3 — no prohibited-use clause, no redistribution or commercial limits. Clean for a commercial closed-source app |
| EmbeddingGemma / Gecko | **Verify before Phase 1 ships** | Do not assume it inherited Gemma 4's Apache-2.0. If it is under Gemma Terms of Use, the prohibited-use restrictions apply to a commercial product and need reading |
| Vāgdhenu | Apache-2.0 | Clean. Runs on our own hardware at render time; only rendered audio ships |
| IndicF5 | MIT | Clean |
| BigVGAN-v2 | **Verify** (NVIDIA) | Affects the render pipeline, not the app binary |
| Scripture text & translations | **Per source, must be tracked** | The real work — and a *commercial* product narrows what is usable. Many public-domain-for-personal-use translations are not licensed for commercial redistribution. See `FEASIBILITY_AND_ROADMAP.md` §3.1 |

**Two consequences of going commercial that are easy to miss:**

1. **Model weights stay downloaded, never bundled.** Originally an app-size decision; it also
   keeps third-party weights out of the binary we distribute. Keep it that way whatever the
   size pressure.
2. **The corpus problem gets harder, not easier.** "Free to read online" is not "licensed for
   commercial redistribution." Budget more time for §3.1, and record an explicit commercial
   grant for every text that ships.

---

## 4. Consequences for the architecture

- **OCR: ML Kit** (`google_mlkit_text_recognition`). Better Devanagari accuracy than Tesseract.
  Still weak on Sanskrit conjuncts, avagraha and vedic accents — measure on real scanned pages
  in Phase 1 and label the OCR path as approximate in the UI regardless.
- **PDF text: `pdfrx`** (MIT / PDFium). Free, and Syncfusion buys us nothing here.
- **Vector store: exact brute-force cosine in pure Dart over int8 vectors in SQLite.** ObjectBox
  is now permitted but not needed. 20,000 chunks × 768 dims is ~15M multiply-accumulates per
  query — tens of milliseconds at most, **to be measured, not assumed**. int8 quantisation holds
  20k chunks in ~15 MB rather than 61 MB. Brute force is *exact*: no HNSW recall cliff, no index
  to build, tune or corrupt. Revisit only with a measurement showing it hurts.
- **An "Open source licences" screen is still required.** MIT, BSD and Apache-2.0 all require
  reproducing their notices in distributed binaries. Closed source does not exempt us.

---

## 5. Actions

- [x] Adopt proprietary licence; add `LICENSE`
- [ ] **Decide §1** (A: buy Professional Licence · B: permissive ephemeris) — **before Phase 3**
- [ ] If B: verify the Taiyin native library licence before adopting `ephemeris`
- [ ] Verify the EmbeddingGemma / Gecko weight licence — **before Phase 1 ships**
- [ ] Verify the BigVGAN-v2 licence before standing up the render pipeline
- [ ] Confirm ObjectBox free-tier terms if it is ever adopted
- [ ] Record an explicit **commercial** redistribution grant for every scripture text that ships
- [ ] CI check that fails the build on any GPL / AGPL / SSPL dependency, wrapper or native
- [ ] In-app "Open source licences" screen reproducing all required notices
