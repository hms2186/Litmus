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
    if instructions.contains("You copy evidence") { return .proof }
    if instructions.contains("You compare") { return .comparison }
    if instructions.contains("You read") { return .topic }
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
let goodQuotes = [dcw: "Both must want what the other has", moe: "so he no longer needs that exact match", link: "so he no longer needs that exact match"]

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
let statusPair = ModelGrader.parseStates("```json\n[{\"criterion\": \"a1\", \"status\": true}, {\"criterion\": \"b2\", \"status\": false}]\n```", ids: ["a1", "b2", "c3"])
expect(statusPair["a1"] == .some(.yes) && statusPair["b2"] == .some(.no) && statusPair["c3"] == .some(nil), "U17b criterion/status pairs are read, an ID not in the reply stays left out", "\(statusPair)")
let positional = ModelGrader.parseStates("{\"criterion_1\": true, \"criterion_2\": false, \"criterion_3\": \"true\"}", ids: ["a1", "b2", "c3"])
expect(positional["a1"] == .some(.yes) && positional["b2"] == .some(.no) && positional["c3"] == .some(.yes), "U18 positional reply is read", "\(positional)")
let partialPositional = ModelGrader.parseStates("{\"criterion_1\": true}", ids: ["a1", "b2"])
expect(partialPositional["a1"] == .some(nil) && partialPositional["b2"] == .some(nil), "U19 a partial positional reply is not guessed", "\(partialPositional)")
let mixed = ModelGrader.parseStates("{\"a1\": true, \"criterion_2\": false}", ids: ["a1", "b2"])
expect(mixed["a1"] == .some(.yes) && mixed["b2"] == .some(nil), "U20 positional is used only when no ID was found by name", "\(mixed)")

// Chapter-aware instructions (measured in Curriculum/official/EXPERIMENT_instructions.md)
let arrayed = ModelGrader.parseStates("```json\n[{\"ID\": \"a1\", \"result\": \"true\"}, {\"ID\": \"b2\", \"value\": false}, {\"ID\": \"c3\", \"status\": true}]", ids: ["a1", "b2", "c3", "d4"])
expect(arrayed["a1"] == .some(.yes) && arrayed["b2"] == .some(.no) && arrayed["c3"] == .some(.yes) && arrayed["d4"] == .some(nil),
       "U21 an array of {ID, result|value|status} objects is read", "\(arrayed)")
expect(GradingPrompts.booleanTokens(6) >= 3 * (20 + 16 * 6), "U22 the token cap leaves room for the array reply")

let recorded = OSAllocatedUnfairLock(initialState: [String]())
let recorder = FixtureTransport { style, ids, _ in
    if style == .proof { return ids.map { "\($0): NONE" }.joined(separator: "\n") }
    return json(ids.map { ($0, "true") })
}
nonisolated struct RecordingTransport: ModelTransport {
    let log: OSAllocatedUnfairLock<[String]>
    let inner: FixtureTransport
    var isReady: Bool { true }
    func respond(instructions: String, prompt: String, maximumTokens: Int) async throws -> String {
        log.withLock { $0.append(instructions) }
        return try await inner.respond(instructions: instructions, prompt: prompt, maximumTokens: maximumTokens)
    }
}
let context = GradingContext(concept: money, chapter: economics3)
expect(context.grade == "Class 10" && context.subject == "Economics" && context.chapter == economics3.chapterName
       && context.topic == money.label && context.passage == money.cardText, "U23 the context is read from the chapter file and concept")
let catalogForContext = GradingCoordinator.catalog(money)
let keyChecks = money.keyPoints.flatMap(\.checks).prefix(2).compactMap { catalogForContext[$0.id] }
let topicChecks = [catalogForContext[money.relevanceCheck.id]!]
let recording = RecordingTransport(log: recorded, inner: recorder)
let withContext = ModelGrader(transport: recording, context: context)
_ = try? await withContext.grade(Array(keyChecks), style: .screening, answers: [goodAnswer])
_ = try? await withContext.grade(topicChecks, style: .topic, answers: [goodAnswer])
_ = try? await withContext.prove(Array(keyChecks), transcript: goodAnswer, minimumWords: 4)
let seen = recorded.withLock { $0 }
expect(seen.count == 3, "U24 three calls were recorded", "\(seen.count)")
if seen.count == 3 {
    expect(seen[0].contains("TEXTBOOK PASSAGE") && seen[0].contains(money.cardText) && seen[0].contains(economics3.chapterName)
           && seen[0].contains(money.label) && seen[0].contains("Class 10 Economics"), "U25 concept checks get the chapter, topic and textbook passage")
    expect(seen[0].contains("You check a student's explanation against a fixed list"), "U26 the rules still follow the chapter text")
    expect(!seen[1].contains("TEXTBOOK PASSAGE") && seen[1].contains(GradingPrompts.roleLine), "U27 relevance and misconception checks get the role line, not the passage")
    expect(!seen[2].contains("TEXTBOOK PASSAGE") && seen[2].contains(GradingPrompts.roleLine), "U28 the quote request gets the role line, not the passage")
}
recorded.withLock { $0.removeAll() }
_ = try? await ModelGrader(transport: recording).grade(Array(keyChecks), style: .screening, answers: [goodAnswer])
expect(recorded.withLock { $0 }.first.map { !$0.contains("TEXTBOOK PASSAGE") && $0.contains(GradingPrompts.roleLine) } == true,
       "U29 without a context the concept checks still get the role line")

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
o = outcome(await grade(goodAnswer, money, economics3, standard(goodTruth, quotes: [dcw: goodQuotes[dcw]!, link: goodQuotes[link]!, moe: "money is a magic bridge for all trades"])))
expect(o?.results[moe]?.state == .uncertain && o?.decision.outcome == .needsClarification(targetCheckId: moe)
       && o?.log.proofRejected == ["\(moe): invented"], "F11 invented quote", show(o))

// F12 a quote copied from the criterion is rejected.
o = outcome(await grade(goodAnswer, money, economics3, standard(goodTruth, quotes: [moe: goodQuotes[moe]!, link: goodQuotes[link]!,
    dcw: "both parties must want to sell and buy each other's goods"])))
expect(o?.results[dcw]?.state == .uncertain && o?.log.proofRejected == ["\(dcw): copiedCriterion"], "F12 copied criterion", show(o))

// K1 a model that says yes to everything cannot pass a list of keywords: the answer states nothing, so the guard overrules the yes
let keywordList = "money, barter, medium, exchange, double coincidence, wants, buyers, sellers"
let allYes: [String: Bool] = ["chk_relevance": true, dcw: true, moe: true, link: true, mchk: false]
o = outcome(await grade(keywordList, money, economics3, standard(allYes, quotes: [dcw: keywordList, moe: keywordList])))
expect(o?.decision.outcome != .mastered && o?.decision.outcome != .likelyMastered
       && o?.results[dcw]?.state != .yes && o?.log.termListOverruled.contains(dcw) == true,
       "K1 keyword list cannot pass, whatever the model says", show(o))
expect(CodeGrader.isTermList(keywordList) && !CodeGrader.isTermList(goodAnswer), "K2 a list is a term list, an explanation is not")
expect(CodeGrader.isTermList("reactant,ko,product,coefficient, subsripts, atom, counting, and rearrangement of atoms"), "K2b the answer a student really gave is a term list")
expect(!CodeGrader.hasFiniteVerb("atom counting, rearrangement of atoms") && CodeGrader.hasFiniteVerb("atoms are conserved"),
       "K3 only a real verb makes a statement")

// F13 the quote check runs out of time. A yes that nothing in the student's own words backs is not accepted (it went
// through as Likely mastered before, which let an unsupported model yes pass an incomplete answer): it becomes uncertain
// and leads to a question. (A yes backed by the textbook phrase in the answer is kept, capped at Likely mastered.)
o = outcome(await grade(goodAnswer, money, economics3, { style, ids, prompt in
    if style == .proof { try await Task.sleep(for: .seconds(5)) }
    return try await standard(goodTruth, quotes: goodQuotes)(style, ids, prompt)
}, settings: GradingSettings(perBatchSeconds: 0.5, totalSeconds: 1.0)))
expect(o?.results[dcw]?.state == .uncertain && o?.decision.outcome != .mastered && o?.decision.outcome != .likelyMastered, "F13 quote check timed out", show(o))

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

// MARK: - Phrasing support (acceptedPhrasings)

let civics1 = try loadChapter("ncert_Civics_10_ch1.compiled.json")
let federal = civics1.concepts.first { $0.conceptId == "civ10_ch1_t3_c2" }!
let vertical = "chk_vertical_higher_lower"
let verticalMisc = "mchk_misc_vertical_horizontal_mix"
let verticalCatalog = GradingCoordinator.catalog(federal)
expect(!verticalCatalog[vertical]!.phrasings.isEmpty, "P0 opted-in check carries its phrasings")
expect(GradingCoordinator.catalog(money)[dcw]!.phrasings.isEmpty, "P0b other checks carry none")
expect(GradingSettings().phrasingSupport, "P0c phrasing support is on, and it affects only opted-in checks (P0b)")

func phrasingResults(misconception: CheckState = .no, corrected: Bool = false) -> ResultSet {
    var results: ResultSet = [:]
    for (id, check) in verticalCatalog {
        switch check.kind {
        case .misconception:
            var r = CheckResult(state: id == verticalMisc ? misconception : .no, source: .model)
            r.corrected = corrected
            results[id] = r
        case .keyPoint:
            results[id] = CheckResult(state: .yes, source: .model, quoteCheck: .proven, quote: "a quote of four words")
        default:
            results[id] = CheckResult(state: .yes, source: .model)
        }
    }
    results[vertical] = CheckResult(state: .no, source: .model)
    return results
}
func lift(_ answer: String, keywordStuffing: Bool = false, misconception: CheckState = .no, corrected: Bool = false) -> (ResultSet, [String]) {
    var results = phrasingResults(misconception: misconception, corrected: corrected)
    let changed = RubricMatrix.supportWithPhrasing(&results, concept: federal, catalog: verticalCatalog, transcript: answer, keywordStuffing: keywordStuffing)
    return (results, changed)
}

let splitAnswer = "Our constitution writes down what each of them may do, and that is why power is split between the top level and the lower levels."
var (lifted, changedIds) = lift(splitAnswer)
expect(changedIds == [vertical] && lifted[vertical]?.state == .yes && lifted[vertical]?.source == .lexical, "P1 one statement with every anchor lifts the check", "\(changedIds)")

(lifted, changedIds) = lift("Top level, lower level, split, shared, divided.")
expect(changedIds.isEmpty && lifted[vertical]?.state == .no, "P2 a list of terms lifts nothing", "\(changedIds)")

(lifted, changedIds) = lift(splitAnswer, keywordStuffing: true)
expect(changedIds.isEmpty, "P3 nothing is lifted when the answer is keyword stuffing")

(lifted, changedIds) = lift("Power is not split between the top level and the lower levels.")
expect(changedIds.isEmpty, "P4 a negated anchor lifts nothing", "\(changedIds)")

(lifted, changedIds) = lift("The top level has its own government. The lower levels are the villages. Everything is shared in meetings.")
expect(changedIds.isEmpty, "P5 anchors spread over several sentences lift nothing", "\(changedIds)")

(lifted, changedIds) = lift(splitAnswer, misconception: .yes)
expect(changedIds.isEmpty && lifted[vertical]?.state == .no, "P6 a stated misconception on the key point blocks the lift")

(lifted, changedIds) = lift(splitAnswer, misconception: .yes, corrected: true)
expect(changedIds == [vertical], "P6b a corrected misconception no longer blocks", "\(changedIds)")

(lifted, changedIds) = lift("Power is divided between the legislature, the executive and the judiciary.")
expect(changedIds.isEmpty, "P7 a horizontal split does not match the vertical check", "\(changedIds)")

let federal2 = civics1.concepts.first { $0.conceptId == "civ10_ch1_t3_c2" }!
(lifted, changedIds) = lift("Power is divided between the top level and the lower levels of the legislature, the executive and the judiciary.")
expect(changedIds.isEmpty, "P7b an excluded word (horizontal organs) in the sentence blocks the lift", "\(changedIds)")
let routes = try loadChapter("ncert_Civics_10_ch2.compiled.json")
let routeConcept = routes.concepts.first { $0.conceptId == "civ10_ch2_t1_c3" }!
let routeCatalog = GradingCoordinator.catalog(routeConcept)
func routeLift(_ answer: String) -> [String] {
    var r: ResultSet = [:]
    for (id, c) in routeCatalog {
        r[id] = c.kind == .misconception ? CheckResult(state: .no, source: .model) : CheckResult(state: .no, source: .model)
    }
    return RubricMatrix.supportWithPhrasing(&r, concept: routeConcept, catalog: routeCatalog, transcript: answer, keywordStuffing: false)
}
expect(routeLift("In coming together federations independent states agree on their own to join and form a bigger unit.") == ["chk_ch2_route_coming_pool"], "P7c a coming-together sentence lifts the pool check")
expect(routeLift("In holding together federations small independent states join voluntarily and the centre is weaker.").isEmpty, "P7d the same words attributed to holding together do not lift")
_ = federal2

do {
    var withModelYes = phrasingResults()
    withModelYes[vertical] = CheckResult(state: .yes, source: .model, quoteCheck: .proven, quote: "split between the top level and the lower levels")
    let before = withModelYes
    let none = RubricMatrix.supportWithPhrasing(&withModelYes, concept: federal, catalog: verticalCatalog, transcript: splitAnswer, keywordStuffing: false)
    expect(none.isEmpty && withModelYes == before, "P8 a model yes is left untouched")
}

do {
    let overlap = CodeGrader.keywordOverlap(splitAnswer, concept: federal, vocabulary: civics1.chapterVocabulary)
    let context = AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: overlap, provisionalOnly: false)
    let without = RuleEngine.decide(federal, results: phrasingResults(), context: context, articulationChecks: civics1.articulationChecks)
    let (withLift, _) = lift(splitAnswer)
    let with = RuleEngine.decide(federal, results: withLift, context: context, articulationChecks: civics1.articulationChecks)
    expect(without.outcome != .mastered && without.outcome != .likelyMastered, "P9a without the lift the core check blocks the pass", "\(without.outcome)")
    expect(with.outcome == .likelyMastered, "P9b with the lift the outcome is Likely mastered and never Mastered", "\(with.outcome) | \(with.trace.joined(separator: " | "))")
}

// MARK: - Relevance of green rows

do {
    let phrases = ["one-third", "Bihar"]
    let one = LexicalGrader.evidence(phrases, in: LexicalGrader.tokenize("Haryana has the highest income and Bihar has the lowest."))
    let both = LexicalGrader.evidence(phrases, in: LexicalGrader.tokenize("About one-third of the children in Bihar are not in school."))
    let single = LexicalGrader.evidence(["Odisha"], in: LexicalGrader.tokenize("Odisha passed the first resolution."))
    let negatedPair = LexicalGrader.evidence(phrases, in: LexicalGrader.tokenize("It is not one-third and Bihar is fine."))
    expect(one == .absent && both == .found && single == .found, "G1 two evidence phrases are needed when the check names two; one is enough when it names one", "\(one) \(both) \(single)")
    expect(negatedPair != .found, "G2 a negated phrase still does not count")
    // A model yes with no quote from the student is not credited and is not shown as right
    var o2 = outcome(await grade(goodAnswer, money, economics3, standard(goodTruth, quotes: [dcw: goodQuotes[dcw]!, moe: goodQuotes[moe]!])))
    let linkCriterion = money.causeLinks.first { $0.id == link }?.criterion ?? "?"
    expect(o2?.results[link]?.state == .uncertain && o2?.decision.report.right.contains(linkCriterion) == false, "G3 a yes without a quote is not shown as right", show(o2))
    o2 = outcome(await grade(goodAnswer, money, economics3, standard(goodTruth, quotes: goodQuotes)))
    expect(o2?.results[link]?.state == .yes && o2?.decision.report.right.contains(linkCriterion) == true, "G4 a yes with a confirmed quote is shown as right", show(o2))
}

// MARK: - Focused recheck helpers

do {
    let criterion = "States that Kerala has a much lower Infant Mortality Rate than Haryana (6 against 28 per 1000 live births)."
    let said = ModelGrader.contentOverlap(of: criterion, in: "kerala has only 6 infant deaths per 1000 compared to 28 in haryana")
    let unrelated = ModelGrader.contentOverlap(of: criterion, in: "Alluvial soil covers the northern plains and is very fertile for wheat.")
    expect(said >= 0.35 && unrelated < 0.2, "H1 content overlap separates a stated idea from an unrelated answer", "\(said) \(unrelated)")
    let answer = "Haryana has the highest income. In Kerala 6 infant deaths per 1000 compared to 28 in Haryana. In Bihar a third of teenagers are out of school. So we need health and education as well."
    let focus = ModelGrader.focus(of: answer, for: criterion)
    expect(focus.contains("infant deaths") && focus.count < answer.count && answer.contains(focus), "H2 the focus window is exact text of the best-matching sentence(s)", focus)
    expect(ModelGrader.focus(of: "Short answer here. Two sentences only.", for: criterion) == "Short answer here. Two sentences only.", "H3 an answer of two pieces or fewer is used whole")
}

// MARK: - Quote pieces (retry for a changed or merged quote)

do {
    let spoken = "so power is shared between the higher level and the lower levels, and below the states there are panchayats and municipalities also, which means the principle goes further down than the state governments"
    let sentences = "Roots grow from their tips. Cells there keep dividing by mitosis. So plants grow longer at the tips."
    let spokenPieces = ModelGrader.segments(of: spoken)
    expect(spokenPieces.count >= 2, "Q1 a long spoken run-on is cut into pieces", "\(spokenPieces.count)")
    expect(spokenPieces.allSatisfy { spoken.contains(spoken[$0]) } && ModelGrader.segments(of: sentences).count == 3, "Q2 pieces are exact substrings; short sentences stay whole")
    let check = GradableCheck(id: "c1", criterion: "States that roots grow from their tips.", kind: .keyPoint, lexical: .never, evidence: [])
    func reply(_ text: String) -> ModelGrader {
        ModelGrader(transport: FixtureTransport(handler: { _, _, _ in text }))
    }
    let picked = try? await reply("c1: 1-2").pickSegments([check], transcript: sentences, minimumWords: 4)
    expect(picked?["c1"] == .genuine("Roots grow from their tips. Cells there keep dividing by mitosis."), "Q3 a piece number gives the student's own words", "\(String(describing: picked))")
    let none = try? await reply("c1: NONE").pickSegments([check], transcript: sentences, minimumWords: 4)
    let outOfRange = try? await reply("c1: 9").pickSegments([check], transcript: sentences, minimumWords: 4)
    expect(none?["c1"] == QuoteVerdict.none && outOfRange?["c1"] == QuoteVerdict.none, "Q4 NONE or a number that does not exist gives no quote")
    let tooShort = try? await reply("c1: 1").pickSegments([check], transcript: sentences, minimumWords: 6)
    expect(tooShort?["c1"] == QuoteVerdict.none, "Q5 a piece shorter than the minimum words is not accepted")
    let wide = try? await reply("c1: 1-3").pickSegments([check], transcript: sentences, minimumWords: 4)
    expect(wide?["c1"] == .genuine("Roots grow from their tips. Cells there keep dividing by mitosis."), "Q6 a range is capped at two neighbouring pieces")
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
