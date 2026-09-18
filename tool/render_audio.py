#!/usr/bin/env python3
"""Render every Sanskrit passage in a content pack to audio, via Vāgdhenu.

The text comes from the pack and goes back to the pack: the server is asked to
read what the database already holds, never to produce scripture of its own.

Resumable by design. Seven hundred sequential HTTP renders will lose a
connection somewhere, and nothing here is worth doing twice — a verse whose
file is already on disk is skipped, so re-running after a failure costs only
what is missing.

    VAGDHENU_KEY=... python3 tool/render_audio.py --out /path/to/audio

Writes one WAV per passage plus `index.jsonl`, which records the meter the
server detected, the duration it reported and the SHA-256 of the file. That
index is what a later step turns into the pack's `audio` blocks.
"""

import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.request

HOST = "tts.abhinava.xyz"

# The chandas the server has a reference clip for, keyed by the name the
# source writes. GET /meters lists the bank; anything missing from it is
# rendered in vasantatilakā, which the server names as its fallback.
#
# Only anuṣṭubh of the Rigveda's meters is in there. Gāyatrī and triṣṭubh,
# which are four fifths of the Saṃhitā between them, are not — so asking for
# them by name would change nothing, and rendering them anyway produces a
# 14-syllable classical chant over an 8- or 11-syllable Vedic line.
METERS = {
    "अनुष्टुप्": "anuṣṭubh",
    "अनुष्टुभ्": "anuṣṭubh",
}


def resolve(host):
    """Addresses for [host], asked for over HTTPS.

    Not a nicety: this record is new, and a resolver that looked it up while it
    was missing will keep saying so until its negative cache expires. DNS over
    HTTPS goes to the authority and skips whatever is cached in between.
    """
    request = urllib.request.Request(
        f"https://cloudflare-dns.com/dns-query?name={host}&type=A",
        headers={"accept": "application/dns-json"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        answer = json.load(response).get("Answer", [])
    return [a["data"] for a in answer if a.get("type") == 1]


# Devanagari digits crash the server (HTTP 500), and they are not part of the
# recitation anyway: the pack schema says verse numbers are removed from
# `lines`, and only the chapter colophons still carry theirs. Taking them out
# is what the schema asks for and what the reciter would do.
DEVANAGARI_DIGITS = str.maketrans('', '', '\u0966\u0967\u0968\u0969\u096a\u096b\u096c\u096d\u096e\u096f')


def speakable(text):
    """The text as it should be recited."""
    cleaned = text.translate(DEVANAGARI_DIGITS)
    # A number removed from between two dandas leaves "॥ ॥", which is a pause
    # taken twice. One danda is the end of the line either way.
    cleaned = re.sub(r"॥\s*॥", "॥", cleaned)
    cleaned = re.sub(r"।\s*।", "।", cleaned)
    return "\n".join(" ".join(line.split()) for line in cleaned.splitlines())


def passages(pack, kinds):
    """Every passage worth rendering, in the order the book has them."""
    content = json.load(open(pack))
    for work in content.get("works", []):
        for section in work.get("sections", []):
            for passage in section.get("passages", []):
                if passage.get("kind") not in kinds:
                    continue
                lines = [l for l in passage.get("lines", []) if l.strip()]
                if lines:
                    yield (
                        work.get("slug", "work"),
                        passage["ref"],
                        speakable("\n".join(lines)),
                        METERS.get((passage.get("meter") or "").strip()),
                    )


def render(text, out, key, address, timeout, meter=None):
    """One passage. Returns the server's headers, or raises."""
    head = out.with_suffix(".headers")
    request = {"text": text}
    if meter:
        request["meter"] = meter
    body = json.dumps(request, ensure_ascii=False).encode()
    result = subprocess.run(
        [
            "curl", "-sS", "--fail", "-m", str(timeout),
            "--resolve", f"{HOST}:443:{address}",
            "-D", str(head),
            "-X", "POST", f"https://{HOST}/tts",
            "-H", f"X-API-Key: {key}",
            "-H", "Content-Type: application/json",
            "--data-binary", "@-",
            "-o", str(out),
        ],
        input=body,
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode().strip() or f"curl {result.returncode}")
    headers = {}
    for line in head.read_text(errors="replace").splitlines():
        if ":" in line:
            name, _, value = line.partition(":")
            headers[name.strip().lower()] = value.strip()
    head.unlink(missing_ok=True)
    if not out.exists() or out.stat().st_size < 1024:
        raise RuntimeError("the server returned nothing worth keeping")
    return headers


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", default="content/bhagavad-gita.sa/content.json")
    parser.add_argument("--out", required=True)
    parser.add_argument("--kinds", default="verse")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--pause", type=float, default=0.3,
                        help="seconds between requests, to be a good guest")
    parser.add_argument("--retries", type=int, default=4)
    parser.add_argument("--known-meters", action="store_true",
                        help="render only verses whose chandas is in the "
                             "server's reference bank, instead of letting the "
                             "rest fall back to vasantatilakā")
    args = parser.parse_args()

    key = os.environ.get("VAGDHENU_KEY")
    if not key:
        sys.exit("VAGDHENU_KEY is not set. The key never lives in this repo.")

    addresses = resolve(HOST)
    if not addresses:
        sys.exit(f"{HOST} does not resolve.")
    address = addresses[0]

    root = pathlib.Path(args.out)
    root.mkdir(parents=True, exist_ok=True)
    index = root / "index.jsonl"
    done = set()
    if index.exists():
        for line in index.read_text().splitlines():
            if line.strip():
                done.add(json.loads(line)["ref"])

    work = list(passages(args.pack, set(args.kinds.split(","))))
    if args.known_meters:
        held = [w for w in work if not w[3]]
        work = [w for w in work if w[3]]
        print(f"{len(held)} passages held back: no reference clip for their "
              f"chandas", flush=True)
    print(f"{len(work)} passages, {len(done)} already rendered", flush=True)
    started = time.time()

    with index.open("a") as log:
        for i, (slug, ref, text, meter) in enumerate(work, 1):
            out = root / f"{ref}.wav"
            if ref in done and out.exists():
                continue
            for attempt in range(1, args.retries + 1):
                try:
                    headers = render(text, out, key, address,
                                     args.timeout, meter)
                    break
                except Exception as error:  # noqa: BLE001 — every failure retries
                    if attempt == args.retries:
                        print(f"  {ref}: giving up — {error}", flush=True)
                        out.unlink(missing_ok=True)
                        headers = None
                        break
                    # Back off, and look the host up again in case it moved.
                    time.sleep(2 ** attempt)
                    try:
                        address = resolve(HOST)[0]
                    except Exception:
                        pass
            if headers is None:
                continue
            log.write(json.dumps({
                "work": slug,
                "ref": ref,
                "file": out.name,
                "bytes": out.stat().st_size,
                "sha256": hashlib.sha256(out.read_bytes()).hexdigest(),
                "duration_s": float(headers.get("x-vagdhenu-duration-s", 0) or 0),
                "meter": headers.get("x-vagdhenu-meter"),
                "meter_source": headers.get("x-vagdhenu-meter-source"),
                "render_s": float(headers.get("x-vagdhenu-render-s", 0) or 0),
                "engine": headers.get("x-vagdhenu-engine"),
            }, ensure_ascii=False) + "\n")
            log.flush()
            if i % 25 == 0 or i == len(work):
                rate = i / max(time.time() - started, 1)
                print(f"  {i}/{len(work)}  {ref}  ({rate:.2f}/s)", flush=True)
            time.sleep(args.pause)

    print("done", flush=True)


if __name__ == "__main__":
    main()
