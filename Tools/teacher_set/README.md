# Teacher / colleague answer set (about 100 answers, written without seeing the grading rules)

Purpose: measure the grader on wording the developers did not write, with labels two people agree on. This is separate from
`stress_set.json`, `holdout_set.json` and the regression gate, and nothing here changes them.

## Rules that keep it honest
1. Authors and labellers never see grading criteria, accepted phrasings or test results. The worksheet shows only the NCERT card text.
2. The frozen set is run **once**. After the run, do not change grading rules, prompts or phrasings to fit it. If a rule change is
   wanted, make it from the tuned sets, then judge it on a *new* worksheet (`--seed` gives different concepts).
3. Two people label every answer independently (`labelA`, `labelB`). A third person settles disagreements in `final`.
4. Answers are written as a Class 9 or 10 student would say or type them, in their own words (the tool warns if 12+ words are copied).

## Steps
1. Make the worksheet (about 40 unseen concepts across subjects, without the rules):
   `python3 -I Tools/teacher_set/make_worksheet.py --concepts 40 --seed 11`
2. Authors fill `answers` in `Tools/teacher_set/worksheet.json` (shape in `answerTemplate`). Aim for 100+ answers, at least:
   40 `complete`, 20 `partial`, 20 `misconception`, 10 of `wrong_topic` / `keyword_list` / `vague`. At least two authors; mix typed and
   spoken style (`"spoken": true` for how a student talks). Labels:
   - `complete`: states every core idea of the concept correctly (this is the only label that should pass)
   - `partial`: correct but missing a core idea
   - `misconception`: states a wrong idea as true
   - `wrong_topic`: a good answer about a different concept
   - `keyword_list`: a list of terms with no explanation
   - `vague`: on topic but says nothing specific
3. A different person fills `labelA` and `labelB` (each blind to the other and to the author's intent), then:
   `python3 -I Tools/teacher_set/finalize_set.py Tools/teacher_set/worksheet.json`
   It reports labeller agreement (kappa), held-out disagreements, quota gaps and copied text, and freezes `teacher_set.json` with a `.sha256` lock.
4. Run it once: `Tools/teacher_set/run_teacher_set.sh` (needs Apple Intelligence). Keep the set inside the repo folder.
5. Record the numbers in `docs/MODEL_REPORT.md` as they are, including false passes, correct answers not passed, and the labeller kappa.

## How to read the result
- Hard gate: false passes must be 0 and keyword lists must not pass. Anything else is a bug to investigate.
- Recall (correct answers passed) is the figure to improve. Compare it with the hold-out set (4 of 20); a value near it means the
  weakness is real; a much higher value means the developer-written sets were unrepresentative.
- Low labeller agreement (kappa below about 0.6) means the labels, not the grader, are the problem: fix the label definitions first.
