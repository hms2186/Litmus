#!/bin/bash
# Builds and runs the Milestone 4 app-flow tests against the app's own source files.
# Usage: Tools/run_app_flow_tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/litmus-app-flow-tests"
mkdir -p "$BUILD"
xcrun swiftc -swift-version 5 -default-isolation MainActor -module-name AppFlowTests \
  -target arm64-apple-macos26.0 \
  "$ROOT/Litmus/CompiledCurriculum.swift" \
  "$ROOT/Litmus/RuleEngine.swift" \
  "$ROOT/Litmus/Graders.swift" \
  "$ROOT/Litmus/GradingCoordinator.swift" \
  "$ROOT/Litmus/CompiledCurriculumStore.swift" \
  "$ROOT/Litmus/AttemptMachine.swift" \
  "$ROOT/Litmus/ProgressStore.swift" \
  "$ROOT/Tools/AppFlowTests/main.swift" \
  -o "$BUILD/app-flow-tests"
"$BUILD/app-flow-tests" "$ROOT/Litmus/Compiled"
