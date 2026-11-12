import json, sys, re
def main():
    any_fail = False
    for path in sys.argv[1:]:
        errs = []
        try:
            with open(path) as f:
                d = json.load(f)
        except Exception as e:
            print(f'❌ {path}: cannot parse JSON ({e})')
            any_fail = True
            continue
        def check(cond, msg):
            if not cond: errs.append(msg)
        for k in ['id','pattern','meaning','level','exercises']:
            check(k in d, f'missing top-level key: {k}')
        if 'level' in d:
            check(d['level'] in ['N5','N4','N3','N2','N1'], f"bad level: {d['level']}")
        if 'id' in d:
            check(bool(re.match(r'^n[1-5]_\d{3}$', d['id'])), f"bad id: {d['id']}")
        if 'exercises' in d:
            check(len(d['exercises']) == 10, f"exercises count != 10 ({len(d['exercises'])})")
            for i, ex in enumerate(d['exercises'], 1):
                for k in ['id','example_sentence','translation','blank_target',
                          'wrong_choices','wrong_choice_explanations',
                          'hiragana_full','audio_alternatives','audio_eligible']:
                    check(k in ex, f'ex {i}: missing {k}')
                if 'id' in ex and 'id' in d:
                    check(ex['id'] == f"{d['id']}_{i}", f"ex {i}: id mismatch ({ex.get('id')})")
                if 'blank_target' in ex and 'example_sentence' in ex:
                    check(ex['blank_target'] in ex['example_sentence'],
                          f"ex {i}: blank_target not in example_sentence")
                if 'wrong_choices' in ex:
                    check(len(ex['wrong_choices']) == 3, f"ex {i}: wrong_choices != 3")
                if 'wrong_choice_explanations' in ex:
                    check(len(ex['wrong_choice_explanations']) == 3,
                          f"ex {i}: wrong_choice_explanations != 3")
                if 'audio_alternatives' in ex:
                    check(len(ex['audio_alternatives']) == 2,
                          f"ex {i}: audio_alternatives != 2")
                    for j, alt in enumerate(ex['audio_alternatives'], 1):
                        check('kanji' in alt and 'hiragana_full' in alt,
                              f"ex {i} alt {j}: missing kanji/hiragana_full")
                if 'audio_eligible' in ex:
                    check(ex['audio_eligible'] is True, f"ex {i}: audio_eligible must be true")
                # Enrichment fields — all optional, validated only when present
                if 'register' in ex:
                    check(ex['register'] in ['casual','neutral','formal','written'],
                          f"ex {i}: bad register: {ex['register']}")
                if 'vocab' in ex:
                    check(isinstance(ex['vocab'], list) and 1 <= len(ex['vocab']) <= 12,
                          f"ex {i}: vocab must be a list of 1-12 items")
                    for j, v in enumerate(ex.get('vocab') or [], 1):
                        check(isinstance(v, dict) and all(k in v for k in ['word','reading','meaning']),
                              f"ex {i} vocab {j}: missing word/reading/meaning")
                        if isinstance(v, dict) and 'reading' in v:
                            check(bool(re.fullmatch(r'[ぁ-ゖーゝゞ・ 　]+', v['reading'])),
                                  f"ex {i} vocab {j}: reading not hiragana: {v.get('reading')}")
                        if isinstance(v, dict) and 'word' in v and 'blank_target' in ex:
                            check(v['word'] != ex['blank_target'],
                                  f"ex {i} vocab {j}: vocab word equals blank_target")
                if 'blank_occurrence' in ex:
                    bo = ex['blank_occurrence']
                    cnt = ex.get('example_sentence','').count(ex.get('blank_target','\0'))
                    check(isinstance(bo, int) and not isinstance(bo, bool) and 1 <= bo <= cnt,
                          f"ex {i}: blank_occurrence {bo} out of range (target occurs {cnt}x)")
                if 'blank_target_reading' in ex:
                    btr = ex['blank_target_reading']
                    # 、 allowed: some (miscut) multi-clause targets contain commas
                    check(bool(re.fullmatch(r'[ぁ-ゖーゝゞ、]+', btr or '')),
                          f"ex {i}: blank_target_reading not hiragana: {btr}")
                    check(bool(re.search(r'[一-鿿々]', ex.get('blank_target',''))),
                          f"ex {i}: blank_target_reading present but blank_target has no kanji")
        if errs:
            print(f'❌ {path}')
            for e in errs: print(f'   {e}')
            any_fail = True
        else:
            print(f'✅ {path}')
    sys.exit(1 if any_fail else 0)
if __name__ == '__main__':
    main()
