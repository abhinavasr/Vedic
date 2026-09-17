#!/usr/bin/env python3
"""Write the request files an AI fills in and hands back.

    python3 tool/translation_requests.py content/rigveda.sa --out ~/Downloads/rigveda-requests

Each file holds whole suktas — never half of one, because a ṛc is read against
the ones around it — up to about --verses per file. What comes back is merged
with tool/merge_translations.dart, which keys on the ref.
"""

import argparse
import json
import pathlib

INSTRUCTIONS = (
    'Translate each verse of the Ṛgveda (Śākala Saṃhitā) below. For every ref '
    'in "verses", return three things: "iast" — the Sanskrit transliterated '
    'into IAST, keeping the Vedic accents where you can; "hi" — a plain Hindi '
    'translation; "en" — a plain English translation. '
    'Translate what the verse says: add nothing, leave nothing out, and do not '
    'explain. Keep the names of gods, ṛṣis and places as they are. '
    'Return only JSON in the shape of "return_format", with one entry per ref, '
    'and do not change or renumber a ref.'
)

RETURN_FORMAT = {
    'verses': {
        '<ref, exactly as given>': {
            'iast': '<the Sanskrit in IAST>',
            'hi': '<Hindi translation>',
            'en': '<English translation>',
        }
    }
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('directory')
    ap.add_argument('--out', required=True)
    ap.add_argument('--verses', type=int, default=120,
                    help='roughly how many verses per file')
    ap.add_argument('--single', action='store_true',
                    help='one file holding everything, grouped by sukta')
    args = ap.parse_args()

    root = pathlib.Path(args.directory)
    out = pathlib.Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    for stale in out.glob('*.json'):
        stale.unlink()

    content = json.loads((root / 'content.json').read_text(encoding='utf-8'))
    work = content['works'][0]

    if args.single:
        # Grouped by sukta rather than flat: the ṛṣi, devatā and chandas are a
        # property of the sukta, and repeating them against all eight thousand
        # verses would add a megabyte that says nothing new.
        suktas, total = [], 0
        for section in work['sections']:
            verses = {p['ref']: p['lines'] for p in section['passages']}
            total += len(verses)
            meters = {p['meter'] for p in section['passages'] if p.get('meter')}
            suktas.append({
                'sukta': section['number'],
                **({'header': section['summary']['sa']}
                   if section.get('summary') else {}),
                **({'meter': sorted(meters)[0]} if len(meters) == 1 else {}),
                'verses': verses,
            })
        body = {
            'instructions': INSTRUCTIONS,
            'return_format': RETURN_FORMAT,
            'work': 'Ṛgveda, Śākala Saṃhitā',
            'pack_id': content['pack_id'],
            'sukta_count': len(suktas),
            'verse_count': total,
            'suktas': suktas,
        }
        out.mkdir(parents=True, exist_ok=True)
        target = out / 'rigveda-all.json'
        target.write_text(json.dumps(body, ensure_ascii=False), encoding='utf-8')
        size = target.stat().st_size
        print(f'{len(suktas)} suktas, {total} verses, '
              f'{size / 1_000_000:.1f} MB → {target}')
        return

    # Group whole suktas into parts.
    parts, current, count = [], [], 0
    for section in work['sections']:
        if current and count + len(section['passages']) > args.verses:
            parts.append(current)
            current, count = [], 0
        current.append(section)
        count += len(section['passages'])
    if current:
        parts.append(current)

    total = 0
    for i, part in enumerate(parts, 1):
        verses = {}
        for section in part:
            about = section.get('summary', {}).get('sa', '')
            for p in section['passages']:
                verses[p['ref']] = {
                    'sanskrit': p['lines'],
                    'sukta': section['number'],
                    **({'meter': p['meter']} if p.get('meter') else {}),
                    **({'sukta_header': about} if about else {}),
                }
        total += len(verses)
        body = {
            'instructions': INSTRUCTIONS,
            'return_format': RETURN_FORMAT,
            'work': 'Ṛgveda, Śākala Saṃhitā',
            'pack_id': content['pack_id'],
            'part': f'{i} of {len(parts)}',
            'suktas': [s['number'] for s in part],
            'verse_count': len(verses),
            'verses': verses,
        }
        name = f'rigveda-{i:03d}-of-{len(parts):03d}.json'
        (out / name).write_text(
            json.dumps(body, ensure_ascii=False, indent=1), encoding='utf-8'
        )
    print(f'{len(parts)} files, {total} verses → {out}')


if __name__ == '__main__':
    main()
