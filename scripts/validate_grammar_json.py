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
        if errs:
            print(f'❌ {path}')
            for e in errs: print(f'   {e}')
            any_fail = True
        else:
            print(f'✅ {path}')
    sys.exit(1 if any_fail else 0)
if __name__ == '__main__':
    main()
