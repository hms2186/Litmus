#!/usr/bin/env python3
"""Builds the worksheet a teacher or colleague uses to write answers (step 1 of Tools/teacher_set/README.md).

Usage: python3 -I Tools/teacher_set/make_worksheet.py [--concepts 40] [--seed 11] [--out Tools/teacher_set/worksheet.json]

The worksheet lists concepts (id, subject, class, chapter, label) with the NCERT card text. It never includes grading
criteria, accepted phrasings or misconceptions, so an author cannot write to the rules. Concepts already used by
stress_set.json or holdout_set.json are left out, so the new set covers unseen concepts.
"""
import argparse, glob, json, os, random

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def used_concepts():
    used = set()
    for name in ("stress_set.json", "holdout_set.json", "adversarial_set.json"):
        path = os.path.join(ROOT, "Tools", "model_experiments", name)
        if not os.path.exists(path):
            continue
        data = json.load(open(path))
        items = data["answers"] if isinstance(data, dict) and "answers" in data else data
        for item in items if isinstance(items, list) else []:
            if isinstance(item, dict) and "conceptId" in item:
                used.add(item["conceptId"])
    return used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--concepts", type=int, default=40)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--out", default=os.path.join(ROOT, "Tools", "teacher_set", "worksheet.json"))
    args = ap.parse_args()
    used = used_concepts()
    pool = []
    for path in sorted(glob.glob(os.path.join(ROOT, "Litmus", "Compiled", "*.compiled.json"))):
        chapter = json.load(open(path))
        for c in chapter["concepts"]:
            if c["conceptId"] in used or len(c["keyPoints"]) < 2:
                continue
            pool.append({"conceptId": c["conceptId"], "subject": chapter["subject"], "grade": chapter["gradeLevel"],
                         "chapter": chapter["chapterName"], "label": c["label"], "cardText": c["cardText"]})
    random.Random(args.seed).shuffle(pool)
    # spread over subjects: round-robin so no subject dominates
    by_subject = {}
    for item in pool:
        by_subject.setdefault(item["subject"], []).append(item)
    chosen = []
    while len(chosen) < args.concepts and any(by_subject.values()):
        for subject in sorted(by_subject):
            if by_subject[subject] and len(chosen) < args.concepts:
                chosen.append(by_subject[subject].pop())
    out = {
        "instructions": "See Tools/teacher_set/README.md. Write answers in your own words as a Class 9 or 10 student would; do not copy the card text.",
        "concepts": chosen,
        "answers": [],
        "answerTemplate": {"id": "A001", "conceptId": "<conceptId from concepts>", "author": "<initials>", "spoken": False,
                            "text": "<the student answer>", "labelA": "complete | partial | misconception | wrong_topic | keyword_list | vague",
                            "labelB": "<second labeller, filled independently>", "note": "<optional>"},
    }
    json.dump(out, open(args.out, "w"), indent=1, ensure_ascii=False)
    print(f"Wrote {args.out}: {len(chosen)} concepts across {len({c['subject'] for c in chosen})} subjects.")


if __name__ == "__main__":
    main()
