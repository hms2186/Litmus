#!/bin/bash
# Builds and runs the Milestone 3 grader tests against the app's own grading source files.
# Usage: Tools/run_grader_tests.sh [--live]   (--live also grades a few answers with the real model)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/litmus-grader-tests"
mkdir -p "$BUILD"
xcrun swiftc -swift-version 5 -default-isolation MainActor -module-name GraderTests \
  -target arm64-apple-macos26.0 \
  "$ROOT/Litmus/CompiledCurriculum.swift" \
  "$ROOT/Litmus/RuleEngine.swift" \
  "$ROOT/Litmus/Graders.swift" \
  "$ROOT/Litmus/GradingCoordinator.swift" \
  "$ROOT/Tools/GraderTests/main.swift" \
  -o "$BUILD/grader-tests"
"$BUILD/grader-tests" "$ROOT/Litmus/Compiled" "$@"
