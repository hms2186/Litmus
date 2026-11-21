# Content review: Geography Class 10, Chapter 1 criteria split

For the content owner. Two criteria that each asked for several separate facts were split so the main idea is required and the
extra detail is optional. This changes what counts as a complete answer, so it is a content decision, not only a technical one.

File changed: `Litmus/Resources/Chapters/ncert_Geography_10_ch1.json` (recompiled; only `Litmus/Compiled/ncert_Geography_10_ch1.compiled.json` changed).
Why: a correct answer that named the northern plains and the three rivers (alluvial) or described gully erosion (erosion) was
held back because the criterion also demanded a detail the student did not mention.

## 1. Alluvial Soils (`geo10_ch1_t6_c2`)

| | Check | Required | Criterion |
|---|---|---|---|
| Before | `chk_geo1_alluvial_where` | yes | States that alluvial soil covers the northern plains, deposited by the Indus, Ganga and Brahmaputra, **and is found in eastern coastal deltas (Mahanadi, Godavari, Krishna, Kaveri).** |
| After | `chk_geo1_alluvial_where` | yes | States that alluvial soil covers the northern plains and was deposited by the Indus, Ganga and Brahmaputra rivers. |
| After (new) | `chk_geo1_alluvial_deltas` | **no** | Adds that alluvial soil is also found in the eastern coastal deltas (Mahanadi, Godavari, Krishna, Kaveri). |

Effect: a student can now reach Likely mastered without mentioning the eastern deltas.

## 2. Soil Erosion (`geo10_ch1_t7_c1`)

| | Check | Required | Criterion |
|---|---|---|---|
| Before | `chk_geo1_gully_erosion` | yes | Explains gully erosion: running water cuts deep channels (gullies), making land unfit for cultivation (bad land), **called ravines in the Chambal basin.** |
| After | `chk_geo1_gully_erosion` | yes | Explains gully erosion: running water cuts deep channels (gullies), making land unfit for cultivation (bad land). |
| After (new) | `chk_geo1_gully_ravines` | **no** | Adds that gully-eroded bad land is called ravines in the Chambal basin. |

Effect: the Chambal ravines detail is no longer needed.

## Measured effect (developer-written answers, not real students)
- `allu_P` and `allu_S` (correct answers without the deltas) went from not passed to Likely mastered. Stress set 70/80 to 72/80.
- `ero_P` and `ero_S` still do not pass; their cause is elsewhere (the model's judgement of the gully check), so this split did not help erosion yet.
- False passes stayed 0 on every set; regression gate passed.

## Decisions for the reviewer
1. Is it acceptable that the eastern deltas and the Chambal ravines are optional for these concepts? If not, revert by restoring the two criteria above (the compiler regenerates the file).
2. `requiredEvidence` on both key points still lists the deltas, Mahanadi, ravines and Chambal. It never lifts a check by itself (`lexical` is `never`), but the grader falls back to those words when a quote proof times out, so it was left unchanged; remove those words if they should no longer be treated as expected evidence.
3. The concept hashes of these two concepts changed, so a saved Likely mastered answer for them is re-graded the next time it is opened.
