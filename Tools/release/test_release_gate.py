#!/usr/bin/env python3
"""Tests for release_gate.py. Run: python3 -I Tools/release/test_release_gate.py"""
import argparse
import contextlib
import csv
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release_gate as rg  # noqa: E402


def answer(i, concept, final, text=None, labels=("pass", "pass"), source="student", intent=None, category="ownWords"):
    label = final
    return {"id": f"R{i:04d}", "conceptId": concept, "slot": "S1", "intent": intent or ("shouldPass" if final == "pass" else "shouldNotPass"),
            "category": category, "text": text or f"unique answer number {i} about subject {concept} with filler words w{i}x{i * 7}",
            "writtenBy": "teacher-1", "source": source, "labels": {"A": labels[0], "B": labels[1]}, "final": label}


def synthetic_set(fail_per_concept=5, concepts=64, pass_per_concept=4):
    answers, i = [], 0
    for c in range(concepts):
        for _ in range(fail_per_concept):
            i += 1
            answers.append(answer(i, f"zz_concept_{c}", "fail", labels=("fail", "fail")))
        for _ in range(pass_per_concept):
            i += 1
            answers.append(answer(i, f"zz_concept_{c}", "pass", labels=("pass", "pass")))
    return {"version": 1, "answers": answers}


class Statistics(unittest.TestCase):
    def test_zero_error_sample_sizes(self):
        self.assertLess(rg.cp_upper(0, 59), 0.05)
        self.assertGreater(rg.cp_upper(0, 58), 0.05)
        self.assertLess(rg.cp_upper(0, 29), 0.10)
        self.assertGreater(rg.cp_upper(0, 28), 0.10)

    def test_cases_needed_table(self):
        self.assertEqual([rg.cases_needed(k, 0.05) for k in (0, 1, 2, 3, 5, 10)], [59, 93, 124, 153, 208, 336])
        self.assertEqual([rg.cases_needed(k, 0.10) for k in (0, 1, 2)], [29, 46, 61])

    def test_known_bound(self):
        self.assertAlmostEqual(rg.cp_upper(9, 300), 0.0518, places=3)
        self.assertAlmostEqual(rg.cp_upper(0, 300), 1 - 0.05 ** (1 / 300), places=6)
        self.assertEqual(rg.cp_upper(5, 5), 1.0)
        self.assertEqual(rg.cp_upper(0, 0), 1.0)

    def test_bound_grows_with_errors_and_shrinks_with_cases(self):
        self.assertLess(rg.cp_upper(2, 300), rg.cp_upper(3, 300))
        self.assertLess(rg.cp_upper(2, 400), rg.cp_upper(2, 300))

    def test_kappa(self):
        pairs = [("pass", "pass")] * 40 + [("pass", "fail")] * 10 + [("fail", "pass")] * 5 + [("fail", "fail")] * 45
        self.assertAlmostEqual(rg.cohen_kappa(pairs), 0.7, places=9)
        self.assertEqual(rg.cohen_kappa([("pass", "pass"), ("fail", "fail")]), 1.0)
        self.assertEqual(rg.cohen_kappa([("pass", "pass")] * 5), 1.0)
        self.assertIsNone(rg.cohen_kappa([]))

    def test_percentile_and_bootstrap(self):
        self.assertEqual(rg.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.95), 10)
        self.assertEqual(rg.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.5), 5)
        low, high = rg.cluster_bootstrap([(f"c{i}", i % 10 == 0) for i in range(200)], None)
        self.assertLess(low, 0.1)
        self.assertGreater(high, 0.1)
        self.assertEqual(rg.cluster_bootstrap([("a", False)] * 20, None), (0.0, 0.0))

    def test_allocation(self):
        seats = rg.allocate({"a": 21, "b": 13, "c": 9}, 10)
        self.assertEqual(sum(seats.values()), 10)
        self.assertEqual(seats["a"], 5)


class Validation(unittest.TestCase):
    def errors(self, data, strict=True):
        return rg.validate(data, None, strict=strict)[0]

    def test_complete_set_is_valid(self):
        errors, warnings, facts = rg.validate(synthetic_set(), None, strict=True)
        self.assertEqual(errors, [], errors[:3])
        self.assertEqual(facts["fail"], 320)
        self.assertEqual(facts["kappa"], 1.0)

    def test_too_few_answers(self):
        data = synthetic_set(concepts=40)
        messages = " ".join(self.errors(data))
        self.assertIn("answers labelled fail", messages)
        self.assertIn("concepts; need at least", messages)

    def test_too_many_per_concept(self):
        data = synthetic_set()
        data["answers"].append(answer(99999, "zz_concept_0", "fail", labels=("fail", "fail")))
        self.assertTrue(any("at most 5 per concept per group" in e for e in self.errors(data)))

    def test_authors_may_not_write_release_answers(self):
        data = synthetic_set()
        data["answers"][0]["source"] = "claude"
        self.assertTrue(any("source must be one of" in e for e in self.errors(data)))
        self.assertEqual([e for e in self.errors(data, strict=False) if "source" in e], [])

    def test_tuning_answers_are_excluded(self):
        tuning, _ = rg.tuning_texts()
        self.assertGreater(len(tuning), 100)
        data = synthetic_set()
        data["answers"][0]["text"] = tuning[0]
        data["answers"][1]["text"] = tuning[5] + " ok"
        self.assertEqual(sum("used for tuning" in e for e in self.errors(data)), 2)

    def test_tuning_concepts_are_excluded(self):
        _, excluded = rg.tuning_texts()
        data = synthetic_set()
        data["answers"][0]["conceptId"] = sorted(excluded)[0]
        self.assertTrue(any("used for tuning; release concepts" in e for e in self.errors(data)))

    def test_duplicates(self):
        data = synthetic_set()
        data["answers"][1]["text"] = data["answers"][0]["text"]
        self.assertTrue(any("same text as" in e for e in self.errors(data)))

    def test_label_quality(self):
        data = synthetic_set()
        for a in data["answers"][:200]:
            a["labels"]["B"] = "fail" if a["labels"]["A"] == "pass" else "pass"
        self.assertTrue(any("kappa" in e for e in self.errors(data)))
        data = synthetic_set()
        for a in data["answers"]:
            a["labels"].pop("B")
        self.assertTrue(any("double-labelled" in e for e in self.errors(data)))

    def test_unadjudicated_disagreement(self):
        data = synthetic_set()
        data["answers"][3]["labels"]["B"] = "fail"
        data["answers"][3]["labels"]["A"] = "pass"
        self.assertTrue(any("nobody adjudicated" in e for e in self.errors(data)))
        data["answers"][3]["adjudicated"] = "pass"
        self.assertFalse(any("nobody adjudicated" in e for e in self.errors(data)))

    def test_dry_run_skips_minimums(self):
        data = synthetic_set(concepts=3)
        self.assertEqual(self.errors(data, strict=False), [])


class Gate(unittest.TestCase):
    def run_gate(self, data, outcomes, dry_run=True):
        """outcomes: {(path, id): outcome} or a function (path, answer) -> (outcome, seconds)."""
        with tempfile.TemporaryDirectory() as tmp:
            set_path, results, report = (os.path.join(tmp, n) for n in ("set.json", "results.csv", "report.md"))
            json.dump(data, open(set_path, "w"))
            with open(results, "w", newline="") as f:
                w = csv.writer(f)
                w.writerow(["id", "path", "outcome", "seconds", "modelCalls", "failedBatches", "trace"])
                for a in data["answers"]:
                    for path in ("model", "fallback"):
                        outcome, seconds = outcomes(path, a)
                        w.writerow([a["id"], path, outcome, seconds, 4, 0, ""])
            args = argparse.Namespace(results=results, set=set_path, report=report, dry_run=dry_run)
            with contextlib.redirect_stdout(io.StringIO()):
                try:
                    rg.cmd_gate(args)
                    code = 0
                except SystemExit as exit_:
                    code = exit_.code
            return code, open(report).read()

    @staticmethod
    def ideal(path, a):
        if path == "fallback":
            return ("likelyMastered" if a["final"] == "pass" and a["id"].endswith("0") else "partial"), 0.1
        return ("mastered" if a["final"] == "pass" else "notYet"), 5.0

    def test_perfect_run_passes(self):
        code, report = self.run_gate(synthetic_set(), self.ideal)
        self.assertEqual(code, 0, report)
        self.assertIn("RELEASE GATE PASSED", report)

    def test_small_sample_cannot_pass_even_with_no_errors(self):
        # 30 wrong answers, none accepted: the upper bound is 9.5%, which does not prove 5%.
        code, report = self.run_gate(synthetic_set(concepts=6, fail_per_concept=5), self.ideal)
        self.assertEqual(code, 1, report)
        self.assertIn("false pass", report)

    def test_false_passes_fail_the_gate(self):
        def outcomes(path, a):
            if path == "model" and a["final"] == "fail" and int(a["id"][1:]) % 12 == 0:  # about 8%
                return "mastered", 5.0
            return self.ideal(path, a)
        code, report = self.run_gate(synthetic_set(), outcomes)
        self.assertEqual(code, 1, report)

    def test_likely_mastered_counts_as_accepted(self):
        def outcomes(path, a):
            if path == "model" and a["final"] == "fail" and int(a["id"][1:]) % 8 == 0:
                return "likelyMastered", 5.0
            return self.ideal(path, a)
        code, report = self.run_gate(synthetic_set(), outcomes)
        self.assertEqual(code, 1, report)
        self.assertIn("Mastered only", report)

    def test_false_fails_fail_the_gate(self):
        def outcomes(path, a):
            if path == "model" and a["final"] == "pass" and int(a["id"][1:]) % 6 == 0:
                return "partial", 5.0
            return self.ideal(path, a)
        self.assertEqual(self.run_gate(synthetic_set(), outcomes)[0], 1)

    def test_clarifications_are_not_false_fails_but_are_limited(self):
        def outcomes(path, a):
            if path == "model" and a["final"] == "pass" and int(a["id"][1:]) % 4 != 0:  # 3 in 4 correct answers: about 33% of all
                return "needsClarification", 5.0
            return self.ideal(path, a)
        code, report = self.run_gate(synthetic_set(), outcomes)
        self.assertEqual(code, 1)
        failed = [line for line in report.splitlines() if "**FAIL**" in line]
        self.assertEqual(len(failed), 1, failed)
        self.assertIn("clarification", failed[0])

    def test_slow_grading_fails(self):
        def outcomes(path, a):
            outcome, seconds = self.ideal(path, a)
            return outcome, (16.0 if path == "model" else seconds)
        self.assertEqual(self.run_gate(synthetic_set(), outcomes)[0], 1)

    def test_fallback_never_mastered(self):
        def outcomes(path, a):
            if path == "fallback" and a["final"] == "pass" and a["id"].endswith("1"):
                return "mastered", 0.1
            return self.ideal(path, a)
        code, report = self.run_gate(synthetic_set(), outcomes)
        self.assertEqual(code, 1)
        self.assertIn("never Mastered", report)

    def test_fallback_false_likely_mastered(self):
        def outcomes(path, a):
            if path == "fallback" and a["final"] == "fail" and int(a["id"][1:]) % 7 == 0:
                return "likelyMastered", 0.1
            return self.ideal(path, a)
        self.assertEqual(self.run_gate(synthetic_set(), outcomes)[0], 1)

    def test_missing_results_fail(self):
        data = synthetic_set()
        with tempfile.TemporaryDirectory() as tmp:
            set_path, results, report = (os.path.join(tmp, n) for n in ("set.json", "results.csv", "report.md"))
            json.dump(data, open(set_path, "w"))
            with open(results, "w", newline="") as f:
                w = csv.writer(f)
                w.writerow(["id", "path", "outcome", "seconds", "modelCalls", "failedBatches", "trace"])
                for a in data["answers"][:100]:
                    w.writerow([a["id"], "model", "mastered" if a["final"] == "pass" else "notYet", 5, 4, 0, ""])
            args = argparse.Namespace(results=results, set=set_path, report=report, dry_run=True)
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as raised:
                rg.cmd_gate(args)
            self.assertEqual(raised.exception.code, 1)
            self.assertIn("every answer was graded", open(report).read())


class Planning(unittest.TestCase):
    def test_plan_is_valid(self):
        with tempfile.TemporaryDirectory() as tmp:
            rg.PLAN, rg.SHEETS = os.path.join(tmp, "plan.json"), os.path.join(tmp, "sheets")
            with contextlib.redirect_stdout(io.StringIO()):
                rg.cmd_plan(argparse.Namespace(concepts=75, seed=2026))
            plan = json.load(open(rg.PLAN))
            _, excluded = rg.tuning_texts()
            self.assertEqual(len(plan["concepts"]), 75)
            self.assertFalse(set(plan["concepts"]) & excluded)
            self.assertEqual(sum(s["intent"] == "shouldNotPass" for s in plan["slots"]), 300)
            self.assertGreaterEqual(sum(s["intent"] == "shouldPass" for s in plan["slots"]), 200)
            per = rg.Counter((s["conceptId"], s["intent"]) for s in plan["slots"])
            self.assertLessEqual(max(per.values()), rg.MAX_PER_CONCEPT_PER_GROUP)
            self.assertGreaterEqual(sum(s["category"] == "ownWords" for s in plan["slots"]) / sum(s["intent"] == "shouldPass" for s in plan["slots"]), 0.6)
            concepts = rg.compiled_concepts()
            for s in plan["slots"]:
                if s["category"] == "misconception":
                    self.assertTrue(concepts[s["conceptId"]]["concept"]["misconceptions"])
                    self.assertTrue(s["misconception"])
            with contextlib.redirect_stdout(io.StringIO()):
                again = rg.cmd_plan(argparse.Namespace(concepts=75, seed=2026))
            self.assertEqual(plan, json.load(open(rg.PLAN)), "the plan is deterministic")


class Workflow(unittest.TestCase):
    def test_sheets_import_and_labels(self):
        with tempfile.TemporaryDirectory() as tmp:
            rg.PLAN, rg.SHEETS, rg.SET = (os.path.join(tmp, "plan.json"), os.path.join(tmp, "sheets"), os.path.join(tmp, "set.json"))
            with contextlib.redirect_stdout(io.StringIO()):
                rg.cmd_plan(argparse.Namespace(concepts=60, seed=1))
            plan = json.load(open(rg.PLAN))
            rows = rg.read_csv(os.path.join(rg.SHEETS, "answers_sheet.csv"))
            self.assertEqual(len(rows), len(plan["slots"]))
            filled = os.path.join(tmp, "filled.csv")
            with open(filled, "w", newline="", encoding="utf-8-sig") as f:
                w = csv.DictWriter(f, fieldnames=list(rows[0]))
                w.writeheader()
                for n, row in enumerate(rows):
                    if n < 40:
                        row["TEXT (fill in)"] = f"a handwritten answer {n} with distinct words q{n}z"
                        row["writtenBy (name or id)"], row["source (student/teacher)"] = "t1", "teacher"
                    w.writerow(row)
            with contextlib.redirect_stdout(io.StringIO()):
                rg.cmd_import_answers(argparse.Namespace(sheet=filled))
                rg.cmd_label_sheets(argparse.Namespace(seed=7, double=0.3))
            self.assertEqual(len(json.load(open(rg.SET))["answers"]), 40)
            a_rows = rg.read_csv(os.path.join(rg.SHEETS, "labels_A.csv"))
            b_rows = rg.read_csv(os.path.join(rg.SHEETS, "labels_B.csv"))
            self.assertEqual(len(a_rows), 40)
            self.assertGreaterEqual(len(b_rows), 12)
            self.assertNotIn("intent", a_rows[0], "labellers must not see the writer's intent")
            for name, sheet_rows, verdict in (("A", a_rows, "pass"), ("B", b_rows, "pass")):
                path = os.path.join(tmp, f"{name}.csv")
                with open(path, "w", newline="", encoding="utf-8-sig") as f:
                    w = csv.DictWriter(f, fieldnames=list(sheet_rows[0]))
                    w.writeheader()
                    for r in sheet_rows:
                        r["verdict (pass/fail)"] = verdict if name == "A" or r["id"].endswith("P1") else "fail"
                        w.writerow(r)
                with contextlib.redirect_stdout(io.StringIO()):
                    rg.cmd_import_labels(argparse.Namespace(sheet=path, labeller=name))
            data = json.load(open(rg.SET))
            self.assertTrue(all("final" in a or len(set(a["labels"].values())) > 1 for a in data["answers"]))
            self.assertTrue(any(len(set(a["labels"].values())) > 1 for a in data["answers"]), "disagreements are flagged, not guessed")


if __name__ == "__main__":
    unittest.main(verbosity=1)
