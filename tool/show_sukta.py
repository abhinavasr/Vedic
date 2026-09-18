#!/usr/bin/env python3
"""Print a sukta's verses, for translating by hand.

    python3 tool/show_sukta.py 1.8 1.9
"""
import json, sys
c = json.load(open('content/rigveda.sa/content.json'))
ps = [p for w in c['works'] for s in w['sections'] for p in s['passages']]
want = sys.argv[1:]
for p in ps:
    m, sk, _ = p['ref'].split('.')
    if f'{m}.{sk}' not in want:
        continue
    has = 'hi' in {t['language'] for t in p.get('translations', [])}
    print(f"\n{p['ref']}{'   [已 has hi]' if has else ''}   {p.get('meter','')}")
    for l in p['lines']:
        print('   ', l)
    for t in p.get('transliterations', []):
        for l in t['lines']:
            print('   ', l)
