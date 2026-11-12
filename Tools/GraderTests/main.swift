//
//  Grader tests for Milestone 3. Compiled with the app's own CompiledCurriculum.swift, RuleEngine.swift,
//  Graders.swift and GradingCoordinator.swift by Tools/run_grader_tests.sh.
//
//  A fixture transport scripts the model's replies, so every failure mode in architecture v4.0
//  change 7 is driven through the real prompts, parsing, fallbacks, retry, quote check and rules.
//  With --live, a few Milestone 0 answers are also graded by the real on-device model.
//

import Foundation
import os

// MARK: - Harness

var failures: [String] = []
var testsRun = 0

func expect(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    testsRun += 1
    if !condition { failures.append("\(name)\(detail().isEmpty ? "" : ": " + detail())") }
}

nonisolated enum FixtureStyle: Sendable { case screening, topic, comparison, proof }

nonisolated func style(of instructions: String) -> FixtureStyle {
    if instructions.hasPrefix("You copy evidence") { return .proof }
    if instructions.hasPrefix("You compare") { return .comparison }
    if instructions.hasPrefix("You read") { return .topic }
    return .screening
}

/// The IDs listed in a prompt ("id: criterion" lines).
nonisolated func ids(in prompt: String) -> [String] {
    prompt.split(separator: "\n").compactMap { line in
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let id = line[..<colon]
        return !id.isEmpty && id != "IMPORTANT" && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } && id.first!.isLetter ? String(id) : nil
    }
}

nonisolated func json(_ pairs: [(String, String)]) -> String {
    "{" + pairs.map { "\"\($0.0)\": \($0.1)" }.joined(separator: ", ") + "}"
}

typealias Handler = @Sendable (FixtureStyle, [String], String) async throws -> String

nonisolated struct FixtureTransport: ModelTransport {
    var ready = true
    let handler: Handler
    var isReady: Bool { ready }
    func respond(instructions: String, prompt: String, maximumTokens: Int) async throws -> String {
        try await handler(style(of: instructions), ids(in: prompt), prompt)
    }
}

/// Thread-safe call counter.
nonisolated final class Counter: Sendable {
    private let counts = OSAllocatedUnfairLock(initialState: [String: Int]())
    func bump(_ key: String) -> Int { counts.withLock { $0[key, default: 0] += 1; return $0[key]! } }
}

/// Answers every boolean batch from `truth` (missing IDs: false) and every proof request with
/// `quotes[id]`, or NONE.
nonisolated func standard(_ truth: [String: Bool], quotes: [String: String] = [:]) -> Handler {
    { style, ids, _ in
        if style == .proof {
            return ids.map { "\($0): \(quotes[$0] ?? "NONE")" }.joined(separator: "\n")
        }
        return json(ids.map { ($0, truth[$0] == true ? "true" : "false") })
    }
}

func loadChapter(_ name: String) throws -> CompiledChapter {
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appending(path: name)
    return try JSONDecoder().decode(CompiledChapter.self, from: Data(contentsOf: url))
}

let fast = GradingSettings(perBatchSeconds: 0.5, totalSeconds: 2.0)

func grade(_ answer: String, _ concept: CompiledConcept, _ chapter: CompiledChapter, _ handler: @escaping Handler,
           ready: Bool = true, settings: GradingSettings = fast) async -> GradingResult {
    await GradingCoordinator(transport: FixtureTransport(ready: ready, handler: handler), settings: settings)
        .grade(answer: answer, concept: concept, chapter: chapter)
}

func outcome(_ result: GradingResult) -> GradingOutcome? {
    if case .graded(let outcome) = result { return outcome }
    return nil
}

func show(_ o: GradingOutcome?) -> String {
    guard let o else { return "blocked" }
    return "\(o.decision.outcome) | \(o.decision.trace.joined(separator: " | ")) | log \(o.log)"
}

// MARK: - Fixtures

let economics3 = try loadChapter("ncert_Economics_10_ch3.compiled.json")
let money = economics3.concepts.first { $0.conceptId == "eco10_ch3_t1_c1" }!
let geography1 = try loadChapter("ncert_Geography_10_ch1.compiled.json")
let alluvial = geography1.concepts.first { $0.conceptId == "geo10_ch1_t6_c2" }!

let dcw = "chk_eco3_double_coincidence"
let moe = "chk_eco3_medium_of_exchange"
let link = "lnk_eco3_money_removes_dcw"
let mchk = "mchk_misc_eco3_barter_needs_money"
let mfix = "mfix_misc_eco3_barter_needs_money"

let goodAnswer = "A shoe maker who wants wheat has to find a farmer who has wheat and also wants shoes. Both must want what the other has. With money, the shoe maker sells shoes to anyone for money and then buys wheat from anyone, so he no longer needs that exact match. Money sits in the middle of every trade."
let goodTruth: [String: Bool] = ["chk_relevance": true, dcw: true, moe: true, link: true, mchk: false]
let goodQuotes = [dcw: "Both must want what the other has", moe: "so he no longer needs that exact match"]

// MARK: - Unit checks

expect(ModelGrader.quoteIsGenuine("Both must want what the other has", in: goodAnswer, minimumWords: 4), "U1 genuine quote")
expect(!ModelGrader.quoteIsGenuine("money removes the need", in: goodAnswer, minimumWords: 4), "U2 invented quote")
expect(!ModelGrader.quoteIsGenuine("Both must", in: goodAnswer, minimumWords: 4), "U3 quote too short")
expect(ModelGrader.quoteIsClose("money acts as an intermediate in the exchange process", in: money.keyPoints[1].checks[0].criterion),
       "U4 copied criterion is close")
let states = ModelGrader.parseStates("```json\n{\"a\": true, \"b\": \"maybe\", \"zz\": true}", ids: ["a", "b", "c"])
expect(states["a"] == .some(.yes) && states["b"] == .some(nil) && states["c"] == .some(nil), "U5 parse: unknown dropped, non-boolean left out", "\(states)")

let story = "The farmer wants shoes. Both must want what the other has! Money fixes this: the shoe maker sells shoes for money. Then he buys wheat."
expect(ModelGrader.excerpt(around: "Both must want what the other has", in: story, contextSentences: 1)
       == "The farmer wants shoes. Both must want what the other has! Money fixes this: the shoe maker sells shoes for money.", "U12 one sentence of context each side")
expect(ModelGrader.excerpt(around: "Both must want what the other has", in: story, contextSentences: 0) == "Both must want what the other has", "U13 no context")
expect(ModelGrader.excerpt(around: "the shoe maker sells shoes for money. Then he buys wheat", in: story, contextSentences: 1)
       == "Both must want what the other has! Money fixes this: the shoe maker sells shoes for money. Then he buys wheat.", "U14 a quote spanning two sentences")
expect(ModelGrader.excerpt(around: "words that are not there", in: story, contextSentences: 1) == "words that are not there", "U15 an unlocatable quote falls back to itself")
expect(ModelGrader.excerpt(around: "the farmer wants shoes", in: story, contextSentences: 2).hasPrefix("The farmer wants shoes.") , "U16 context stops at the start of the answer")

let paired = ModelGrader.parseStates("```json {\"criterion\": \"a1\", \"answer\": \"true\", \"criterion\": \"b2\", \"answer\": false} ```", ids: ["a1", "b2"])
expect(paired["a1"] == .some(.yes) && paired["b2"] == .some(.no), "U17 criterion/answer pairs are read", "\(paired)")
let positional = ModelGrader.parseStates("{\"criterion_1\": true, \"criterion_2\": false, \"criterion_3\": \"true\"}", ids: ["a1", "b2", "c3"])
expect(positional["a1"] == .some(.yes) && positional["b2"] == .some(.no) && positional["c3"] == .some(.yes), "U18 positional reply is read", "\(positional)")
let partialPositional = ModelGrader.parseStates("{\"criterion_1\": true}", ids: ["a1", "b2"])
expect(partialPositional["a1"] == .some(nil) && partialPositional["b2"] == .some(nil), "U19 a partial positional reply is not guessed", "\(partialPositional)")
let mixed = ModelGrader.parseStates("{\"a1\": true, \"criterion_2\": false}", ids: ["a1", "b2"])
expect(mixed["a1"] == .some(.yes) && mixed["b2"] == .some(nil), "U20 positional is used only when no ID was found by name", "\(mixed)")

let kerala = GradableCheck(id: "k", criterion: "Mentions Kerala", kind: .keyPoint, lexical: .evidence, evidence: ["Kerala"])
let keralaNever = GradableCheck(id: "k2", criterion: "Mentions Kerala", kind: .keyPoint, lexical: .never, evidence: ["Kerala"])
expect(LexicalGrader.grade([kerala], transcript: "Kerala has a low infant mortality rate.")["k"]?.state == .yes, "U6 keyword evidence")
expect(LexicalGrader.grade([kerala], transcript: "It is certainly not Kerala that does well.")["k"]?.state == .uncertain, "U7 negated evidence")
expect(LexicalGrader.grade([kerala], transcript: "Haryana has high income.")["k"]?.state == .uncertain, "U8 absent evidence is not a no")
expect(LexicalGrader.grade([keralaNever], transcript: "Kerala does well.")["k2"]?.state == .uncertain, "U9 untagged check")
expect(CodeGrader.isKeywordStuffing("money barter exchange wants coincidence medium currency"), "U10 keyword list")
expect(!CodeGrader.isKeywordStuffing(goodAnswer), "U11 real sentences")

// MARK: - Failure modes

// F1 every reply correct: Mastered, with quotes proven.
var o = outcome(await grade(goodAnswer, money, economics3, standard(goodTruth, quotes: goodQuotes)))
expect(o?.decision.outcome == .mastered && o?.results[dcw]?.quoteCheck == .proven && o?.log.failedBatches.isEmpty == true,
       "F1 clean run", show(o))

// F2 invented IDs are dropped.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .proof { return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt) }
    return json(ids.map { ($0, goodTruth[$0] == true ? "true" : "false") } + [("chk_invented", "true")])
}))
expect(o?.decision.outcome == .mastered && o?.results["chk_invented"] == nil, "F2 invented ID", show(o))

// F3 an ID left out the first time is answered by the second try.
let counter3 = Counter()
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids.contains(moe) && counter3.bump("moe") == 1 {
        return json(ids.filter { $0 != moe }.map { ($0, "true") })
    }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.decision.outcome == .mastered && o?.results[moe]?.source == .model && o?.log.retried == [moe], "F3 second try", show(o))

// F4 an ID left out twice stays uncertain (omitted) and is asked about.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening { return json(ids.filter { $0 != moe }.map { ($0, "true") }) }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.results[moe]?.source == .omitted && o?.decision.outcome == .needsClarification(targetCheckId: moe)
       && o?.log.stillOmitted == [moe], "F4 omitted twice", show(o))

// F5 a value that is not true or false counts as left out.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening { return json(ids.map { ($0, $0 == moe ? "\"maybe\"" : "true") }) }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.results[moe]?.state == .uncertain && o?.results[moe]?.source == .omitted, "F5 non-boolean", show(o))

// F6 an empty reply: the batch falls back to keywords.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids.contains(dcw) { return "" }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.results[dcw]?.source == .lexical && o?.log.failedBatches.contains { $0.contains("graded check by check") } == true
       && o?.results[moe]?.source == .model && o?.decision.outcome != .mastered, "F6 empty reply", show(o))

// F27 a batch is refused because of the combination of checks, but each check alone is fine: graded by the model
// check by check, nothing falls back to keywords.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids.count > 1 && ids.contains(dcw) && !prompt.contains("IMPORTANT") { throw TransportError.guardrail }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.decision.outcome == .mastered && o?.log.fallbackChecks.isEmpty == true
       && o?.log.failedBatches.contains { $0.contains("graded check by check") } == true, "F27 refused batch graded check by check", show(o))

// F28 the model answers NONE for one check of a batch but quotes it when asked alone.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .proof && ids.count > 1 && ids.contains(dcw) {
        return ids.map { "\($0): \($0 == dcw ? "NONE" : (goodQuotes[$0] ?? "NONE"))" }.joined(separator: "\n")
    }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.decision.outcome == .mastered && o?.results[dcw]?.quoteCheck == .proven, "F28 NONE recovered by asking alone", show(o))

// F29 a check the model really cannot quote, even alone, stays unproven.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .proof && ids.contains(dcw) { return ids.map { "\($0): \($0 == dcw ? "NONE" : (goodQuotes[$0] ?? "NONE"))" }.joined(separator: "\n") }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.results[dcw]?.state == .uncertain && o?.decision.outcome == .needsClarification(targetCheckId: dcw), "F29 NONE stays NONE", show(o))

// F30 the model keys its reply by "criterion" instead of the IDs: the second try asks for the exact IDs.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids.contains(dcw) && !prompt.contains("IMPORTANT") {
        return "{" + ids.map { "\"criterion\": \"\($0)\", \"answer\": \"true\"" }.joined(separator: ", ") + "}"
    }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.decision.outcome == .mastered, "F30 reply keyed by criterion", show(o))
// ...and when only the strict-format retry is wrong too, the checks stay left out.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids.contains(dcw) { return ids.count > 1 ? "{\"criterion_1\": true}" : "{}" }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.results[dcw]?.state == .uncertain && o?.results[dcw]?.source == .lexical && o?.decision.outcome != .mastered,
       "F30b a partial positional reply is not guessed", show(o))

// F31 the batch says "no" to the one check that blocks mastery, but asked alone it is "yes", and the answer holds a genuine
// quote that states it (read with its neighbouring sentences): the "no" is overturned.
let recheckHandler: Handler = { style, ids, prompt in
    if style == .screening && ids == [dcw] { return json([(dcw, "true")]) }   // the lenient recheck and the confirmation
    return try await standard(goodTruth.merging([dcw: false]) { $1 }, quotes: goodQuotes)(style, ids, prompt)
}
o = outcome(await grade(goodAnswer, money, economics3, recheckHandler))
expect(o?.decision.outcome == .mastered && o?.log.recheckFlipped == [dcw] && o?.results[dcw]?.quoteCheck == .proven
       && o?.results[dcw]?.history.last?.event == .recheck, "F31 verified recheck overturns a false no", show(o))

// F32 asked alone it is still "no": stays no.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids == [dcw] { return json([(dcw, "false")]) }
    return try await standard(goodTruth.merging([dcw: false]) { $1 }, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.log.rechecked == [dcw] && o?.log.recheckFlipped.isEmpty == true && o?.results[dcw]?.state == .no
       && o?.decision.outcome != .mastered, "F32 a no that stays no", show(o))

// F33 the lenient recheck says "yes" but the answer holds no genuine quote for it: not overturned.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .proof { return ids.map { "\($0): \($0 == dcw ? "NONE" : (goodQuotes[$0] ?? "NONE"))" }.joined(separator: "\n") }
    return try await recheckHandler(style, ids, prompt)
}))
expect(o?.log.rechecked == [dcw] && o?.log.recheckFlipped.isEmpty == true && o?.results[dcw]?.state == .no, "F33 no genuine quote: stays no", show(o))

// F34 the lenient recheck says yes and the quote is genuine, but the quote read with its context does not state the check:
// not overturned. (The lenient call sees the whole answer; the confirmation sees only the excerpt, which stops before its last sentence.)
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids == [dcw] { return json([(dcw, prompt.contains("Money sits in the middle") ? "true" : "false")]) }
    return try await standard(goodTruth.merging([dcw: false]) { $1 }, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.log.rechecked == [dcw] && o?.log.recheckFlipped.isEmpty == true && o?.results[dcw]?.state == .no,
       "F34 quote with context does not state the check: stays no", show(o))

// F35 switched off: the "no" is final.
var noRecheck = fast
noRecheck.recheckNoResults = false
o = outcome(await grade(goodAnswer, money, economics3, recheckHandler, settings: noRecheck))
expect(o?.log.rechecked.isEmpty == true && o?.results[dcw]?.state == .no, "F35 recheck switched off", show(o))

// F36 a no that is not the only blocker is not rechecked: a misconception was stated.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids == [dcw] { return json([(dcw, "true")]) }
    return try await standard(goodTruth.merging([dcw: false, mchk: true]) { $1 }, quotes: goodQuotes.merging([mchk: "With money, the shoe maker sells shoes to anyone for money"]) { $1 })(style, ids, prompt)
}))
expect(o?.log.rechecked.isEmpty == true, "F36 no recheck when mastery is out of reach anyway", show(o))

// F7 a batch that hangs is cut off at the per-batch limit.
let started7 = ContinuousClock.now
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids.contains(dcw) { try await Task.sleep(for: .seconds(5)) }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
let elapsed7 = GradingCoordinator.seconds(since: started7)
expect(o?.log.failedBatches.contains { $0.contains("timeout") } == true && elapsed7 < 1.5 && o?.results[dcw]?.source == .lexical,
       "F7 timeout", "\(elapsed7) s, \(show(o))")

// F8 the guardrails refuse every batch: the answer is not graded.
let blocked = await grade("some words", money, economics3, { _, _, _ in throw TransportError.guardrail })
expect({ if case .blocked = blocked { return true } else { return false } }(), "F8 guardrail on everything")

// F9 the guardrails refuse one batch: that batch falls back, the rest is graded.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .topic { throw TransportError.guardrail }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.results[mchk]?.source == .lexical && o?.decision.outcome == .likelyMastered, "F9 guardrail on one batch", show(o))

// F10 the model is unavailable: keyword grading only, never Mastered, never off-topic.
o = outcome(await grade(goodAnswer, money, economics3, standard(goodTruth), ready: false))
expect(o?.results.values.allSatisfy { $0.source == .lexical || $0.source == .code } == true
       && o?.decision.outcome != .mastered && o?.decision.outcome != .offTopic, "F10 model unavailable", show(o))

// F11 an invented quote turns the yes into uncertain, which leads to a question, not a failure.
o = outcome(await grade(goodAnswer, money, economics3, standard(goodTruth, quotes: [dcw: goodQuotes[dcw]!, moe: "money is a magic bridge for all trades"])))
expect(o?.results[moe]?.state == .uncertain && o?.decision.outcome == .needsClarification(targetCheckId: moe)
       && o?.log.proofRejected == ["\(moe): invented"], "F11 invented quote", show(o))

// F12 a quote copied from the criterion is rejected.
o = outcome(await grade(goodAnswer, money, economics3, standard(goodTruth, quotes: [moe: goodQuotes[moe]!,
    dcw: "both parties must want to sell and buy each other's goods"])))
expect(o?.results[dcw]?.state == .uncertain && o?.log.proofRejected == ["\(dcw): copiedCriterion"], "F12 copied criterion", show(o))

// F13 the quote check runs out of time: mastery is capped at Likely mastered.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .proof { try await Task.sleep(for: .seconds(5)) }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}, settings: GradingSettings(perBatchSeconds: 0.5, totalSeconds: 1.0)))
expect(o?.results[dcw]?.quoteCheck == .timedOut && o?.decision.outcome == .likelyMastered, "F13 quote check timed out", show(o))

// F14 a misconception without quoted proof is not held against the student.
var truth14 = goodTruth
truth14[mchk] = true
o = outcome(await grade(goodAnswer, money, economics3, standard(truth14, quotes: goodQuotes)))
expect(o?.results[mchk]?.state == .uncertain && o?.decision.outcome == .likelyMastered, "F14 unproven misconception", show(o))

// F15 a misconception the student really stated gives Needs correction.
let misconceptionAnswer = "We use money because it is precious in itself. In barter both people must want each other's goods."
o = outcome(await grade(misconceptionAnswer, money, economics3, standard(
    ["chk_relevance": true, mchk: true, dcw: true, moe: false, link: false],
    quotes: [mchk: "money because it is precious in itself", dcw: "both people must want each other's goods"])))
expect(o?.decision.outcome == .needsCorrection && o?.results[mchk]?.quoteCheck == .proven, "F15 proven misconception", show(o))
let corrected15 = o

// F19 a genuine quote that, read on its own, does not state the misconception: not held against the student.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    // The confirmation call grades only the quote; it does not state the wrong idea.
    if style == .topic && ids == [mchk] && !prompt.contains("shoe maker") { return json([(mchk, "false")]) }
    return try await standard(truth14, quotes: goodQuotes.merging([mchk: "Both must want what the other has"]) { $1 })(style, ids, prompt)
}))
expect(o?.results[mchk]?.state == .uncertain && o?.log.misconceptionNotConfirmed == [mchk] && o?.decision.outcome == .likelyMastered,
       "F19 quote does not state the misconception", show(o))

// F25 a genuine quote that, even with its neighbouring sentences, does not state the mastery check: the yes is
// not accepted, and the student is asked about it (found by the Milestone 6 dry run). A confirmation call is the
// only call that lists just [dcw] and does not contain the answer's last sentence.
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids == [dcw] && !prompt.contains("Money sits in the middle") { return json([(dcw, "false")]) }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}))
expect(o?.results[dcw]?.state == .uncertain && o?.log.quoteNotConfirmed == [dcw]
       && o?.decision.outcome == .needsClarification(targetCheckId: dcw), "F25 quote does not state the mastery check", show(o))

// F26 a quote that states the check only together with the sentence before it (the dry run's "both must want
// what the other has"): confirmed with context, so the answer is accepted without a follow-up question.
func contextOnly(_ settings: GradingSettings) async -> GradingOutcome? {
    outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
        if style == .screening && ids == [dcw] && !prompt.contains("Money sits in the middle") {
            return json([(dcw, prompt.contains("A shoe maker who wants wheat") ? "true" : "false")])
        }
        return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
    }, settings: settings))
}
o = await contextOnly(fast)
expect(o?.decision.outcome == .mastered && o?.results[dcw]?.quoteCheck == .proven && o?.log.quoteNotConfirmed.isEmpty == true,
       "F26 quote confirmed with its context", show(o))
var noContext = fast
noContext.confirmContextSentences = 0
o = await contextOnly(noContext)
expect(o?.log.quoteNotConfirmed == [dcw] && o?.decision.outcome == .needsClarification(targetCheckId: dcw),
       "F26b the same quote read alone is not confirmed", show(o))

// A flag that cannot be backed is ruled out only when the student's own words explicitly reject or
// correct the wrong idea: a genuine quote that, read on its own, states the correct idea.
let mrej = "mrej_misc_eco3_barter_needs_money"
let rejectSentence = "Money is not useful because it is valuable in itself; it is useful because everyone accepts it in exchange."
let answer20 = goodAnswer + " " + rejectSentence
let truth20 = truth14.merging([mrej: true]) { $1 }
let quotes20 = goodQuotes.merging([mrej: rejectSentence]) { $1 }

// F20 a verified rejection rules the flag out; the mastery evidence is still quote-checked.
o = outcome(await grade(answer20, money, economics3, standard(truth20, quotes: quotes20)))
expect(o?.results[mchk]?.state == .no && o?.results[mchk]?.quoteCheck == .proven && o?.log.misconceptionRuledOut == [mchk]
       && o?.results[dcw]?.quoteCheck == .proven && o?.decision.outcome == .mastered, "F20 verified rejection", show(o))

// F20b the optional rule-out step is skipped when little of the time budget is left: still Likely mastered, and no
// time is spent on it. (The first pass takes 1.7 s of a 2.2 s budget.)
let slowFirstPass = GradingSettings(perBatchSeconds: 2.0, totalSeconds: 2.2)
o = outcome(await grade(answer20, money, economics3, { style, ids, prompt in
    if style == .topic { try await Task.sleep(for: .seconds(1.7)) }
    return try await standard(truth20, quotes: quotes20)(style, ids, prompt)
}, settings: slowFirstPass))
expect(o?.log.misconceptionRuledOut.isEmpty == true && o?.decision.outcome != .needsCorrection, "F20b rule-out skipped when time is short", show(o))

// F21 a genuine rejection quote that, read on its own, does not state the correct idea: stays uncertain.
o = outcome(await grade(answer20, money, economics3, standard(truth14.merging([mrej: false]) { $1 }, quotes: quotes20)))
expect(o?.results[mchk]?.state == .uncertain && o?.log.misconceptionRuledOut.isEmpty == true && o?.decision.outcome == .likelyMastered,
       "F21 rejection not confirmed", show(o))

// F22 an invented rejection quote: stays uncertain.
o = outcome(await grade(answer20, money, economics3, standard(truth20, quotes: goodQuotes.merging([mrej: "money is never valuable at all"]) { $1 })))
expect(o?.results[mchk]?.state == .uncertain && o?.log.misconceptionRuledOut.isEmpty == true, "F22 invented rejection quote", show(o))

// F23 the flag's own quote check is refused, but the student explicitly rejects the idea: ruled out,
// and the separate mastery batch is unaffected by the refusal.
o = outcome(await grade(answer20, money, economics3, { style, ids, prompt in
    if style == .proof && ids.contains(mchk) { throw TransportError.guardrail }
    return try await standard(truth20, quotes: quotes20)(style, ids, prompt)
}))
expect(o?.results[mchk]?.state == .no && o?.log.proofNotChecked == [mchk] && o?.results[dcw]?.quoteCheck == .proven
       && o?.decision.outcome == .mastered, "F23 rejection after a refused quote check", show(o))

// F16 an off-topic answer.
let offTopic = "Photosynthesis is how green plants make sugar from sunlight."
o = outcome(await grade(offTopic, money, economics3, standard([:])))
expect(o?.context.keywordOverlap == 0 && o?.decision.outcome == .offTopic, "F16 off-topic", show(o))

// F17 a list of keywords links nothing.
o = outcome(await grade("money barter exchange wants coincidence medium currency", money, economics3, standard(goodTruth, quotes: goodQuotes)))
expect(o?.log.keywordStuffing == true && o?.results[link]?.state == .no && o?.results[link]?.source == .code,
       "F17 keyword stuffing", show(o))

// F18 the total budget runs out: later batches fall back to keywords.
let started18 = ContinuousClock.now
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .screening && ids.contains(dcw) { try await Task.sleep(for: .seconds(0.9)) }
    if style == .screening && ids.contains(link) { try await Task.sleep(for: .seconds(2)) }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}, settings: GradingSettings(perBatchSeconds: 2.0, totalSeconds: 1.0)))
let elapsed18 = GradingCoordinator.seconds(since: started18)
expect(o?.results[link]?.source == .lexical && elapsed18 < 1.6, "F18 total budget", "\(elapsed18) s, \(show(o))")

// MARK: - Follow-ups

// M1 a retry after Needs correction: the correction is recognised and the earlier evidence kept.
if let previous = corrected15 {
    let retry = "Money is useful because it is a medium of exchange, so we don't need a double coincidence of wants."
    let coordinator = GradingCoordinator(transport: FixtureTransport(handler: { style, ids, prompt in
        switch style {
        case .comparison: return json(ids.map { ($0, $0 == mfix ? "true" : "false") })
        case .proof: return ids.map { "\($0): \($0 == dcw ? "both people must want each other's goods" : "Money is useful because it is a medium of exchange")" }.joined(separator: "\n")
        default: return json(ids.map { ($0, ($0 == moe || $0 == link || $0 == dcw || $0 == "chk_relevance") ? "true" : "false") })
        }
    }), settings: fast)
    let followed = outcome(await coordinator.gradeFollowUp(answer: retry, previous: previous, concept: money, chapter: economics3))
    expect(followed?.decision.outcome == .mastered && followed?.decision.revisitLater == true
           && followed?.decision.report.fixedByStudent.count == 1 && followed?.results[mchk]?.corrected == true
           && followed?.events.contains { $0.kind == .correction && $0.checkId == mchk } == true
           && followed?.context.clarificationRoundsLeft == 1,
           "M1 correction retry", show(followed))
} else {
    expect(false, "M1 correction retry", "F15 did not produce an outcome")
}

// M2 a follow-up that contradicts an earlier point records a conflict and keeps the earlier yes.
let fertile = "chk_geo1_alluvial_fertile"
let dense = "chk_geo1_alluvial_dense"
let alluvialAnswer = "Alluvial soil covers the entire northern plains. It was deposited by the Indus, the Ganga and the Brahmaputra, and it is also found in the deltas of the Mahanadi, Godavari, Krishna and Kaveri. Due to its high fertility, these regions are intensively cultivated and densely populated."
let alluvialQuote = "Alluvial soil covers the entire northern plains"
let first2 = outcome(await grade(alluvialAnswer, alluvial, geography1, { style, ids, _ in
    if style == .proof { return ids.map { "\($0): \(alluvialQuote)" }.joined(separator: "\n") }
    return json(ids.compactMap { id in
        if id == fertile { return nil }  // left out twice: uncertain
        return (id, id.hasPrefix("mchk_") ? "false" : "true")
    })
}))
expect(first2?.decision.outcome == .needsClarification(targetCheckId: fertile), "M2a question about the open check", show(first2))
if let previous = first2 {
    let coordinator = GradingCoordinator(transport: FixtureTransport(handler: { style, ids, _ in
        switch style {
        case .comparison: return json(ids.map { ($0, $0 == "ctr_" + dense ? "true" : "false") })
        case .proof: return ids.map { "\($0): \(alluvialQuote)" }.joined(separator: "\n")
        default: return json(ids.map { ($0, $0 == fertile ? "true" : "false") })
        }
    }), settings: fast)
    let followed = outcome(await coordinator.gradeFollowUp(answer: "It is very fertile with potash and lime, but not many people live there.",
                                                           previous: previous, concept: alluvial, chapter: geography1))
    expect(followed?.results[dense]?.state == .yes && followed?.context.conflicts.map(\.checkId) == [dense]
           && followed?.results[fertile]?.state == .yes && followed?.decision.report.conflicts.count == 1
           && followed?.decision.outcome == .partial(almostThere: true),
           "M2b contradiction", show(followed))
}

// MARK: - Live smoke test

if CommandLine.arguments.contains("--live") {
    #if canImport(FoundationModels)
    print("\nLive model (no assertions; the real on-device model):")
    let live = GradingCoordinator(transport: FoundationModelsTransport())
    let samples: [(String, CompiledConcept, CompiledChapter, String)] = [
        ("allu_T1 textbook", alluvial, geography1, alluvialAnswer + " Alluvial soils contain potash, phosphoric acid and lime, ideal for sugarcane, paddy and wheat. According to age, it is old alluvial called Bangar and new alluvial called Khadar. Bangar has more kanker nodules, while Khadar has more fine particles and is more fertile."),
        ("allu_M1 misconception", alluvial, geography1, "Bangar is more fertile than Khadar because it is older and has more kanker."),
        ("allu_O1 off-topic", alluvial, geography1, "Per capita income is total income divided by population."),
        ("money_P1 paraphrase", money, economics3, goodAnswer),
    ]
    for (name, concept, chapter, answer) in samples {
        let result = await live.grade(answer: answer, concept: concept, chapter: chapter)
        guard case .graded(let o) = result else { print("  \(name): blocked by guardrails"); continue }
        print("  \(name): \(o.decision.outcome) in \(String(format: "%.1f", o.log.seconds)) s, \(o.log.modelCalls) calls"
              + (o.log.failedBatches.isEmpty ? "" : ", failed \(o.log.failedBatches)")
              + (o.log.proofRejected.isEmpty ? "" : ", quotes rejected \(o.log.proofRejected)")
              + (o.log.proofNotChecked.isEmpty ? "" : ", quote not checked \(o.log.proofNotChecked)")
              + (o.log.misconceptionNotConfirmed.isEmpty ? "" : ", misconception not confirmed \(o.log.misconceptionNotConfirmed)")
              + (o.log.misconceptionRuledOut.isEmpty ? "" : ", misconception ruled out by explicit rejection \(o.log.misconceptionRuledOut)")
              + (o.log.stillOmitted.isEmpty ? "" : ", omitted \(o.log.stillOmitted)"))
        print("      trace: " + o.decision.trace.joined(separator: " | "))
        for (id, r) in o.results.sorted(by: { $0.key < $1.key }) where r.quote != nil || r.source != .model || id.hasPrefix("mchk_") {
            print("      \(id): \(r.state.rawValue) from \(r.source.rawValue)\(r.quote.map { " quote \"\($0)\"" } ?? "")\(r.quoteCheck == .timedOut ? " (quote timed out)" : "")")
        }
    }
    #endif
}

// MARK: - Result

print("Grader tests: \(testsRun) checks")
if failures.isEmpty {
    print("ALL PASSED")
} else {
    print("\(failures.count) FAILED:")
    for failure in failures { print("  - " + failure) }
    exit(1)
}
