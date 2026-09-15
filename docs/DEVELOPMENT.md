# Development setup (macOS)

**Develop on the Mac.** This is not a preference — **Xcode only runs on macOS**, so the iOS half
of the app cannot be built anywhere else. A Linux container can compile and test the Dart and
Android sides, but it can never produce an iOS build.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Flutter | **3.47.4 stable** (Dart 3.13.3) | Pin it — `flutter --version` should match |
| Xcode | 15+ with Command Line Tools | `sudo xcode-select --install` |
| CocoaPods | latest | `sudo gem install cocoapods` |
| Android Studio | latest, with SDK 35 + NDK | For the Android toolchain and emulator |
| JDK | 17 | Bundled with Android Studio is fine |

```sh
brew install --cask flutter android-studio
flutter doctor        # resolve everything it flags before continuing
```

## First-time setup

```sh
git clone https://github.com/abhinavasr/Vedic.git
cd Vedic
./scripts/bootstrap.sh    # generates the Flutter project and applies platform config
flutter pub get
flutter analyze && flutter test
```

`bootstrap.sh` is idempotent — safe to re-run. It is deliberately thin: it lets
`flutter create` generate the `ios/` and `android/` scaffolding (hand-written platform
directories rot badly across Flutter upgrades) and then applies only the project-specific
settings listed in §"Platform configuration" below.

## You need a physical phone

The simulator is fine for UI, navigation, database and panchang work. It is **useless for
anything AI-related**:

- The device capability gate **refuses simulators by design** — an iOS Simulator reports the
  Mac's RAM and disk, so it would happily claim a 2 GB phone can run a 2.4 GB model.
- LiteRT-LM needs real hardware; the accelerator backends do not exist on a simulator.
- Every performance figure that matters (cold load, generation speed, OCR accuracy, retrieval
  latency) is meaningless off-device.

**Recommended test devices:** one Qualcomm/Snapdragon Android phone and one iPhone. Snapdragon
matters disproportionately — it is most of the Android market and the **only** NPU path
LiteRT-LM supports, and the playbook this project inherits **never measured a Snapdragon
device**. Assume nothing there until it is measured.

A phone near the capability floor (3–4 GB RAM) is more valuable for testing than a flagship —
the flagship will never show you the failures your users hit.

## Platform configuration applied by bootstrap

**iOS** (`ios/Podfile`, `ios/Runner.xcodeproj`)
- Deployment target **16.0** minimum (LiteRT-LM requires it)
- Share extension target + App Group, so shared PDFs land in a container the app can read
- Release: `STRIP_STYLE = non-global` — FFI plugins using `DynamicLibrary.process()` lose their
  symbols otherwise, and **debug builds prove nothing about release**

**Android** (`android/app/build.gradle.kts`)
- `minSdk 31` (Android 12 — the capability floor for the LLM)
- Exclude the WebGPU accelerators, which cannot run on Android:
  ```kotlin
  packaging { jniLibs {
      excludes += "**/libLiteRtTopKWebGpuSampler.so"
      excludes += "**/libLiteRtWebGpuAccelerator.so"
      // Do NOT exclude libQnn*.so — that is the Qualcomm NPU path (~54 MB uncompressed,
      // +18.7 MB on the arm64 Play download). Snapdragon is most of the market.
  } }
  ```
- Intent filters for `application/pdf` and `text/plain` on `ACTION_SEND` / `ACTION_SEND_MULTIPLE`

## Configuration

Model and content-pack hosts are `--dart-define`d, never hardcoded, so switching hosts is a
config change rather than a release:

```sh
flutter run \
  --dart-define=ASSISTANT_MODEL_BASE=https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main \
  --dart-define=ASSISTANT_MODEL_FALLBACK_BASE=https://<our-mirror>/models \
  --dart-define=CONTENT_PACK_BASE=https://<our-mirror>/packs
```

## Before pushing

```sh
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

CI runs the same three. Keep them green — a red CI on a project this early is just noise that
trains you to ignore it.

## Note on the AI model download

The Gemma model is **2.4 GB**. Download it once over Wi-Fi on each test device and it persists;
do not uninstall the app casually during AI work or you will re-download it. Cold load is ~62 s
per process start on a Tensor G5, so expect the first inference after every app launch to be slow
— that is the model loading, not generation.
