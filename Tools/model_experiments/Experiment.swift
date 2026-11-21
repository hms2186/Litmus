//
//  Scratch experiment (not part of the app): compares grading variants on the app's own drift set,
//  using the app's own ModelGrader, GradingCoordinator.catalog and compiled curriculum.
//
import Foundation
import FoundationModels
import NaturalLanguage

// MARK: - Structured output types (static @Generable, positional numbers instead of dynamic IDs)

@Generable
struct PlainVerdict {
    @Guide(description: "The number of the criterion, starting at 1")
    var number: Int
    @Guide(description: "True only if the transcript clearly states the idea")
    var met: Bool
}

@Generable
struct PlainVerdicts {
    var verdicts: [PlainVerdict]
}

@Generable
struct EvidenceVerdict {
    @Guide(description: "The number of the criterion, starting at 1")
    var number: Int
    @Guide(description: "Words copied exactly from the student's transcript that show the idea, or NONE")
    var evidence: String
    @Guide(description: "True only if the copied words clearly state the idea")
    var met: Bool
}

@Generable
struct EvidenceVerdicts {
    var verdicts: [EvidenceVerdict]
}


struct ConceptContext: Sendable {
    var grade = "", subject = "", chapter = "", topic = "", passage = ""
    var indicators: [(text: String, level: String)] = []
}
final class ContextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ConceptContext()
    var current: ConceptContext { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: ConceptContext) { lock.lock(); value = v; lock.unlock() }
}

/// Collects what the model was sent and answered, for the trace probe (never used by the grading path).
final class Recorded: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    func drain() -> [String] { lock.lock(); defer { lock.unlock() }; let r = items; items = []; return r }
}

/// Wraps a transport and records every reply unchanged.
struct RecordingTransport: ModelTransport {
    let inner: any ModelTransport
    let log: Recorded
    var isReady: Bool { inner.isReady }
    func respond(instructions: String, prompt: String, maximumTokens: Int) async throws -> String {
        let out = try await inner.respond(instructions: instructions, prompt: prompt, maximumTokens: maximumTokens)
        log.add("PROMPT TAIL: \(prompt.suffix(160).replacingOccurrences(of: "\n", with: " "))\n      RAW REPLY: \(out)")
        return out
    }
}

func chapterInstructions(_ variant: Variant, base: String, _ c: ConceptContext) -> String {
    let area = c.subject == "Civics" ? "Civics (Political Science)" : c.subject
    var head = """
    You are the answer checker inside a study app for Indian CBSE students. This answer belongs to the \(c.grade) \(area) NCERT chapter "\(c.chapter)", topic "\(c.topic)".
    The student is a \(c.grade) pupil and may use everyday words instead of textbook terms. Facts about history, politics, economics, geography or science may be described plainly; judge only whether the idea is stated.
    """
    if variant == .chapterPassage || variant == .chapterAll {
        head += "\n\nTEXTBOOK PASSAGE (NCERT, the source of truth for this topic):\n\(c.passage)\nA criterion is met only when the student's words carry the same idea as the passage. The passage is for comparison; it is never part of the student's answer."
    }
    if variant == .chapterOfficial || variant == .chapterAll, !c.indicators.isEmpty {
        head += "\n\nOFFICIAL CBSE LEARNING INDICATORS for this topic (what a student is expected to do, with the thinking level):\n" + c.indicators.map { "- \($0.text) [\($0.level)]" }.joined(separator: "\n")
    }
    return head + "\n\n" + base
}


/// Some replies come back as [{"ID": "x", "result": "true"}]; turn them into {"x": true} so judgement, not format, is measured.
func normaliseReply(_ text: String) -> String {
    guard text.contains("\"ID\"") else { return text }
    let pattern = "\"ID\"\\s*:\\s*\"([^\"]+)\"\\s*,\\s*\"(?:result|value|status|answer|met|verdict)\"\\s*:\\s*\"?(true|false)"
    guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
    let ns = text as NSString
    var pairs: [String] = []
    for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        pairs.append("\"\(ns.substring(with: m.range(at: 1)))\": \(ns.substring(with: m.range(at: 2)).lowercased())")
    }
    return pairs.isEmpty ? text : "{" + pairs.joined(separator: ", ") + "}"
}

// MARK: - Stats

final class Stats: @unchecked Sendable {
    private let lock = NSLock()
    var calls = 0
    var seconds = 0.0
    var errors: [String: Int] = [:]
    func record(_ s: Double) { lock.lock(); calls += 1; seconds += s; lock.unlock() }
    func error(_ e: String) { lock.lock(); errors[e, default: 0] += 1; lock.unlock() }
}

// MARK: - Transports

enum Variant: String {
    case current            // the app today (plain text, default guardrails)
    case permissive         // plain text, permissive guardrails
    case context            // plain text + role/audience context in the instructions
    case structured         // static @Generable verdicts
    case structuredEvidence // @Generable verdicts that copy evidence first
    case contextPermissive
    case contextPermissiveExample
    case chapter          // role + subject, class, chapter and topic from the chapter file
    case chapterPassage   // + the textbook passage as source of truth
    case chapterOfficial  // + official CBSE indicators and cognitive levels
    case chapterAll       // passage + official indicators
    case hybrid2          // passage for concept checks only; everything else exactly as the generic role-line version
    case hybrid           // passage for concept checks only; chapter context for misconception/relevance/comparison
}

nonisolated struct ExperimentTransport: ModelTransport {
    let variant: Variant
    let stats: Stats
    var box: ContextBox? = nil
    var isReady: Bool { SystemLanguageModel.default.isAvailable }

    static let contextLine = "This is for a tutoring app for Class 9 and 10 students following the NCERT syllabus in India. Students may describe history, politics or science events factually; judge only whether the idea is stated."

    static let example = """
    Worked example, not from this student: criterion "States that plants make their own food using sunlight." The transcript "Plants use light to make food for themselves" is true (different words, same meaning). The transcript "Plants need sunlight to live" is false (the idea of making food is missing).
    """

    func respond(instructions: String, prompt: String, maximumTokens: Int) async throws -> String {
        let start = ContinuousClock.now
        defer {
            let d = ContinuousClock.now - start
            stats.record(Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
        }
        do {
            switch variant {
            case .current:
                return try await plain(instructions: instructions, prompt: prompt, maximumTokens: maximumTokens, guardrails: .default)
            case .permissive:
                return try await plain(instructions: instructions, prompt: prompt, maximumTokens: maximumTokens, guardrails: .permissiveContentTransformations)
            case .context:
                return try await plain(instructions: Self.contextLine + "\n" + instructions, prompt: prompt, maximumTokens: maximumTokens, guardrails: .default)
            case .contextPermissive:
                return try await plain(instructions: Self.contextLine + "\n" + instructions, prompt: prompt, maximumTokens: maximumTokens, guardrails: .permissiveContentTransformations)
            case .contextPermissiveExample:
                return try await plain(instructions: Self.contextLine + "\n" + instructions + "\n" + Self.example, prompt: prompt, maximumTokens: maximumTokens, guardrails: .permissiveContentTransformations)
            case .chapter, .chapterPassage, .chapterOfficial, .chapterAll:
                let text = chapterInstructions(variant, base: instructions, box?.current ?? ConceptContext())
                return try await plain(instructions: text, prompt: prompt, maximumTokens: maximumTokens, guardrails: .permissiveContentTransformations)
            case .hybrid2:
                let isConceptCheck = instructions.hasPrefix("You check")
                let text = isConceptCheck ? chapterInstructions(.chapterPassage, base: instructions, box?.current ?? ConceptContext())
                                          : Self.contextLine + "\n" + instructions
                return try await plain(instructions: text, prompt: prompt, maximumTokens: maximumTokens, guardrails: .permissiveContentTransformations)
            case .hybrid:
                let isConceptCheck = instructions.hasPrefix("You check")
                let text = chapterInstructions(isConceptCheck ? .chapterPassage : .chapter, base: instructions, box?.current ?? ConceptContext())
                return try await plain(instructions: text, prompt: prompt, maximumTokens: maximumTokens, guardrails: .permissiveContentTransformations)
            case .structured, .structuredEvidence:
                return try await structured(instructions: instructions, prompt: prompt)
            }
        } catch {
            stats.error(String(describing: FoundationModelsTransport.transportError(error)).prefix(40).description)
            throw FoundationModelsTransport.transportError(error)
        }
    }

    private func plain(instructions: String, prompt: String, maximumTokens: Int, guardrails: SystemLanguageModel.Guardrails) async throws -> String {
        let model = SystemLanguageModel(useCase: .general, guardrails: guardrails)
        let session = LanguageModelSession(model: model, instructions: instructions)
        let r = try await session.respond(to: Prompt(prompt), options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maximumTokens * 3 + 40))
        if ProcessInfo.processInfo.environment["LITMUS_DEBUG"] != nil {
            let lines = prompt.components(separatedBy: "\n")
            var ids: [String] = []
            if let h = lines.firstIndex(where: { $0.hasSuffix("(ID: criterion)") || $0.hasSuffix("(ID: idea)") }) {
                var i = h + 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty, let c = lines[i].range(of: ": ") { ids.append(String(lines[i][..<c.lowerBound])); i += 1 }
            }
            let parsed = ModelGrader.parseStates(r.content, ids: ids)
            let found = parsed.values.filter { $0 != nil }.count
            if found < ids.count {
                FileHandle.standardError.write(("RAW found \(found)/\(ids.count) ids, tokens cap \(maximumTokens): " + r.content.prefix(300).replacingOccurrences(of: "\n", with: " ⏎ ") + "\n").data(using: .utf8)!)
            }
        }
        return normaliseReply(r.content)
    }

    /// Replaces "ID: criterion" lines by numbered lines, asks for typed verdicts, and writes the reply back as the
    /// {"ID": true} object the app's grader already parses.
    private func structured(instructions: String, prompt: String) async throws -> String {
        var lines = prompt.components(separatedBy: "\n")
        guard let header = lines.firstIndex(where: { $0.hasSuffix("(ID: criterion)") || $0.hasSuffix("(ID: idea)") || $0.hasSuffix("(ID: statement)") }) else {
            throw TransportError.unusableReply
        }
        var ids: [String] = []
        var i = header + 1
        while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
            guard let colon = lines[i].range(of: ": ") else { break }
            ids.append(String(lines[i][..<colon.lowerBound]))
            lines[i] = "\(ids.count). " + lines[i][colon.upperBound...]
            i += 1
        }
        lines[header] = lines[header].replacingOccurrences(of: "(ID: criterion)", with: "(numbered)")
            .replacingOccurrences(of: "(ID: idea)", with: "(numbered)")
        if let last = lines.lastIndex(where: { $0.hasPrefix("Reply with only a JSON") }) {
            lines[last] = "Give one verdict for every numbered item."
        }
        let rebuilt = lines.joined(separator: "\n").replacingOccurrences(of: "IDs starting with \"lnk_\"", with: "Items that link two ideas")
        let model = SystemLanguageModel(useCase: .general, guardrails: .default)
        let session = LanguageModelSession(model: model, instructions: instructions)
        var met: [Int: Bool] = [:]
        if variant == .structuredEvidence {
            let r = try await session.respond(to: Prompt(rebuilt), generating: EvidenceVerdicts.self,
                                              options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 90 * ids.count + 40))
            for v in r.content.verdicts { met[v.number] = v.met }
        } else {
            let r = try await session.respond(to: Prompt(rebuilt), generating: PlainVerdicts.self,
                                              options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 30 * ids.count + 40))
            for v in r.content.verdicts { met[v.number] = v.met }
        }
        let pairs = ids.enumerated().compactMap { index, id -> String? in
            guard let m = met[index + 1] else { return nil }
            return "\"\(id)\": \(m)"
        }
        return "{" + pairs.joined(separator: ", ") + "}"
    }
}

// MARK: - Measurement

struct CheckOutcome { let answerId: String; let category: String; let checkId: String; let expected: Bool; let got: CheckState }

struct Report {
    var name: String
    var outcomes: [CheckOutcome] = []
    var failedBatches = 0
    var totalBatches = 0
    var seconds = 0.0
    var stats: Stats

    func agreement(_ filter: (CheckOutcome) -> Bool = { _ in true }) -> Double {
        let sel = outcomes.filter(filter)
        guard !sel.isEmpty else { return 0 }
        return Double(sel.filter { $0.got != .uncertain && ($0.got == .yes) == $0.expected }.count) / Double(sel.count)
    }
    var falseYes: Int { outcomes.filter { $0.got == .yes && !$0.expected }.count }
    var falseNo: Int { outcomes.filter { $0.got == .no && $0.expected }.count }
    var uncertain: Int { outcomes.filter { $0.got == .uncertain }.count }
}

func measure(name: String, set: DriftSet, store: CompiledCurriculumStore, transport: any ModelTransport, stats: Stats, box: ContextBox? = nil, perBatchSeconds: Double = 8) async -> Report {
    var report = Report(name: name, stats: stats)
    let grader = ModelGrader(transport: transport)
    let began = ContinuousClock.now
    for answer in set.answers {
        guard let concept = store.entriesById[answer.conceptId]?.concept else { continue }
        box?.set(contextFor(answer.conceptId))
        let catalog = GradingCoordinator.catalog(concept)
        let batches = concept.batches.topic.map { ($0, BatchStyle.topic) } + (concept.batches.a + concept.batches.b).map { ($0, BatchStyle.screening) }
        var states: [String: CheckState] = [:]
        for (ids, style) in batches {
            let checks = ids.compactMap { catalog[$0] }
            guard !checks.isEmpty else { continue }
            report.totalBatches += 1
            do {
                let results = try await GradingCoordinator.withTimeout(perBatchSeconds) {
                    try await grader.grade(checks, style: style, answers: [answer.text])
                }
                for (id, r) in results { states[id] = r.state }
            } catch {
                report.failedBatches += 1
            }
        }
        let expected = Set(answer.yes)
        let skipped = Set(answer.skip)
        for id in catalog.keys.sorted() where !skipped.contains(id) {
            report.outcomes.append(CheckOutcome(answerId: answer.id, category: answer.category, checkId: id,
                                                expected: expected.contains(id), got: states[id] ?? .uncertain))
        }
    }
    let d = ContinuousClock.now - began
    report.seconds = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    return report
}

func printReport(_ r: Report) {
    func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    let cats = ["textbook", "paraphrase", "misconception"]
    let perCat = cats.map { c in "\(c) \(pct(r.agreement { $0.category == c }))" }.joined(separator: " | ")
    print("""
    [\(r.name)] agreement \(pct(r.agreement())) over \(r.outcomes.count) checks | falseYes \(r.falseYes) falseNo \(r.falseNo) uncertain \(r.uncertain)
        by category: \(perCat)
        failed batches \(r.failedBatches)/\(r.totalBatches) | model calls \(r.stats.calls), mean \(String(format: "%.2f", r.stats.calls == 0 ? 0 : r.stats.seconds / Double(r.stats.calls))) s | wall \(String(format: "%.0f", r.seconds)) s | errors \(r.stats.errors)
    """)
    fflush(stdout)
}

func compare(_ base: Report, _ other: Report) {
    var better = 0, worse = 0
    var worseList: [String] = []
    for (a, b) in zip(base.outcomes, other.outcomes) where a.answerId == b.answerId && a.checkId == b.checkId {
        let ca = a.got != .uncertain && (a.got == .yes) == a.expected
        let cb = b.got != .uncertain && (b.got == .yes) == b.expected
        if !ca && cb { better += 1 }
        if ca && !cb { worse += 1; worseList.append("\(b.answerId)/\(b.checkId)") }
    }
    print("    vs current: fixed \(better) checks, broke \(worse)\(worse > 0 ? " e.g. " + worseList.prefix(4).joined(separator: ", ") : "")")
    fflush(stdout)
}

// MARK: - Entry

setvbuf(stdout, nil, _IOLBF, 0) // line-buffered, so a piped run shows each result as it happens
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let only = CommandLine.arguments.count > 2 ? Set(CommandLine.arguments[2].split(separator: ",").map(String.init)) : nil
let set = try JSONDecoder().decode(DriftSet.self, from: Data(contentsOf: root.appending(path: "Litmus/Resources/Evaluation/drift_set.json")))
let compiled = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Litmus/Compiled"), includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasSuffix(".compiled.json") }
let store = CompiledCurriculumStore(urls: compiled)
struct TagFile: Decodable { struct Ind: Decodable { let text: String; let level: String? }; struct Tag: Decodable { let status: String; let indicators: [Ind]? }; let tags: [String: Tag] }
let tagFile = try JSONDecoder().decode(TagFile.self, from: Data(contentsOf: root.appending(path: "Curriculum/official/concept_tags.json")))
func contextFor(_ conceptId: String) -> ConceptContext {
    guard let e = store.entriesById[conceptId] else { return ConceptContext() }
    var c = ConceptContext(grade: e.chapter.gradeLevel, subject: e.chapter.subject, chapter: e.chapter.chapterName, topic: e.concept.label, passage: e.concept.cardText)
    if let t = tagFile.tags[conceptId], t.status != "unmapped" { c.indicators = (t.indicators ?? []).map { ($0.text, $0.level ?? "Applying") } }
    return c
}
print("Model: \(SystemLanguageModel.default.availability) | answers \(set.answers.count) | recorded baseline \(set.baseline.map { String($0.agreement) } ?? "none")")


if let only, only.contains("semdist") {
    // Cosine distance from each key-point criterion to the closest statement of the answer, against the human label
    var rows: [(Double, Bool, String)] = []
    for answer in set.answers where answer.category != "misconception" {
        guard let entry = store.entriesById[answer.conceptId] else { continue }
        let catalog = GradingCoordinator.catalog(entry.concept)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = answer.text
        let statements = tokenizer.tokens(for: answer.text.startIndex..<answer.text.endIndex).map { String(answer.text[$0]) }
            .filter(CodeGrader.hasFiniteVerb)
            .filter { !LexicalGrader.tokenize($0).contains(where: LexicalGrader.negations.contains) }
        for (id, check) in catalog where check.kind == .keyPoint && check.lexical == .evidence && !answer.skip.contains(id) {
            guard let d = RubricMatrix.semanticDistance(criterion: check.criterion, statements: statements) else { continue }
            rows.append((d, answer.yes.contains(id), "\(answer.id) \(id)"))
        }
    }
    rows.sort { $0.0 < $1.0 }
    for r in rows { print(String(format: "%.3f", r.0), r.1 ? "YES" : "no ", r.2) }
    exit(0)
}

if let only, only.contains("labelrows") {
    // What the Rule Engine decides when the human labels are the check results: shows which row blocks a pass
    for answer in set.answers where answer.category != "misconception" {
        guard let entry = store.entriesById[answer.conceptId] else { continue }
        let catalog = GradingCoordinator.catalog(entry.concept)
        var results = CodeGrader.articulation(entry.chapter.articulationChecks, transcript: answer.text, vocabulary: entry.chapter.chapterVocabulary)
        for id in catalog.keys where !answer.skip.contains(id) {
            results[id] = CheckResult(state: answer.yes.contains(id) ? .yes : .no, source: .model)
        }
        let overlap = CodeGrader.keywordOverlap(answer.text, concept: entry.concept, vocabulary: entry.chapter.chapterVocabulary)
        let ctx = AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: overlap, provisionalOnly: false)
        let d = RuleEngine.decide(entry.concept, results: results, context: ctx, articulationChecks: entry.chapter.articulationChecks)
        print("\(answer.id): \(d.outcome) | \(d.trace.joined(separator: " | "))")
        for kp in entry.concept.keyPoints {
            let o = d.keyPointOutcomes[kp.id].map { "\($0)" } ?? "?"
            let miss = kp.checks.filter { results[$0.id]?.state != .yes }.map { "\($0.id)\($0.isRequired ? "*" : "")=\(results[$0.id]?.state.rawValue ?? "unset")" }
            print("    \(kp.role) w\(kp.weight) \(kp.passRule) -> \(o)\(miss.isEmpty ? "" : "  not-yes: " + miss.joined(separator: ", "))")
        }
    }
    exit(0)
}

if let only, only.contains("e2e") {
    func kind(_ o: EvaluationOutcome) -> String {
        switch o {
        case .mastered, .likelyMastered: return "pass"
        case .partial: return "partial"
        case .notYet: return "notYet"
        case .needsCorrection: return "needsCorrection"
        case .needsClarification: return "needsClarification"
        case .offTopic: return "offTopic"
        case .notGradable: return "notGradable"
        }
    }
    /// The outcome the rule engine gives when the human labels are the check results.
    func labelled(_ answer: DriftAnswer, _ entry: CompiledCurriculumStore.Entry) -> EvaluationOutcome {
        let catalog = GradingCoordinator.catalog(entry.concept)
        var results = CodeGrader.articulation(entry.chapter.articulationChecks, transcript: answer.text, vocabulary: entry.chapter.chapterVocabulary)
        for id in catalog.keys where !answer.skip.contains(id) {
            results[id] = CheckResult(state: answer.yes.contains(id) ? .yes : .no, source: .model)
        }
        let overlap = CodeGrader.keywordOverlap(answer.text, concept: entry.concept, vocabulary: entry.chapter.chapterVocabulary)
        let ctx = AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: overlap, provisionalOnly: false)
        return RuleEngine.decide(entry.concept, results: results, context: ctx, articulationChecks: entry.chapter.articulationChecks).outcome
    }
    for variant in [Variant.contextPermissive, .hybrid2].filter({ only.contains($0.rawValue) }) {
        let stats = Stats()
        let ebox = ContextBox()
        var gradingSettings = GradingSettings()
        gradingSettings.rubricEvidence = ProcessInfo.processInfo.environment["NO_RUBRIC"] == nil
    gradingSettings.phrasingSupport = ProcessInfo.processInfo.environment["PHRASING"] == "1"
    gradingSettings.holdMisconceptionOnSharedQuote = ProcessInfo.processInfo.environment["HOLD"] == "1"
        let coordinator = GradingCoordinator(transport: ExperimentTransport(variant: variant, stats: stats, box: ebox), settings: gradingSettings)
        var match = 0, total = 0, blocked = 0, wrongPass = 0, missedPass = 0
        var seconds = 0.0
        var lines: [String] = []
        for answer in set.answers {
            guard let entry = store.entriesById[answer.conceptId] else { continue }
            ebox.set(contextFor(answer.conceptId))
            let want = kind(labelled(answer, entry))
            let t0 = ContinuousClock.now
            let result = await coordinator.grade(answer: answer.text, concept: entry.concept, chapter: entry.chapter)
            let d = ContinuousClock.now - t0
            seconds += Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
            total += 1
            switch result {
            case .blocked:
                blocked += 1; lines.append("\(answer.id): BLOCKED (labels say \(want))")
            case .graded(let o):
                let got = kind(o.decision.outcome)
                if got == want { match += 1 }
                else if got == "pass" { wrongPass += 1 }
                else if want == "pass" { missedPass += 1 }
                lines.append("\(answer.id): got \(got) | labels say \(want)\(got == want ? "" : "   <-- DIFFERENT")")
            }
        }
        print("[\(variant.rawValue)] END-TO-END: same outcome as the labels \(match)/\(total) | blocked \(blocked) | passed but labels say no \(wrongPass) | labels say pass but not passed \(missedPass) | mean \(String(format: "%.1f", seconds / Double(total))) s | model calls \(stats.calls) | errors \(stats.errors)")
        print(lines.joined(separator: "\n"))
        fflush(stdout)
    }
    exit(0)
}

if let only, only.contains("adv") {
    // Hand-written adversarial answers for the two concepts that have accepted phrasings (labels by the developer, not students).
    // PHRASING=1 turns the lift on. A false pass is an answer labelled "must not pass" that reaches Mastered or Likely mastered.
    struct Adv: Decodable { let id: String; let conceptId: String; let expectPass: Bool; let text: String }
    struct AdvSet: Decodable { let answers: [Adv] }
    let advSet = try JSONDecoder().decode(AdvSet.self, from: Data(contentsOf: root.appending(path: "Tools/model_experiments/adversarial_set.json")))
    var settings = GradingSettings()
    settings.phrasingSupport = ProcessInfo.processInfo.environment["PHRASING"] == "1"
    settings.holdMisconceptionOnSharedQuote = ProcessInfo.processInfo.environment["HOLD"] == "1"
    let coordinator = GradingCoordinator(transport: FoundationModelsTransport(), settings: settings)
    var falsePass = 0, missed = 0, right = 0
    for a in advSet.answers {
        guard let e = store.entriesById[a.conceptId] else { continue }
        guard case .graded(let o) = await coordinator.grade(answer: a.text, concept: e.concept, chapter: e.chapter) else { print("\(a.id): blocked"); continue }
        let passed: Bool = { switch o.decision.outcome { case .mastered, .likelyMastered: return true; default: return false } }()
        if passed == a.expectPass { right += 1 } else if passed { falsePass += 1 } else { missed += 1 }
        let tag = passed == a.expectPass ? "ok  " : (passed ? "FALSE PASS" : "missed")
        print("\(tag) \(a.id): \(o.decision.outcome) | lifted \(o.log.phrasingSupported) | \(Int(o.log.seconds * 10) / 10) s")
    }
    print("ADVERSARIAL phrasing=\(settings.phrasingSupport): right \(right)/\(advSet.answers.count) | false passes \(falsePass) | missed passes \(missed)")
    exit(0)
}

if let only, only.contains("rows") {
    // What the session-summary rows say, against what the answer says. The rows are the engine report: "right" = criteria of
    // checks that came back yes, "missing"/"vague"/"corrections" = the rest. Part 1: rows vs the developer's per-check labels.
    // Part 2: each answer graded under TWO OTHER topics, where almost nothing may be green (rows must follow the input).
    var settings = GradingSettings()
    settings.phrasingSupport = ProcessInfo.processInfo.environment["PHRASING"] == "1"
    settings.holdMisconceptionOnSharedQuote = ProcessInfo.processInfo.environment["HOLD"] == "1"
    let coordinator = GradingCoordinator(transport: FoundationModelsTransport(), settings: settings)
    var greenWrong = 0, redWrong = 0, rowsChecked = 0
    for a in set.answers where a.category != "misconception" {
        guard let e = store.entriesById[a.conceptId] else { continue }
        guard case .graded(let o) = await coordinator.grade(answer: a.text, concept: e.concept, chapter: e.chapter) else { continue }
        let catalog = GradingCoordinator.catalog(e.concept)
        let yes = Set(a.yes), skip = Set(a.skip)
        let green = Set(o.decision.report.right)
        var lines: [String] = []
        for (id, c) in catalog where c.kind == .keyPoint || c.kind == .causeLink {
            if skip.contains(id) { continue }
            rowsChecked += 1
            let isGreen = green.contains(c.criterion)
            if isGreen && !yes.contains(id) { greenWrong += 1; lines.append("   GREEN but labelled no: \(c.criterion.prefix(80))") }
            if !isGreen && yes.contains(id) { redWrong += 1; lines.append("   NOT green but labelled yes: \(c.criterion.prefix(80))") }
        }
        print("\(a.id) [\(e.concept.label)] -> \(o.decision.outcome) | green \(green.count) of \(catalog.values.filter { $0.kind == .keyPoint || $0.kind == .causeLink }.count)")
        lines.forEach { print($0) }
    }
    print("PART 1: rows checked \(rowsChecked) | green but labelled no \(greenWrong) | labelled yes but not green \(redWrong)")
    // Part 2: wrong-topic grading. Each paraphrase/textbook answer under two other concepts.
    let foreign: [(String, [String])] = [
        ("fed_P1", ["civ10_ch2_t1_c3", "eco10_ch3_t1_c1"]),
        ("route_P1", ["civ10_ch1_t3_c2", "geo10_ch1_t6_c2"]),
        ("money_T1", ["civ10_ch1_t3_c2", "civ10_ch2_t1_c3"]),
        ("jfm_P1", ["eco10_ch3_t1_c1", "civ10_ch2_t1_c3"]),
    ]
    var wrongTopicGreen = 0, wrongTopicRows = 0, wrongTopicPass = 0
    for (aid, others) in foreign {
        guard let a = set.answers.first(where: { $0.id == aid }) else { continue }
        for cid in others {
            guard let e = store.entriesById[cid] else { print("   (unknown concept \(cid))"); continue }
            guard case .graded(let o) = await coordinator.grade(answer: a.text, concept: e.concept, chapter: e.chapter) else { print("\(aid) under \(cid): blocked/offTopic"); continue }
            let n = o.decision.report.right.count
            let total = GradingCoordinator.catalog(e.concept).values.filter { $0.kind == .keyPoint || $0.kind == .causeLink }.count
            wrongTopicGreen += n; wrongTopicRows += total
            let passed: Bool = { switch o.decision.outcome { case .mastered, .likelyMastered: return true; default: return false } }()
            if passed { wrongTopicPass += 1 }
            print("\(aid) under [\(e.concept.label)] -> \(o.decision.outcome) | green \(n) of \(total)\(n > 0 ? " : " + o.decision.report.right.map { String($0.prefix(60)) }.joined(separator: " ; ") : "")")
        }
    }
    print("PART 2: wrong-topic green rows \(wrongTopicGreen) of \(wrongTopicRows) | wrong-topic passes \(wrongTopicPass)")
    exit(0)
}

if let only, only.contains("stress") {
    // Simulated Class 9-10 student answers (written by the developer, NOT real students) over 10 concepts and 8 categories
    // (P full paraphrase, S spoken style, X partial, M misconception, R reversed/swapped, L keyword list, V vague, O off topic).
    // Part 1 grades each answer under its own concept; part 2 grades every P and S answer under the next concept (wrong topic).
    // Writes one JSON line per run to STRESS_OUT (default /private/tmp/claude-502/stress.jsonl) with every check's state/source.
    // PHRASING=1 turns the accepted-phrasing lift on. Uses the shipped transport.
    struct SA: Decodable { let id: String; let conceptId: String; let category: String; let expectPass: Bool; let spoken: Bool; let text: String }
    struct SS: Decodable { let answers: [SA] }
    let sset = try JSONDecoder().decode(SS.self, from: Data(contentsOf: root.appending(path: ProcessInfo.processInfo.environment["STRESS_SET"] ?? "Tools/model_experiments/stress_set.json")))
    var st = GradingSettings()
    st.phrasingSupport = ProcessInfo.processInfo.environment["PHRASING"] == "1"
    st.holdMisconceptionOnSharedQuote = ProcessInfo.processInfo.environment["HOLD"] == "1"
    let coord = GradingCoordinator(transport: FoundationModelsTransport(), settings: st)
    let outPath = ProcessInfo.processInfo.environment["STRESS_OUT"] ?? "/private/tmp/claude-502/stress.jsonl"
    FileManager.default.createFile(atPath: outPath, contents: nil)
    let handle = FileHandle(forWritingAtPath: outPath)!
    func emit(_ obj: [String: Any]) { if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) { handle.write(d); handle.write(Data("\n".utf8)) } }
    func isPass(_ o: EvaluationOutcome) -> Bool { switch o { case .mastered, .likelyMastered: return true; default: return false } }
    var falsePass = 0, missed = 0, ok = 0, total = 0
    var secs: [Double] = []
    let conceptOrder = Array(Set(sset.answers.map(\.conceptId))).sorted()
    for a in sset.answers {
        guard let e = store.entriesById[a.conceptId] else { continue }
        let t0 = ContinuousClock.now
        let res = await coord.grade(answer: a.text, concept: e.concept, chapter: e.chapter, spoken: a.spoken)
        let wall = Double((ContinuousClock.now - t0).components.seconds) + Double((ContinuousClock.now - t0).components.attoseconds) / 1e18
        guard case .graded(let o) = res else { print("BLOCKED \(a.id)"); emit(["run": "own", "id": a.id, "blocked": true]); continue }
        total += 1; secs.append(wall)
        let passed = isPass(o.decision.outcome)
        let tag = passed == a.expectPass ? "ok" : (passed ? "FALSE PASS" : "missed")
        if passed == a.expectPass { ok += 1 } else if passed { falsePass += 1 } else { missed += 1 }
        let catalog = GradingCoordinator.catalog(e.concept)
        let checks: [[String: Any]] = o.results.sorted { $0.key < $1.key }.map { id, r in
            ["id": id, "kind": "\(catalog[id]?.kind as Any)", "state": r.state.rawValue, "source": r.source.rawValue, "quote": r.quote ?? "", "lexical": catalog[id]?.lexical == .evidence]
        }
        emit(["run": "own", "id": a.id, "concept": e.concept.label, "category": a.category, "expectPass": a.expectPass, "passed": passed, "outcome": "\(o.decision.outcome)",
              "seconds": (wall * 10).rounded() / 10, "green": o.decision.report.right.count, "missing": o.decision.report.missing.count, "vague": o.decision.report.vague.count,
              "corrections": o.decision.report.corrections.count, "rightRows": o.decision.report.right, "missingRows": o.decision.report.missing, "vagueRows": o.decision.report.vague, "correctionRows": o.decision.report.corrections, "phrasingLifted": o.log.phrasingSupported, "evidenceLifted": o.log.rubricSupported,
              "keywordStuffing": o.log.keywordStuffing, "termListOverruled": o.log.termListOverruled, "proofRejected": o.log.proofRejected, "rechecked": o.log.rechecked, "focusedRechecked": o.log.focusedRechecked, "focusedFlipped": o.log.focusedFlipped,
              "recheckFlipped": o.log.recheckFlipped, "calls": o.log.modelCalls, "checks": checks])
        print("\(tag.padding(toLength: 10, withPad: " ", startingAt: 0)) \(a.id.padding(toLength: 10, withPad: " ", startingAt: 0)) \("\(o.decision.outcome)".prefix(34).padding(toLength: 34, withPad: " ", startingAt: 0)) green \(o.decision.report.right.count) | \(String(format: "%.1f", wall)) s | lifted \(o.log.phrasingSupported)")
    }
    print("PART 1 (own topic): \(ok)/\(total) as labelled | false passes \(falsePass) | missed passes \(missed) | mean \(String(format: "%.1f", secs.reduce(0, +) / Double(max(secs.count, 1)))) s | max \(String(format: "%.1f", secs.max() ?? 0)) s")
    var wrongPass = 0, wrongGreen = 0, wrongRows = 0, wrongTotal = 0
    for a in sset.answers where a.category == "P" || a.category == "S" {
        guard let idx = conceptOrder.firstIndex(of: a.conceptId), let e = store.entriesById[conceptOrder[(idx + 1) % conceptOrder.count]] else { continue }
        let res = await coord.grade(answer: a.text, concept: e.concept, chapter: e.chapter, spoken: a.spoken)
        guard case .graded(let o) = res else { emit(["run": "wrongTopic", "id": a.id, "blocked": true]); continue }
        wrongTotal += 1
        let n = o.decision.report.right.count
        let rows = GradingCoordinator.catalog(e.concept).values.filter { $0.kind == .keyPoint || $0.kind == .causeLink }.count
        wrongGreen += n; wrongRows += rows
        if isPass(o.decision.outcome) { wrongPass += 1 }
        emit(["run": "wrongTopic", "id": a.id, "askedConcept": e.concept.label, "outcome": "\(o.decision.outcome)", "green": n, "rows": rows, "greenCriteria": o.decision.report.right])
        if n > 0 || isPass(o.decision.outcome) { print("WRONG TOPIC \(a.id) under [\(e.concept.label)] -> \(o.decision.outcome) | green \(n)/\(rows)") }
    }
    print("PART 2 (wrong topic): \(wrongTotal) answers | passes \(wrongPass) | green rows \(wrongGreen) of \(wrongRows)")
    handle.closeFile()
    exit(0)
}

if let only, only.contains("kwlist") {
    // Keyword-only answers: the chapter's own terms in a list, with no statement. None of them may pass.
    var kwSettings = GradingSettings()
    kwSettings.phrasingSupport = ProcessInfo.processInfo.environment["PHRASING"] == "1"
    kwSettings.holdMisconceptionOnSharedQuote = ProcessInfo.processInfo.environment["HOLD"] == "1"
    let coordinator = GradingCoordinator(transport: FoundationModelsTransport(), settings: kwSettings)
    var passed = 0, total = 0
    // every 40th concept, plus the two concepts that have accepted phrasings (their anchor words as a list)
    let ids = Array(Set(store.entriesById.keys.sorted().enumerated().filter { $0.offset % 40 == 5 }.map(\.element)
                        + ["civ10_ch1_t3_c2", "civ10_ch2_t1_c3"])).sorted()
    for id in ids {
        guard let e = store.entriesById[id] else { continue }
        var seen = Set<String>(), terms: [String] = []
        for p in e.concept.keyPoints.flatMap(\.requiredEvidence) {
            for w in p.split(separator: " ") where w.count >= 5 && seen.insert(w.lowercased()).inserted { terms.append(String(w)) }
        }
        let list = terms.prefix(7).joined(separator: ", ")
        let result = await coordinator.grade(answer: list, concept: e.concept, chapter: e.chapter)
        guard case .graded(let o) = result else { print("\(id): blocked"); continue }
        total += 1
        let pass: Bool = { switch o.decision.outcome { case .mastered, .likelyMastered: return true; default: return false } }()
        if pass { passed += 1 }
        print("\(pass ? "PASS(!!)" : "ok      ") \(id) \(o.decision.outcome) | \(list.prefix(70))")
    }
    // The anchor words of the accepted phrasings, as lists and as scrambled non-statements: none may pass either.
    let anchorLists: [(String, String)] = [
        ("civ10_ch1_t3_c2", "top level, lower level, split, shared, divided, central government"),
        ("civ10_ch1_t3_c2", "higher level lower level power split between"),
        ("civ10_ch2_t1_c3", "independent, separate, join, united, by themselves, agreed"),
        ("civ10_ch2_t1_c3", "independent states join by themselves coming together holding together"),
    ]
    for (id, list) in anchorLists {
        guard let e = store.entriesById[id] else { continue }
        guard case .graded(let o) = await coordinator.grade(answer: list, concept: e.concept, chapter: e.chapter) else { print("\(id): blocked"); continue }
        total += 1
        let pass: Bool = { switch o.decision.outcome { case .mastered, .likelyMastered: return true; default: return false } }()
        if pass { passed += 1 }
        print("\(pass ? "PASS(!!)" : "ok      ") anchors \(id) \(o.decision.outcome) | \(list)")
    }
    print("KEYWORD LISTS PASSED: \(passed) of \(total)")
    exit(0)
}

if let only, only.contains("demo") {
    // A readable end-to-end run for people: the answer, every check with the model's verdict and quote, the outcome
    let ids = (ProcessInfo.processInfo.environment["DEMO_IDS"] ?? "money_T1").split(separator: ",").map(String.init)
    var gradingSettings = GradingSettings()
    gradingSettings.rubricEvidence = ProcessInfo.processInfo.environment["NO_RUBRIC"] == nil
    gradingSettings.phrasingSupport = ProcessInfo.processInfo.environment["PHRASING"] == "1"
    gradingSettings.holdMisconceptionOnSharedQuote = ProcessInfo.processInfo.environment["HOLD"] == "1"
    let box = ContextBox()
    // DEMO_APP=1 grades exactly as the shipped app does (its own transport and prompts), not an experiment variant
    let coordinator: GradingCoordinator = ProcessInfo.processInfo.environment["DEMO_APP"] != nil
        ? GradingCoordinator(transport: FoundationModelsTransport(), settings: gradingSettings)
        : GradingCoordinator(transport: ExperimentTransport(variant: .hybrid2, stats: Stats(), box: box), settings: gradingSettings)
    for id in ids {
        var found = set.answers.first(where: { $0.id == id })
        // A custom answer: DEMO_CONCEPT=<conceptId> DEMO_TEXT="..." (the id is then only a label)
        if found == nil, let cid = ProcessInfo.processInfo.environment["DEMO_CONCEPT"], let text = ProcessInfo.processInfo.environment["DEMO_TEXT"] {
            found = DriftAnswer(id: id, conceptId: cid, category: "custom", text: text, yes: [], skip: [])
        }
        guard let answer = found, let entry = store.entriesById[answer.conceptId] else { print("unknown \(id)"); continue }
        box.set(contextFor(answer.conceptId))
        print("TOPIC: \(entry.chapter.chapterName)  >  \(entry.concept.label)")
        print("PASSAGE (what the textbook says): \(entry.concept.cardText)\n")
        print("STUDENT ANSWER: \(answer.text)\n")
        let result = await coordinator.grade(answer: answer.text, concept: entry.concept, chapter: entry.chapter, spoken: ProcessInfo.processInfo.environment["DEMO_SPOKEN"] != nil)
        guard case .graded(let o) = result else { print("blocked by guardrails"); continue }
        print("CHECKS (each key idea, judged by the on-device model):")
        let catalog = GradingCoordinator.catalog(entry.concept)
        for (cid, r) in o.results.sorted(by: { $0.key < $1.key }) {
            guard let c = catalog[cid] else { continue }
            print("  [\(r.state.rawValue.uppercased())] \(c.criterion)")
            if let q = r.quote, r.state == .yes { print("        student's own words: \"\(q)\"") }
        }
        print("\nENGINE DECISION: \(o.decision.outcome)   (weight passed \(o.decision.passedWeight) of \(o.decision.scoredWeight))")
        print("PARAKH LEVEL: \(RubricMatrix.level(of: o.decision.outcome).map { $0.rawValue } ?? "n/a")")
        print("RULE TRACE: \(o.decision.trace.joined(separator: " | "))\n")
    }
    exit(0)
}

if let only, only.contains("verbtest") {
    for id in ["fed_P1", "route_P1", "jfm_P1"] {
        let a = set.answers.first { $0.id == id }!
        let tok = NLTokenizer(unit: .sentence); tok.string = a.text
        for r in tok.tokens(for: a.text.startIndex..<a.text.endIndex) {
            let sentence = String(a.text[r])
            let tagger = NLTagger(tagSchemes: [.lexicalClass]); tagger.string = sentence
            var tags: [String] = []
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { t, rr in tags.append("\(sentence[rr])/\(t?.rawValue ?? "?")"); return true }
            print("\(id) finiteVerb=\(CodeGrader.hasFiniteVerb(sentence)) :: \(tags.joined(separator: " "))")
        }
    }
    exit(0)
}

if let only, only.contains("qtrace") {
    // Raw model replies for chosen stress answers (QIDS=a,b,c), through the shipped transport. Diagnosis only.
    struct SA: Decodable { let id: String; let conceptId: String; let text: String; let spoken: Bool }
    struct SS: Decodable { let answers: [SA] }
    let sset = try JSONDecoder().decode(SS.self, from: Data(contentsOf: root.appending(path: ProcessInfo.processInfo.environment["STRESS_SET"] ?? "Tools/model_experiments/stress_set.json")))
    let ids = (ProcessInfo.processInfo.environment["QIDS"] ?? "").split(separator: ",").map(String.init)
    var st = GradingSettings()
    st.phrasingSupport = true
    if ProcessInfo.processInfo.environment["NOSEG"] == "1" { st.segmentQuoteRetry = false }
    if ProcessInfo.processInfo.environment["NOPROVE"] == "1" { st.proveDisplayedGreen = false }
    for id in ids {
        let drift = set.answers.first(where: { $0.id == id }).map { SA(id: $0.id, conceptId: $0.conceptId, text: $0.text, spoken: false) }
        guard let a = sset.answers.first(where: { $0.id == id }) ?? drift, let e = store.entriesById[a.conceptId] else { continue }
        let rec = Recorded()
        let coord = GradingCoordinator(transport: RecordingTransport(inner: FoundationModelsTransport(), log: rec), settings: st)
        let res = await coord.grade(answer: a.text, concept: e.concept, chapter: e.chapter, spoken: a.spoken)
        guard case .graded(let o) = res else { print(id, "blocked"); continue }
        print("==== \(id): \(o.decision.outcome)\nANSWER: \(a.text)")
        rec.drain().forEach { print("  \($0)") }
        print("log: proofRejected \(o.log.proofRejected) misNotConfirmed \(o.log.misconceptionNotConfirmed) notConfirmed \(o.log.quoteNotConfirmed) ruledOut \(o.log.misconceptionRuledOut)")
    }
    exit(0)
}

if let only, only.contains("trace") {
    let stats = Stats()
    let coordinator = GradingCoordinator(transport: ExperimentTransport(variant: .contextPermissive, stats: stats), settings: GradingSettings())
    for id in ["fed_T1", "fed_P1", "route_P1", "jfm_P1"] {
        let answer = set.answers.first { $0.id == id }!
        guard let entry = store.entriesById[answer.conceptId] else { continue }
        let result = await coordinator.grade(answer: answer.text, concept: entry.concept, chapter: entry.chapter)
        guard case .graded(let o) = result else { print(id, "blocked"); continue }
        print("== \(id): \(o.decision.outcome)")
        print("trace: \(o.decision.trace.joined(separator: " | "))")
        let expected = Set(answer.yes)
        for (cid, r) in o.results.sorted(by: { $0.key < $1.key }) where !answer.skip.contains(cid) {
            let exp = expected.contains(cid)
            if r.state == .uncertain, let q = r.quote { print("   QUOTE for \(cid): \"\(q)\"") }
            if (r.state == .yes) != exp { print("   MISMATCH \(cid): expected \(exp ? "yes" : "no") got \(r.state) (\(r.source)) quote:\(r.quoteCheck)") }
        }
        print("recheckSkipped: \(o.log.recheckSkipped)")
        if id == "route_P1" {
            for (cid, r) in o.results.sorted(by: { $0.key < $1.key }) { print("   STATE \(cid) = \(r.state.rawValue) (\(r.source)) corrected:\(r.corrected ?? false)") }
            var assumed = o.results
            assumed["chk_ch2_route_coming_pool"]?.state = .yes
            let overlap = CodeGrader.keywordOverlap(answer.text, concept: entry.concept, vocabulary: entry.chapter.chapterVocabulary)
            let ctx = AttemptContext(clarificationRoundsLeft: 1, keywordOverlap: overlap, provisionalOnly: false)
            let d2 = RuleEngine.decide(entry.concept, results: assumed, context: ctx, articulationChecks: entry.chapter.articulationChecks)
            print("   IF coming_pool were yes: \(d2.outcome) | \(d2.trace.joined(separator: " | "))")
        }
        if let cid = ["fed_P1": "chk_vertical_higher_lower", "route_P1": "chk_ch2_route_coming_pool"][id],
           let check = GradingCoordinator.catalog(entry.concept)[cid] {
            // Probe only: re-asks this one check step by step the way recheckBlockingNos does, and prints each step. Grades nothing.
            let rec = Recorded()
            let probe = ModelGrader(transport: RecordingTransport(inner: ExperimentTransport(variant: .contextPermissive, stats: Stats()), log: rec),
                                    context: GradingContext(concept: entry.concept, chapter: entry.chapter))
            let again = try? await probe.grade([check], style: .screening, answers: [answer.text], strictFormat: true, lenient: true)
            print("   PROBE \(cid) lenient recheck -> \(String(describing: again?[cid]?.state))")
            let proof = try? await probe.prove([check], transcript: answer.text, minimumWords: GradingSettings().minimumQuoteWords)
            print("   PROBE \(cid) proof verdict -> \(String(describing: proof?[cid]))")
            if case .genuine(let quote)? = proof?[cid] {
                let excerpt = ModelGrader.excerpt(around: quote, in: answer.text, contextSentences: GradingSettings().confirmContextSentences)
                let confirm = try? await probe.grade([check], style: .screening, answers: [excerpt])
                print("   PROBE \(cid) in-context confirmation -> \(String(describing: confirm?[cid]?.state))")
            }
            rec.drain().forEach { print("   \($0)") }
        }
        print("log: failed \(o.log.failedBatches) rejected \(o.log.proofRejected) notConfirmed \(o.log.quoteNotConfirmed) rechecked \(o.log.rechecked) flipped \(o.log.recheckFlipped) phrasing \(o.log.phrasingSupported)")
    }
    exit(0)
}

var baseReport: Report?
for variant in [Variant.current, .permissive, .context, .structured, .structuredEvidence, .contextPermissive, .contextPermissiveExample, .chapter, .chapterPassage, .chapterOfficial, .chapterAll, .hybrid, .hybrid2] {
    if let only, !only.contains(variant.rawValue) { continue }
    let stats = Stats()
    let vbox = ContextBox()
    let r = await measure(name: variant.rawValue, set: set, store: store, transport: ExperimentTransport(variant: variant, stats: stats, box: vbox), stats: stats, box: vbox)
    printReport(r)
    if variant == .current { baseReport = r } else if let baseReport { compare(baseReport, r) }
}

// The current keyword fallback on the same answers (what the app does without Apple Intelligence)
do {
    var lex = Report(name: "keyword fallback (no AI)", stats: Stats())
    for answer in set.answers {
        guard let concept = store.entriesById[answer.conceptId]?.concept else { continue }
        let catalog = GradingCoordinator.catalog(concept)
        let results = LexicalGrader.grade(Array(catalog.values), transcript: answer.text)
        let expected = Set(answer.yes), skipped = Set(answer.skip)
        for id in catalog.keys.sorted() where !skipped.contains(id) {
            lex.outcomes.append(CheckOutcome(answerId: answer.id, category: answer.category, checkId: id, expected: expected.contains(id), got: results[id]?.state ?? .uncertain))
        }
    }
    printReport(lex)
}
