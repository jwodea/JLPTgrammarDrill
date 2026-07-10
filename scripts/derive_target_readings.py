#!/usr/bin/env python3
"""Derive blank_target_reading for every exercise whose blank_target contains kanji,
by aligning example_sentence against hiragana_full using kana/punctuation anchors.

Additive-only: the ONLY change ever made to a file is inserting the
"blank_target_reading" key into exercises where (a) the target contains kanji,
(b) the key is absent, and (c) the alignment is unambiguous. Ambiguous or
unalignable cases are skipped and reported — the enrichment pass fills those.

Usage:
    python scripts/derive_target_readings.py [--dry-run] [files...]
Default file set: JLPTGrammarDrill/n[1-5]_*.json
"""
import json, re, sys, glob, os

HIRA = r'ぁ-ゖーゝゞ'
KATA_START, KATA_END = 0x30A1, 0x30F6
KANJI_RE = re.compile(r'[一-鿿々〆ヶ]')
# Characters copied verbatim into hiragana_full (anchors): hiragana + punctuation/symbols
LITERAL_RE = re.compile(rf'[{HIRA}。、！？!?・「」『』（）()\s：:；;〜～…,．.0-9０-９]')


def kata_to_hira(s: str) -> str:
    return ''.join(
        chr(ord(c) - 0x60) if KATA_START <= ord(c) <= KATA_END else c
        for c in s
    )


def tokenize(sentence: str):
    """Split sentence into tokens: ('lit', text) for anchor chars (katakana folded
    to hiragana), ('unk', text) for maximal runs of unknown-reading chars (kanji etc.)."""
    tokens = []
    for ch in sentence:
        folded = kata_to_hira(ch)
        kind = 'lit' if LITERAL_RE.fullmatch(folded) else 'unk'
        if tokens and tokens[-1][0] == kind:
            tokens[-1][1] += folded if kind == 'lit' else ch
        else:
            tokens.append([kind, folded if kind == 'lit' else ch])
    return tokens


def align(sentence: str, hiragana_full: str):
    """Return (lazy_alignment, greedy_alignment) — each a list of
    (token_kind, token_text, reading) — or None if the sentence doesn't align.
    Ambiguity is judged per-span by the caller: a span whose reading agrees
    under both the lazy and greedy alignment is unambiguous even if some
    other part of the sentence isn't."""
    tokens = tokenize(sentence)
    target = kata_to_hira(hiragana_full)

    def match(quant):
        pattern = ''.join(
            re.escape(t[1]) if t[0] == 'lit' else f'(.+{quant})'
            for t in tokens
        )
        m = re.fullmatch(pattern, target)
        if not m:
            return None
        out, gi = [], 0
        for kind, text in tokens:
            if kind == 'lit':
                out.append((kind, text, text))
            else:
                gi += 1
                out.append((kind, text, m.group(gi)))
        return out

    lazy, greedy = match('?'), match('')
    if lazy is None or greedy is None:
        return None
    return lazy, greedy


def reading_for_span(sentence: str, aligned, start: int, end: int):
    """Reading for sentence[start:end]; None if the span cuts through an unknown run."""
    pos, parts = 0, []
    for kind, text, reading in aligned:
        tok_start, tok_end = pos, pos + len(text)
        pos = tok_end
        if tok_end <= start or tok_start >= end:
            continue
        if kind == 'unk':
            if start > tok_start or end < tok_end:
                return None  # partial kanji run — ambiguous
            parts.append(reading)
        else:
            parts.append(text[max(start - tok_start, 0):min(end, tok_end) - tok_start])
    return ''.join(parts)


def process(path: str, dry_run: bool):
    with open(path, encoding='utf-8') as f:
        original = f.read()
    d = json.loads(original)
    added, skipped, kana_only = 0, [], 0
    for ex in d.get('exercises', []):
        bt = ex.get('blank_target', '')
        if not KANJI_RE.search(bt):
            kana_only += 1
            continue
        if 'blank_target_reading' in ex:
            continue
        sent, hira = ex.get('example_sentence', ''), ex.get('hiragana_full')
        if not hira or bt not in sent:
            skipped.append((ex.get('id'), 'no hiragana_full or target not in sentence'))
            continue
        # Corpus inconsistency: some hiragana_full lack the sentence's terminal 。.
        # Alignment on 。-stripped strings; span indices are unaffected (。 is final
        # and never part of a blank_target).
        alignments = align(sent.rstrip('。'), hira.rstrip('。'))
        if alignments is None:
            skipped.append((ex.get('id'), 'no alignment'))
            continue
        start = sent.index(bt)
        readings = [
            reading_for_span(sent, a, start, start + len(bt))
            for a in alignments
        ]
        reading = readings[0]
        if readings[0] != readings[1] or not reading \
                or not re.fullmatch(rf'[{HIRA}]+', reading):
            skipped.append((ex.get('id'), f'ambiguous/invalid reading: {readings!r}'))
            continue
        ex['blank_target_reading'] = reading
        added += 1
    if added and not dry_run:
        # Safety: round-trip must be byte-identical except for our additions
        with open(path, 'w', encoding='utf-8') as f:
            f.write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
    return added, skipped, kana_only


def main():
    args = sys.argv[1:]
    dry_run = '--dry-run' in args
    files = [a for a in args if not a.startswith('--')]
    if not files:
        root = os.path.join(os.path.dirname(__file__), '..', 'JLPTGrammarDrill')
        files = sorted(glob.glob(os.path.join(root, 'n[1-5]_*.json')))
    total_added, total_skipped, files_touched = 0, [], 0
    for path in files:
        try:
            added, skipped, _ = process(path, dry_run)
        except Exception as e:
            print(f'ERROR {os.path.basename(path)}: {e}')
            continue
        total_added += added
        if added:
            files_touched += 1
        for ex_id, why in skipped:
            total_skipped.append((ex_id, why))
    print(f'{"[dry-run] " if dry_run else ""}readings added: {total_added} '
          f'across {files_touched} files; skipped (need manual pass): {len(total_skipped)}')
    for ex_id, why in total_skipped:
        print(f'  SKIP {ex_id}: {why}')


if __name__ == '__main__':
    main()
