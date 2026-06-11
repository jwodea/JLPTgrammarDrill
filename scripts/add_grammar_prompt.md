# Prompt — Add 3 BunpoTester Grammar JSON files (next batch)

Paste this prompt into a Claude session inside the `BunpoTester` repo. It auto-picks the next 3 unprocessed grammar items from `scripts/high_confidence_missing.csv`, generates the JSON files, saves them, validates them, and reports. No manual row-picking required.

---

## Copy from here ↓

You are extending **BunpoTester**, a Japanese grammar drill app. Each grammar point lives in one JSON file at `JLPTGrammarDrill/<id>.json`. There are 394 high-confidence missing items queued in `scripts/high_confidence_missing.csv`; this prompt processes them 3 at a time.

### Step 1 — Pick the next 3 items

1. Read `scripts/high_confidence_missing.csv`. Columns: `suggested_id, level, primary_pattern, all_forms_seen, meaning, sources, num_sources`.
2. List `JLPTGrammarDrill/` and collect every existing `n[1-5]_\d{3}\.json` filename.
3. Walk the CSV top-to-bottom (it is pre-ordered N5 → N4 → N3 → N2 → N1) and pick the **first 3 rows whose `suggested_id` does not already have a JSON file**. These are the batch.
4. State the 3 chosen items (id, pattern, meaning, level) before generating, so I can interrupt if needed.

### Step 2 — Generate each file

Schema (exact — every key required, no extras):

- `id` — matches the CSV `suggested_id` (e.g. `"n3_071"`)
- `pattern` — most canonical Japanese form, prefixed with `〜` when it attaches to something. No romaji/English here.
- `meaning` — short English gloss (refine the CSV's `meaning` if needed for clarity)
- `level` — `"N5"` | `"N4"` | `"N3"` | `"N2"` | `"N1"` (matches the row)
- `exercises` — array of **exactly 10** exercise objects

Each exercise object (in this key order, matching existing files):

- `id` — `"<file_id>_<n>"`, n = 1..10
- `example_sentence` — natural Japanese sentence using the pattern. Difficulty must match the JLPT level (N5/N4 everyday vocab and basic kanji; N3 broader/abstract; N2 news/workplace/formal register; N1 literary, idiomatic, formal).
- `translation` — natural English translation (not literal)
- `blank_target` — the substring of `example_sentence` that becomes the blank. Must appear verbatim. Use the pattern itself, or its pattern-defining portion (e.g. for `〜ことから` blank `ことから`; for `〜ざるを得ない` blank `ざるを得ない`).
- `wrong_choices` — array of **exactly 3** plausible-but-wrong alternatives a real learner might confuse with the answer. Same grammatical category, roughly similar length. Avoid distractors that are wrong on form alone.
- `wrong_choice_explanations` — array of **exactly 3** strings, one per wrong choice in order. Each must (a) state what the wrong choice means/does and (b) explain why it doesn't fit *this* sentence. Reference specific words in the sentence when useful. 1–3 sentences each. Avoid generic explanations.
- `hiragana_full` — full hiragana reading of `example_sentence`, preserving punctuation. Convert all kanji to hiragana; leave katakana words as katakana (the existing files use lowercased katakana e.g. `スポーツ → すぽーつ` — match that convention).
- `audio_alternatives` — array of exactly **2** rephrasings, each an object `{ "kanji": ..., "hiragana_full": ... }`. Use different vocabulary, register, or word order. At least one of the two should still use the pattern when natural.
- `audio_eligible` — `true` (boolean)

### Content quality rules

1. **Pattern shows up** in every `example_sentence` and ideally in at least one alternative.
2. **Variety across the 10 exercises**: different subjects, settings, registers; don't reuse the same verb stem or scenario.
3. **Distractor quality**: pick adjacent grammar points, sibling particles, similar conjugations. A learner who half-understands the pattern should be tempted.
4. **Hiragana correctness**: double-check every reading (今日 → きょう, 一日 → ついたち vs いちにち by context, 行く → いく, etc.).
5. **No markdown inside the JSON**, no comments, no trailing commas.

### Reference shape (do not reuse content)

```json
{
  "id": "n5_001",
  "pattern": "〜です",
  "meaning": "polite copula (is / am / are)",
  "level": "N5",
  "exercises": [
    {
      "id": "n5_001_1",
      "example_sentence": "これは本です。",
      "translation": "This is a book.",
      "blank_target": "です",
      "wrong_choices": ["だ", "でした", "ある"],
      "wrong_choice_explanations": [
        "だ is the plain copula; this sentence requires the polite form です.",
        "でした is the past polite copula, but the sentence is present tense.",
        "ある means 'to exist' for inanimate objects but cannot link a noun predicate."
      ],
      "hiragana_full": "これはほんです。",
      "audio_alternatives": [
        { "kanji": "これは本だ。", "hiragana_full": "これはほんだ。" },
        { "kanji": "この本です。", "hiragana_full": "このほんです。" }
      ],
      "audio_eligible": true
    }
    // ... 9 more exercises
  ]
}
```

### Step 3 — Save the files

Write each file to `JLPTGrammarDrill/<id>.json`. Use the file write tool — do not paste JSON into chat as the deliverable.

### Step 4 — Validate

Run:

```
python scripts/validate_grammar_json.py JLPTGrammarDrill/<id1>.json JLPTGrammarDrill/<id2>.json JLPTGrammarDrill/<id3>.json
```

If the validator prints any `❌`, fix the file and re-run until all 3 show `✅`.

### Step 5 — Polish pass (you do this before reporting done)

For each of the 3 files, internally check:

- `blank_target` appears in `example_sentence` exactly once and is the pattern-defining portion.
- Every exercise's `example_sentence` actually uses the pattern.
- The 10 exercises don't repeat verbs/nouns/scenarios.
- Hiragana readings are correct for every kanji — re-verify any uncommon readings.
- Distractors are tempting, not obviously broken.
- `audio_alternatives` are genuinely different phrasings, not trivial swaps.

If you find issues, fix and re-validate before reporting.

### Step 6 — Report

Reply with a 3-bullet summary:

- `<id1>`: `<pattern>` — done (any notes on tricky choices)
- `<id2>`: `<pattern>` — done
- `<id3>`: `<pattern>` — done

Then stop. The next batch is handled by re-running this prompt.

---

## Notes

- **Tracking is automatic**: completion is determined by whether `JLPTGrammarDrill/<id>.json` exists. No "done" column to maintain.
- **To skip an item**: create an empty placeholder file `JLPTGrammarDrill/<id>.json` (or remove the row from the CSV) so it's not picked again.
- **To regenerate an item**: delete the existing JSON file and the next run will pick it up.
- **Batch size**: change "3" to any number if you want larger batches — the picking logic still works.
- **Order**: the CSV is pre-sorted N5 → N4 → N3 → N2 → N1. Going in order keeps the register consistent across a session.

## Source list ID ranges

- **N5**: `n5_082` → `n5_102` (21 items)
- **N4**: `n4_108` → `n4_152` (45 items)
- **N3**: `n3_071` → `n3_148` (78 items)
- **N2**: `n2_201` → `n2_316` (116 items)
- **N1**: `n1_101` → `n1_234` (134 items)
