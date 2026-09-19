#!/usr/bin/env python3
"""Turn the Rigveda source files into a content pack JSON.

    python3 tool/rigveda_to_json.py content/rigveda.sa

Which sukta each file holds comes from `sukta-index.csv`, which was settled by
matching the text rather than by trusting the filenames — see the note at the
top of that file.

Two things about the sources shape this:

  * The header line — verse count, ṛṣi, devatā, chandas — is sometimes run
    together with the first verse on one line. It can still be told apart,
    because a header is plain Sanskrit and every verse carries Vedic accents.
    The first accented character is where the header stops.

  * Verses are separated by their own numbers, ॥१॥ ॥२॥, which the pack format
    does not keep: a verse's number is its ref, not part of its text.
"""

import argparse
import csv
import json
import pathlib
import re
import unicodedata

# Udātta, anudātta and the rest. None of these appear in a header.
ACCENTS = '॒॑᳐᳑᳒᳓᳔᳕᳖᳗᳘᳜᳝᳞᳟᳚᳛᳠᳡꣠꣡꣢꣣'

DIGITS = {c: str(i) for i, c in enumerate('०१२३४५६७८९')}

# The maṇḍala number as the title writes it.
DEVANAGARI = {n: ''.join('०१२३४५६७८९'[int(d)] for d in str(n)) for n in range(1, 11)}

# Chandas worth naming, longest first so "अनुष्टुप्" wins over "अनुष्टु".
METERS = [
    'गायत्री', 'त्रिष्टुप्', 'त्रिष्टुभ्', 'जगती', 'अनुष्टुप्', 'अनुष्टुभ्',
    'बृहती', 'सतोबृहती', 'पङ्क्ति', 'पंक्ति', 'उष्णिक्', 'विराट्', 'ककुप्',
    'द्विपदा', 'अतिजगती', 'शक्वरी', 'अतिशक्वरी', 'अष्टि', 'अत्यष्टि',
    'धृति', 'प्रगाथ',
]


def devanagari_int(text):
    if text and all(c in DIGITS for c in text):
        return int(''.join(DIGITS[c] for c in text))
    return None


def split_header(text):
    """The header, and the body that follows it."""
    for i, c in enumerate(text):
        if c in ACCENTS:
            # Back up to the start of the accented word, then to the divider
            # that closed the header.
            cut = text.rfind('।', 0, i)
            start = cut + 1 if cut != -1 else 0
            return text[:start].strip(), text[start:]
    # No accents anywhere: treat the first line as the header.
    line, _, rest = text.partition('\n')
    return line.strip(), rest


def meter_of(header):
    for name in METERS:
        if name in header:
            return name
    return None


# A verse ends with its own number. The sources write that three ways: ॥१॥,
# ॥१ with the closing danda left off at the end of a line, and — in the dvipadā
# suktas — a pāda counter in the margin as well, which is not a verse number at
# all and has to be left out of the text.
# Sometimes the number itself is left out and only the double danda closes the
# verse (RV 1.136.4, among others). The verse still ended; it is numbered by
# the one before it.
VERSE_END = re.compile(r'॥\s*([०-९]*)\s*॥?')
MARGIN_NUMBER = re.compile(r'\s+[०-९]+\s*$')


# The sources type visarga as an ASCII colon about as often as they use the
# real "ः" — "अ॒द्रुह॑:" rather than "अ॒द्रुहः". It looks close enough on the page
# and is not a Devanagari mark at all, so it has to be normalised before the
# text is stored: otherwise the reader sees a colon, the transliterator drops
# the sound, and the speech synthesiser is handed punctuation mid-word.
COLON_VISARGA = re.compile(r'(?<=[\u0900-\u097F\u1CD0-\u1CFF\uA8E0-\uA8FF]):')


def normalise(line):
    """Typography the edition used that is not what the text says."""
    return COLON_VISARGA.sub('\u0903', line)


def verses(body):
    """The verses, in order, without their numbers."""
    out = []
    parts = VERSE_END.split(body)
    # parts is [text, number, text, number, …]; the tail after the last number
    # is whatever trailing whitespace the file ends with.
    previous = 0
    for i in range(0, len(parts) - 1, 2):
        number = devanagari_int(parts[i + 1]) or previous + 1
        lines = []
        for line in parts[i].split('\n'):
            line = MARGIN_NUMBER.sub('', line)
            line = re.sub(r'\s+', ' ', line).strip()
            if line and any('\u0900' <= c <= '\u097f' for c in line):
                lines.append(normalise(line))
        if lines and number:
            out.append((number, lines))
            previous = number
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('directory')
    ap.add_argument('--revision', type=int, default=1)
    args = ap.parse_args()
    root = pathlib.Path(args.directory)

    index = []
    with open(root / 'sukta-index.csv', encoding='utf-8') as f:
        for row in csv.DictReader(l for l in f if not l.startswith('#')):
            index.append((int(row['mandala']), int(row['sukta']), row['file']))
    index.sort()

    # Sections gathered per maṇḍala rather than into one heap. The Ṛgveda is
    # not a book of 1,028 chapters: it is ten, and they are what the tradition
    # names, what editions print as separate volumes, and what somebody means
    # when they say where they are in it. Flat, the reader met 483 chips in a
    # row with nothing to tell one part of the book from another.
    by_mandala, total, held = {}, 0, []
    for mandala, sukta, name in index:
        text = (root / 'sources' / name).read_text(encoding='utf-8')
        header, body = split_header(text)
        found = verses(body)
        # The header opens with the number of verses — except where it opens
        # with a numbered list of ṛṣis instead (RV 10.136), where a leading
        # "1" means the first ṛṣi and not a one-verse sukta.
        numbers = [n for n, _ in found]
        claimed = devanagari_int((header.split() or [''])[0].strip('()'))
        # The verse numbers have to be 1…N, once each. Where they are not, the
        # text is carrying two numberings at once: the dvipadā suktas print the
        # standard verse number on one half-line and the unit number on the
        # next, and a parser cannot tell which the citation means.
        ordered = numbers == list(range(1, len(numbers) + 1))
        if not ordered or (claimed and claimed > 1 and claimed != len(found)):
            # Held back rather than shipped. A ref is a citation and can never
            # be renumbered afterwards, so a sukta whose verse division is not
            # yet settled is worth more outside the pack than in it — the
            # dvipadā suktas, where the printed text groups two pādas to a unit
            # and the standard numbering does not, are most of these.
            why = 'numbering not 1…N' if not ordered else 'header count differs'
            held.append((mandala, sukta, claimed, len(found), why, name))
            continue
        passages = []
        for number, lines in found:
            passages.append({
                'ref': f'{mandala}.{sukta}.{number}',
                'kind': 'verse',
                'label': f'{mandala}.{sukta}.{number}',
                'lines': lines,
                **({'meter': meter_of(header)} if meter_of(header) else {}),
            })
        total += len(passages)
        section = {
            'kind': 'sukta',
            'number': f'{mandala}.{sukta}',
            'passages': passages,
        }
        if header:
            # The whole header, kept as it stands: it names the ṛṣi, the devatā
            # and the chandas, sometimes verse by verse, and picking it apart
            # would lose more than it would tidy.
            section['summary'] = {'sa': header}
        by_mandala.setdefault(mandala, []).append(section)

    content = {
        'format': 'vedic-pack-content',
        'format_version': 1,
        'pack_id': 'rigveda.sa',
        'revision': args.revision,
        'languages': ['sa'],
        'licences': [{
            'id': 'rigveda-sa',
            'name': 'Ṛgveda, Śākala Saṃhitā',
            'attribution': 'Ṛgveda Śākala Saṃhitā, accented Devanagari text.',
        }],
        'voices': [],
        'works': [
            {
                # Numbered so they sort as they are read, and so a tenth
                # maṇḍala never files between the first and the second.
                'slug': f'rigveda-{mandala:02d}',
                'kind': 'scripture',
                'title': {
                    'sa': f'ऋग्वेदः · मण्डल {DEVANAGARI[mandala]}',
                    'en': f'Rigveda · Maṇḍala {mandala}',
                },
                'original_language': 'sa',
                'script': 'Deva',
                'edition': 'Śākala Saṃhitā',
                'licence': 'rigveda-sa',
                'source_note': (
                    f'Maṇḍala {mandala}: {len(sections)} suktas of the '
                    f'{len(index)} supplied, as text files with Vedic '
                    'accents. Which sukta each file holds was settled by '
                    'matching the text, not the filenames: see '
                    'sukta-index.csv.'
                ),
                'sections': sections,
            }
            for mandala, sections in sorted(by_mandala.items())
        ],
    }
    out = root / 'content.json'
    out.write_text(json.dumps(content, ensure_ascii=False), encoding='utf-8')
    suktas = sum(len(v) for v in by_mandala.values())
    print(f'{len(by_mandala)} mandalas, {suktas} suktas, {total} verses → {out}')
    if held:
        review = root / 'needs-review.csv'
        with review.open('w', encoding='utf-8') as f:
            f.write('# Suktas left out of the pack: the number of verses the\n')
            f.write('# header states and the number the text divides into do not\n')
            f.write('# agree, so their verse numbering — which is their citation —\n')
            f.write('# is not settled. Most are dvipadā, where the printed text\n')
            f.write('# groups two pādas into one numbered unit and the standard\n')
            f.write('# citation does not.\n')
            f.write('mandala,sukta,header_says,verses_found,why,file\n')
            for m, s_, claimed, got, why, name in held:
                f.write(f'{m},{s_},{claimed or ""},{got},{why},"{name}"\n')
        print(f'{len(held)} suktas held back → {review}')


if __name__ == '__main__':
    main()
