# Litmus

An on-device tutor for iPad that helps students learn by explaining. A student picks a chapter and a topic, runs a focus timer on a race circuit, then explains the topic aloud, in writing or with Apple Pencil. Litmus checks the explanation against the curriculum and shows what was right, what was missing and what to try next.

![Platform](https://img.shields.io/badge/platform-iPadOS%2026.5%2B-blue) ![Language](https://img.shields.io/badge/Swift-SwiftUI-orange) ![Privacy](https://img.shields.io/badge/privacy-on--device-green)

## Overview

Litmus is built on the Feynman technique: you understand an idea when you can explain it simply. The app turns that into a short loop.

1. **Choose.** On Home, pick a subject, a chapter and a topic.
2. **Focus.** Start a timer. The car drives a circuit in three sectors, and you earn a coin at each of the three checkpoints.
3. **Explain.** Speak, sketch or type your explanation to the race engineer.
4. **Review.** See which ideas you covered, which you missed, and flashcards with the NCERT textbook diagrams to revise.

Everything runs on the device. Speech recognition, handwriting recognition and grading use Apple frameworks and the on-device Foundation Models, so a student's answers never leave the iPad.

The app covers the NCERT syllabus for Class 9 and Class 10 Science, and for Class 10 Social Science (Civics, Economics, Geography and History).

## Configure the sample code project

To build and run Litmus you need:

- A Mac with **Xcode 26.6** or later.
- An iPad (or the iPad simulator) running **iPadOS 26.5** or later. The grading model needs a device that supports Apple Intelligence; on a simulator, grading falls back to keyword checking.
- An Apple Developer account for running on a device.

Then:

1. Open `Litmus.xcodeproj` in Xcode.
2. Select the **Litmus** project, then each target (**Litmus** and **LitmusWidgets**), and in **Signing & Capabilities** choose your own team.
3. Change the bundle identifiers if `dev.Hemanth.Litmus` and `dev.Hemanth.Litmus.LitmusWidgets` are not yours to use. The widget's identifier must start with the app's.
4. Choose the **Litmus** scheme and an iPad, then choose **Product > Run**.

The first launch plays the Litmus launch animation. To skip it while developing, add `-skipSplash` to the scheme's **Arguments Passed On Launch**.

## What's in the project

| Folder | What it holds |
|---|---|
| `Litmus/` | The app: SwiftUI screens, the grading engine and the bundled curriculum |
| `LitmusWidgets/` | The widget extension that draws the timer's Live Activity |
| `Shared/` | Code compiled into both targets (the Live Activity's attributes) |
| `Curriculum/` | Source material and checks for the curriculum: follow-up questions, extracted textbook text and the review report |
| `Tools/` | The curriculum compiler, the chapter authoring scripts and the engine test suites |
| `docs/` | The developer guide |

For how the pieces fit together, read the [developer guide](docs/DEVELOPER_GUIDE.md).

## Features

- **Timer on a circuit.** A focus timer shown as a lap of a Formula 1 circuit, split into three sectors with a coin at the end of each.
- **Explain three ways.** Speak, sketch with Apple Pencil, or type. The race engineer asks the same question in each way.
- **Grading you can trust.** A fixed rule engine turns checked results into an outcome. The model can help to decide whether an idea was covered, but it can never decide the result by itself.
- **Flashcards with diagrams.** Cards come from the topic's own curriculum text and carry the NCERT diagrams, with read-aloud and an adjustable reading speed.
- **Live Activity.** With **Widget Timer** on in Settings, the timer keeps running on the Lock Screen when the app is in the background.
- **Accessibility.** Text Size, Bold Text, Reduce Motion and Haptic Feedback, under **Settings > Accessibility**, apply across the app.
- **Liquid Glass.** The interface follows the iPadOS 26 design language, including the sidebar-adaptable tab bar.

## Run the tests

The grading engine has its own test suites. They compile the engine's source files and run on your Mac, with no simulator.

```bash
Tools/run_engine_tests.sh        # every outcome for every concept, about 5 minutes
Tools/run_grader_tests.sh        # the graders
Tools/run_maintenance_tests.sh   # clean-up, re-grading and the drift check
Tools/run_app_flow_tests.sh      # a student's whole attempt, end to end
```

## Content and credits

The curriculum text and diagrams are based on NCERT textbooks. NCERT materials are the property of the National Council of Educational Research and Training. Check that your use of them, and of the character artwork and videos in `Litmus/` and `Litmus/Assets.xcassets`, is permitted before you publish or distribute this project.

## See also

- [Developer guide](docs/DEVELOPER_GUIDE.md)
- [Curriculum build step](Curriculum/README.md)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
