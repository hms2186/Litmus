# How Litmus's AI works, and what each file does

This replaces the outdated `LLM_EXPLAINER_PROMPT.md`. It describes the app as built, including what the AI is
allowed to do and what it is not.

## The idea in one paragraph

A student explains a topic in their own words (spoken or typed). Litmus does **not** ask the on-device language model
"is this answer good?". It breaks the topic into a short list of small yes/no checks that come from the NCERT
chapter text, asks the model each check one at a time, asks it to **copy the exact words** from the student's answer as
proof, and then lets plain, deterministic code decide the result. The model is a reader. The decision is made by rules
you can read and test.

## Why it is built this way

- A language model can sound sure and be wrong. Apple's own guidance for generative AI says small input changes
  can change the output, and that hallucination risk should be limited by scoping what the model is asked
  (Human Interface Guidelines, Generative AI).
- So the model is only asked narrow questions, never to invent facts, and every "yes" has to be backed by words the student
  actually said.
- Everything runs on the device with Apple's Foundation Models framework. Nothing the student says leaves the iPad.
- If the model is unavailable, a non-AI fallback (keyword and phrase matching) still works, and it never gives the top
  result (see "What the result can be").

## The journey of one answer

1. **Speech or typing.** Spoken answers use Apple's `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26), with the
   chapter's own terms passed as hints so words like "proto-industrialisation" are heard correctly. Typed text is used
   exactly as typed.
2. **Clean-up (speech only).** `TranscriptCleaner` fixes near-miss words to the chapter's vocabulary ("reactant ko" is
   not changed into something else; only close misspellings of real chapter words are snapped).
3. **Sorting.** `AnswerSorter` decides if this is gradable at all: empty, too short, "I don't know", off topic, etc.
   Those get a friendly prompt, not a grade.
4. **Checks.** `GradingCoordinator` runs the topic's checks against the on-device model in small batches, with time
   limits so a slow model cannot freeze the screen.
5. **Proof.** For every "yes", the model must quote the student's own words. If the quote is not really in the answer,
   or the sentence has no verb (just a list of terms), the "yes" is thrown out.
6. **Guards (plain code).** A list of keywords with no statements ("reactants, products, coefficients...") is
   detected and cannot pass, however the model answered.
7. **Evidence support.** If the model said "no" but the student clearly stated the textbook phrase in a real sentence,
   `RubricMatrix` can lift it to a "yes", marked as *evidence-supported* (this can only reach "Likely mastered").
8. **Decision.** `RuleEngine` turns the check results into an outcome. No model involved.
9. **Feedback.** The review screen shows what was missing, vague and right, using the student's own quoted words.
10. **Saving.** `ProgressRecorder` stores the result per profile.

## What the result can be

| Result | Meaning |
| --- | --- |
| Mastered | Every core idea confirmed by the model with a verified quote (PARAKH "Advanced") |
| Likely mastered | Core ideas evidenced, but at least one only by the student's own words (PARAKH "Proficient") |
| Partial / Not yet | Some ideas stated, the core not yet (PARAKH "Basic") |
| Needs clarification / correction | Unclear, or a wrong idea was stated |
| Not gradable / Off topic | Not graded on its merits |

The mapping to the three PARAKH proficiency levels is this app's own, written down in `RubricMatrix.swift` so it can
be reviewed. PARAKH defines the levels, not a scoring recipe for spoken answers.

## What each file does

### Content (the source of truth)
- `Resources/Chapters/*.json` – the NCERT chapter content: topics, key points, textbook evidence phrases, cause
  links, common misconceptions. This is what the model is checked against. **The model's own knowledge is not used.**
- `Resources/Evaluation/*.json` – labelled example answers used to measure how well grading behaves.
- `Tools/compile_curriculum.py`, `dsl.py` – compile the chapter JSON into the app's fixed list of concepts (961) and
  freeze a hash of each so content cannot change silently.

### Grading (`Litmus/Grading`)
- `AttemptMachine.swift` – the small state machine: ready, grading, follow-up, finished.
- `GradingCoordinator.swift` – runs the whole pipeline above: batching, time limits, quote proofs, guards.
- `Graders.swift` – the three graders: `ModelGrader` (on-device model, with the system instructions),
  `LexicalGrader` (phrase matching), `CodeGrader` (rules like "is this a real sentence or a list of terms").
  The **system instructions** live here: each check gets the chapter, the topic, and the textbook passage, and is told
  to judge only what the student *said*.
- `RubricMatrix.swift` – PARAKH level mapping and evidence support.
- `RuleEngine.swift` – the final, deterministic decision.
- `TranscriptCleaner.swift` – snaps misheard speech to chapter vocabulary.
- `DriftCheck.swift` – re-tests the model on a fixed set after an OS update; until it passes, the best result is
  "Likely mastered".
- `AppMaintenance.swift` – background re-grade of saved answers and review cards.
- `FeynmanContracts.swift` – the shared data types.

### Screens and speech (`Litmus/Explain`)
- `FeedbackViewModel.swift` – connects the screen to the engine; pre-loads the model while the student is still choosing.
- `ExplainView.swift` – the Explain stage, the review screen, the session summary and the "Your Answer" sheet.
- `LiveSpeechRecorder.swift`, `VoiceEngineService.swift` – microphone and Apple speech recognition.
- `DebriefComposer.swift`, `FeedbackPhrasing.swift` – turn results into readable feedback.
- `HintsView.swift`, `ReviewCardView.swift` – hints (cost coins) and revisit cards.

### Testing
- `Tools/GraderTests` and the app-flow tests – run the engine without the app.
- `Tools/model_experiments` – run the real on-device model over labelled answers to measure it.

## What was measured (honestly)

- On 30 self-labelled answers: 24 correct, **0 false passes**.
- A keyword-only list scored 0 of 24 passes after the guards.
- The model's wording of borderline answers can change from run to run, and differs between the simulator, an iPad
  and a Mac. That is why the guards and the proof step exist, and why real student answers are still needed before
  claiming accuracy.

## What it will not do

- It will not pass a list of keywords.
- It will not use outside knowledge, the topic's name, or "what the student probably meant".
- It will not give the top result when the model is unavailable or has not passed the drift check.
- It never sends audio or answers off the device.
