#!/usr/bin/env python3
"""
One-time migration script: splits 30 multi-pattern JSON files into per-pattern files.

Input:  BunpoTester/N1-1.json ... N3-10.json
Output: BunpoTester/n1_001.json ... n3_070.json (flat, same directory)

Note: N2 patterns n2_102-n2_200 only appear in files N2-1 through N2-5,
so they have 5 exercises each. All other patterns have 10.
"""

import json
import os
from collections import defaultdict

INPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "BunpoTester")
OUTPUT_BASE = INPUT_DIR


def base_pattern_id(exercise_id: str) -> str:
    """Strip the trailing _N suffix: 'n1_001_1' -> 'n1_001'"""
    return exercise_id.rsplit("_", 1)[0]


def main():
    # Collect all exercises grouped by base pattern ID
    patterns = defaultdict(lambda: {"meta": None, "exercises": []})

    for level in ["N1", "N2", "N3"]:
        for set_num in range(1, 11):
            filename = f"{level}-{set_num}.json"
            filepath = os.path.join(INPUT_DIR, filename)
            if not os.path.exists(filepath):
                print(f"WARNING: {filename} not found, skipping")
                continue

            with open(filepath, "r", encoding="utf-8") as f:
                data = json.load(f)

            for exercise in data["grammar"]:
                base_id = base_pattern_id(exercise["id"])

                if patterns[base_id]["meta"] is None:
                    patterns[base_id]["meta"] = {
                        "pattern": exercise["pattern"],
                        "meaning": exercise["meaning"],
                        "level": exercise["level"],
                    }

                patterns[base_id]["exercises"].append({
                    "id": exercise["id"],
                    "example_sentence": exercise["example_sentence"],
                    "translation": exercise["translation"],
                    "blank_target": exercise["blank_target"],
                    "wrong_choices": exercise["wrong_choices"],
                    "wrong_choice_explanations": exercise.get("wrong_choice_explanations", []),
                })

    # Write per-pattern files
    counts = {"N1": 0, "N2": 0, "N3": 0}
    exercise_count_summary = {}

    for base_id in sorted(patterns.keys()):
        data = patterns[base_id]
        meta = data["meta"]
        level = meta["level"]
        exercises = sorted(data["exercises"], key=lambda e: e["id"])

        # Track exercise counts
        ex_count = len(exercises)
        if ex_count not in exercise_count_summary:
            exercise_count_summary[ex_count] = []
        exercise_count_summary[ex_count].append(base_id)

        # Build output JSON
        output = {
            "id": base_id,
            "pattern": meta["pattern"],
            "meaning": meta["meaning"],
            "level": level,
            "exercises": exercises,
        }

        filename = f"{base_id}.json"
        output_path = os.path.join(OUTPUT_BASE, filename)

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(output, f, ensure_ascii=False, indent=2)

        counts[level] += 1

    # Report
    total = sum(counts.values())
    print(f"Generated {total} pattern files:")
    for level, count in sorted(counts.items()):
        print(f"  {level}: {count} files")

    print("\nExercise counts:")
    for count, ids in sorted(exercise_count_summary.items()):
        print(f"  {count} exercises: {len(ids)} patterns")

    print("\nMigration complete.")


if __name__ == "__main__":
    main()
