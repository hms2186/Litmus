# Curriculum

This folder holds the build step that turns the hand-written chapters (`Litmus/ncert_*.json`) into checked, compiled chapters for the grading engine. It is Milestone 1 of architecture version 4.0.

## Folder contents

| Path | What it is |
|---|---|
| `../Tools/compile_curriculum.py` | The compiler, migrator and source detector. Run it with `python3 -I` from anywhere |
| `followups/*.tsv` | **Where follow-up questions are written.** Each line is `keyPointId<TAB>question`. Wrap a word in `[[ ]]` when the question has to name it, such as a case-study name, a date, or the term being asked about |
| `pdf_text/` | Text extracted from the NCERT PDFs (Reprint 2026-27), used to check every quote |
| `pdf_sources.json` | Which PDF and page offset each chapter uses |
| `../Litmus/Compiled/` | The output: one `*.compiled.json` per chapter. It's inside the app folder, so it ships in the app bundle, and the app loads it from there |
| `review_report.html` | Everything that needs a person to check it |

## Day-to-day use

To edit a chapter or a follow-up:

```bash
python3 -I Tools/compile_curriculum.py migrate --mirror
python3 -I Tools/compile_curriculum.py
```

- `migrate` applies the follow-up TSVs and fills in any v4.1 fields that are missing. It never overwrites a role or lexical value someone has set. `--mirror` copies the chapters to `~/Desktop/JSON NCERT`.
- `compile` checks everything. If it finds any error, it writes no compiled files. Use `--release` before shipping: it also fails while any chapter's review is still `pending`.

## Engine tests (Milestone 2)

```bash
Tools/run_engine_tests.sh
```

This compiles the app's own `RuleEngine.swift` and `CompiledCurriculum.swift` with [Tools/EngineTests/main.swift](../Tools/EngineTests/main.swift), then runs the tests against `Litmus/Compiled/`. Run it after compiling the curriculum and after any engine change. It takes about a minute.

It checks:
- golden scenarios;
- every combination of check results for concepts with up to 9 checks, and 20,000 seeded samples for larger ones, against invariants I1, I2, I3, I5 and I7;
- that every outcome is reachable for every concept (I6);
- 100,000 random follow-up merges (I4).

## Grader tests (Milestone 3)

```bash
Tools/run_grader_tests.sh
Tools/run_grader_tests.sh --live
```

This compiles the app's grading files (`Graders.swift`, `GradingCoordinator.swift`, `RuleEngine.swift` and `CompiledCurriculum.swift`) with [Tools/GraderTests/main.swift](../Tools/GraderTests/main.swift).

A fixture transport scripts the model's replies, so each failure mode runs through the real prompts, parsing, fallbacks, second try, quote check and rules:
- invented IDs, missing IDs, non-boolean values and empty replies;
- timeouts, the total time budget running out, and guardrail refusals;
- invented quotes, quotes copied from the criterion, and quote checks that run out of time;
- misconception quotes that are genuine but don't state the misconception;
- mastery quotes that are genuine but don't state the check, even with the sentences around them, and quotes that do state it once those sentences are read with them (`confirmContextSentences`, default 1);
- the model being unavailable, and keyword stuffing;
- replies keyed by "criterion" or "criterion_1" instead of the IDs (read when unambiguous, otherwise left out and asked again with a format reminder);
- a refused or unusable batch (each check is then graded on its own before the keyword fallback);
- a quote request that answers NONE for one check of a batch (asked again alone);
- a model "no" that blocks mastery (asked again alone in lenient wording; it is overturned only by a genuine quote that, read with its neighbouring sentences, states the check; at most 3 checks, never for keyword lists, switch `recheckNoResults`);
- the optional misconception rule-out being skipped when less than a quarter of the time budget is left;
- correction retries and contradictions in follow-ups.

`--live` also grades four Milestone 0 answers with the real on-device model, without assertions.

## App-flow tests (Milestone 4)

```bash
Tools/run_app_flow_tests.sh
```

These check:
- the compiled-chapter store, including refusing unsupported or unreadable files;
- Phase 2 answer sorting;
- every attempt-state transition;
- SwiftData progress, using an in-memory store, saved only as `EvaluationOutcome` allows;
- whole journeys driven the way `FeedbackViewModel` drives them.

**In the app**
- Topics from compiled chapters use the engine and `EngineFeedbackView`. All other topics keep the legacy path.
- **Testing launch arguments:** `-subject "Social Science" -branch Economics -chapter "Money" -topic "Money as a Medium" -typed "<answer>"` selects a topic and submits a typed answer.
- **Debug builds** print one `🧪 [Engine]` console line per grading, with the outcome, calls, time, failed batches and trace.

**Simulator limitation:** the iOS Simulator reports the model as available, but its calls fail in Apple's safety layer (`SensitiveContentAnalysisML`). So in the Simulator, grading always falls back to keywords. The real model has to be tested on an iPad.

## Background work (Milestone 5)

```bash
Tools/run_maintenance_tests.sh
Tools/run_drift_baseline.sh
```

- `run_maintenance_tests.sh` checks the re-grade, the cleanup, review cards and the drift check.
- `run_drift_baseline.sh` re-measures the drift baseline with the real model. Run it after changing `Litmus/drift_set.json`, the prompts or the compiled chapters.

**Re-grade of Likely mastered answers.** This runs when the app becomes active, and as a background processing task while the iPad is charging.
- Only checks that are uncertain or came from the keyword fallback go back to the model.
- **Mastered:** upgraded quietly, and the transcript is deleted.
- **A problem found:** the result becomes a review card with the student's own words, shown before the next attempt. Dismissing the card deletes the transcript.
- **Still Likely mastered:** tried again only after the OS build changes.

**30-day cleanup and concept changes.** A provisional record older than 30 days, or whose concept hash, schema or evaluator version no longer matches, is deleted. The concept then becomes a live revisit question.

**Drift check.** After each OS build change, the 30 labelled answers in `drift_set.json` are graded with pass 1.
- **Pass:** agreement of at least 95% of the shipped baseline. The current baseline is 0.8976 over 254 checks, measured on a Mac running macOS 27.0.1.
- **Until it passes on the current build:** grading is provisional-only, and re-grades wait.
- **Inconclusive:** a run in which more than half the batches fail records nothing. The iOS Simulator always does this.
- Its model calls wait while a student's answer is being graded.

**Speech.**
- The recognizer is primed with the topic's evidence phrases and chapter terms (`contextualStrings`, at most 100).
- It recognises on the device when it can, preferring en-IN, then en-US.
- Punctuation is added automatically.
- The mean confidence of final results feeds the "unintelligible" re-prompt.

**Debug aid:** `-seedReviewCard` adds a sample review card for the selected topic.

## What the compiler checks

**Structure**
- passRules are valid;
- every misconception is linked to a keyPoint;
- every keyPoint has a verify quote;
- IDs are unique across all chapters, and concept labels are unique.

**v4.1 fields**
- every concept has a core keyPoint, and its core weight is above 0;
- `role` and `lexical` have valid values.

**Quotes**
- every verify quote must appear on the printed page it cites.

**Follow-up leaks**
- a follow-up may not contain an answer phrase. An answer phrase is a `requiredEvidence` phrase that isn't already in the concept's label or probe, or marked with `[[ ]]`.

## Reviewing the v4.1 suggestions

Each chapter has a `review` block with `"status": "pending"`. To approve a chapter:
1. Open `review_report.html`.
2. Check each concept's roles, follow-up questions and keyword-gradable checks.
3. Fix anything wrong: roles and `lexical` in the chapter JSON, follow-ups in the TSV.
4. Set `review.status` to `"approved"` and fill in `reviewedBy` and `reviewedOn`.

**How the suggestions were made**

| Field | Rule |
|---|---|
| Role | Weight 2 or more is `core`; weight 1 is `supporting`. A concept with no weight-2 keyPoint has its heaviest keyPoint promoted to `core` |
| `lexical: evidence` | Only "Names / Mentions / Gives an example / Uses the term" checks whose evidence is a specific name or number that the check itself mentions (78 of 755 checks) |
| Follow-ups | Written by Claude for all 373 core keyPoints |

## Things compiled files settle

- The model prompts live in the Swift engine, not in the compiled files. Milestone 0 showed that prompts change often, and they shouldn't need a recompile. This differs from the v4.0 plan.
- `conceptHash` covers only what affects grading: keyPoints, checks, rules, roles, links and misconceptions. Editing a follow-up or the card text doesn't change it, so saved Likely mastered answers stay valid.
- Batches follow the Milestone 0 decisions:
  - a **topic** batch with relevance and the misconception checks;
  - group **A** with the core keyPoint checks;
  - group **B** with supporting checks and causeLinks;
  - at most 6 checks per batch.
