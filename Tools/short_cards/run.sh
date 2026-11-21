#!/bin/bash
# Usage: Tools/short_cards/run.sh [count]   writes Litmus/short_cards.json (resumable). Needs Apple Intelligence on this Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="${TMPDIR:-/tmp}/litmus-short-cards"; mkdir -p "$BUILD/src"
cp "$ROOT/Tools/short_cards/main.swift" "$BUILD/src/main.swift"
xcrun swiftc -swift-version 5 -default-isolation MainActor -module-name ShortCards -target arm64-apple-macos26.0 \
  "$ROOT/Litmus/Curriculum/CompiledCurriculum.swift" "$ROOT/Litmus/Curriculum/CompiledCurriculumStore.swift" \
  "$ROOT/Litmus/Flashcards/OnDeviceFlashcardGenerator.swift" "$BUILD/src/main.swift" -o "$BUILD/short_cards"
"$BUILD/short_cards" "$ROOT" "${1:-}"
