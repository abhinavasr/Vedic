#!/usr/bin/env python3
"""Write rendered audio into a pack's content JSON.

Takes what `render_audio.py` measured and `upload_audio.py` published, and adds
to each passage the `audio` block the app reads — and, where the pack has none,
the meter the renderer detected on the way past.

    python3 tool/merge_audio.py --dir /path/to/audio [--revision 21]

Pack revisions are immutable, so this bumps the revision by default: a pack
that gains audio is a new revision, not an edit of the old one.
"""

import argparse
import json
import pathlib
import sys

VOICE = {
    "id": "vagdhenu-m1",
    "name": "Vāgdhenu",
    "language": "sa",
    "style": "chant",
    "engine": "vagdhenu@2026-09-16",
    "licence": "vagdhenu",
}

LICENCE = {
    "id": "vagdhenu",
    "name": "Sanskrit chant audio",
    "attribution": "Recitation rendered by Vāgdhenu.",
}

# The server names meters in plain ASCII; the pack spells them as they are
# written. Anything not listed is kept as it came, rather than guessed at.
METERS = {
    "anushtubh": "anuṣṭubh",
    "trishtubh": "triṣṭubh",
    "vasantatilaka": "vasantatilakā",
    "upajati": "upajāti",
    "indravajra": "indravajrā",
    "upendravajra": "upendravajrā",
    "shalini": "śālinī",
    "malini": "mālinī",
    "shikharini": "śikhariṇī",
}


def load(path):
    return [
        json.loads(line)
        for line in pathlib.Path(path).read_text().splitlines()
        if line.strip()
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True)
    parser.add_argument("--pack", default="content/bhagavad-gita.sa/content.json")
    parser.add_argument("--revision", type=int, default=None)
    parser.add_argument("--mime", default="audio/wav")
    args = parser.parse_args()

    root = pathlib.Path(args.dir)
    uploads = {u["ref"]: u for u in load(root / "uploads.jsonl")}
    if not uploads:
        sys.exit("nothing uploaded yet")

    pack_path = pathlib.Path(args.pack)
    pack = json.loads(pack_path.read_text())

    pack["revision"] = args.revision or pack["revision"] + 1
    if not any(l["id"] == LICENCE["id"] for l in pack.get("licences", [])):
        pack.setdefault("licences", []).append(LICENCE)
    pack["voices"] = [
        v for v in pack.get("voices", []) if v.get("id") != VOICE["id"]
    ] + [VOICE]

    attached = meters = missing = 0
    for work in pack.get("works", []):
        for section in work.get("sections", []):
            for passage in section.get("passages", []):
                record = uploads.get(passage.get("ref"))
                if record is None:
                    if passage.get("kind") in {"verse", "prose"}:
                        missing += 1
                    continue
                passage["audio"] = [
                    {
                        "voice": VOICE["id"],
                        "file": record["url"],
                        "mime": args.mime,
                        # The server reports seconds; the pack stores
                        # milliseconds, and a recording is never zero long.
                        "duration_ms": max(1, round(record["duration_s"] * 1000)),
                        "size": record["bytes"],
                        "sha256": record["sha256"],
                    }
                ]
                attached += 1
                # Only where the pack has none: a meter somebody entered by
                # hand outranks one a machine detected.
                detected = record.get("meter")
                if detected and not passage.get("meter"):
                    passage["meter"] = METERS.get(detected, detected)
                    meters += 1

    pack_path.write_text(json.dumps(pack, ensure_ascii=False))
    print(
        f"revision {pack['revision']}: {attached} passages with audio, "
        f"{meters} meters filled in, {missing} still without audio"
    )


if __name__ == "__main__":
    main()
