#!/bin/bash
# Builds and runs the Milestone 5 tests (re-grade, cleanup, review cards, drift) against the app's own files.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/litmus-maintenance-tests"
mkdir -p "$BUILD"
xcrun swiftc -swift-version 5 -default-isolation MainActor -module-name MaintenanceTests \
  -target arm64-apple-macos26.0 \
  "$ROOT/Litmus/CompiledCurriculum.swift" \
  "$ROOT/Litmus/RuleEngine.swift" \
  "$ROOT/Litmus/Graders.swift" \
  "$ROOT/Litmus/GradingCoordinator.swift" \
  "$ROOT/Litmus/CompiledCurriculumStore.swift" \
  "$ROOT/Litmus/ProgressStore.swift" \
  "$ROOT/Litmus/DriftCheck.swift" \
  "$ROOT/Tools/MaintenanceTests/main.swift" \
  -o "$BUILD/maintenance-tests"
"$BUILD/maintenance-tests" "$ROOT"
