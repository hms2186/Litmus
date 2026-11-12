#!/bin/bash
# Measures the drift-check baseline with the real on-device model and writes it into Litmus/drift_set.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/litmus-drift-baseline"
mkdir -p "$BUILD"
xcrun swiftc -swift-version 5 -default-isolation MainActor -module-name DriftBaseline \
  -target arm64-apple-macos26.0 \
  "$ROOT/Litmus/Curriculum/CompiledCurriculum.swift" \
  "$ROOT/Litmus/Grading/RuleEngine.swift" \
  "$ROOT/Litmus/Grading/Graders.swift" \
  "$ROOT/Litmus/Grading/GradingCoordinator.swift" \
  "$ROOT/Litmus/Curriculum/CompiledCurriculumStore.swift" \
  "$ROOT/Litmus/Grading/DriftCheck.swift" \
  "$ROOT/Tools/DriftBaseline/main.swift" \
  -o "$BUILD/drift-baseline"
"$BUILD/drift-baseline" "$ROOT"
