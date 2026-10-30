# Litmus developer guide

How Litmus is built, how to change it, and why it is built that way. Read the [README](../README.md) first for what the app does and how to run it.

## Contents

- [Requirements and targets](#requirements-and-targets)
- [How the app starts](#how-the-app-starts)
- [Navigation](#navigation)
- [The focus timer](#the-focus-timer)
- [Explaining and grading](#explaining-and-grading)
- [The curriculum](#the-curriculum)
- [Data and settings](#data-and-settings)
- [Accessibility](#accessibility)
- [Layout that follows the window](#layout-that-follows-the-window)
- [Design decisions](#design-decisions)
- [Media and assets](#media-and-assets)
- [Tests](#tests)
- [Troubleshooting](#troubleshooting)
- [Conventions](#conventions)

## Requirements and targets

| | |
|---|---|
| Xcode | 26.6 or later |
| Deployment target | iPadOS 26.5 (the app also builds for iPhone) |
| Language | Swift 5 language mode, SwiftUI throughout |
| Default isolation | `MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION`) |
| Frameworks | SwiftUI, SwiftData, FoundationModels, Speech, AVFoundation, AVKit, PencilKit, Vision, NaturalLanguage, ActivityKit, WidgetKit, UserNotifications, BackgroundTasks |

The project has two targets.

| Target | Product | Bundle identifier |
|---|---|---|
| `Litmus` | The app | `dev.Hemanth.Litmus` |
| `LitmusWidgets` | A widget extension, embedded in the app | `dev.Hemanth.Litmus.LitmusWidgets` |

Folders are Xcode *synchronized groups*: add a file to `Litmus/`, `LitmusWidgets/` or `Shared/` on disk and it joins its target, with no project edit. `Shared/` belongs to both targets. `Info.plist` in each folder is excluded from compiling and used as the target's Info file.

## How the app starts

`LitmusApp` creates the SwiftData container and registers the background task, then shows `LaunchContainer`.

`LaunchContainer` shows the launch animation first (`LitmusSplashView`). The dashboard (`F1AppRouter`) is **not built until the animation has fully appeared**. Building it takes the main thread for a moment on a device, and the animation's timers would otherwise run out during the stall and skip the animation. The animation waits for the dashboard to report it is ready, then zooms and fades into it.

The container also wraps everything in `F1AccessibilityHost` (see [Accessibility](#accessibility)) and sets one scroll edge style for every scroll view. Launch with `-skipSplash` to go straight to the dashboard.

## Navigation

`F1AppRouter` owns the app's state and a `TabView` with the `.sidebarAdaptable` style, so the tab bar can open into a sidebar. The tabs are in `AppNavigationTab`:

| Tab | Screen | Notes |
|---|---|---|
| Home | `F1HomeDashboardView` | Greeting, the session card, weekly streaks, the Revise banner and study analysis |
| Timer | `F1TimerSetupView` | Pick a circuit, a length and a tyre, then **Begin** |
| Explain | `F1TeamRadioStudioView` | The race engineer. Speak, Sketch or Type, then the debrief |
| Flashcards | `F1StudyDeckView` | Chapters as tiles; a tile opens its deck with a zoom transition |

Settings opens from the gear in the top right of Home and Timer, as a screen pushed on that tab's `NavigationStack`, so it has the system back button. The Revise page presents Settings in a stack of its own.

Full-screen moments are layered over the tabs by the router: the **start lights** (`F1StartSequenceView`), the **cockpit** (`F1LiveCockpitHUDView`), the **Congratulations** card and the onboarding.

Back buttons: screens inside a navigation stack use the system's. Screens that cover it use `F1BackButton`, which has one fixed position (`F1BackButton.leading` and `.top`) so the control is in the same place everywhere.

## The focus timer

1. **Begin** on the Timer tab runs `beginLap()`, which resets the lap and shows the start lights.
2. When the fifth light is on, `startLap()` opens the cockpit, starts the clock and starts the Live Activity.
3. The clock (`LapClock`) is held by the router but not observed by it, so only the cockpit redraws each second.
4. The time left is computed from an **end date**, not by counting ticks. If the app goes to the background and returns, the clock is correct at once.

### The circuit

The track in the cockpit is the circuit from the design, stored as 92 points along its centre line, scaled to a unit box (`waypoints` in `F1LiveCockpitHUDView`). A spline through them is sampled into 600 points and parameterised by arc length. The lap has three sectors, drawn red, blue and yellow, which end at 33.9% and 72.9% of the track's length.

The timer is split into three equal parts. A piecewise mapping (`trackProgress`) makes the car reach the end of sector 1 and sector 2 exactly at one third and two thirds of the time, and the finish line at 100%.

### Coins

There are three checkpoints and one coin for each: one third, two thirds, and the end of the timer. `F1AppRouter.awardCheckpointCoinsIfDue()` awards them, once each per lap (`F1SessionProgressManager.awardLapCoin`). The cockpit pops a coin from below the screen, shows "+1" in the middle and flies it to the badge; the badge counts up when the coin lands.

When the timer reaches zero, the lap closes about two seconds later so the last coin can land.

A session lights that day's streak only when it reaches halfway. Explaining adds time to the day's chart but does not light the streak.

### Live Activity

With **Widget Timer** on in Settings, `startLap()` starts a Live Activity (`F1LiveActivityManager`). The widget (`LitmusWidgets/LitmusFocusLiveActivity.swift`) draws:

- the countdown, with `Text(timerInterval:)`;
- three sector bars, each a `ProgressView(timerInterval:)` for its third of the timer;
- the tyre compound, the topic and a paused state.

Because time itself drives the countdown and the bars, they keep moving while the app is in the background, with no updates sent. The app only updates the activity when the timer is paused or resumed.

A local notification for the end of the timer is scheduled when the lap starts, so it arrives even if the app is closed. It is cancelled if the student finishes early.

`F1FocusLapActivityAttributes` is in `Shared/` because both the app (to start the activity) and the widget (to draw it) need it.

## Explaining and grading

The Explain tab has three ways to answer, in `ExplainInputMode`:

| Mode | Input | Code |
|---|---|---|
| Speak | On-device speech recognition | `LiveSpeechRecorder` |
| Sketch (`.write`) | Apple Pencil, read with Vision text recognition | `DigitalScratchpadCanvas`, `PencilTextExtractor` |
| Type | The keyboard | `F1TeamRadioStudioView` |

The engineer asks the question differently for each mode (`modeLine(_:)`), and the line is read aloud by `F1EngineerVoice`, which wraps `VoiceEngineService` (`AVSpeechSynthesizer`).

### The grading engine

For topics in the compiled curriculum, `FeedbackViewModel` runs the engine below. Other topics use the older `ConceptEvaluator` path.

```
answer ──▶ AnswerSorter ──▶ AttemptMachine ──▶ GradingCoordinator ──▶ RuleEngine ──▶ ProgressStore
           (is it gradable?)  (fixed states)    (graders, bounded)     (fixed rules)   (SwiftData)
```

1. **`AnswerSorter`** (in `AttemptMachine.swift`) decides whether an answer can be graded at all: empty, unintelligible, "I don't know" and off-topic answers never reach grading.
2. **`AttemptMachine`** is a pure state machine: `ready`, `grading`, `awaitingFollowUp`, `correcting`, `finished` and the re-prompt states. The view model feeds events in and reads the state out.
3. **`GradingCoordinator`** turns an answer into checked results. It runs the code checks, then the model graders in parallel batches, retries omitted IDs once, guards against keyword stuffing, and falls back to keyword matching if a batch fails or times out. Every model call is bounded in time.
4. **`Graders`**: `CodeGrader` (checks that need no model), `ModelGrader` (the on-device model through a `ModelTransport`; its replies are checked, unknown IDs are dropped and anything that is not clearly true counts as "left out") and `LexicalGrader` (keyword fallback, never says no).
5. **`RuleEngine`** is pure: no I/O, no clock, no model. The same checked results always give the same `EvaluationOutcome`. This is what keeps the verdict explainable and testable.
6. **`ProgressStore`** writes progress to SwiftData, only from the outcome's own properties, so a provisional result can never be saved as confirmed mastery.

### Provisional results and the drift check

The on-device model changes with OS updates. `DriftCheck` re-grades 30 labelled answers (`drift_set.json`) after the OS build changes and compares the agreement with a stored baseline. Until the check passes on the current build, the best outcome is **Likely mastered**, never **Mastered**.

`AppMaintenance` runs the background work: a 30-day clean-up of stored transcripts, re-grading saved Likely-mastered answers, and the drift check. It runs when the app becomes active and as a background processing task while the iPad charges.

Transcripts are stored only on the device.

## The curriculum

Chapters are authored as JSON in `Litmus/ncert_*.json` and compiled to `Litmus/Compiled/*.compiled.json`, which the app loads from its bundle (`CompiledCurriculumStore`). A file written by an unsupported compiler version is refused as a whole, so no chapter is half-understood.

| Content | Chapters |
|---|---|
| Class 10 Science | 13 |
| Class 9 Science | 13 |
| Class 10 Civics, Economics, History | 5 each |
| Class 10 Geography | 7 |
| Class 9 Social Science | 15 |

To add or change a chapter:

```bash
python3 -I Tools/chapters/sci10_1.py        # build a chapter from its compact description
python3 -I Tools/compile_curriculum.py migrate
python3 -I Tools/compile_curriculum.py      # checks everything; writes nothing if it finds an error
```

`Tools/chapters/dsl.py` builds a chapter from a short description and checks every quote against the extracted textbook text. A chapter cannot contain a quote that is not in the book. The compile step uses the same check. [`Curriculum/README.md`](../Curriculum/README.md) describes the folders, the follow-up question files and the release checks.

## Data and settings

| Store | What it holds |
|---|---|
| SwiftData | `ConceptProgress`, `AttemptRecord`, `ProvisionalRecord`: progress and saved answers |
| `UserDefaults` | Coins, weekly streaks, study minutes, session history (`F1SessionProgressManager`) |
| `@AppStorage` | Profile (`learner_*`), Settings toggles (`settings_*`) and Accessibility options (`a11y_*`) |

The profile keys are `learner_name`, `learner_grade`, `learner_curriculum`, `learner_nationality`, `learner_driver_number`, `learner_about` and `learner_daily_goal_minutes`. The Accessibility keys are in `F1A11yKey`.

## Accessibility

Settings has an **Accessibility** page with Text Size (seven steps), Bold Text, Reduce Motion and Haptic Feedback. They sit beside the system's own settings and apply to the whole app.

`F1AccessibilityHost` reads the options and publishes them to the environment (`f1TextScale`, `f1BoldText`, `f1ReduceMotion`, `f1Haptics`). It also sets `dynamicTypeSize`, so system text styles follow the Text Size step, and `legibilityWeight`, so Bold Text bolds system fonts.

Most text in the app is drawn at design sizes. Use these helpers so new text follows the options:

```swift
Text("Explain it").f1Font(size: 22, weight: .semibold)        // instead of .font(.system(size:weight:))
view.f1Feedback(.selection, trigger: value)                    // instead of .sensoryFeedback
@Environment(\.f1ReduceMotion) private var reduceMotion        // instead of the system key
```

Reduce Motion is on when either the system's switch or the app's is on. Never use motion as the only way to show something; pair it with haptics or text.

## Layout that follows the window

The sidebar changes the width of the content while it animates. Reading that width into state on every frame would rebuild the screen for every frame of the animation. `onSettledWidth` (`Litmus/F1Layout.swift`) reports the width once, when it first appears and again after it has stopped changing for 140 milliseconds.

Home measures the width with a spacer that the content cannot widen. The content sits in an overlay of the spacer; measuring the content itself would make a wide layout widen its own container, and the layout would never shrink back.

Sizes on Home come from `d(_:)`, which scales the Figma design's points by the screen width (1312 points wide in landscape, 820 in portrait). Below 1100 points wide, Home switches to a one-column portrait layout.

## Design decisions

- **Liquid Glass is for tiles and controls.** Tiles use `.glassEffect(.regular)`. Controls that respond to touch add `.interactive()`. Glass is not stacked on glass: items inside a glass card use a plain fill.
- **One scroll edge style.** `.scrollEdgeEffectStyle(.soft, for: .all)` is set once at the app root.
- **Official controls.** Pickers are `Picker`, with `.segmented` for the subject and `.inline` inside a `Menu` for the chapter and topic lists. Settings uses `NavigationStack`, `NavigationLink` and `navigationTitle`.
- **SF Symbols for every interface icon.** Artwork (the characters and the textbook diagrams) is the only image content.
- **Motion that explains.** Transitions show where something came from: the Flashcards tile zooms into its deck, the coin flies to the badge it adds to.
- **Always reachable.** Touch targets are at least 44 points. Text follows the Text Size step. Custom controls carry accessibility labels.

## Media and assets

- **Asset catalog** (`Litmus/Assets.xcassets`): app colours, the characters, and the NCERT diagrams used by flashcards (`chem_*` and `bio_*`). A diagram is linked to its concept in `F1ConceptDiagrams.swift`.
- **Videos** in `Litmus/`: `Idle123.mov` (the engineer waiting), `listening1.1.mov` (the engineer listening), and `idle-1.mov`, `wrong-1.mov` and `proceedtonxt-1.mov` for the debrief. `LoopingPlayerView` plays them in a loop.
- **Cut-outs.** The clips have a black background. `idle_mask` (in the asset catalog) and the `race_engineer_listening` still are used as masks, so the character appears at full opacity on the garage background. If you replace a clip, make a new mask from its frames.
- **App icon.** `Logo_Litmus.icon`, made in Icon Composer.

## Tests

| Script | What it checks |
|---|---|
| `Tools/run_engine_tests.sh` | The rule engine's invariants, for every outcome of every concept |
| `Tools/run_grader_tests.sh` | The graders against the compiled chapters |
| `Tools/run_maintenance_tests.sh` | Clean-up, re-grading and the drift check |
| `Tools/run_app_flow_tests.sh` | An attempt from answer to saved progress |
| `Tools/run_drift_baseline.sh` | Re-measures the drift baseline with the real on-device model |
| `Tools/release/release_gate.py` | The release gate: a held-out, human-labelled answer set decides whether grading can ship |

The scripts compile the engine's source files directly with `swiftc`, so keep the engine files free of UI imports. After changing the engine or the curriculum, run the engine tests.

## Troubleshooting

**The build fails with a signing error.** Choose your own team for both targets, and change the bundle identifiers if they are not yours.

**The timer's Live Activity does not appear.** Check that **Widget Timer** is on in Settings, and that Live Activities are allowed for Litmus in iPadOS Settings. The widget extension must be built and embedded: build the **Litmus** scheme, not only the app target.

**Grading is always "keyword" matching.** The on-device model is not available, for example on a simulator or a device without Apple Intelligence. The keyword grader is the fallback, and results can only be **Likely mastered** at best.

**A notification prompt covers the screen on first launch.** That is the system's permission prompt for notifications.

## Conventions

- Names: types for screens start with `F1` (the circuit theme); the engine files have plain names (`RuleEngine`, `Graders`).
- Comments describe why, in plain sentences. Each file starts with a header that says what it is for.
- New screens use the accessibility helpers, glass tiles and `F1BackButton` as described above.
- Keep the engine pure: `RuleEngine` and `AttemptMachine` have no I/O, no clock and no model, so they can be tested exhaustively.
