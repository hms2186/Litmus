#!/bin/bash
# Regression gate for the grading pipeline. Needs a Mac with Apple Intelligence (it runs the real on-device model).
# Usage: Tools/run_regression_gate.sh          (about 15 minutes)
# Hard gates (any failure exits 1): the four test suites pass; no keyword list passes; no answer labelled "must not pass"
# reaches Mastered or Likely mastered (30-answer, adversarial and stress sets); no wrong-topic answer passes.
# Floors (also exit 1 when missed): correct outcomes on each set must not drop below the numbers recorded in docs/MODEL_REPORT.md.
# The answer sets are developer-written student-mindset tests, not real students.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${TMPDIR:-/tmp}/litmus-gate"; mkdir -p "$OUT"
FLOOR_E2E=${FLOOR_E2E:-26}       # of 30
FLOOR_ADV=${FLOOR_ADV:-19}       # of 21
FLOOR_STRESS=${FLOOR_STRESS:-72} # of 80
fail=0
bad() { echo "GATE FAIL: $1"; fail=1; }

for t in grader app_flow maintenance engine; do
  Tools/run_${t}_tests.sh > "$OUT/$t.log" 2>&1
  if tail -3 "$OUT/$t.log" | grep -q "ALL PASSED"; then echo "ok   $t suite"; else bad "$t suite (see $OUT/$t.log)"; fi
done

PHRASING=1 Tools/model_experiments/run.sh kwlist > "$OUT/kwlist.log" 2>&1
kw=$(grep -o "KEYWORD LISTS PASSED: [0-9]*" "$OUT/kwlist.log" | grep -o "[0-9]*$" | tail -1)
[ "${kw:-x}" = "0" ] && echo "ok   keyword lists passed 0" || bad "keyword lists passed ${kw:-unknown} (must be 0)"

PHRASING=1 Tools/model_experiments/run.sh e2e,contextPermissive > "$OUT/e2e.log" 2>&1
line=$(grep "END-TO-END" "$OUT/e2e.log" | tail -1)
fp=$(echo "$line" | sed -n 's/.*passed but labels say no \([0-9]*\).*/\1/p'); same=$(echo "$line" | sed -n 's/.*labels \([0-9]*\)\/30.*/\1/p')
[ "${fp:-x}" = "0" ] && echo "ok   30-answer false passes 0" || bad "30-answer false passes ${fp:-unknown}"
[ "${same:-0}" -ge "$FLOOR_E2E" ] && echo "ok   30-answer $same/30 (floor $FLOOR_E2E)" || bad "30-answer ${same:-unknown}/30 below floor $FLOOR_E2E"

PHRASING=1 Tools/model_experiments/run.sh adv > "$OUT/adv.log" 2>&1
line=$(grep "ADVERSARIAL" "$OUT/adv.log" | tail -1)
fp=$(echo "$line" | sed -n 's/.*false passes \([0-9]*\).*/\1/p'); right=$(echo "$line" | sed -n 's/.*right \([0-9]*\)\/21.*/\1/p')
[ "${fp:-x}" = "0" ] && echo "ok   adversarial false passes 0" || bad "adversarial false passes ${fp:-unknown}"
[ "${right:-0}" -ge "$FLOOR_ADV" ] && echo "ok   adversarial $right/21 (floor $FLOOR_ADV)" || bad "adversarial ${right:-unknown}/21 below floor $FLOOR_ADV"

PHRASING=1 STRESS_OUT="$OUT/stress.jsonl" Tools/model_experiments/run.sh stress > "$OUT/stress.log" 2>&1
p1=$(grep "PART 1" "$OUT/stress.log" | tail -1); p2=$(grep "PART 2" "$OUT/stress.log" | tail -1)
fp=$(echo "$p1" | sed -n 's/.*false passes \([0-9]*\).*/\1/p'); ok=$(echo "$p1" | sed -n 's/.*: \([0-9]*\)\/80.*/\1/p'); wt=$(echo "$p2" | sed -n 's/.*passes \([0-9]*\).*/\1/p')
[ "${fp:-x}" = "0" ] && echo "ok   stress false passes 0" || bad "stress false passes ${fp:-unknown}"
[ "${wt:-x}" = "0" ] && echo "ok   wrong-topic passes 0" || bad "wrong-topic passes ${wt:-unknown}"
[ "${ok:-0}" -ge "$FLOOR_STRESS" ] && echo "ok   stress $ok/80 (floor $FLOOR_STRESS)" || bad "stress ${ok:-unknown}/80 below floor $FLOOR_STRESS"

[ $fail -eq 0 ] && echo "REGRESSION GATE PASSED" || echo "REGRESSION GATE FAILED (logs in $OUT)"
exit $fail
