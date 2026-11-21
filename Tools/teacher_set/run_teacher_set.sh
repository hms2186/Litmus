#!/bin/bash
# Runs the frozen teacher/colleague-authored set once through the shipped grading configuration (needs Apple Intelligence).
# Usage: Tools/teacher_set/run_teacher_set.sh [path/to/teacher_set.json]
# Refuses to run if the file no longer matches its .sha256 lock, so an edited set cannot be mistaken for the frozen one.
# Report the numbers as they come; do not change grading rules or phrasings to fit this set afterwards.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SET="${1:-$ROOT/Tools/teacher_set/teacher_set.json}"
[ -f "$SET" ] || { echo "No frozen set at $SET. Run Tools/teacher_set/finalize_set.py first."; exit 1; }
if [ -f "$SET.sha256" ]; then
  want=$(cut -d' ' -f1 "$SET.sha256"); have=$(shasum -a 256 "$SET" | cut -d' ' -f1)
  [ "$want" = "$have" ] || { echo "The set changed after it was frozen (sha256 mismatch). Re-run finalize_set.py from the worksheet."; exit 1; }
else
  echo "warning: no .sha256 lock next to the set"
fi
OUT="${TMPDIR:-/tmp}/litmus-teacher-set"; mkdir -p "$OUT"
STRESS_SET="${SET#$ROOT/}" PHRASING=1 STRESS_OUT="$OUT/teacher_set.jsonl" "$ROOT/Tools/model_experiments/run.sh" stress > "$OUT/teacher_set.log" 2>&1
grep "FALSE PASS\|missed\|PART\|WRONG" "$OUT/teacher_set.log"
echo "Per-check detail: $OUT/teacher_set.jsonl   Full log: $OUT/teacher_set.log"
