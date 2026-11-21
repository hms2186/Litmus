# Official framework data

Extracted from the CBSE Learning Framework for Classes IX and X (CBSE with Azim Premji University, aligned to the NCERT
secondary-stage learning outcomes):

| File | Source | SHA-256 |
|---|---|---|
| Learning_Standards_Science.pdf | https://cbseacademic.nic.in/cbe/documents/Learning_Standards_Science.pdf | df4fcc0a81e59e564d2d92d5dc6110652758b3b90f60e893b91113b44e5e4ef4 |
| Learning_Standards_SocialScience.pdf | https://cbseacademic.nic.in/cbe/documents/Learning_Standards_SocialScience.pdf | 5fba5484b8549c0ea35942e2cd36a52dedcc84277e0a2b3d6aaf87e41d7b5499 |

| File | What it is |
|---|---|
| `cbse_learning_framework.json` | 76 chapters, their content-domain learning outcomes (CLO) and 1,307 indicators, each with a cognitive level |
| `cognitive_level_rules.json` | The verb rules that give an outcome or indicator its level (Knowing, Applying, Reasoning). The source states the levels but not one per indicator, so these are rules, not quotes |
| `concept_tags.json` | One entry per compiled concept (961): official chapter, up to 3 outcomes, up to 3 indicators, cognitive levels, a status and `reviewed: false` |

Rebuild with `Tools/official_framework/run.sh`.

## Status values
- `chapter-confirmed`: Class 10. The chapter matches the official one by name. Outcomes and indicators are proposed by similarity.
- `proposed` / `weak`: Class 9. The official chapters are for the previous books, so the chapter is proposed by similarity (>= 0.15, or 0.10 to 0.15).
- `unmapped`: nothing in the framework covers the topic (new 2025-26 book content).

On Class 10, similarity finds the right chapter 85.9% of the time (93% precision at the `proposed` threshold), which is the
accuracy to expect for Class 9 chapters. Outcome and indicator matching inside a chapter has no ground truth yet: a teacher must confirm it.

## Compiled chapters are not changed
`Litmus/Compiled/*.compiled.json` are frozen by the release gate and `conceptHash` covers everything that affects grading,
so tags live here, keyed by `conceptId`. They can be embedded at the next freeze.
