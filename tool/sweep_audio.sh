#!/bin/sh
# Uploads rendered audio to the vault and deletes the local copy once it is
# safely there.
#
# Eight thousand verses is a couple of gigabytes of WAV, and none of it needs
# to stay on this machine: the pack references the vault, never a local file.
# So this runs alongside the renderer and keeps the working directory small.
#
# A file is only deleted after upload_audio.py has recorded it in
# uploads.jsonl, which it writes only once the vault has echoed back a
# SHA-256 matching the one taken before sending. The two indexes stay — they
# are what merge_audio.py turns into the pack's audio blocks, and they are
# kilobytes.
#
#   VAULT_UPLOAD_PASSWORD=... tool/sweep_audio.sh <dir> [seconds]
set -e
cd "$(dirname "$0")/.."
DIR="$1"
EVERY="${2:-300}"

while :; do
  if [ -f "$DIR/index.jsonl" ]; then
    python3 tool/upload_audio.py --dir "$DIR" >> "$DIR/upload.log" 2>&1 || true
    python3 - "$DIR" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
safe = set()
path = root / 'uploads.jsonl'
if path.exists():
    for line in path.read_text().splitlines():
        if line.strip():
            safe.add(json.loads(line)['ref'])
freed = gone = 0
for wav in root.glob('*.wav'):
    if wav.stem in safe:
        freed += wav.stat().st_size
        wav.unlink()
        gone += 1
if gone:
    print(f'swept {gone} files, {freed / 1e6:.0f} MB', flush=True)
PY
    # The vault URLs live in the repository, not in a scratch directory.
    # They are the only record of where 8,000 recordings went: lose them and
    # every one has to be rendered and uploaded again, while the audio
    # itself sits in the vault unreferenced. A megabyte of JSONL is a cheap
    # price for never being in that position.
    mkdir -p content/rigveda.sa/audio
    cp "$DIR/index.jsonl" content/rigveda.sa/audio/index.jsonl 2>/dev/null || true
    cp "$DIR/uploads.jsonl" content/rigveda.sa/audio/uploads.jsonl 2>/dev/null || true
  fi

  # Nothing left to do once the renderer has stopped and the last sweep ran.
  if ! pgrep -f render_audio.py > /dev/null; then
    echo "renderer has finished; final sweep done"
    exit 0
  fi
  sleep "$EVERY"
done
