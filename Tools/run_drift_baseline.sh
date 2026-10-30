#!/bin/bash
# Measures the drift-check baseline with the real on-device model and writes it into Litmus/drift_set.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/litmus-drift-baseline"
mkdir -p "$BUILD"
xcrun swiftc -swift-version 5 -default-isolation MainActor -module-name DriftBaseline \
  -target arm64-apple-macos26.0 \
  "$ROOT/Litmus/CompiledCurriculum.swift" \
  "$ROOT/Litmus/RuleEngine.swift" \
  "$ROOT/Litmus/Graders.swift" \
  "$ROOT/Litmus/GradingCoordinator.swift" \
  "$ROOT/Litmus/CompiledCurriculumStore.swift" \
  "$ROOT/Litmus/DriftCheck.swift" \
  "$ROOT/Tools/DriftBaseline/main.swift" \
  -o "$BUILD/drift-baseline"
"$BUILD/drift-baseline" "$ROOT"
