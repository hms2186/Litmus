#!/bin/bash
# Builds and runs the RuleEngine tests against the app's own engine source files.
# Usage: Tools/run_engine_tests.sh   (compile the curriculum first: python3 -I Tools/compile_curriculum.py)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/litmus-engine-tests"
mkdir -p "$BUILD"
xcrun swiftc -O -swift-version 5 -default-isolation MainActor -module-name EngineTests \
  "$ROOT/Litmus/CompiledCurriculum.swift" \
  "$ROOT/Litmus/RuleEngine.swift" \
  "$ROOT/Tools/EngineTests/main.swift" \
  -o "$BUILD/engine-tests"
"$BUILD/engine-tests" "$ROOT/Litmus/Compiled"
