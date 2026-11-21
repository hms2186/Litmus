#!/bin/bash
# Compares grading-instruction variants on the real on-device model, using the app's own grading source files.
# Usage: Tools/model_experiments/run.sh <variants>        e.g. current,contextPermissive,hybrid2
#        Tools/model_experiments/run.sh e2e,contextPermissive,hybrid2     (end to end through GradingCoordinator)
# Needs a Mac with Apple Intelligence. It never writes into the app or into drift_set.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="${TMPDIR:-/tmp}/litmus-model-experiments"
mkdir -p "$BUILD/src"
cp "$ROOT/Tools/model_experiments/Experiment.swift" "$BUILD/src/main.swift"
xcrun swiftc -swift-version 5 -default-isolation MainActor -module-name Experiment -target arm64-apple-macos26.0 \
  "$ROOT/Litmus/Curriculum/CompiledCurriculum.swift" "$ROOT/Litmus/Grading/RuleEngine.swift" "$ROOT/Litmus/Grading/RubricMatrix.swift" \
  "$ROOT/Litmus/Grading/Graders.swift" "$ROOT/Litmus/Grading/GradingCoordinator.swift" \
  "$ROOT/Litmus/Curriculum/CompiledCurriculumStore.swift" "$ROOT/Litmus/Grading/DriftCheck.swift" \
  "$BUILD/src/main.swift" -o "$BUILD/experiment"
"$BUILD/experiment" "$ROOT" "${1:-current,contextPermissive,hybrid2}"
