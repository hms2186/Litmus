# Experiment: chapter-aware grading instructions

Run on 2026-11-17, macOS 27.2.1, on-device model AFM 3 Core Advanced, the app's own `ModelGrader` and `GradingCoordinator`,
the 30 labelled answers in `drift_set.json` (10 Class 10 civics / economics / geography concepts, 254 checks).
Reproduce: `Tools/model_experiments/run.sh current,contextPermissive,chapter,chapterPassage,chapterOfficial,chapterAll,hybrid2`.

| Instruction variant | Agreement with labels | False yes | False no | Guardrail refusals |
|---|---|---|---|---|
| Today's app (default guardrails, no context) | 70.9% | 26 | 6 | 9 of 90 batches |
| Role line + permissive guardrails | 89.0% | 15 | 13 | 0 |
| + subject, class, chapter and topic from the chapter file | 88.6% | 13 | 16 | 0 |
| + the textbook passage | 90.6% | 6 | 18 | 0 |
| + official CBSE indicators and levels | 83.9% | 17 | 22 | 0 |
| passage + official indicators | 86.6% | 14 | 20 | 0 |
| **Passage for concept checks only, everything else as the role-line version (hybrid2)** | **91.7%** | 12 | **9** | 0 |

End to end through the coordinator (same outcome as the rule engine gives from the labels): today 18 of 30, role line +
permissive 23, passage everywhere 18, hybrid2 24.

Notes
- The replies from the longer instructions came back as `[{"ID": "x", "result": "true"}]`, which the app's parser drops.
  The numbers above normalise that shape (and allow more reply tokens) for every variant so judgement, not format, is compared.
  Without it the chapter variants scored 67.7% to 82.7%.
- The passage helps concept checks but, given to the misconception and relevance checks, lowers detection of a stated wrong idea
  (94.1% to 83.5%), so those keep the generic instructions.
- Official indicators in the prompt do not help; use them for reporting.
- Small set, variants chosen on it: treat differences of 1 to 2 points, or one end-to-end answer, as noise.
