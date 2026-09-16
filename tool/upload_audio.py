#!/usr/bin/env python3
"""Upload rendered audio to the vault and record where each file landed.

Reads the `index.jsonl` that `render_audio.py` wrote, uploads anything not yet
uploaded, and appends to `uploads.jsonl`. Resumable for the same reason the
renderer is: seven hundred uploads will drop one somewhere, and re-running
should cost only what is missing.

The vault's reply carries its own SHA-256. It is checked against the digest
taken before sending, so a file that arrived corrupted is noticed here rather
than as a burst of static on somebody's phone.

    VAULT_UPLOAD_PASSWORD=... python3 tool/upload_audio.py --dir /path/to/audio
"""

import argparse
import json
import os
import pathlib
import subprocess
import sys
import time

UPLOAD = "https://ai.abhinava.xyz/audio-vault/upload"


def upload(path, password, timeout):
    """One file. Returns the vault's record of it."""
    result = subprocess.run(
        [
            "curl", "-sS", "--fail", "-m", str(timeout),
            "-X", "POST", UPLOAD,
            "-H", f"X-Upload-Password: {password}",
            "-F", f"file=@{path}",
        ],
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode().strip() or f"curl {result.returncode}")
    return json.loads(result.stdout.decode())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--retries", type=int, default=4)
    parser.add_argument("--pause", type=float, default=0.2)
    args = parser.parse_args()

    password = os.environ.get("VAULT_UPLOAD_PASSWORD")
    if not password:
        sys.exit("VAULT_UPLOAD_PASSWORD is not set. The password never lives in this repo.")

    root = pathlib.Path(args.dir)
    rendered = [
        json.loads(line)
        for line in (root / "index.jsonl").read_text().splitlines()
        if line.strip()
    ]

    log_path = root / "uploads.jsonl"
    done = {}
    if log_path.exists():
        for line in log_path.read_text().splitlines():
            if line.strip():
                record = json.loads(line)
                done[record["ref"]] = record

    print(f"{len(rendered)} rendered, {len(done)} already uploaded", flush=True)
    started = time.time()
    failures = 0

    with log_path.open("a") as log:
        for i, item in enumerate(rendered, 1):
            ref = item["ref"]
            if ref in done:
                continue
            path = root / item["file"]
            if not path.exists():
                print(f"  {ref}: missing {path.name}", flush=True)
                continue
            record = None
            for attempt in range(1, args.retries + 1):
                try:
                    record = upload(path, password, args.timeout)
                    break
                except Exception as error:  # noqa: BLE001 — every failure retries
                    if attempt == args.retries:
                        print(f"  {ref}: giving up — {error}", flush=True)
                        failures += 1
                    else:
                        time.sleep(2 ** attempt)
            if record is None:
                continue
            # What the vault stored must be what we rendered. A mismatch here
            # is a corrupted upload, and it is cheaper to catch it now.
            if record.get("sha256") != item["sha256"]:
                print(f"  {ref}: DIGEST MISMATCH — not recording", flush=True)
                failures += 1
                continue
            log.write(json.dumps({
                "ref": ref,
                "id": record["id"],
                "url": record["downloadUrl"],
                "bytes": record["bytes"],
                "sha256": record["sha256"],
                "duration_s": item["duration_s"],
                "meter": item.get("meter"),
            }, ensure_ascii=False) + "\n")
            log.flush()
            if i % 25 == 0 or i == len(rendered):
                rate = i / max(time.time() - started, 1)
                print(f"  {i}/{len(rendered)}  {ref}  ({rate:.2f}/s)", flush=True)
            time.sleep(args.pause)

    print(f"done, {failures} failed", flush=True)


if __name__ == "__main__":
    main()
