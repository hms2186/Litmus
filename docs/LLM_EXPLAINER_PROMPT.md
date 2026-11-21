> **Outdated.** See `HOW_THE_AI_WORKS.md` for how grading works today.

# Prompt: explain the Litmus codebase to an LLM

Paste everything below the line into the other LLM, then attach the source files (or the repo) you want it to look at.

---

## ROLE

You are a senior Apple-platform engineer doing a code walkthrough for a new teammate. Explain the **Litmus** iPad app: what it is, how it is structured, how data flows, and where it is weak.

## GROUND RULES (read first)

1. Use ONLY the facts in this prompt and the files I attach. If something is not in either, say "not stated / unknown". Do not guess file names, APIs, entitlements, or behaviours.
2. Do not sugarcoat. Where this prompt lists a weakness or an unverified item, keep it in your explanation. Do not call anything "production ready", "robust" or "complete" unless the evidence below says so.
3. Separate **measured** (a test or experiment produced a number) from **claimed** (a doc or comment says so) from **unverified**.
4. Quote file paths exactly. When you cite behaviour, name the file.
5. If my attached code contradicts this prompt, trust the code and tell me about the mismatch.

## 1. WHAT THE APP IS

- Native **SwiftUI iPad app** (iPhone layouts exist via compact size class but are unverified). Study companion for **NCERT Class 9/10** students.
- Core idea: the **Feynman method**. The student studies with a focus timer, then *explains* a concept aloud (or by text/handwriting). An **on-device** model grades the explanation against a compiled curriculum and gives feedback.
- Targets **iPadOS 18.0+**. Liquid Glass is applied through helper modifiers (`litmusGlass`, `litmusGlassButton`, `litmusProminentGlassButton`) that use the real API on 26+ and fall back on older systems. The fallbacks on iPadOS 18 are not verified.
- Heading to TestFlight. No third-party Swift packages. Swift 5 language mode with **MainActor default isolation** (so non-UI types are marked `nonisolated` explicitly).
- Bundle id and App Group appear as `dev.Bongo` in some places and `dev.Mohith` in others (e.g. `group.dev.Mohith.Litmus` in `Shared/LitmusWidgetData.swift`). README / DEVELOPER_GUIDE disagree with the project. Treat the Xcode project as the source of truth and flag the mismatch.
- The entitlements file is **empty**, while the developer guide claims a Family Controls entitlement. Screen Time features therefore cannot work as documented until entitlements are added.

Scale: about **22,163 lines of Swift** across the app, widget, shared code.

## 2. USER-FACING FLOW

Four tabs owned by `App/MainTabView.swift`: Home, Timer, Explain, Revise (flashcards). `MainTabView` owns `FeedbackViewModel(transport: LitmusApp.transport)` and layers the lap (timer) views on top.

1. **Home** (`Home/HomeView.swift`): subject → chapter tiles → topic sheet. Choosing a topic sets the current topic.
2. **Timer** (`Timer/TimerSetupView.swift`, `Timer/FocusTimerView.swift`): choose a duration (tyre-compound presets 15/25/45/60/80 min, or a wheel picker). The F1/tyre theming is cosmetic. "Finish" shows an alert "Did you finish learning?"; **Yes** goes to Explain with no celebration, **Not Yet** stays. Coins are awarded at lap checkpoints (`StudyProgressManager.awardLapCoin`). A Live Activity and notifications exist (`LiveActivityManager`, `NotificationManager`).
3. **Explain** (`Explain/ExplainView.swift`, `Explain/FeedbackViewModel.swift`): student explains the topic (speech via `LiveSpeechRecorder` / `VoiceEngineService`, typed, or PencilKit). The answer goes to the grading engine. If the outcome is mastered / likely-mastered, a summary shows directly. Otherwise a **review screen** shows three rows (missing / vague / right) built by `Explain/DebriefComposer.swift` from the stored report, the compiled concept and the student's own sentences. A follow-up question may be asked.
4. **Revise** (flashcards): `FlashcardLibrary` cards per chapter; widgets deep-link via `litmus://deck?...` and `litmus://revise`.

Profiles: `Settings/ProfileStore.swift` supports multiple learner profiles. Each profile has its own `storageKey`, its own SwiftData `ModelContainer` (`LitmusApp.container(for:)`) and its own UserDefaults namespace in `StudyProgressManager`.

## 3. DATA LAYER

- **UserDefaults (per-profile namespace)** via `Curriculum/StudyProgressManager.swift` (singleton, `ObservableObject`): coins, weekly streak array (Sunday first), daily minutes, sessions (`StudySession` JSON), active dates, focusDone/explainDone arrays. Week reset logic in `resetWeekIfNeeded`.
- **SwiftData** in `Curriculum/ProgressStore.swift`, three models:
  - `ConceptProgress` (unique `conceptId`; status, isProvisional, needsReview, revisitLater, everMastered, pendingRevisit, attempts, lastAttemptAt)
  - `AttemptRecord` (attemptId, conceptId, conceptHash, outcome, passedWeight/scoredWeight, rounds, createdAt)
  - `ProvisionalRecord` (unique attemptId; transcripts, results blob, evaluatorVersion, regrade fields). Transcripts are stored **only here, on device**.
  - `ProgressRecorder.evaluatorVersion = "m4.1"`. Progress is written only from `EvaluationOutcome` properties so the UI cannot save a provisional result as confirmed mastery.
- **Compiled curriculum**: JSON bundled in the app, loaded through `CurriculumLoader` / `CompiledCurriculumStore` into `CompiledChapter` / `CompiledConcept` (criteria, key points with `requiredEvidence`, misconceptions with `wrong`/`fix`, `hint`). **961 concepts** are counted from the files (an older test hard-coded 718 and went stale). Each concept has a `conceptHash` that the release gate freezes.
- **Widgets**: `Timer/WidgetSync.swift` writes a `LitmusWidgetSnapshot` (topics, streaks, coins) as JSON into the App Group `UserDefaults`, plus small cover JPEGs in the group container; `Shared/LitmusWidgetData.swift` is compiled into both app and widget targets.

## 4. THE GRADING ENGINE (the heart of the app)

Pipeline: `AnswerSorter` → `AttemptMachine` → `GradingCoordinator` → `RuleEngine` → `ProgressStore`.

- Grading files now in `Litmus/Grading/`: AppMaintenance, AttemptMachine, DriftCheck, FeynmanContracts (chapter-loading structs only), Graders, GradingCoordinator, RubricMatrix, RuleEngine. The older `ConceptEvaluator` / `FeynmanCognitiveEngine` / `FeynmanTutorPipeline` / `GuardrailLayer` / `DeterministicStorageBridge` path was **deleted**; all 961 listed concepts have compiled entries, so the engine is the only grading path. A topic without a compiled entry is simply not graded.
- `Grading/GradingCoordinator.swift`: orchestrates a grading run. Holds a private `GradingContext?` and wraps public entry points as `gradeScoped / gradeFollowUpScoped / regradeScoped`, constructing `ModelGrader(transport:context:)` at four sites.
- `Grading/Graders.swift`: `ModelGrader`, `LexicalGrader`, `CodeGrader`, `GradingPrompts` (`roleLine`, `conceptCheckInstructions`, `generalInstructions`), `GradingContext`, and a `ModelTransport` protocol with `FoundationModelsTransport` (Apple on-device model) and `UnavailableTransport` (when the model is not available).
- `FoundationModelsTransport` uses `SystemLanguageModel` / `LanguageModelSession`, greedy sampling, and permissive-content-transformations guardrails (default guardrails refused or distorted student text). The model has an 8192-token context.
- Reply format: the model is asked for plain JSON-ish output that is parsed manually (including the array shape `[{"ID":…,"result":…}]` and token caps). `@Generable` guided generation was **tested and rejected** for grading.
- **PARAKH rubric layer** (`Grading/RubricMatrix.swift`): maps outcomes to PARAKH Rashtriya Sarvekshan 2024 proficiency levels (Basic = partial/not yet, Proficient = Likely mastered, Advanced = Mastered). The PDF gives level names and descriptors only, not a scoring recipe, so the mapping is this app's own. It also lets textbook evidence phrases in the student's own words overrule a model false "no" (only for checks the compiler marked `lexical == evidence`; never for keyword lists or stated misconceptions; can only yield Proficient). **Measured effect on the 30 labelled answers: none** (24/30 with and without, 0 false passes). The level is not shown in the UI.
- Pass rule (`RuleEngine.decide`): every core key point must pass and passed weight must be >= 70% of scored weight; a key point passes only if all its required checks are yes.
- Safeguards in the engine: pass-2 quote proofs (a "yes" must be backed by a quote that exists in the answer), a recheck of a blocking "no", a keyword-stuffing guard, and a **drift check**.
- `Grading/DriftCheck.swift` + `Litmus/Resources/Evaluation/drift_set.json`: a fixed labelled set; baseline **0.9173** measured on OS 27.2.1. Until the drift check passes on a device, the best outcome is a provisional "Likely mastered", not "Mastered".
- `EvaluationOutcome` cases (from `storageName`): notGradable, offTopic, needsCorrection, mastered, likelyMastered, needsClarification, partial(almostThere), notYet.

### Measured results (this Mac, one dataset)
- Dataset: **30 labelled answers / 254 checks**. This is small and was labelled by us, not by teachers.
- Original prompt: **70.9%** per-check; end-to-end outcome **18/30**.
- Current prompt (role line + permissive guardrails + the chapter passage supplied for concept checks only): **91.7%** per-check; end-to-end **24/30**.
- Adding official framework indicators to the prompt made results **worse**, so they are not in the prompt. Free-form model-generated feedback **hallucinated**, which is why feedback is composed from stored data instead.
- Caveat: tuned and tested on the same small set, so overfitting is possible. Science and Class 9 have **no** labelled evaluation data. The release evaluation has **not** been re-run and re-frozen since the grading changes.

## 5. OFFICIAL FRAMEWORK DATA

- `Curriculum/official/*` plus `Tools/official_framework/{dump_pdf_lines.swift, parse_official.py, build_tags.py, run.sh}`: CBSE Learning Framework (Classes IX/X) → NCERT learning outcomes → competency-level outcomes → indicators, tagged Knowing / Applying / Reasoning by a **verb rule** (heuristic, not teacher-reviewed). Stored as a **sidecar**, not in the model prompt.
- The PARAKH document used is an MCQ survey structure, not an explanation rubric. Do not describe PARAKH as the grading rubric.

## 6. FEEDBACK / REVIEW SCREEN

- `Explain/DebriefComposer.swift` composes three lines without a model call: right (first criterion + the student's matching sentence), missing (stored misconception fix, or missing criteria), vague (follow-up question or hint). Quotes are only shown if a sentence shares ≥2 content words with the idea.
- Known wording weakness: when nothing was stated the line is generic ("None of the key ideas… stated yet") plus the opening sentence of the answer.

## 7. TESTS AND TOOLS (command-line harnesses, not XCTest)

- `Tools/GraderTests/main.swift` (70 checks), `Tools/AppFlowTests/main.swift` (44), `Tools/MaintenanceTests/main.swift` (29), run via `Tools/run_*_tests.sh` (e.g. `run_app_flow_tests.sh`). Engine tests take ~4 minutes.
- `run_drift_baseline.sh` regenerates the drift baseline. `Tools/model_experiments/{Experiment.swift, run.sh}` is the prompt experiment harness.
- Tests passing means those scripted checks pass; it says nothing about UI on a real device or about accuracy on unseen answers.

## 8. HONEST WEAKNESSES TO INCLUDE

- Accuracy evidence is one small, self-labelled dataset; no teacher review of the 63 chapters or of the official tags.
- Release evaluation not re-run/frozen after the prompt and RubricMatrix changes.
- Correct answers phrased in the student's own words are the main failure: the model gives a false "no"/"uncertain" on one check (e.g. `route_P1`, `jfm_P1`) and the strict rule sends the student to the review screen. Phrase evidence cannot fix paraphrases. 2 of the 9 answers labelled pass still miss.
- Results vary slightly between runs on the same Mac (an earlier run missed `fed_T1`/`fed_P1`, a later one did not).
- `Flashcards/OnDeviceFlashcardGenerator.swift` still uses NaturalLanguage templates (called from `ExplainView`), not Foundation Models.
- Singleton `StudyProgressManager` on UserDefaults with a manual profile namespace is fragile compared with SwiftData.
- iPhone layouts, iPadOS 18 fallbacks, and Dynamic Type extremes are not verified.
- Open handoff issues: Start→Timer ghosting, delayed Liquid Glass on 26.6.2, duplicated coin drawing code, bundle id / doc mismatches, empty entitlements, Home greeting shows the raw username (on hold).
- Several large view files mix layout, state and logic.
- Speech recognition and Screen Time features depend on permissions/entitlements not proven in this prompt.

## 9. WHAT I WANT FROM YOU

Produce, in order:
1. A one-paragraph plain-English summary of the app.
2. A layered architecture map (UI → view models → engine → storage → widgets) with file names.
3. The end-to-end data flow for one Explain attempt, step by step, naming files.
4. A table of key files: path, responsibility, what it depends on.
5. A "measured vs claimed vs unverified" table.
6. The weakness list above, ranked by risk to a TestFlight launch, plus anything *additional* you find in the attached code. Mark each addition as your own inference.
7. A list of questions you could not answer from the material given.

Do not pad, do not praise, and do not invent.
