//
//  Engine tests for RuleEngine.swift (architecture v4.0, change 7). Compiled together with the app's
//  own RuleEngine.swift and CompiledCurriculum.swift by Tools/run_engine_tests.sh, so the code under
//  test is exactly the code the app ships.
//
//  1. Golden scenarios on a hand-built concept (the worked examples from the architecture).
//  2. Every compiled concept: every combination of check results (3^n) when n <= 9, otherwise a
//     seeded random sample, checked against invariants I1, I2, I3, I5 and I7.
//  3. I6: every outcome is reachable for every concept.
//  4. I4: random follow-up merges never change a yes or no without an event that explains it.
//

import Foundation

// MARK: - Harness

var failures: [String] = []
var checksRun = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    checksRun += 1
    if !condition() {
        failures.append(message())
    }
}

/// Deterministic random numbers, so every run tests the same sample.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

func model(_ state: CheckState) -> CheckResult { CheckResult(state: state, source: .model) }

func results(_ states: [String: CheckState]) -> ResultSet { states.mapValues(model) }

/// Order used by I3: higher is better. nil for outcomes that keyPoint checks cannot cause.
func rank(_ outcome: EvaluationOutcome) -> Int? {
    switch outcome {
    case .notGradable, .needsCorrection: nil
    case .offTopic: 0
    case .notYet: 1
    case .partial: 2
    case .needsClarification: 3
    case .likelyMastered: 4
    case .mastered: 5
    }
}

func kind(_ outcome: EvaluationOutcome) -> String {
    switch outcome {
    case .notGradable: "notGradable"
    case .offTopic: "offTopic"
    case .needsCorrection: "needsCorrection"
    case .mastered: "mastered"
    case .likelyMastered: "likelyMastered"
    case .needsClarification: "needsClarification"
    case .partial: "partial"
    case .notYet: "notYet"
    }
}

func describe(_ decision: Decision) -> String {
    "\(decision.outcome) | " + decision.trace.joined(separator: " | ")
}

// MARK: - 1. Golden scenarios

let goldenJSON = """
{"conceptId":"golden","topicId":"t","topicTitle":"T","label":"Golden concept","headingType":null,"sourcePages":[1],
 "conceptHash":"x","cardText":"card","hint":"HINT","probe":"PROBE",
 "relevanceCheck":{"id":"chk_relevance","criterion":"relevant"},
 "keyPoints":[
  {"id":"k1","role":"core","weight":2,"scored":true,"passRule":{"kind":"allRequired"},"followUp":"F1","requiredEvidence":["a"],
   "checks":[{"id":"c1","criterion":"C1","isRequired":true,"lexical":"never","followUp":"F1"},
             {"id":"c1o","criterion":"C1 optional","isRequired":false,"lexical":"never","followUp":"F1"}],"misconceptionIds":["m1"]},
  {"id":"k2","role":"core","weight":2,"scored":true,"passRule":{"kind":"minCount","n":1},"followUp":"F2","requiredEvidence":["b"],
   "checks":[{"id":"c2a","criterion":"C2A","isRequired":false,"lexical":"evidence","followUp":"F2"},
             {"id":"c2b","criterion":"C2B","isRequired":false,"lexical":"never","followUp":"F2"}],"misconceptionIds":[]},
  {"id":"k3","role":"supporting","weight":1,"scored":true,"passRule":{"kind":"allRequired"},"followUp":null,"requiredEvidence":["c"],
   "checks":[{"id":"c3","criterion":"C3","isRequired":true,"lexical":"never","followUp":"HINT"}],"misconceptionIds":[]},
  {"id":"k4","role":"supporting","weight":1,"scored":true,"passRule":{"kind":"anyOf"},"followUp":null,"requiredEvidence":["d"],
   "checks":[{"id":"c4","criterion":"C4","isRequired":false,"lexical":"never","followUp":"HINT"}],"misconceptionIds":[]}],
 "causeLinks":[{"id":"l1","linksChecks":["c1","c2a"],"criterion":"L1","isRequired":true}],
 "misconceptions":[{"id":"m1","wrong":"W","fix":"FIX1","checkId":"mchk_m1","checkCriterion":"x","fixCheckId":"mfix_m1",
                    "fixCheckCriterion":"y","keyPointIds":["k1"],"isRequired":true}],
 "weights":{"core":4,"scored":6},"batches":{"topic":[],"a":[],"b":[]}}
"""
let golden = try JSONDecoder().decode(CompiledConcept.self, from: Data(goldenJSON.utf8))
let allYes: [String: CheckState] = ["chk_relevance": .yes, "c1": .yes, "c1o": .yes, "c2a": .yes, "c2b": .yes,
                                     "c3": .yes, "c4": .yes, "l1": .yes, "mchk_m1": .no]
let oneRound = AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: 3)
let noRounds = AttemptContext(clarificationRoundsLeft: 0, keywordOverlap: 3)

func goldenDecide(_ changes: [String: CheckState], _ context: AttemptContext = oneRound,
                  edit: (inout ResultSet) -> Void = { _ in }) -> Decision {
    var set = results(allYes.merging(changes) { _, new in new })
    edit(&set)
    return RuleEngine.decide(golden, results: set, context: context)
}

func golden(_ name: String, _ decision: Decision, _ outcome: EvaluationOutcome, _ extra: (Decision) -> Bool = { _ in true }) {
    expect(decision.outcome == outcome && extra(decision), "golden \(name): expected \(outcome), got \(describe(decision))")
}

golden("G1 everything right", goldenDecide([:]), .mastered)
golden("G2 one supporting missed, 5/6", goldenDecide(["c4": .no]), .mastered)
golden("G3 both supporting missed, 4/6", goldenDecide(["c3": .no, "c4": .no]), .partial(almostThere: true))
golden("G4 both supporting uncertain", goldenDecide(["c3": .uncertain, "c4": .uncertain]),
       .needsClarification(targetCheckId: "c3")) { $0.report.followUp == "HINT" && $0.report.missing.isEmpty }
golden("G5 same, no round left", goldenDecide(["c3": .uncertain, "c4": .uncertain], noRounds),
       .partial(almostThere: true)) { $0.report.missing == ["C3", "C4"] }
golden("G6 misconception stated", goldenDecide(["mchk_m1": .yes]), .needsCorrection) {
    $0.report.corrections == ["FIX1"] && $0.keyPointOutcomes["k1"] == .misconception
}
golden("G7 misconception unassessed by fallback", goldenDecide([:]) { $0["mchk_m1"] = CheckResult(state: .uncertain, source: .lexical) },
       .likelyMastered)
golden("G8 deciding check from keyword fallback", goldenDecide([:]) { $0["c1"] = CheckResult(state: .yes, source: .lexical) },
       .likelyMastered)
golden("G9 quote check timed out", goldenDecide([:]) { $0["c1"]?.quoteCheck = .timedOut }, .likelyMastered)
golden("G10 provisional-only mode",
       goldenDecide([:], AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: 3, provisionalOnly: true)), .likelyMastered)
let allNo: [String: CheckState] = ["chk_relevance": .no, "c1": .no, "c1o": .no, "c2a": .no, "c2b": .no, "c3": .no, "c4": .no, "l1": .no]
golden("G11 off-topic", goldenDecide(allNo, AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: 0)), .offTopic)
golden("G11b irrelevant only by keyword fallback", goldenDecide(allNo, AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: 0)) {
    $0["chk_relevance"] = CheckResult(state: .no, source: .lexical)
}, .notYet)
golden("G11c keyword overlap present", goldenDecide(allNo, oneRound), .notYet)
golden("G12 judged irrelevant but checks open",
       goldenDecide(allNo.merging(["c1": .uncertain, "c2a": .uncertain]) { _, new in new },
                    AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: 0)),
       .needsClarification(targetCheckId: "chk_relevance")) { $0.report.followUp == "PROBE" }
golden("G13 yes inside a failed keyPoint is still right", goldenDecide(["c1": .no], noRounds), .partial(almostThere: false)) {
    $0.report.right.contains("C1 optional") && $0.report.missing.contains("C1")
}
golden("G14 core failed blocks clarification", goldenDecide(["c1": .no, "c3": .uncertain]), .partial(almostThere: false))

// Merges
do {
    // G15: a stated misconception, then an explicit correction.
    let first = results(allYes.merging(["mchk_m1": .yes]) { _, new in new })
    golden("G15a before correction", RuleEngine.decide(golden, results: first, context: oneRound), .needsCorrection)
    var grading = RuleEngine.FollowUpGrading()
    grading.fixes = ["mfix_m1": .yes]
    let (merged, context, events) = RuleEngine.merge(first, context: oneRound, followUp: grading, concept: golden)
    expect(events.map(\.kind) == [.correction], "golden G15 events: \(events)")
    golden("G15b after correction", RuleEngine.decide(golden, results: merged, context: context), .mastered) {
        $0.revisitLater && $0.report.fixedByStudent == ["FIX1"] && $0.report.corrections.isEmpty
    }

    // G16: no -> yes is a correction; yes -> no is ignored.
    let second = results(allYes.merging(["c3": .no]) { _, new in new })
    grading = RuleEngine.FollowUpGrading()
    grading.resolved = ["c3": model(.yes), "c1": model(.no)]
    let (merged2, _, events2) = RuleEngine.merge(second, context: oneRound, followUp: grading, concept: golden)
    expect(merged2["c3"]?.state == .yes && merged2["c1"]?.state == .yes && events2.map(\.kind) == [.correction],
           "golden G16: c3 \(String(describing: merged2["c3"]?.state)), c1 \(String(describing: merged2["c1"]?.state)), events \(events2)")

    // G17: a contradiction is recorded, asked about, then resolved by a later answer.
    let twoRounds = AttemptContext(clarificationRoundsLeft: 2, keywordOverlap: 3)
    grading = RuleEngine.FollowUpGrading()
    grading.contradictions = ["ctr_c1": .yes]
    let (merged3, context3, events3) = RuleEngine.merge(results(allYes), context: twoRounds, followUp: grading, concept: golden)
    expect(merged3["c1"]?.state == .yes && context3.conflicts.map(\.checkId) == ["c1"] && events3.map(\.kind) == [.contradiction],
           "golden G17 merge: \(context3.conflicts) \(events3)")
    golden("G17b conflict is asked about", RuleEngine.decide(golden, results: merged3, context: context3),
           .needsClarification(targetCheckId: "c1")) { $0.report.followUp == "F1" }
    grading = RuleEngine.FollowUpGrading()
    grading.resolved = ["c1": model(.no)]
    let (merged4, context4, events4) = RuleEngine.merge(merged3, context: context3, followUp: grading, concept: golden)
    expect(merged4["c1"]?.state == .no && context4.conflicts.isEmpty && events4.map(\.kind) == [.conflictResolved]
           && context4.clarificationRoundsLeft == 0, "golden G17 resolve: \(events4) \(context4)")
    golden("G17c after resolving", RuleEngine.decide(golden, results: merged4, context: context4), .partial(almostThere: false))

    // G18: a misconception first stated in the follow-up.
    grading = RuleEngine.FollowUpGrading()
    grading.resolved = ["mchk_m1": model(.yes)]
    let (merged5, context5, events5) = RuleEngine.merge(results(allYes), context: oneRound, followUp: grading, concept: golden)
    expect(events5.map(\.kind) == [.misconceptionStated], "golden G18 events: \(events5)")
    golden("G18b", RuleEngine.decide(golden, results: merged5, context: context5), .needsCorrection)
}
let goldenFailures = failures.count
print("Golden scenarios: \(goldenFailures == 0 ? "all passed" : "\(goldenFailures) failed")")

// MARK: - 2. Every compiled concept

let compiledDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Curriculum/compiled")
let files = try FileManager.default.contentsOfDirectory(at: compiledDir, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasSuffix(".compiled.json") }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
var concepts: [CompiledConcept] = []
for file in files {
    concepts += try JSONDecoder().decode(CompiledChapter.self, from: Data(contentsOf: file)).concepts
}

let exhaustiveLimit = 9
let sampleSize = 20_000
var rng = SplitMix64(state: 2026_10_23)
var exhaustiveConcepts = 0
var assignmentsTested = 0
var outcomeCounts: [String: Int] = [:]
let start = Date()

for concept in concepts {
    let keyPointChecks = concept.keyPoints.flatMap { $0.checks.map(\.id) }
    let variables = [concept.relevanceCheck.id] + keyPointChecks + concept.misconceptions.map(\.checkId) + concept.causeLinks.map(\.id)
    let keyPointCheckSet = Set(keyPointChecks)
    let core = concept.keyPoints.filter { $0.role == .core }
    let n = variables.count
    let exhaustive = n <= exhaustiveLimit
    if exhaustive { exhaustiveConcepts += 1 }
    let total = exhaustive ? Int(pow(3.0, Double(n))) : sampleSize
    let states: [CheckState] = [.yes, .no, .uncertain]
    let contextA = AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: 3)
    let contextB = AttemptContext(clarificationRoundsLeft: 0, keywordOverlap: 0)
    let contextC = AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: 0, provisionalOnly: true)
    var conceptFailures = 0

    for index in 0..<total {
        var assignment: [String: CheckState] = [:]
        var code = index
        for variable in variables {
            if exhaustive {
                assignment[variable] = states[code % 3]
                code /= 3
            } else {
                assignment[variable] = states[Int.random(in: 0..<3, using: &rng)]
            }
        }
        let set = results(assignment)
        assignmentsTested += 1
        let before = failures.count

        for context in [contextA, contextB, contextC] {
            let decision = RuleEngine.decide(concept, results: set, context: context)
            outcomeCounts[kind(decision.outcome), default: 0] += 1
            let stated = concept.misconceptions.contains { assignment[$0.checkId] == .yes }

            // I2: a stated, uncorrected misconception always gives Needs correction (after rows 0 and 1).
            if stated && decision.outcome != .offTopic {
                expect(decision.outcome == .needsCorrection, "I2 \(concept.conceptId): \(describe(decision))")
            }
            // I1: Mastered needs every required misconception ruled out, and never in provisional-only mode.
            if decision.outcome == .mastered {
                expect(!context.provisionalOnly, "I1 provisional \(concept.conceptId): \(describe(decision))")
                expect(concept.misconceptions.filter(\.isRequired).allSatisfy { assignment[$0.checkId] == .no },
                       "I1 misconceptions \(concept.conceptId): \(describe(decision))")
            }
            // I7: the outcome agrees with the facts and with its own properties.
            switch decision.outcome {
            case .mastered, .likelyMastered:
                expect(core.allSatisfy { decision.keyPointOutcomes[$0.id] == .pass }
                       && 10 * decision.passedWeight >= 7 * decision.scoredWeight,
                       "I7 mastery facts \(concept.conceptId): \(describe(decision))")
            case .needsClarification:
                expect(context.clarificationRoundsLeft > 0 && decision.report.followUp != nil && decision.report.missing.isEmpty,
                       "I7 clarification \(concept.conceptId): \(describe(decision))")
            case .offTopic:
                expect(!keyPointCheckSet.contains { assignment[$0] == .yes } && context.keywordOverlap == 0,
                       "I7 off-topic \(concept.conceptId): \(describe(decision))")
            default:
                break
            }
            expect(decision.outcome.isProvisional == (decision.outcome == .likelyMastered)
                   && decision.outcome.savesProgress == (decision.outcome.isTerminal && decision.outcome != .notGradable),
                   "I7 properties \(concept.conceptId): \(decision.outcome)")
            if decision.report.followUp != nil {
                expect({ if case .needsClarification = decision.outcome { return true } else { return false } }(),
                       "I7 follow-up without clarification \(concept.conceptId): \(describe(decision))")
            }
        }

        // I5: the same input always gives the same decision.
        let first = RuleEngine.decide(concept, results: set, context: contextA)
        expect(first == RuleEngine.decide(concept, results: set, context: contextA), "I5 \(concept.conceptId)")

        // I1, keyword fallback: if every yes keyPoint check came from the fallback, never Mastered.
        if keyPointChecks.contains(where: { assignment[$0] == .yes }) {
            var fallback = set
            for id in keyPointChecks where assignment[id] == .yes {
                fallback[id] = CheckResult(state: .yes, source: .lexical)
            }
            let decision = RuleEngine.decide(concept, results: fallback, context: contextA)
            expect(decision.outcome != .mastered, "I1 fallback \(concept.conceptId): \(describe(decision))")
        }

        // I3: turning one keyPoint check from no to yes never makes the outcome worse.
        if let baseRank = rank(first.outcome) {
            for id in keyPointChecks where assignment[id] == .no {
                var flipped = set
                flipped[id] = model(.yes)
                let after = RuleEngine.decide(concept, results: flipped, context: contextA)
                if let afterRank = rank(after.outcome) {
                    expect(afterRank >= baseRank, "I3 \(concept.conceptId) flipping \(id): \(first.outcome) -> \(describe(after))")
                }
            }
        }
        if failures.count > before { conceptFailures += 1 }
        if conceptFailures >= 5 { break }  // enough examples for one concept
    }
}
let sweepSeconds = Date().timeIntervalSince(start)
print("Sweep: \(concepts.count) concepts (\(exhaustiveConcepts) exhaustive, \(concepts.count - exhaustiveConcepts) sampled), "
      + "\(assignmentsTested) result combinations, \(String(format: "%.1f", sweepSeconds)) s")
print("Outcomes seen: " + outcomeCounts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " · "))

// MARK: - 3. I6: every outcome is reachable for every concept

for concept in concepts {
    let keyPointChecks = concept.keyPoints.flatMap { $0.checks.map(\.id) }
    func build(_ keyPointState: CheckState, misconception: CheckState = .no, relevance: CheckState = .yes,
               edit: (inout [String: CheckState]) -> Void = { _ in }) -> ResultSet {
        var assignment: [String: CheckState] = [concept.relevanceCheck.id: relevance]
        for id in keyPointChecks { assignment[id] = keyPointState }
        for link in concept.causeLinks { assignment[link.id] = keyPointState }
        for misconception_ in concept.misconceptions { assignment[misconception_.checkId] = misconception }
        edit(&assignment)
        return results(assignment)
    }
    func reach(_ name: String, _ set: ResultSet, _ context: AttemptContext, _ test: (EvaluationOutcome) -> Bool) {
        let decision = RuleEngine.decide(concept, results: set, context: context)
        expect(test(decision.outcome), "I6 \(concept.conceptId) cannot reach \(name): \(describe(decision))")
    }
    let open = AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: 3)
    let closed = AttemptContext(clarificationRoundsLeft: 0, keywordOverlap: 0)
    reach("mastered", build(.yes), open) { $0 == .mastered }
    reach("likelyMastered", build(.yes), AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: 3, provisionalOnly: true)) { $0 == .likelyMastered }
    if !concept.misconceptions.isEmpty {
        reach("needsCorrection", build(.yes, misconception: .yes), open) { $0 == .needsCorrection }
    }
    reach("offTopic", build(.no, relevance: .no), closed) { $0 == .offTopic }
    reach("notYet", build(.no), open) { $0 == .notYet }
    let firstCore = concept.keyPoints.first { $0.role == .core }!
    reach("needsClarification", build(.yes) { a in firstCore.checks.forEach { a[$0.id] = .uncertain } }, open) {
        if case .needsClarification = $0 { return true } else { return false }
    }
    if concept.keyPoints.filter(\.scored).count >= 2 {
        reach("partial", build(.yes) { a in firstCore.checks.forEach { a[$0.id] = .no } }, closed) {
            if case .partial = $0 { return true } else { return false }
        }
    }
}

// MARK: - 4. I4: merges

var mergesTested = 0
for _ in 0..<100_000 {
    let concept = concepts[Int.random(in: 0..<concepts.count, using: &rng)]
    let keyPointChecks = concept.keyPoints.flatMap { $0.checks.map(\.id) }
    let ids = keyPointChecks + concept.misconceptions.map(\.checkId) + concept.causeLinks.map(\.id)
    let states: [CheckState] = [.yes, .no, .uncertain]
    var previous: ResultSet = [:]
    for id in ids { previous[id] = model(states[Int.random(in: 0..<3, using: &rng)]) }
    var context = AttemptContext(clarificationRoundsLeft: Int.random(in: 0...2, using: &rng), keywordOverlap: 2)
    for id in keyPointChecks where previous[id]?.state == .yes && Bool.random(using: &rng) && Int.random(in: 0..<4, using: &rng) == 0 {
        context.conflicts.append(Conflict(checkId: id, round: 0))
    }
    var grading = RuleEngine.FollowUpGrading()
    for id in ids where Bool.random(using: &rng) { grading.resolved[id] = model(states[Int.random(in: 0..<3, using: &rng)]) }
    for misconception in concept.misconceptions where Bool.random(using: &rng) {
        grading.fixes[misconception.fixCheckId] = Bool.random(using: &rng) ? .yes : .no
    }
    for id in keyPointChecks where Int.random(in: 0..<4, using: &rng) == 0 { grading.contradictions["ctr_" + id] = .yes }

    let (merged, updated, events) = RuleEngine.merge(previous, context: context, followUp: grading, concept: concept)
    mergesTested += 1
    let conflictedBefore = Set(context.conflicts.map(\.checkId))
    for id in ids {
        let old = previous[id]!.state
        let new = merged[id]!.state
        guard old != new else { continue }
        let explained = events.contains { $0.checkId == id && $0.from == old && $0.to == new }
        let lastEvent = merged[id]!.history.last?.event
        if old == .uncertain {
            expect(explained && lastEvent == .newEvidence, "I4 new evidence \(id): \(old)->\(new) \(events)")
        } else if old == .no && new == .yes {
            expect(explained && [.correction, .misconceptionStated, .conflictResolved].contains(lastEvent),
                   "I4 no->yes \(id): \(events)")
        } else {
            // yes -> no only when a recorded conflict is resolved by a later answer.
            expect(old == .yes && conflictedBefore.contains(id) && lastEvent == .conflictResolved,
                   "I4 forbidden change \(id): \(old)->\(new) \(events)")
        }
    }
    for conflict in updated.conflicts {
        expect(merged[conflict.checkId]?.state == .yes, "I4 conflict on a check that is not yes: \(conflict)")
    }
    for misconception in concept.misconceptions where merged[misconception.checkId]?.corrected == true {
        let wasCorrected = previous[misconception.checkId]?.corrected == true
        expect(wasCorrected || (grading.fixes[misconception.fixCheckId] == .yes && merged[misconception.checkId]?.state == .yes),
               "I4 correction without an explicit fix: \(misconception.id)")
    }
    expect(updated.clarificationRoundsLeft == max(0, context.clarificationRoundsLeft - 1) && updated.round == context.round + 1,
           "I4 rounds: \(context.clarificationRoundsLeft) -> \(updated.clarificationRoundsLeft)")
}
print("Merges: \(mergesTested) random follow-ups")

// MARK: - Result

print("Checks run: \(checksRun)")
if failures.isEmpty {
    print("ALL PASSED")
} else {
    let byInvariant = Dictionary(grouping: failures) { String($0.prefix { $0 != " " }) }.mapValues(\.count)
    print("\(failures.count) FAILED: " + byInvariant.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " · "))
    print("First failures:")
    for failure in failures.prefix(25) { print("  - " + failure) }
    exit(1)
}
