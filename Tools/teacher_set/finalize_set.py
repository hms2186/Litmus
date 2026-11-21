#!/usr/bin/env python3
"""Validates a filled worksheet and, if it passes, freezes it as the runner file (step 3 of Tools/teacher_set/README.md).

Usage: python3 -I Tools/teacher_set/finalize_set.py Tools/teacher_set/worksheet.json [--out Tools/teacher_set/teacher_set.json]

Checks: fields and ids, known concepts, allowed labels, answer length, copied textbook text, coverage quotas, and that two
labellers labelled every answer independently. An answer whose labels differ needs a `final` label from a third person (or
agreement after discussion); until then it is held out of the frozen set and reported. Writes the runner file plus a
.sha256 lock so any later edit is visible. Exits 1 on any hard error.
"""
import argparse, collections, hashlib, json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LABELS = {"complete", "partial", "misconception", "wrong_topic", "keyword_list", "vague"}
CATEGORY = {"complete": "P", "partial": "X", "misconception": "M", "wrong_topic": "O", "keyword_list": "L", "vague": "V"}
QUOTA = {"complete": 40, "partial": 20, "misconception": 20, "other": 10}  # minimums for ~100 answers (other = wrong_topic + keyword_list + vague)
MIN_WORDS, MAX_WORDS, COPY_RUN = 3, 220, 12


def words(text):
    return re.findall(r"[a-z0-9']+", text.lower())


def longest_shared_run(answer, source):
    a, s = words(answer), words(source)
    grams = {tuple(s[i:i + COPY_RUN]) for i in range(len(s) - COPY_RUN + 1)}
    return any(tuple(a[i:i + COPY_RUN]) in grams for i in range(len(a) - COPY_RUN + 1))


def kappa(pairs):
    n = len(pairs)
    if n == 0:
        return None
    agree = sum(1 for a, b in pairs if a == b) / n
    ca, cb = collections.Counter(a for a, _ in pairs), collections.Counter(b for _, b in pairs)
    expect = sum((ca[l] / n) * (cb[l] / n) for l in LABELS)
    return 1.0 if expect == 1 else (agree - expect) / (1 - expect)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("worksheet")
    ap.add_argument("--out", default=os.path.join(ROOT, "Tools", "teacher_set", "teacher_set.json"))
    args = ap.parse_args()
    data = json.load(open(args.worksheet))
    cards = {c["conceptId"]: c for c in data.get("concepts", [])}
    errors, warnings, held, kept, pairs = [], [], [], [], []
    seen = set()
    for a in data.get("answers", []):
        aid = a.get("id", "?")
        if aid in seen:
            errors.append(f"{aid}: duplicate id")
        seen.add(aid)
        if a.get("conceptId") not in cards:
            errors.append(f"{aid}: conceptId not in the worksheet")
            continue
        text = (a.get("text") or "").strip()
        n = len(words(text))
        if not (MIN_WORDS <= n <= MAX_WORDS):
            errors.append(f"{aid}: {n} words (need {MIN_WORDS} to {MAX_WORDS})")
        if not a.get("author"):
            errors.append(f"{aid}: author missing")
        la, lb = a.get("labelA"), a.get("labelB")
        if la not in LABELS or lb not in LABELS:
            errors.append(f"{aid}: labelA/labelB must each be one of {sorted(LABELS)} (got {la!r}, {lb!r}); labelB is the independent second labeller")
            continue
        if longest_shared_run(text, cards[a["conceptId"]]["cardText"]):
            warnings.append(f"{aid}: copies {COPY_RUN}+ words in a row from the textbook text; a student would not, check it")
        pairs.append((la, lb))
        final = la if la == lb else a.get("final")
        if final not in LABELS:
            held.append(f"{aid}: labels differ ({la} vs {lb}) and no `final` label; left out of the frozen set")
            continue
        kept.append((a, final))
    counts = collections.Counter(f for _, f in kept)
    other = counts["wrong_topic"] + counts["keyword_list"] + counts["vague"]
    for label in ("complete", "partial", "misconception"):
        if counts[label] < QUOTA[label]:
            warnings.append(f"only {counts[label]} '{label}' answers (aim for {QUOTA[label]}+)")
    if other < QUOTA["other"]:
        warnings.append(f"only {other} wrong_topic/keyword_list/vague answers (aim for {QUOTA['other']}+)")
    authors = collections.Counter(a["author"] for a, _ in kept if a.get("author"))
    if len(kept) > 0 and max(authors.values()) / len(kept) > 0.5:
        warnings.append("one author wrote more than half of the answers; ask a second author for variety")
    k = kappa(pairs)
    print(f"{len(data.get('answers', []))} answers read, {len(kept)} usable, {len(held)} held, labeller agreement kappa = {k:.2f}" if k is not None else "no answers")
    print("labels:", dict(counts))
    for line in warnings:
        print("warning:", line)
    for line in held:
        print("held:", line)
    for line in errors:
        print("ERROR:", line)
    if errors or not kept:
        print("NOT FROZEN.")
        sys.exit(1)
    out = []
    for a, final in kept:
        spoken = bool(a.get("spoken"))
        category = "S" if final == "complete" and spoken else CATEGORY[final]
        out.append({"id": a["id"], "conceptId": a["conceptId"], "category": category, "expectPass": final == "complete",
                    "spoken": spoken, "text": a["text"].strip()})
    json.dump({"answers": out}, open(args.out, "w"), indent=1, ensure_ascii=False)
    digest = hashlib.sha256(open(args.out, "rb").read()).hexdigest()
    open(args.out + ".sha256", "w").write(digest + "  " + os.path.basename(args.out) + "\n")
    print(f"Frozen {len(out)} answers to {args.out} (sha256 {digest[:12]}...).")
    print("Run once, with no rule changes afterwards:  Tools/teacher_set/run_teacher_set.sh")


if __name__ == "__main__":
    main()
