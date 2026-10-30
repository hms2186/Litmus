# Release gate

Label set: 50 answers over 10 concepts (41 labelled fail, 9 labelled pass), kappa 1.0 on 50 double-labelled.

| Gate | Result | Detail |
|---|---|---|
| Label set valid | PASS | ok |
| Model path: every answer was graded | PASS | 50 graded |
| Model path: false pass (Mastered or Likely mastered) ≤ 5% | **FAIL** | 0 of 41 wrong answers accepted (0.0%); upper bound 7.0%; concept bootstrap 0.0%–0.0% |
| Model path: false fail ≤ 10% | **FAIL** | 0 of 9 correct answers rejected (0.0%); upper bound 28.3%; concept bootstrap 0.0%–0.0% |
| Model path: clarification rate ≤ 25% | PASS | 2 of 50 (4.0%); upper bound 12.1% |
| Model path: time to grade p50 ≤ 8 s, p95 ≤ 15 s | PASS | p50 6.6 s, p95 10.8 s, max 13.7 s |
|  | info | Mastered only (without Likely mastered): 0 false passes, upper bound 7.0% |
| Fallback path: every answer was graded | PASS | 50 graded |
| Fallback path: Likely mastered given to a wrong answer ≤ 10% | PASS | 0 of 41 wrong answers accepted (0.0%); upper bound 7.0%; concept bootstrap 0.0%–0.0% |
| Fallback path: never Mastered | PASS | 0 Mastered outcomes |
|  | info | What the fallback does with correct answers (it is meant to be conservative): needsClarification 9 |

**Sample sizes needed to prove a 5% false-pass rate** (exact, 95% confidence): 0 errors → 59, 1 errors → 93, 2 errors → 124, 3 errors → 153, 5 errors → 208, 10 errors → 336

**Outcome mix, model path:** likelyMastered 4, mastered 4, needsClarification 2, needsCorrection 3, notYet 19, offTopic 7, partial 11

warning: only 0 of 9 should-pass answers are in the student's own words; aim for about half

**RELEASE GATE FAILED** (2): Model path: false pass (Mastered or Likely mastered) ≤ 5%; Model path: false fail ≤ 10% (dry run: the minimum sizes and the freeze were not enforced)
