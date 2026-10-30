//
//  App-flow tests for Milestone 4. Compiled with the app's own CompiledCurriculumStore.swift,
//  AttemptMachine.swift, ProgressStore.swift and the grading files by Tools/run_app_flow_tests.sh.
//
//  1. The store loads the compiled chapters and refuses unsupported ones.
//  2. Phase 2 answer sorting.
//  3. Every attempt-state transition.
//  4. Progress is saved only as EvaluationOutcome allows (in-memory SwiftData).
//  5. Whole journeys, driven the way FeedbackViewModel drives them.
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

let compiledDir = URL(fileURLWithPath: CommandLine.arguments[1])
let compiledURLs = try FileManager.default.contentsOfDirectory(at: compiledDir, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasSuffix(".compiled.json") }

// MARK: - 1. Store

let store = CompiledCurriculumStore(urls: compiledURLs)
expect(store.refused.isEmpty && store.entriesById.count == 718 && store.entriesByLabel.count == 718,
       "S1 loads all compiled concepts", "\(store.entriesById.count) by id, \(store.entriesByLabel.count) by label, refused \(store.refused)")
let moneyEntry = store.entry(forLabel: "Money as a Medium of Exchange")
expect(moneyEntry?.concept.conceptId == "eco10_ch3_t1_c1" && moneyEntry?.chapter.subject == "Economics", "S2 lookup by label")

let tempDir = FileManager.default.temporaryDirectory.appending(path: "litmus-store-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
var future = try String(contentsOf: compiledURLs.first { $0.lastPathComponent.contains("Economics_10_ch3") }!, encoding: .utf8)
future = future.replacingOccurrences(of: "\"compilerVersion\": \"1.0.0\"", with: "\"compilerVersion\": \"2.0.0\"")
let futureURL = tempDir.appending(path: "ncert_future.compiled.json")
try future.write(to: futureURL, atomically: true, encoding: .utf8)
let brokenURL = tempDir.appending(path: "ncert_broken.compiled.json")
try "{ not json".write(to: brokenURL, atomically: true, encoding: .utf8)
let strict = CompiledCurriculumStore(urls: [futureURL, brokenURL])
expect(strict.entriesById.isEmpty && strict.refused.count == 2 && strict.refused.contains { $0.reason.contains("2.0.0") },
       "S3 refuses unsupported or unreadable files", "\(strict.refused)")

// MARK: - 2. Answer sorting

let money = moneyEntry!.concept
let economics3 = moneyEntry!.chapter
func sort(_ text: String, confidence: Double? = nil) -> AnswerSorting {
    AnswerSorter.sort(text, confidence: confidence, concept: money, vocabulary: economics3.chapterVocabulary)
}
expect(sort("   ") == .notGradable(.empty), "A1 empty")
expect(sort("Money is used to buy things in a market", confidence: 0.2) == .notGradable(.unintelligible), "A2 low confidence")
expect(sort("I don't know") == .notGradable(.dontKnow) && sort("no idea really") == .notGradable(.dontKnow), "A3 don't know")
expect(sort("it is good") == .notGradable(.tooShort), "A4 short with no matching words")
if case .gradable = sort("double coincidence of wants") { expect(true, "A5") } else { expect(false, "A5 short but with chapter words", "\(sort("double coincidence of wants"))") }
if case .gradable(let overlap) = sort("People swap things they have for things they want from other people.") {
    expect(overlap >= 0, "A6 long answer without chapter words is still graded")
} else {
    expect(false, "A6 long answer without chapter words is still graded")
}
expect(sort("I don't know much, but money lets a shoe maker sell shoes to anyone and buy wheat from anyone else.") != .notGradable(.dontKnow),
       "A7 'I don't know' inside a real answer is not a don't-know")

// MARK: - 3. State machine

var machine = AttemptMachine()
machine.handle(.submit(.notGradable(.tooShort)))
expect(machine.state == .reprompt(.tooShort, followUpPending: false) && !machine.offerKeyboard, "M1 re-prompt")
machine.handle(.submit(.notGradable(.empty)))
expect(machine.offerKeyboard, "M2 keyboard offered after two re-prompts")
machine.handle(.submit(.gradable(keywordOverlap: 2)))
expect(machine.state == .grading(followUp: false) && machine.consecutiveReprompts == 0, "M3 grading a first answer")
machine.handle(.submit(.gradable(keywordOverlap: 2)))
expect(machine.state == .grading(followUp: false), "M4 a second submit while grading is ignored")
machine.handle(.graded(.needsClarification(targetCheckId: "x")))
expect(machine.state == .awaitingFollowUp(targetCheckId: "x") && machine.nextAnswerIsFollowUp, "M5 clarification")
machine.handle(.submit(.notGradable(.empty)))
expect(machine.state == .reprompt(.empty, followUpPending: true) && machine.nextAnswerIsFollowUp, "M6 a re-prompt keeps the follow-up pending")
machine.handle(.submit(.gradable(keywordOverlap: 0)))
expect(machine.state == .grading(followUp: true), "M7 the next answer is graded as a follow-up")
machine.handle(.graded(.partial(almostThere: true)))
expect(machine.state == .finished(.partial(almostThere: true)) && !machine.nextAnswerIsFollowUp, "M8 finished")
machine.handle(.submit(.gradable(keywordOverlap: 1)))
expect(machine.state == .grading(followUp: false), "M9 after a final outcome the next answer starts fresh")
machine.handle(.graded(.needsCorrection))
expect(machine.state == .correcting && machine.nextAnswerIsFollowUp, "M10 a correction retry continues the attempt")
machine.handle(.submit(.gradable(keywordOverlap: 1)))
machine.handle(.graded(nil))
expect(machine.state == .blocked && !machine.nextAnswerIsFollowUp, "M11 guardrail refusal: not graded, next answer fresh")
machine.handle(.submit(.gradable(keywordOverlap: 1)))
machine.handle(.graded(.offTopic))
expect(machine.state == .offTopic && !machine.nextAnswerIsFollowUp, "M12 off-topic redirect")
machine.handle(.submit(.gradable(keywordOverlap: 1)))
machine.handle(.reset)
machine.handle(.graded(.mastered))
expect(machine.state == .ready, "M13 a late result after leaving the concept is dropped")

// MARK: - Fixture transport (as in the grader tests)

nonisolated enum FixtureStyle: Sendable { case screening, topic, comparison, proof }
nonisolated func fixtureStyle(_ instructions: String) -> FixtureStyle {
    if instructions.hasPrefix("You copy evidence") { return .proof }
    if instructions.hasPrefix("You compare") { return .comparison }
    if instructions.hasPrefix("You read") { return .topic }
    return .screening
}
nonisolated func fixtureIds(_ prompt: String) -> [String] {
    prompt.split(separator: "\n").compactMap { line in
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let id = line[..<colon]
        return !id.isEmpty && id != "IMPORTANT" && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } && id.first!.isLetter ? String(id) : nil
    }
}
/// `truth` returns nil to leave an ID out of the reply.
nonisolated struct FixtureTransport: ModelTransport {
    let truth: @Sendable (String) -> Bool?
    let quote: @Sendable (String) -> String
    var isReady: Bool { true }
    func respond(instructions: String, prompt: String, maximumTokens: Int) async throws -> String {
        let ids = fixtureIds(prompt)
        if fixtureStyle(instructions) == .proof { return ids.map { "\($0): \(quote($0))" }.joined(separator: "\n") }
        return "{" + ids.compactMap { id in truth(id).map { "\"\(id)\": \($0)" } }.joined(separator: ", ") + "}"
    }
}

let dcw = "chk_eco3_double_coincidence"
let moe = "chk_eco3_medium_of_exchange"
let goodAnswer = "A shoe maker who wants wheat has to find a farmer who has wheat and also wants shoes. Both must want what the other has. With money, the shoe maker sells shoes to anyone for money and then buys wheat from anyone, so he no longer needs that exact match."
let quotes = [dcw: "Both must want what the other has", moe: "so he no longer needs that exact match"]
let fast = GradingSettings(perBatchSeconds: 0.5, totalSeconds: 2.0)

func coordinator(_ truth: @escaping @Sendable (String) -> Bool?) -> GradingCoordinator {
    GradingCoordinator(transport: FixtureTransport(truth: truth, quote: { quotes[$0] ?? "NONE" }), settings: fast)
}
func graded(_ result: GradingResult) -> GradingOutcome? {
    if case .graded(let outcome) = result { return outcome }
    return nil
}

// MARK: - 4. Progress

let container = try ModelContainer(for: ConceptProgress.self, AttemptRecord.self, ProvisionalRecord.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let context = ModelContext(container)
func progress(_ id: String) -> ConceptProgress? {
    try? context.fetch(FetchDescriptor<ConceptProgress>(predicate: #Predicate { $0.conceptId == id })).first
}
func provisionalCount(_ id: String) -> Int {
    (try? context.fetchCount(FetchDescriptor<ProvisionalRecord>(predicate: #Predicate { $0.conceptId == id }))) ?? -1
}
func attemptCount() -> Int { (try? context.fetchCount(FetchDescriptor<AttemptRecord>())) ?? -1 }

// Likely mastered: saved as provisional, with the transcript.
let likely = graded(await coordinator({ id in id != "chk_relevance" ? !id.hasPrefix("mchk_") : true }).grade(answer: goodAnswer, concept: money, chapter: economics3))
let likelyAsProvisional: GradingOutcome? = likely.map { outcome in
    // Simulate an unassessed misconception: the rules then give Likely mastered.
    var results = outcome.results
    results["mchk_misc_eco3_barter_needs_money"] = CheckResult(state: .uncertain, source: .lexical)
    let decision = RuleEngine.decide(money, results: results, context: outcome.context, articulationChecks: economics3.articulationChecks)
    return GradingOutcome(answers: outcome.answers, results: results, context: outcome.context, decision: decision, events: [], log: outcome.log)
}
expect(likelyAsProvisional?.decision.outcome == .likelyMastered, "P0 setup", "\(String(describing: likelyAsProvisional?.decision.outcome))")
if let likelyAsProvisional {
    expect(ProgressRecorder.record(likelyAsProvisional, concept: money, schemaRevision: 1, attemptId: UUID(), in: context), "P1 likely mastered is saved")
    let saved = progress(money.conceptId)
    let record = try? context.fetch(FetchDescriptor<ProvisionalRecord>()).first
    expect(saved?.status == "likelyMastered" && saved?.isProvisional == true && saved?.everMastered == false
           && record?.transcripts == [goodAnswer] && record?.conceptHash == money.conceptHash,
           "P2 provisional progress and record", "\(String(describing: saved?.status)) \(String(describing: record?.transcripts))")
}

// Mastered: confirmed, and the earlier provisional record (with its transcript) is deleted.
if let mastered = likely, mastered.decision.outcome == .mastered {
    ProgressRecorder.record(mastered, concept: money, schemaRevision: 1, attemptId: UUID(), in: context)
    let saved = progress(money.conceptId)
    expect(saved?.status == "mastered" && saved?.isProvisional == false && saved?.everMastered == true && saved?.attempts == 2
           && provisionalCount(money.conceptId) == 0, "P3 mastered supersedes provisional", "\(String(describing: saved?.status))")
} else {
    expect(false, "P3 mastered supersedes provisional", "fixture did not produce Mastered: \(String(describing: likely?.decision.trace))")
}

// Needs clarification and off-topic are not saved.
let attemptsBefore = attemptCount()
let open = graded(await coordinator({ id in id == moe ? nil : !id.hasPrefix("mchk_") }).grade(answer: goodAnswer, concept: money, chapter: economics3))
if let open {
    expect(open.decision.outcome == .needsClarification(targetCheckId: moe), "P4 setup", "\(open.decision.outcome)")
    expect(!ProgressRecorder.record(open, concept: money, schemaRevision: 1, attemptId: UUID(), in: context)
           && attemptCount() == attemptsBefore, "P5 a clarification is not saved")
}
let offTopic = graded(await coordinator({ _ in false }).grade(answer: "Photosynthesis is how green plants make sugar from sunlight.",
                                                              concept: money, chapter: economics3))
expect(offTopic?.decision.outcome == .offTopic && offTopic.map { !ProgressRecorder.record($0, concept: money, schemaRevision: 1, attemptId: UUID(), in: context) } == true,
       "P6 off-topic is not saved")

// MARK: - 5. Journeys (as FeedbackViewModel drives them)

/// Sorts, steps the machine, grades (first answer or follow-up) and records, like the view model.
func journey(_ answers: [String], coordinator: GradingCoordinator) async -> (AttemptMachine, GradingOutcome?) {
    var machine = AttemptMachine()
    var last: GradingOutcome?
    let attemptId = UUID()
    for answer in answers {
        machine.handle(.submit(AnswerSorter.sort(answer, confidence: nil, concept: money, vocabulary: economics3.chapterVocabulary)))
        guard case .grading(let followUp) = machine.state else { continue }
        let result = followUp && last != nil
            ? await coordinator.gradeFollowUp(answer: answer, previous: last!, concept: money, chapter: economics3)
            : await coordinator.grade(answer: answer, concept: money, chapter: economics3)
        guard case .graded(let outcome) = result else { machine.handle(.graded(nil)); continue }
        last = outcome
        machine.handle(.graded(outcome.decision.outcome))
        ProgressRecorder.record(outcome, concept: money, schemaRevision: 1, attemptId: attemptId, in: context)
    }
    return (machine, last)
}

// J1 first answer leaves the medium-of-exchange point open; the follow-up supplies it.
let moeCalls = OSAllocatedUnfairLock(initialState: 0)
let j1 = await journey([goodAnswer, "", "Money is a medium of exchange, so no one needs to find a person who wants exactly what they have."],
                       coordinator: GradingCoordinator(transport: FixtureTransport(truth: { id in
                           if id == moe { return moeCalls.withLock { $0 += 1; return $0 > 2 ? true : nil } }  // left out until the follow-up
                           return !id.hasPrefix("mchk_") && !id.hasPrefix("ctr_") && !id.hasPrefix("mfix_")
                       }, quote: { id in id == moe ? "Money is a medium of exchange" : quotes[id] ?? "NONE" }), settings: fast))
expect(j1.0.state == .finished(.mastered) && j1.1?.answers.count == 2 && progress(money.conceptId)?.status == "mastered",
       "J1 clarification, a re-prompt, then mastered", "\(j1.0.state) \(String(describing: j1.1?.decision.trace))")

// J2 the guardrails refuse everything: nothing is graded or saved.
let attemptsBeforeJ2 = attemptCount()
nonisolated struct RefusingTransport: ModelTransport {
    var isReady: Bool { true }
    func respond(instructions: String, prompt: String, maximumTokens: Int) async throws -> String { throw TransportError.guardrail }
}
let j2 = await journey([goodAnswer], coordinator: GradingCoordinator(transport: RefusingTransport(), settings: fast))
expect(j2.0.state == .blocked && j2.1 == nil && attemptCount() == attemptsBeforeJ2, "J2 refused answer is neither graded nor saved")

try? FileManager.default.removeItem(at: tempDir)

// MARK: - Result

print("App-flow tests: \(checksRun) checks")
if failures.isEmpty {
    print("ALL PASSED")
} else {
    print("\(failures.count) FAILED:")
    for failure in failures { print("  - " + failure) }
    exit(1)
}
