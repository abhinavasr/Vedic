#!/usr/bin/env bash
# Generate the Flutter project and apply this project's platform configuration.
# Idempotent — safe to re-run. Run from the repository root.
#
# Deliberately thin: `flutter create` owns the ios/ and android/ scaffolding, because
# hand-written platform directories rot badly across Flutter upgrades. This only applies
# the settings that are specific to this project, and each edit is guarded so re-running
# is a no-op.

set -euo pipefail

FLUTTER_VERSION="3.47.4"
ORG="com.abhinavasr"
APP_NAME="vedic"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
skip() { printf '    (already applied) %s\n' "$*"; }

# --- preflight ---------------------------------------------------------------
command -v flutter >/dev/null || { warn "flutter not found on PATH. See docs/DEVELOPMENT.md"; exit 1; }

have="$(flutter --version 2>/dev/null | sed -n '1s/.*Flutter \([0-9.]*\).*/\1/p')"
if [ "$have" != "$FLUTTER_VERSION" ]; then
  warn "Flutter $have found, this project pins $FLUTTER_VERSION."
  warn "Continuing, but analyzer and lockfile differences are on you."
fi

# --- 1. generate the project -------------------------------------------------
if [ ! -f "$ROOT/lib/main.dart" ]; then
  info "Generating Flutter project (org=$ORG, name=$APP_NAME)"
  flutter create --org "$ORG" --project-name "$APP_NAME" \
    --platforms=android,ios --empty .
else
  skip "Flutter project exists"
fi

# --- 2. Android --------------------------------------------------------------
GRADLE="$ROOT/android/app/build.gradle.kts"
[ -f "$GRADLE" ] || GRADLE="$ROOT/android/app/build.gradle"

if [ -f "$GRADLE" ]; then
  if grep -q "libLiteRtWebGpuAccelerator" "$GRADLE"; then
    skip "Android jniLibs excludes"
  else
    info "Android: minSdk 31 + WebGPU jniLibs excludes -> $(basename "$GRADLE")"
    warn "Applying a text edit to $GRADLE — review the diff before committing."
    python3 - "$GRADLE" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()

# minSdk: LiteRT-LM needs Android 12 (SDK 31); flutter.minSdkVersion is lower.
s = re.sub(r'minSdk\s*=?\s*(flutter\.minSdkVersion|\d+)', 'minSdk = 31', s, count=1)

block = '''
    // LiteRT-LM ships every accelerator backend. The WebGPU ones cannot run on Android
    // and only add size. Do NOT exclude libQnn*.so — that is the Qualcomm NPU path
    // (~54 MB uncompressed, +18.7 MB on the arm64 Play download), and Snapdragon is
    // most of the Android market as well as the only NPU path LiteRT-LM supports.
    packaging {
        jniLibs {
            excludes += "**/libLiteRtTopKWebGpuSampler.so"
            excludes += "**/libLiteRtWebGpuAccelerator.so"
        }
    }
'''
# Insert just before the closing brace of the android { } block.
m = re.search(r'\nandroid\s*\{', s)
if m:
    depth, i = 0, m.end() - 1
    while i < len(s):
        if s[i] == '{': depth += 1
        elif s[i] == '}':
            depth -= 1
            if depth == 0: break
        i += 1
    s = s[:i] + block + s[i:]
    open(p, 'w', encoding='utf-8').write(s)
    print("    android block patched")
else:
    sys.exit("    could not locate the android { } block — apply manually")
PY
  fi
else
  warn "No android/app/build.gradle[.kts] found — skipping Android config"
fi

# --- 3. iOS ------------------------------------------------------------------
# Flutter 3.47 generates Swift Package Manager projects, so there is usually no Podfile.
# The Xcode project's build settings are the source of truth for the deployment target.
PBXPROJ="$ROOT/ios/Runner.xcodeproj/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
  if grep -q "IPHONEOS_DEPLOYMENT_TARGET = 1[0-5]\." "$PBXPROJ"; then
    info "iOS: Xcode project deployment target 16.0 (required by LiteRT-LM)"
    sed -i.bak 's/IPHONEOS_DEPLOYMENT_TARGET = 1[0-5]\.[0-9]*;/IPHONEOS_DEPLOYMENT_TARGET = 16.0;/g' "$PBXPROJ"
    rm -f "$PBXPROJ.bak"
  else
    skip "iOS Xcode project deployment target"
  fi
fi

PODFILE="$ROOT/ios/Podfile"
if [ -f "$PODFILE" ]; then
  if grep -q "^platform :ios, '16.0'" "$PODFILE"; then
    skip "iOS deployment target"
  else
    info "iOS: deployment target 16.0 (required by LiteRT-LM)"
    if grep -q "^# *platform :ios" "$PODFILE"; then
      sed -i.bak "s/^# *platform :ios.*/platform :ios, '16.0'/" "$PODFILE"
    else
      sed -i.bak "s/^platform :ios.*/platform :ios, '16.0'/" "$PODFILE"
    fi
    rm -f "$PODFILE.bak"
  fi
elif [ ! -f "$PBXPROJ" ]; then
  warn "No ios/ project found — skipping iOS config"
fi

XCCONFIG="$ROOT/ios/Flutter/Release.xcconfig"
if [ -f "$XCCONFIG" ]; then
  if grep -q "STRIP_STYLE" "$XCCONFIG"; then
    skip "iOS STRIP_STYLE"
  else
    info "iOS: STRIP_STYLE = non-global (keeps FFI symbols in release builds)"
    printf '\n// FFI plugins using DynamicLibrary.process() lose their symbols otherwise.\n// Debug builds prove nothing about release here.\nSTRIP_STYLE = non-global\n' >> "$XCCONFIG"
  fi
fi

# --- 4. deps -----------------------------------------------------------------
info "flutter pub get"
flutter pub get

# --- 5. what this script cannot do ------------------------------------------
cat <<'MANUAL'

------------------------------------------------------------------------------
Bootstrap complete. Three things still need doing by hand:

  1. iOS share extension — must be added in Xcode (File > New > Target >
     Share Extension), together with an App Group shared between Runner and the
     extension. Keep the extension THIN: copy the shared file into the App Group
     container and hand off. It runs in a ~120 MB memory jail, so no PDF parsing
     and no inference inside it.

  2. Android intent filters — add ACTION_SEND / ACTION_SEND_MULTIPLE for
     application/pdf and text/plain to android/app/src/main/AndroidManifest.xml.

  3. Signing — set your Apple team in Xcode, and an Android keystore for release.

Review `git diff` before committing: steps 2 and 3 above edit generated files.
------------------------------------------------------------------------------
MANUAL
