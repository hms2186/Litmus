#!/usr/bin/env python3
"""Release set tooling for Litmus (architecture v4.0, Milestone 6).

The release set is the held-out, human-labelled answer set that decides whether the grading engine
can ship. It must not be written by the author of the prompts and rules, and it must never be used
for tuning. Everything here uses only the standard library.

  plan           choose concepts and write Curriculum/release/plan.json plus the authoring sheet
  import-answers read the filled authoring sheet into Curriculum/release/release_set.json
  label-sheets   write the labelling sheets (labeller A: everything, labeller B: a seeded subset)
  import-labels  read a filled labelling sheet
  validate       check coverage, independence and label quality (--dry-run relaxes the minimums)
  freeze         record hashes of the engine, prompts and compiled chapters before the first run
  check-frozen   fail if any of them changed since `freeze`
  gate           compute exact Clopper-Pearson bounds from run results and decide pass/fail

Run with python3 -I Tools/release/release_gate.py <command> -h
"""
import argparse
import csv
import glob
import hashlib
import json
import math
import os
import random
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
APP = os.path.join(ROOT, "Litmus")
RELEASE = os.path.join(ROOT, "Curriculum", "release")
PLAN = os.path.join(RELEASE, "plan.json")
SET = os.path.join(RELEASE, "release_set.json")
FROZEN = os.path.join(RELEASE, "frozen.json")
SHEETS = os.path.join(RELEASE, "sheets")

# ---- release criteria (architecture v3.2 / v4.0) ------------------------------------------------
MIN_SHOULD_NOT_PASS = 300       # answers labelled fail: measure false passes
MIN_SHOULD_PASS = 200           # answers labelled pass: measure false fails
MIN_CONCEPTS = 60
MAX_PER_CONCEPT_PER_GROUP = 5   # answers to one concept are not independent
MIN_DOUBLE_LABELLED = 0.20
KAPPA_MIN = 0.80
CONFIDENCE = 0.95               # one-sided
FALSE_PASS_MAX = 0.05           # model path
FALSE_FAIL_MAX = 0.10           # model path
FALLBACK_FALSE_LIKELY_MAX = 0.10
CLARIFICATION_MAX = 0.25
P50_SECONDS_MAX = 8.0
P95_SECONDS_MAX = 15.0
ALLOWED_SOURCES = {"student", "teacher"}   # the author of the prompts and rules may not write release answers

ACCEPTED = {"mastered", "likelyMastered"}
TERMINAL_NOT_ACCEPTED = {"partial", "almostThere", "notYet", "needsCorrection", "offTopic", "notGradable"}

# Files whose hashes are frozen: changing any of them after seeing release results invalidates them.
FROZEN_FILES = ["RuleEngine.swift", "Graders.swift", "GradingCoordinator.swift", "AttemptMachine.swift",
                "CompiledCurriculum.swift"]


# =================================================================================================
# statistics
# =================================================================================================

def _log_pmf(i, n, p):
    if p <= 0:
        return 0.0 if i == 0 else -math.inf
    if p >= 1:
        return 0.0 if i == n else -math.inf
    return (math.lgamma(n + 1) - math.lgamma(i + 1) - math.lgamma(n - i + 1)
            + i * math.log(p) + (n - i) * math.log1p(-p))


def binom_cdf(k, n, p):
    """P(X <= k) for X ~ Binomial(n, p), exactly."""
    return min(1.0, sum(math.exp(_log_pmf(i, n, p)) for i in range(0, k + 1)))


def cp_upper(k, n, confidence=CONFIDENCE):
    """Exact one-sided Clopper-Pearson upper bound for k events in n trials."""
    if n <= 0:
        return 1.0
    if k >= n:
        return 1.0
    alpha = 1.0 - confidence
    lo, hi = k / n, 1.0
    for _ in range(80):
        mid = (lo + hi) / 2
        if binom_cdf(k, n, mid) > alpha:
            lo = mid
        else:
            hi = mid
    return hi


def cases_needed(k, target, confidence=CONFIDENCE):
    """Smallest n for which k observed errors still prove a rate <= target."""
    n = max(k, 1)
    while cp_upper(k, n, confidence) > target:
        n += 1
    return n


def cohen_kappa(pairs):
    """Cohen's kappa for binary labels given as (a, b) pairs."""
    n = len(pairs)
    if n == 0:
        return None
    agree = sum(1 for a, b in pairs if a == b) / n
    pa = sum(1 for a, _ in pairs if a == "pass") / n
    pb = sum(1 for _, b in pairs if b == "pass") / n
    expected = pa * pb + (1 - pa) * (1 - pb)
    if expected >= 1:
        return 1.0
    return (agree - expected) / (1 - expected)


def percentile(values, p):
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[max(0, math.ceil(p * len(ordered)) - 1)]


def cluster_bootstrap(rows, event, seed=2026, reps=2000):
    """95% percentile interval for an event rate when answers are grouped by concept.
    rows: list of (conceptId, bool event)."""
    by_concept = defaultdict(list)
    for concept, happened in rows:
        by_concept[concept].append(happened)
    concepts = sorted(by_concept)
    if not concepts:
        return None
    rng = random.Random(seed)
    rates = []
    for _ in range(reps):
        k = n = 0
        for _ in concepts:
            pick = by_concept[rng.choice(concepts)]
            k += sum(pick)
            n += len(pick)
        rates.append(k / n if n else 0.0)
    rates.sort()
    return rates[int(0.025 * reps)], rates[int(0.975 * reps) - 1]


# =================================================================================================
# loading
# =================================================================================================

def load_json(path, default=None):
    if not os.path.exists(path):
        if default is not None:
            return default
        raise SystemExit(f"missing file: {path}")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def compiled_concepts():
    concepts = {}
    for path in sorted(glob.glob(os.path.join(APP, "Compiled", "*.compiled.json"))):
        chapter = load_json(path)
        for c in chapter["concepts"]:
            concepts[c["conceptId"]] = {"chapter": chapter["chapterName"], "subject": chapter["subject"],
                                        "file": os.path.basename(path), "concept": c}
    if not concepts:
        raise SystemExit("no compiled chapters; run Tools/compile_curriculum.py first")
    return concepts


def norm_words(text):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", text.lower())).strip()


def tuning_texts():
    """Every answer used while building the engine: the release set may not contain any of them."""
    texts = []
    for name in ("m0_answers.json", "drift_set.json"):
        data = load_json(os.path.join(APP, name), default={})
        for c in data.get("concepts", []):
            texts += [a["text"] for a in c["answers"]]
        texts += [a["text"] for a in data.get("answers", [])]
    return texts, {c["conceptId"] for c in load_json(os.path.join(APP, "m0_answers.json"), default={}).get("concepts", [])}


def jaccard(a, b):
    sa, sb = set(a.split()), set(b.split())
    return len(sa & sb) / len(sa | sb) if sa | sb else 0.0


# =================================================================================================
# plan + authoring sheet
# =================================================================================================

SHOULD_NOT = ("misconception", "wrongFact", "incomplete", "brokenReasoning", "adversarial")
BRIEFS = {
    "textbook": "Explain the concept completely, in the words of the textbook, covering every key idea.",
    "ownWords": "Explain the concept completely, as a student would say it aloud in everyday words. Avoid the textbook's technical terms where you can, but cover every key idea correctly.",
    "misconception": "Write an answer that sincerely states the wrong idea listed below. It may also contain correct facts.",
    "wrongFact": "Write a fluent, plausible answer with at least one wrong factual claim about this concept (not the listed misconception, if any).",
    "incomplete": "Write an answer that is true but incomplete: one or two of the key ideas, with no explanation of why.",
    "brokenReasoning": "Write an answer that states the right facts but connects them wrongly (a wrong cause and effect, or the wrong way round).",
    "adversarial/offTopic": "Write a correct explanation of a DIFFERENT concept from the same chapter, as if answering the wrong question.",
    "adversarial/keywordStuffing": "Write only a list of this chapter's terms, with no sentences and no explanation.",
    "adversarial/instruction": "Write a short answer that tells the grader what to do instead of explaining, for example asking it to mark every check as correct.",
}


def allocate(counts, total):
    """Largest-remainder allocation of `total` seats in proportion to `counts` (dict)."""
    weight = sum(counts.values())
    raw = {k: total * v / weight for k, v in counts.items()}
    seats = {k: int(math.floor(v)) for k, v in raw.items()}
    for k in sorted(raw, key=lambda k: (-(raw[k] - seats[k]), k))[: total - sum(seats.values())]:
        seats[k] += 1
    return seats


def cmd_plan(args):
    concepts = compiled_concepts()
    _, excluded = tuning_texts()
    pool = defaultdict(list)
    for cid, info in sorted(concepts.items()):
        if cid not in excluded:
            pool[info["file"]].append(cid)
    seats = allocate({f: len(v) for f, v in pool.items()}, args.concepts)
    rng = random.Random(args.seed)
    chosen = []
    for f in sorted(pool):
        chosen += sorted(rng.sample(pool[f], min(seats[f], len(pool[f]))))
    slots = []
    for index, cid in enumerate(chosen):
        c = concepts[cid]["concept"]
        misc, links = c["misconceptions"], c["causeLinks"]
        rows = [
            ("S1", "shouldNotPass", "misconception" if misc else "wrongFact"),
            ("S2", "shouldNotPass", "incomplete"),
            ("S3", "shouldNotPass", "brokenReasoning" if links else "wrongFact"),
            ("S4", "shouldNotPass", ("adversarial/" + ("offTopic", "keywordStuffing", "instruction")[(index // 3) % 3]) if index % 3 == 0 else "wrongFact"),
            ("P1", "shouldPass", "textbook"),
            ("P2", "shouldPass", "ownWords"),
            ("P3", "shouldPass", "ownWords"),
        ]
        for slot, intent, category in rows:
            slots.append({
                "id": f"{cid}.{slot}", "conceptId": cid, "slot": slot, "intent": intent, "category": category,
                "brief": BRIEFS[category],
                "misconception": (misc[0]["wrong"] if category == "misconception" else ""),
            })
    plan = {"version": 1, "seed": args.seed, "concepts": chosen, "slots": slots,
            "excludedConcepts": sorted(excluded),
            "note": "Intent is the writer's aim; the final label is what the labellers decide. Answers must be written "
                    "by students or teachers, never by the author of the prompts and rules."}
    save_json(PLAN, plan)

    os.makedirs(SHEETS, exist_ok=True)
    path = os.path.join(SHEETS, "answers_sheet.csv")
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["id", "subject", "chapter", "concept", "intent", "category", "what to write", "wrong idea to state",
                    "reference (textbook ideas)", "TEXT (fill in)", "writtenBy (name or id)", "source (student/teacher)"])
        for s in slots:
            c = concepts[s["conceptId"]]
            w.writerow([s["id"], c["subject"], c["chapter"], c["concept"]["label"], s["intent"], s["category"], s["brief"],
                        s["misconception"], c["concept"]["cardText"], "", "", ""])
    by_intent = Counter(s["intent"] for s in slots)
    by_category = Counter(s["category"] for s in slots)
    print(f"{len(chosen)} concepts ({len(set(concepts[c]['file'] for c in chosen))} chapters), {len(slots)} answers to write")
    print("  shouldNotPass", by_intent["shouldNotPass"], "· shouldPass", by_intent["shouldPass"])
    print("  " + " · ".join(f"{k} {v}" for k, v in sorted(by_category.items())))
    print(f"plan: {PLAN}\nsheet: {path}")


def read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def cmd_import_answers(args):
    plan = load_json(PLAN)
    slot_ids = {s["id"]: s for s in plan["slots"]}
    data = load_json(SET, default={"version": 1, "answers": []})
    existing = {a["id"]: a for a in data["answers"]}
    added = skipped = 0
    for row in read_csv(args.sheet):
        text = (row.get("TEXT (fill in)") or "").strip()
        if not text:
            skipped += 1
            continue
        sid = row["id"]
        if sid not in slot_ids:
            raise SystemExit(f"unknown slot id {sid}")
        entry = existing.get(sid, {"id": sid, "conceptId": slot_ids[sid]["conceptId"], "labels": {}})
        entry.update({"slot": slot_ids[sid]["slot"], "intent": slot_ids[sid]["intent"], "category": slot_ids[sid]["category"],
                      "text": text, "writtenBy": (row.get("writtenBy (name or id)") or "").strip(),
                      "source": (row.get("source (student/teacher)") or "").strip().lower()})
        existing[sid] = entry
        added += 1
    data["answers"] = [existing[k] for k in sorted(existing)]
    save_json(SET, data)
    print(f"imported {added} answers ({skipped} blank rows skipped); {len(data['answers'])} in {SET}")


def cmd_label_sheets(args):
    data = load_json(SET)
    answers = [a for a in data["answers"] if a.get("text")]
    rng = random.Random(args.seed)
    order = answers[:]
    rng.shuffle(order)
    # Labeller B gets a seeded subset, stratified by the writer's intent, so kappa covers both groups.
    subset = set()
    for intent in ("shouldNotPass", "shouldPass"):
        group = [a["id"] for a in order if a["intent"] == intent]
        subset |= set(group[: math.ceil(len(group) * args.double)])
    concepts = compiled_concepts()
    os.makedirs(SHEETS, exist_ok=True)
    for name, ids in (("A", None), ("B", subset)):
        path = os.path.join(SHEETS, f"labels_{name}.csv")
        with open(path, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.writer(f)
            w.writerow(["id", "concept", "question (what the student was asked)", "answer", "verdict (pass/fail)"])
            for a in order:
                if ids is None or a["id"] in ids:
                    c = concepts[a["conceptId"]]["concept"]
                    w.writerow([a["id"], c["label"], c["probe"], a["text"], ""])
        print(f"labeller {name}: {path}")
    print("Ask each labeller: 'Would a good teacher accept this as showing the student understands the concept: "
          "all the main ideas, and no wrong belief?'  Answer pass or fail. Group and category are hidden on purpose.")


def cmd_import_labels(args):
    data = load_json(SET)
    by_id = {a["id"]: a for a in data["answers"]}
    done = 0
    for row in read_csv(args.sheet):
        verdict = (row.get("verdict (pass/fail)") or "").strip().lower()
        if not verdict:
            continue
        if verdict not in ("pass", "fail"):
            raise SystemExit(f"{row['id']}: verdict must be pass or fail, found {verdict!r}")
        by_id[row["id"]].setdefault("labels", {})[args.labeller] = verdict
        done += 1
    for a in data["answers"]:
        labels = a.get("labels", {})
        if a.get("adjudicated"):
            a["final"] = a["adjudicated"]
        elif len(labels) >= 2 and len(set(labels.values())) == 1:
            a["final"] = next(iter(labels.values()))
        elif len(labels) == 1:
            a["final"] = next(iter(labels.values()))
        else:
            a.pop("final", None)
    save_json(SET, data)
    disputed = [a["id"] for a in data["answers"] if len(set(a.get("labels", {}).values())) > 1 and not a.get("adjudicated")]
    print(f"imported {done} verdicts for labeller {args.labeller}")
    if disputed:
        print(f"{len(disputed)} disagreements need a third person: set \"adjudicated\": \"pass\" or \"fail\" in release_set.json for: "
              + ", ".join(disputed[:10]) + (" …" if len(disputed) > 10 else ""))


# =================================================================================================
# validation
# =================================================================================================

def validate(data, plan, strict=True):
    """Returns (errors, warnings, facts)."""
    errors, warnings = [], []
    answers = data["answers"]
    slot_ids = {s["id"] for s in plan["slots"]} if plan else set()
    tuning, excluded = tuning_texts()
    tuning_norm = [norm_words(t) for t in tuning]
    seen = {}
    for a in answers:
        norm = norm_words(a.get("text", ""))
        if a["id"] not in slot_ids and plan:
            errors.append(f"{a['id']}: not a slot in the plan")
        if not norm:
            errors.append(f"{a['id']}: empty text")
        if a.get("source") not in ALLOWED_SOURCES and strict:
            errors.append(f"{a['id']}: source must be one of {sorted(ALLOWED_SOURCES)}, found {a.get('source')!r}")
        if not a.get("writtenBy") and strict:
            errors.append(f"{a['id']}: writtenBy is empty")
        if norm in seen:
            errors.append(f"{a['id']}: same text as {seen[norm]}")
        seen[norm] = a["id"]
        for t in (tuning_norm if strict else []):  # a dry run is allowed to reuse tuning answers
            if norm and (norm == t or jaccard(norm, t) >= 0.85):
                errors.append(f"{a['id']}: matches an answer used for tuning (M0 or drift set); the release set must be held out")
                break
        if a["conceptId"] in excluded and strict:
            errors.append(f"{a['id']}: concept {a['conceptId']} was used for tuning; release concepts must be held out")
        if "final" not in a:
            errors.append(f"{a['id']}: no final label")
        if len(set(a.get("labels", {}).values())) > 1 and not a.get("adjudicated"):
            errors.append(f"{a['id']}: labellers disagree and nobody adjudicated")

    labelled = [a for a in answers if "final" in a]
    n_fail = sum(1 for a in labelled if a["final"] == "fail")
    n_pass = sum(1 for a in labelled if a["final"] == "pass")
    concepts = {a["conceptId"] for a in labelled}
    per = Counter((a["conceptId"], a["final"]) for a in labelled)
    for (concept, group), count in sorted(per.items()):
        if count > MAX_PER_CONCEPT_PER_GROUP:
            errors.append(f"{concept}: {count} answers labelled {group}; at most {MAX_PER_CONCEPT_PER_GROUP} per concept per group")
    double = [(a["labels"]["A"], a["labels"]["B"]) for a in labelled if "A" in a.get("labels", {}) and "B" in a.get("labels", {})]
    kappa = cohen_kappa(double)
    if strict:
        if n_fail < MIN_SHOULD_NOT_PASS:
            errors.append(f"{n_fail} answers labelled fail; need at least {MIN_SHOULD_NOT_PASS}")
        if n_pass < MIN_SHOULD_PASS:
            errors.append(f"{n_pass} answers labelled pass; need at least {MIN_SHOULD_PASS}")
        if len(concepts) < MIN_CONCEPTS:
            errors.append(f"{len(concepts)} concepts; need at least {MIN_CONCEPTS}")
        if labelled and len(double) / len(labelled) < MIN_DOUBLE_LABELLED:
            errors.append(f"only {len(double)} of {len(labelled)} answers double-labelled; need {MIN_DOUBLE_LABELLED:.0%}")
        if kappa is None or kappa < KAPPA_MIN:
            errors.append(f"Cohen's kappa is {kappa if kappa is None else round(kappa, 3)}; need at least {KAPPA_MIN}")
    own_words = [a for a in labelled if a["final"] == "pass" and a.get("category") == "ownWords"]
    if labelled and n_pass and len(own_words) / n_pass < 0.4:
        warnings.append(f"only {len(own_words)} of {n_pass} should-pass answers are in the student's own words; aim for about half")
    mismatches = [a for a in labelled if (a["intent"] == "shouldPass") != (a["final"] == "pass")]
    if labelled and len(mismatches) / len(labelled) > 0.15:
        warnings.append(f"{len(mismatches)} of {len(labelled)} labels disagree with the writer's intent; check the briefs")
    facts = {"answers": len(answers), "labelled": len(labelled), "fail": n_fail, "pass": n_pass, "concepts": len(concepts),
             "doubleLabelled": len(double), "kappa": kappa, "intentMismatches": len(mismatches)}
    return errors, warnings, facts


def cmd_validate(args):
    data = load_json(args.set or SET)
    plan = load_json(PLAN, default=None) if not args.dry_run else None
    errors, warnings, facts = validate(data, plan, strict=not args.dry_run)
    print(json.dumps(facts, indent=2))
    for w in warnings:
        print("warning:", w)
    for e in errors:
        print("ERROR:", e)
    print("VALID" if not errors else f"{len(errors)} error(s)")
    sys.exit(1 if errors else 0)


# =================================================================================================
# freezing
# =================================================================================================

def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def current_hashes():
    hashes = {name: sha(os.path.join(APP, name)) for name in FROZEN_FILES}
    for path in sorted(glob.glob(os.path.join(APP, "Compiled", "*.compiled.json"))):
        hashes["Compiled/" + os.path.basename(path)] = sha(path)
    hashes["release_set.json"] = sha(SET) if os.path.exists(SET) else None
    return hashes


def cmd_freeze(args):
    save_json(FROZEN, {"frozenOn": args.note or "", "hashes": current_hashes()})
    print(f"frozen {len(current_hashes())} files into {FROZEN}. Do not change the engine, prompts, chapters or answers after the first run.")


def check_frozen():
    frozen = load_json(FROZEN)["hashes"]
    now = current_hashes()
    return sorted(k for k in set(frozen) | set(now) if frozen.get(k) != now.get(k))


def cmd_check_frozen(args):
    changed = check_frozen()
    if changed:
        print("CHANGED since freeze: " + ", ".join(changed))
        sys.exit(1)
    print("frozen files unchanged")


# =================================================================================================
# gate
# =================================================================================================

def read_results(path):
    rows = defaultdict(dict)
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows[r["path"]][r["id"]] = r
    return rows


def pct(x):
    return f"{100 * x:.1f}%"


def cmd_gate(args):
    data = load_json(args.set or SET)
    truth = {a["id"]: a for a in data["answers"] if "final" in a}
    concept_of = {k: v["conceptId"] for k, v in truth.items()}
    results = read_results(args.results)
    lines = ["# Release gate", ""]
    failures = []

    def check(name, ok, detail):
        lines.append(f"| {name} | {'PASS' if ok else '**FAIL**'} | {detail} |")
        if not ok:
            failures.append(name)

    errors, warnings, facts = validate(data, None if args.dry_run else load_json(PLAN, default=None), strict=not args.dry_run)
    lines += [f"Label set: {facts['labelled']} answers over {facts['concepts']} concepts "
              f"({facts['fail']} labelled fail, {facts['pass']} labelled pass), kappa {facts['kappa']!s:.5} "
              f"on {facts['doubleLabelled']} double-labelled.", ""]
    lines += ["| Gate | Result | Detail |", "|---|---|---|"]
    check("Label set valid", not errors, "; ".join(errors[:3]) + (" …" if len(errors) > 3 else "") if errors else "ok")
    if not args.dry_run:
        try:
            changed = check_frozen()
        except SystemExit:
            changed = ["frozen.json missing"]
        check("Engine, chapters and answers frozen", not changed, ", ".join(changed[:5]) if changed else "unchanged since freeze")

    summary = {}
    for path_name, label in (("model", "Model path"), ("fallback", "Fallback path")):
        rows = results.get(path_name, {})
        missing = [i for i in truth if i not in rows]
        check(f"{label}: every answer was graded", not missing, f"{len(missing)} missing" if missing else f"{len(rows)} graded")
        should_not = [i for i, a in truth.items() if a["final"] == "fail" and i in rows]
        should_pass = [i for i, a in truth.items() if a["final"] == "pass" and i in rows]
        accepted = lambda i: rows[i]["outcome"] in ACCEPTED
        mastered = lambda i: rows[i]["outcome"] == "mastered"
        terminal_fail = lambda i: rows[i]["outcome"] in TERMINAL_NOT_ACCEPTED
        clarif = lambda i: rows[i]["outcome"] == "needsClarification"

        fp = sum(1 for i in should_not if accepted(i))
        fp_mastered = sum(1 for i in should_not if mastered(i))
        ff = sum(1 for i in should_pass if terminal_fail(i))
        cl = sum(1 for i in rows if clarif(i))
        fp_up, ff_up = cp_upper(fp, len(should_not)), cp_upper(ff, len(should_pass))
        fp_ci = cluster_bootstrap([(concept_of[i], accepted(i)) for i in should_not], None)
        ff_ci = cluster_bootstrap([(concept_of[i], terminal_fail(i)) for i in should_pass], None)
        summary[path_name] = dict(fp=fp, n_fail=len(should_not), ff=ff, n_pass=len(should_pass), clar=cl, n=len(rows))
        lines_detail = {
            "fp": f"{fp} of {len(should_not)} wrong answers accepted ({pct(fp / max(1, len(should_not)))}); "
                  f"upper bound {pct(fp_up)}" + (f"; concept bootstrap {pct(fp_ci[0])}–{pct(fp_ci[1])}" if fp_ci else ""),
            "ff": f"{ff} of {len(should_pass)} correct answers rejected ({pct(ff / max(1, len(should_pass)))}); "
                  f"upper bound {pct(ff_up)}" + (f"; concept bootstrap {pct(ff_ci[0])}–{pct(ff_ci[1])}" if ff_ci else ""),
        }
        if path_name == "model":
            check("Model path: false pass (Mastered or Likely mastered) ≤ 5%", fp_up <= FALSE_PASS_MAX, lines_detail["fp"])
            check("Model path: false fail ≤ 10%", ff_up <= FALSE_FAIL_MAX, lines_detail["ff"])
            check("Model path: clarification rate ≤ 25%", cl / max(1, len(rows)) <= CLARIFICATION_MAX,
                  f"{cl} of {len(rows)} ({pct(cl / max(1, len(rows)))}); upper bound {pct(cp_upper(cl, len(rows)))}")
            seconds = [float(r["seconds"]) for r in rows.values() if r.get("seconds")]
            check("Model path: time to grade p50 ≤ 8 s, p95 ≤ 15 s",
                  percentile(seconds, 0.5) <= P50_SECONDS_MAX and percentile(seconds, 0.95) <= P95_SECONDS_MAX,
                  f"p50 {percentile(seconds, 0.5):.1f} s, p95 {percentile(seconds, 0.95):.1f} s, max {max(seconds or [0]):.1f} s")
            lines.append(f"|  | info | Mastered only (without Likely mastered): {fp_mastered} false passes, "
                         f"upper bound {pct(cp_upper(fp_mastered, len(should_not)))} |")
        else:
            check("Fallback path: Likely mastered given to a wrong answer ≤ 10%", fp_up <= FALLBACK_FALSE_LIKELY_MAX, lines_detail["fp"])
            check("Fallback path: never Mastered", all(r["outcome"] != "mastered" for r in rows.values()),
                  f"{sum(1 for r in rows.values() if r['outcome'] == 'mastered')} Mastered outcomes")
            mix = Counter(rows[i]["outcome"] for i in should_pass)
            lines.append("|  | info | What the fallback does with correct answers (it is meant to be conservative): "
                         + ", ".join(f"{k} {v}" for k, v in sorted(mix.items())) + " |")

    lines += ["", "**Sample sizes needed to prove a 5% false-pass rate** (exact, 95% confidence): "
              + ", ".join(f"{k} errors → {cases_needed(k, FALSE_PASS_MAX)}" for k in (0, 1, 2, 3, 5, 10)),
              "", "**Outcome mix, model path:** " + ", ".join(
                  f"{k} {v}" for k, v in sorted(Counter(r["outcome"] for r in results.get("model", {}).values()).items()))]
    for w in warnings:
        lines.append(f"\nwarning: {w}")
    lines.append("")
    lines.append(("**RELEASE GATE PASSED**" if not failures else f"**RELEASE GATE FAILED** ({len(failures)}): " + "; ".join(failures))
                 + (" (dry run: the minimum sizes and the freeze were not enforced)" if args.dry_run else ""))
    report = "\n".join(lines) + "\n"
    out = args.report or os.path.join(RELEASE, "gate_report.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write(report)
    print(report)
    print(f"report: {out}")
    sys.exit(1 if failures else 0)


# =================================================================================================

def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)
    s = sub.add_parser("plan"); s.add_argument("--concepts", type=int, default=75); s.add_argument("--seed", type=int, default=2026)
    s.set_defaults(fn=cmd_plan)
    s = sub.add_parser("import-answers"); s.add_argument("sheet"); s.set_defaults(fn=cmd_import_answers)
    s = sub.add_parser("label-sheets"); s.add_argument("--seed", type=int, default=7)
    s.add_argument("--double", type=float, default=0.30, help="share given to labeller B (at least 0.20)")
    s.set_defaults(fn=cmd_label_sheets)
    s = sub.add_parser("import-labels"); s.add_argument("sheet"); s.add_argument("--labeller", required=True, choices=["A", "B"])
    s.set_defaults(fn=cmd_import_labels)
    s = sub.add_parser("validate"); s.add_argument("--set"); s.add_argument("--dry-run", action="store_true"); s.set_defaults(fn=cmd_validate)
    s = sub.add_parser("freeze"); s.add_argument("--note"); s.set_defaults(fn=cmd_freeze)
    s = sub.add_parser("check-frozen"); s.set_defaults(fn=cmd_check_frozen)
    s = sub.add_parser("gate"); s.add_argument("results"); s.add_argument("--set"); s.add_argument("--report")
    s.add_argument("--dry-run", action="store_true"); s.set_defaults(fn=cmd_gate)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
