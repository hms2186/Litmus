#!/bin/bash
# Release evaluation (Milestone 6). Validates the release set, checks that nothing changed since
# `freeze`, grades every answer on the model path and the fallback path, then applies the gate.
#
#   Tools/run_release_eval.sh                       full run against Curriculum/release/release_set.json
#   Tools/run_release_eval.sh --dry-run <set.json>  pipeline check on a small set (no minimums, no freeze)
#   Tools/run_release_eval.sh --path model|fallback restrict the paths (the gate then needs both)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
gate() { python3 -I "$ROOT/Tools/release/release_gate.py" "$@"; }
DRY=0; SET="$ROOT/Curriculum/release/release_set.json"; PATHS=both
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; SET="$2"; shift 2;;
    --path) PATHS="$2"; shift 2;;
    *) echo "unknown argument $1"; exit 2;;
  esac
done
OUT="$ROOT/Curriculum/release/results"
mkdir -p "$OUT"
RESULTS="$OUT/$([ $DRY = 1 ] && echo dryrun || echo results).csv"

if [ $DRY = 1 ]; then
  gate validate --dry-run --set "$SET"
else
  gate validate --set "$SET"
  gate check-frozen
fi

BUILD="${TMPDIR:-/tmp}/litmus-release-run"
mkdir -p "$BUILD"
xcrun swiftc -swift-version 5 -default-isolation MainActor -module-name ReleaseRun -target arm64-apple-macos26.0 \
  "$ROOT/Litmus/CompiledCurriculum.swift" "$ROOT/Litmus/RuleEngine.swift" "$ROOT/Litmus/Graders.swift" \
  "$ROOT/Litmus/GradingCoordinator.swift" "$ROOT/Litmus/CompiledCurriculumStore.swift" \
  "$ROOT/Tools/ReleaseRun/main.swift" -o "$BUILD/release-run" 2>&1 | grep -E "error" || true
"$BUILD/release-run" "$ROOT" "$SET" "$RESULTS" --path "$PATHS"

if [ $DRY = 1 ]; then
  gate gate "$RESULTS" --set "$SET" --dry-run --report "$OUT/dryrun_gate_report.md" || true
else
  gate check-frozen
  gate gate "$RESULTS" --set "$SET"
fi
