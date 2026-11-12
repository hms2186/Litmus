//
//  Milestone 5 tests: background re-grade of provisional records, the 30-day cleanup, review cards,
//  and the drift check. Compiled with the app's own source files by Tools/run_maintenance_tests.sh.
//

import Foundation
import SwiftData
import os

var failures: [String] = []
var checksRun = 0

func expect(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    checksRun += 1
    if !condition { failures.append("\(name)\(detail().isEmpty ? "" : ": " + detail())") }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let compiled = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Litmus/Compiled"), includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasSuffix(".compiled.json") }
let store = CompiledCurriculumStore(urls: compiled)
let entry = store.entry(forLabel: "Money as a Medium of Exchange")!
let money = entry.concept
let economics3 = entry.chapter

let dcw = "chk_eco3_double_coincidence"
let moe = "chk_eco3_medium_of_exchange"
let link = "lnk_eco3_money_removes_dcw"
let mchk = "mchk_misc_eco3_barter_needs_money"
let goodAnswer = "A shoe maker who wants wheat has to find a farmer who has wheat and also wants shoes. Both must want what the other has. With money, the shoe maker sells shoes to anyone for money and then buys wheat from anyone, so he no longer needs that exact match."
let quotes = [dcw: "Both must want what the other has", moe: "so he no longer needs that exact match",
              mchk: "With money, the shoe maker sells shoes to anyone for money"]

// MARK: - Fixture transport

nonisolated func fixtureIsProof(_ instructions: String) -> Bool { instructions.hasPrefix("You copy evidence") }
nonisolated func fixtureIds(_ prompt: String) -> [String] {
    prompt.split(separator: "\n").compactMap { line in
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let id = line[..<colon]
        return !id.isEmpty && id != "IMPORTANT" && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } && id.first!.isLetter ? String(id) : nil
    }
}

nonisolated final class Calls: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)
    func bump() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

/// `truth(id, prompt)`: nil leaves the ID out; throwing `unusable` returns an empty reply.
nonisolated struct FixtureTransport: ModelTransport {
    var ready = true
    let calls = Calls()
    let truth: @Sendable (String, String) -> Bool?
    var isReady: Bool { ready }
    func respond(instructions: String, prompt: String, maximumTokens: Int) async throws -> String {
        calls.bump()
        let ids = fixtureIds(prompt)
        if fixtureIsProof(instructions) { return ids.map { "\($0): \(quotes[$0] ?? "NONE")" }.joined(separator: "\n") }
        return "{" + ids.compactMap { id in truth(id, prompt).map { "\"\(id)\": \($0)" } }.joined(separator: ", ") + "}"
    }
}

let fast = GradingSettings(perBatchSeconds: 0.5, totalSeconds: 2.0)
func coordinator(_ transport: FixtureTransport, provisionalOnly: Bool = false) -> GradingCoordinator {
    var settings = fast
    settings.provisionalOnly = provisionalOnly
    return GradingCoordinator(transport: transport, settings: settings)
}

/// All correct, misconception not stated; a mastered re-grade.
let allGood = FixtureTransport(truth: { id, _ in !id.hasPrefix("mchk_") })

// A saved Likely mastered result: one deciding check came from the keyword fallback and the
// misconception was never assessed.
func likelyResults() -> ResultSet {
    [
        "chk_relevance": CheckResult(state: .yes, source: .model),
        dcw: CheckResult(state: .yes, source: .lexical),
        moe: CheckResult(state: .yes, source: .model, quoteCheck: .proven, quote: quotes[moe]),
        link: CheckResult(state: .yes, source: .model),
        mchk: CheckResult(state: .uncertain, source: .lexical),
    ]
}
let likelyDecision = RuleEngine.decide(money, results: likelyResults(),
                                       context: AttemptContext(clarificationRoundsLeft: 0, keywordOverlap: 3),
                                       articulationChecks: economics3.articulationChecks)
expect(likelyDecision.outcome == .likelyMastered, "setup: saved result is Likely mastered", "\(likelyDecision.trace)")

// MARK: - 1. Re-grade

func regrade(_ transport: FixtureTransport, previous: ResultSet = likelyResults()) async -> GradingOutcome? {
    guard case .graded(let o) = await coordinator(transport).regrade(transcripts: [goodAnswer], previous: previous,
                                                                      concept: money, chapter: economics3) else { return nil }
    return o
}

var o = await regrade(allGood)
expect(o?.decision.outcome == .mastered && o?.results[dcw]?.source == .model && o?.results[mchk]?.state == .no,
       "R1 re-grade confirms mastery", "\(String(describing: o?.decision.trace))")

// R2 the model now finds the misconception, backed by the student's words: a problem.
let finds = FixtureTransport(truth: { id, _ in id.hasPrefix("mchk_") ? true : true })
o = await regrade(finds)
expect(o?.decision.outcome == .needsCorrection, "R2 re-grade finds a misconception", "\(String(describing: o?.decision.trace))")

// R3 checks the model already graded keep their results, even if the model would now answer otherwise.
let contrary = FixtureTransport(truth: { id, _ in id == dcw ? true : (id.hasPrefix("mchk_") ? false : false) })
o = await regrade(contrary)
expect(o?.results[moe]?.state == .yes && o?.results[link]?.state == .yes, "R3 model-graded checks are kept",
       "\(String(describing: o?.results.mapValues(\.state)))")

// R4 the model fails: the earlier results stay and the answer stays provisional.
let broken = FixtureTransport(truth: { _, _ in nil })
o = await regrade(broken)
expect(o?.results[dcw]?.source == .lexical && o?.decision.outcome == .likelyMastered, "R4 failed re-grade keeps earlier results",
       "\(String(describing: o?.decision.trace))")

// MARK: - 2. Maintenance

let container = try ModelContainer(for: ConceptProgress.self, AttemptRecord.self, ProvisionalRecord.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let context = ModelContext(container)

func savedLikely(createdAt: Date = .now, hash: String? = nil) -> UUID {
    let outcome = GradingOutcome(answers: [goodAnswer], results: likelyResults(), context: AttemptContext(clarificationRoundsLeft: 0, keywordOverlap: 3),
                                 decision: likelyDecision, events: [], log: GradingLog())
    let id = UUID()
    ProgressRecorder.record(outcome, concept: money, schemaRevision: 1, attemptId: id, in: context, now: createdAt)
    if let hash, let record = try? context.fetch(FetchDescriptor<ProvisionalRecord>()).first { record.conceptHash = hash }
    return id
}
func records() -> [ProvisionalRecord] { (try? context.fetch(FetchDescriptor<ProvisionalRecord>())) ?? [] }
func progress() -> ConceptProgress? {
    let id = money.conceptId
    return try? context.fetch(FetchDescriptor<ConceptProgress>(predicate: #Predicate { $0.conceptId == id })).first
}
func clear() {
    try? context.delete(model: ProvisionalRecord.self)
    try? context.delete(model: ConceptProgress.self)
    try? context.delete(model: AttemptRecord.self)
    try? context.save()
}
func maintain(_ transport: FixtureTransport, build: String = "build-A", provisionalOnly: Bool = false, now: Date = .now) async -> MaintenanceReport {
    await ProvisionalMaintenance.run(context: context, store: store, coordinator: coordinator(transport, provisionalOnly: provisionalOnly),
                                     osBuild: build, now: now)
}

// P1 confirmed: progress upgraded quietly, transcript deleted.
_ = savedLikely()
var report = await maintain(allGood)
expect(report.confirmed == [money.conceptId] && records().isEmpty && progress()?.status == "mastered"
       && progress()?.isProvisional == false && progress()?.everMastered == true, "P1 confirmed by re-grade", "\(report)")

// P2 a problem: a review card that keeps the student's words; acted on once.
clear(); _ = savedLikely()
let findsAgain = FixtureTransport(truth: { _, _ in true })
report = await maintain(findsAgain)
let card = ProvisionalMaintenance.reviewCard(for: money.conceptId, in: context)
expect(report.reviewCards == [money.conceptId] && card?.transcripts == [goodAnswer] && card?.regradeOutcome == "needsCorrection"
       && card?.reviewNotes.isEmpty == false && progress()?.needsReview == true && progress()?.isProvisional == false,
       "P2 review card", "\(report)")
let callsBefore = findsAgain.calls.value
report = await maintain(findsAgain)
expect(findsAgain.calls.value == callsBefore && report.reviewCards.isEmpty, "P3 a review card is not re-graded again")
if let card { ProvisionalMaintenance.dismissReviewCard(card, in: context) }
expect(records().isEmpty, "P4 dismissing the review card deletes the transcript")

// P5 still Likely mastered: tried once per OS build.
clear(); _ = savedLikely()
let stillUnsure = FixtureTransport(truth: { id, _ in id.hasPrefix("mchk_") ? nil : true })
report = await maintain(stillUnsure)
let firstCalls = stillUnsure.calls.value
expect(report.stillProvisional == [money.conceptId] && records().first?.lastTriedBuild == "build-A", "P5 still provisional", "\(report)")
_ = await maintain(stillUnsure)
expect(stillUnsure.calls.value == firstCalls, "P6 not retried on the same build")
_ = await maintain(stillUnsure, build: "build-B")
expect(stillUnsure.calls.value > firstCalls, "P7 retried after the OS build changes")

// P8 the concept changed: no re-grade, a live revisit instead.
clear(); _ = savedLikely(hash: "an-old-hash")
report = await maintain(allGood)
expect(report.conceptChanged == [money.conceptId] && records().isEmpty && progress()?.pendingRevisit == true,
       "P8 concept changed", "\(report)")

// P9 the next saved attempt clears the revisit flag.
_ = savedLikely()
expect(progress()?.pendingRevisit == false, "P9 a new attempt clears the revisit")

// P10 30 days: an expired provisional record becomes a revisit; an expired review card is deleted.
clear(); _ = savedLikely(createdAt: Date.now.addingTimeInterval(-31 * 86_400))
report = await maintain(allGood)
expect(report.expired == [money.conceptId] && records().isEmpty && progress()?.pendingRevisit == true, "P10 expired record", "\(report)")
clear(); _ = savedLikely(createdAt: Date.now.addingTimeInterval(-31 * 86_400))
records().first?.regradeOutcome = "partial"
report = await maintain(allGood)
expect(records().isEmpty && progress()?.pendingRevisit == false, "P11 expired review card is deleted without a revisit")

// P12 provisional-only (drift not checked) or no model: nothing is re-graded, nothing is lost.
clear(); _ = savedLikely()
report = await maintain(allGood, provisionalOnly: true)
expect(report.skippedModelNotReady == 1 && records().count == 1 && allGood.calls.value >= 0, "P12 provisional-only skips re-grades", "\(report)")
report = await maintain(FixtureTransport(ready: false, truth: { _, _ in true }))
expect(report.skippedModelNotReady == 1 && records().count == 1, "P13 no model: kept for later", "\(report)")

// MARK: - 3. Drift

let set = try JSONDecoder().decode(DriftSet.self, from: Data(contentsOf: root.appending(path: "Litmus/drift_set.json")))
expect(set.answers.count == 30 && set.answers.allSatisfy { store.entriesById[$0.conceptId] != nil }, "D0 drift set is complete")

// A model that agrees with every label.
let byText = Dictionary(uniqueKeysWithValues: set.answers.map { ($0.text, Set($0.yes)) })
let perfect = FixtureTransport(truth: { id, prompt in
    let yes = byText.first { prompt.contains($0.key) }?.value ?? []
    return yes.contains(id)
})
let perfectRun = await DriftCheck.measure(set, store: store, transport: perfect)
expect(perfectRun?.agreement == 1.0 && perfectRun?.answers == 30, "D1 perfect agreement", "\(String(describing: perfectRun))")

let allNo = await DriftCheck.measure(set, store: store, transport: FixtureTransport(truth: { _, _ in false }))
let labelled = set.answers.reduce(0) { total, answer in
    total + GradingCoordinator.catalog(store.entriesById[answer.conceptId]!.concept).keys.filter { !answer.skip.contains($0) }.count
}
let yesLabels = set.answers.reduce(0) { $0 + $1.yes.count }
expect(allNo.map { abs($0.agreement - Double(labelled - yesLabels) / Double(labelled)) < 1e-9 } == true,
       "D2 an all-no model scores the share of no labels", "\(String(describing: allNo))")
expect(await DriftCheck.measure(set, store: store, transport: FixtureTransport(ready: false, truth: { _, _ in true })) == nil,
       "D3 no measurement without the model")

let baseline = DriftBaseline(agreement: 0.9, checks: 300, measuredOn: "test", osBuild: "test")
func measurement(_ agreement: Double) -> DriftCheck.Measurement { .init(agreement: agreement, checks: 300, answers: 30, failedBatches: 0) }
expect(DriftCheck.passes(measurement(0.86), baseline: baseline) && !DriftCheck.passes(measurement(0.85), baseline: baseline)
       && DriftCheck.passes(measurement(0.1), baseline: nil), "D4 pass rule: 95% of the baseline")

let defaults = UserDefaults(suiteName: "litmus-drift-test-\(UUID().uuidString)")!
let monitor = DriftMonitor(defaults: defaults)
expect(monitor.provisionalOnly(build: "A"), "D5 provisional-only until checked")
monitor.record(measurement(0.88), baseline: baseline, build: "A")
expect(!monitor.provisionalOnly(build: "A") && monitor.provisionalOnly(build: "B"), "D6 a pass counts for that build only")
monitor.record(measurement(0.5), baseline: baseline, build: "B")
expect(monitor.provisionalOnly(build: "B") && monitor.isChecked(build: "B"), "D7 a failed check keeps provisional-only")

// D9 a run where most model calls fail is inconclusive: nothing is recorded, still provisional-only.
let failing = await DriftCheck.measure(set, store: store, transport: FixtureTransport(truth: { _, _ in nil }))
expect(failing?.isInconclusive == true, "D9 mostly failed calls are inconclusive", "\(String(describing: failing))")
let inconclusiveMonitor = DriftMonitor(defaults: UserDefaults(suiteName: "litmus-drift-test-\(UUID().uuidString)")!)
let ran = await inconclusiveMonitor.runIfNeeded(set: set, store: store, transport: FixtureTransport(truth: { _, _ in nil }),
                                                build: "C", isBusy: { false })
expect(!ran && !inconclusiveMonitor.isChecked(build: "C") && inconclusiveMonitor.provisionalOnly(build: "C"),
       "D10 an inconclusive run records nothing")

let busyCalls = OSAllocatedUnfairLock(initialState: 0)
let waited = await DriftCheck.measure(DriftSet(version: 1, note: nil, baseline: nil, answers: Array(set.answers.prefix(1))),
                                      store: store, transport: perfect,
                                      isBusy: { busyCalls.withLock { $0 += 1; return $0 < 2 } })
expect(waited?.answers == 1 && busyCalls.withLock { $0 } >= 2, "D8 waits while a student's answer is being graded")

// MARK: - Result

print("Maintenance tests: \(checksRun) checks")
if failures.isEmpty {
    print("ALL PASSED")
} else {
    print("\(failures.count) FAILED:")
    for failure in failures { print("  - " + failure) }
    exit(1)
}
