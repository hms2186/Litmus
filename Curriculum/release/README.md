# Release set and gate (Milestone 6)

The release set is the held-out, human-labelled answer set that decides whether the grading engine can ship. **It must not be written by the person who wrote the prompts and rules** (that is why the tools reject `source: claude`), and **it must never be used for tuning**.

## What has to be true to ship

| Gate | Limit | How it is judged |
|---|---|---|
| Wrong answers accepted (model path) | ≤ 5% | Upper end of the exact one-sided 95% Clopper–Pearson interval. "Accepted" means Mastered **or** Likely mastered |
| Correct answers rejected (model path) | ≤ 10% | Same method. Only final outcomes count; a follow-up question is not a rejection |
| Follow-up question rate (model path) | ≤ 25% | Point estimate (the interval is printed) |
| Time to grade (model path) | median ≤ 8 s, slowest 5% ≤ 15 s | Measured on this Mac. Repeat on the target iPad |
| Likely mastered given to a wrong answer (fallback path) | ≤ 10% | Upper bound. The fallback path must also never produce Mastered |
| Label quality | Cohen's κ ≥ 0.8 | At least 20% of answers labelled by two people independently; every disagreement settled by a third |
| Size and spread | ≥ 300 answers labelled fail, ≥ 200 labelled pass, ≥ 60 concepts, ≤ 5 answers per concept per group | Answers to one concept are not independent |
| Held out | none of the 10 tuning concepts, none of the answers in `m0_answers.json` or `drift_set.json` | Matched by text, including near-duplicates |
| Frozen | engine, prompts, chapters and answers unchanged since `freeze` | By SHA-256, so the thresholds cannot be tuned after seeing results |

With 59 wrong answers and no errors, 5% is provable. Each additional error needs more: 93, 124, 153, 208 and 336 answers for 1, 2, 3, 5 and 10 errors. The plan asks for 300 and 225 so that a few errors do not sink a good engine.

## Procedure

```bash
python3 -I Tools/release/release_gate.py plan                       # 75 concepts, 525 answers to write
```

1. **Authors write the answers.** Hand `sheets/answers_sheet.csv` to teachers or students. Each row says which concept, what kind of answer to write and, for misconceptions, which wrong idea to state. They fill `TEXT`, `writtenBy` and `source` (student or teacher). About two thirds of the correct answers are meant to be in everyday words.
2. **Import them.**
   ```bash
   python3 -I Tools/release/release_gate.py import-answers <filled sheet>.csv
   python3 -I Tools/release/release_gate.py label-sheets
   ```
3. **Label them.** Two people, independently. The sheets hide the writer's intent and the category, and ask: *would a good teacher accept this as showing the student understands the concept: all the main ideas, and no wrong belief?* Labeller A gets everything, labeller B a seeded 30%.
   ```bash
   python3 -I Tools/release/release_gate.py import-labels sheets/labels_A.csv --labeller A
   python3 -I Tools/release/release_gate.py import-labels sheets/labels_B.csv --labeller B
   ```
   A third person settles disagreements by adding `"adjudicated": "pass"` or `"fail"` to those answers in `release_set.json`.
4. **Check, freeze and run.**
   ```bash
   python3 -I Tools/release/release_gate.py validate
   python3 -I Tools/release/release_gate.py freeze --note "release candidate 1"
   Tools/run_release_eval.sh
   ```
   The run grades every answer on the **model path** (the real on-device model, about 5 s per answer) and on the **fallback path** (no model), then prints the gate report to `gate_report.md`. It resumes if interrupted.

If the gate fails, fix the engine, then **write a new release set** (or add fresh answers and relabel) before trying again. Reusing the same answers after changing the engine turns the release set into a tuning set.

## Dry run

`Tools/run_release_eval.sh --dry-run Tools/release/fixtures/dryrun_set.json` runs the whole pipeline on 50 Milestone 0 answers. Those were written by Claude and used for tuning, so a dry run checks the pipeline only. It skips the minimum sizes, the held-out checks and the freeze, and a small set cannot pass the gate anyway, because the exact bounds are too wide.

## Tests

`python3 -I -W ignore Tools/release/test_release_gate.py` covers the exact bounds (the 59 and 29 zero-error cases, the whole sample-size table), kappa, the validation rules, each gate decision, and the plan, sheet and label round trip.
