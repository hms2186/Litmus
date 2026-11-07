//
//  M0Benchmark.swift
//  Milestone 0: measures how accurately and how quickly the on-device model grades checks,
//  against the labelled answers in m0_answers.json. DEBUG builds only.
//
//  The same code runs in the Mac harness and on the iPad (launch argument -M0Benchmark), so
//  accuracy and speed are measured the same way on both. Nothing here is used for grading.
//

#if DEBUG
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum M0Benchmark {

    // MARK: - Dataset

    struct Dataset: Codable {
        let version: Int
        let concepts: [DatasetConcept]
    }

    struct DatasetConcept: Codable {
        let conceptId: String
        let file: String
        let answers: [LabelledAnswer]
    }

    struct LabelledAnswer: Codable {
        let id: String
        let category: String
        let text: String
        let yes: [String]
        let skip: [String]?
    }

    static func loadCurricula(for dataset: Dataset, data: (String) -> Data?) throws -> [String: FeynmanCurriculum] {
        var curricula: [String: FeynmanCurriculum] = [:]
        for file in Set(dataset.concepts.map(\.file)) {
            guard let bytes = data(file) else {
                throw NSError(domain: "M0Benchmark", code: 404, userInfo: [NSLocalizedDescriptionKey: "\(file) not found"])
            }
            curricula[file] = try JSONDecoder().decode(FeynmanCurriculum.self, from: bytes)
        }
        return curricula
    }

    // MARK: - Checks

    enum Kind: String, CaseIterable {
        case relevance, keyPoint, misconception, causeLink
    }

    struct Check {
        let id: String
        let text: String
        let kind: Kind
    }

    enum State: String {
        case yes, no, uncertain
    }

    /// Outcome of the pass 2 quote check for one pass 1 `.yes`.
    enum Proof: String {
        case genuine    // the quote appears in the transcript
        case close      // not exact, but at least 80% of the quote's words are in the transcript
        case invented   // a quote was given but it is not in the transcript
        case copiedCriterion // the "quote" is the criterion text, not the student's words
        case none       // the model answered NONE
        case unparsed   // the ID was missing from the reply
        case failed     // the call threw
    }

    /// The checks version 4.0 grades with the model: relevance, keyPoint checks, one generated
    /// check per misconception, and the cause links. Articulation checks are code-graded in v4.0.
    static func checks(for concept: FeynmanConcept) -> [Check] {
        var list = [Check(
            id: "chk_relevance",
            text: "The answer attempts to explain \(concept.label), even if it uses everyday words instead of textbook terms.",
            kind: .relevance
        )]
        for keyPoint in concept.keyPoints {
            list += keyPoint.assessment.checks.map { Check(id: $0.id, text: $0.criterion, kind: .keyPoint) }
        }
        list += concept.misconceptions.map {
            Check(id: "mchk_" + $0.id, text: "The answer states or implies this wrong idea: \($0.wrong)", kind: .misconception)
        }
        list += concept.causeLinks.map { Check(id: $0.id, text: $0.criterion, kind: .causeLink) }
        return list
    }

    static func batches(_ checks: [Check], size: Int) -> [[Check]] {
        stride(from: 0, to: checks.count, by: size).map { Array(checks[$0..<min($0 + size, checks.count)]) }
    }

    // MARK: - Configurations

    struct Config {
        let name: String
        let batchSize: Int
        let parallel: Bool
        let proofPass: Bool
        /// Relevance and misconception checks go in their own batch with their own instructions,
        /// instead of sharing keyPoint batches (whose instructions say "false if stated wrongly").
        var topicBatch = false
        /// Answers taken from each concept; nil runs all of them.
        let answersPerConcept: Int?
    }

    /// Greedy sampling makes accuracy identical for parallel and sequential runs of the same
    /// batch size, so the sequential runs use a 20-answer subset and exist only for timing.
    static let defaultConfigs = [
        Config(name: "batch6-parallel+proof", batchSize: 6, parallel: true, proofPass: true, answersPerConcept: nil),
        Config(name: "batch3-parallel", batchSize: 3, parallel: true, proofPass: false, answersPerConcept: nil),
        Config(name: "batch6-sequential", batchSize: 6, parallel: false, proofPass: false, answersPerConcept: 2),
        Config(name: "batch3-sequential", batchSize: 3, parallel: false, proofPass: false, answersPerConcept: 2),
        Config(name: "batch6-topic+proof", batchSize: 6, parallel: true, proofPass: true, topicBatch: true, answersPerConcept: nil)
    ]

    /// The iPad run: the setup chosen from the Mac results on all answers, plus a sequential
    /// subset to show whether parallel calls help on the device.
    static let ipadConfigs = [
        Config(name: "batch6-topic+proof", batchSize: 6, parallel: true, proofPass: true, topicBatch: true, answersPerConcept: nil),
        Config(name: "batch6-topic-sequential", batchSize: 6, parallel: false, proofPass: false, topicBatch: true, answersPerConcept: 2)
    ]

    /// Errors thrown by model calls, by description, so failed calls can be diagnosed.
    private static var errorTally: [String: Int] = [:]

    // MARK: - Results

    struct Row {
        let config: String
        let answerId: String
        let conceptId: String
        let category: String
        let checkId: String
        let kind: Kind
        let expected: Bool
        let got: State
        let proof: Proof?
        let quote: String?
    }

    struct ConfigResult {
        let config: Config
        var rows: [Row] = []
        var callSeconds: [Double] = []
        var failedCalls = 0
        var answerSeconds: [Double] = []
        var proofCallSeconds: [Double] = []
        var proofAnswerSeconds: [Double] = []
    }

    struct Report {
        let markdown: String
        let csv: String
    }

    // MARK: - Run

    static func run(
        dataset: Dataset,
        curricula: [String: FeynmanCurriculum],
        configs: [Config],
        log: (String) -> Void
    ) async -> Report {
        var results: [ConfigResult] = []
        errorTally = [:]
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else {
            let reason = "\(SystemLanguageModel.default.availability)"
            log("Model unavailable: \(reason)")
            return Report(markdown: "# M0 benchmark\n\nModel unavailable: \(reason)\n", csv: "")
        }
        for config in configs {
            log("== \(config.name)")
            var result = ConfigResult(config: config)
            for datasetConcept in dataset.concepts {
                guard let concept = curricula[datasetConcept.file]?.topics
                    .flatMap(\.concepts).first(where: { $0.conceptId == datasetConcept.conceptId }) else {
                    log("Concept \(datasetConcept.conceptId) not found in \(datasetConcept.file)")
                    continue
                }
                let checkList = checks(for: concept)
                let answers = config.answersPerConcept.map { Array(datasetConcept.answers.prefix($0)) } ?? datasetConcept.answers
                for answer in answers {
                    let states = await screen(answer.text, checks: checkList, config: config, into: &result)
                    var proofs: [String: (proof: Proof, quote: String?)] = [:]
                    if config.proofPass {
                        let decisive = checkList.filter { (states[$0.id] == .yes) && ($0.kind == .keyPoint || $0.kind == .misconception) }
                        proofs = await prove(answer.text, checks: decisive, into: &result)
                    }
                    let skipped = Set(answer.skip ?? [])
                    let expectedYes = Set(answer.yes)
                    for check in checkList where !skipped.contains(check.id) {
                        result.rows.append(Row(
                            config: config.name, answerId: answer.id, conceptId: concept.conceptId,
                            category: answer.category, checkId: check.id, kind: check.kind,
                            expected: expectedYes.contains(check.id), got: states[check.id] ?? .uncertain,
                            proof: proofs[check.id]?.proof, quote: proofs[check.id]?.quote
                        ))
                    }
                    let wrong = checkList.filter { !skipped.contains($0.id) && (states[$0.id] == .yes) != expectedYes.contains($0.id) }
                    log("\(answer.id): \(String(format: "%.1f", result.answerSeconds.last ?? 0)) s, \(wrong.count) wrong\(wrong.isEmpty ? "" : " (" + wrong.map(\.id).joined(separator: ", ") + ")")")
                }
            }
            results.append(result)
        }
        #else
        log("FoundationModels is not available on this platform.")
        #endif
        return Report(markdown: markdown(results), csv: csv(results))
    }

    // MARK: - Model calls

    #if canImport(FoundationModels)
    private static let screeningInstructions = """
    You check a student's explanation against a fixed list of criteria from an NCERT chapter.
    For each criterion ID, answer true only if the transcript clearly states that idea, in the student's own words or with the same meaning.
    Answer false if the idea is missing, stated wrongly, or only named as a keyword without being explained.
    Judge only what the transcript says. Do not use outside knowledge to fill gaps.
    Do not score, grade, summarise or give feedback. Answer only true or false for every ID.
    """

    private static let topicInstructions = """
    You read a student's answer and report what the student says. You do not judge whether it is correct.
    For "chk_relevance", answer true if the student is trying to explain the named topic, even if the answer is short, incomplete or wrong.
    For each ID starting with "mchk_", answer true if the student says or clearly implies that idea, even though the idea is wrong. Answer false if the student does not say it or says the opposite.
    Judge only what the transcript says. Answer only true or false for every ID.
    """

    private static func topicPrompt(_ batch: [Check], transcript: String) -> String {
        """
        IDEAS TO LOOK FOR (ID: idea)
        \(batch.map { "\($0.id): \($0.text)" }.joined(separator: "\n"))

        STUDENT TRANSCRIPT
        \"\"\"
        \(transcript)
        \"\"\"

        Reply with only a JSON object that maps every ID above to true or false.
        """
    }

    private static let proofInstructions = """
    You copy evidence from a student's answer. Copy words exactly as they appear in the answer.
    Never add, change or reorder words, and never use words that are not in the answer.
    """

    /// Pass 1 for one answer: every batch, timed. IDs the model leaves out stay `.uncertain`.
    private static func screen(_ transcript: String, checks: [Check], config: Config, into result: inout ConfigResult) async -> [String: State] {
        let answerStart = ContinuousClock.now
        var states: [String: State] = [:]
        var outcomes: [(states: [String: State], seconds: Double, failed: Bool)] = []
        var batchList: [(checks: [Check], topic: Bool)]
        if config.topicBatch {
            let topic = checks.filter { $0.kind == .relevance || $0.kind == .misconception }
            let rest = checks.filter { $0.kind == .keyPoint || $0.kind == .causeLink }
            batchList = batches(topic, size: config.batchSize).map { ($0, true) } + batches(rest, size: config.batchSize).map { ($0, false) }
        } else {
            batchList = batches(checks, size: config.batchSize).map { ($0, false) }
        }
        if config.parallel {
            await withTaskGroup(of: (states: [String: State], seconds: Double, failed: Bool).self) { group in
                for batch in batchList {
                    group.addTask { await screenBatch(batch.checks, topic: batch.topic, transcript: transcript) }
                }
                for await outcome in group { outcomes.append(outcome) }
            }
        } else {
            for batch in batchList {
                outcomes.append(await screenBatch(batch.checks, topic: batch.topic, transcript: transcript))
            }
        }
        for outcome in outcomes {
            states.merge(outcome.states) { _, new in new }
            result.callSeconds.append(outcome.seconds)
            if outcome.failed { result.failedCalls += 1 }
        }
        result.answerSeconds.append(seconds(since: answerStart))
        return states
    }

    private static func screenBatch(_ batch: [Check], topic: Bool, transcript: String) async -> (states: [String: State], seconds: Double, failed: Bool) {
        let start = ContinuousClock.now
        let prompt = topic ? topicPrompt(batch, transcript: transcript) : """
        CRITERIA (ID: criterion)
        \(batch.map { "\($0.id): \($0.text)" }.joined(separator: "\n"))

        IDs starting with "lnk_" are true only if the student connects the two ideas as cause and effect, not if they only state both.
        IDs starting with "mchk_" are true only if the student states or clearly implies that wrong idea.
        "chk_relevance" is true if the student is trying to explain the named topic, even in everyday words.

        STUDENT TRANSCRIPT
        \"\"\"
        \(transcript)
        \"\"\"

        Reply with only a JSON object that maps every ID above to true or false.
        """
        do {
            let session = LanguageModelSession(model: .default, instructions: topic ? topicInstructions : screeningInstructions)
            let response = try await session.respond(
                to: Prompt(prompt),
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 20 + 16 * batch.count)
            )
            return (parseStates(response.content, ids: batch.map(\.id)), seconds(since: start), false)
        } catch {
            errorTally["pass 1: \(error)", default: 0] += 1
            return (Dictionary(uniqueKeysWithValues: batch.map { ($0.id, State.uncertain) }), seconds(since: start), true)
        }
    }

    /// Pass 2 for one answer: asks for the exact supporting words behind each decisive `.yes`.
    private static func prove(_ transcript: String, checks: [Check], into result: inout ConfigResult) async -> [String: (proof: Proof, quote: String?)] {
        guard !checks.isEmpty else { return [:] }
        let answerStart = ContinuousClock.now
        var proofs: [String: (proof: Proof, quote: String?)] = [:]
        await withTaskGroup(of: (proofs: [String: (proof: Proof, quote: String?)], seconds: Double).self) { group in
            for batch in batches(checks, size: 6) {
                group.addTask { await proveBatch(batch, transcript: transcript) }
            }
            for await outcome in group {
                proofs.merge(outcome.proofs) { _, new in new }
                result.proofCallSeconds.append(outcome.seconds)
            }
        }
        result.proofAnswerSeconds.append(seconds(since: answerStart))
        return proofs
    }

    private static func proveBatch(_ batch: [Check], transcript: String) async -> (proofs: [String: (proof: Proof, quote: String?)], seconds: Double) {
        let start = ContinuousClock.now
        let prompt = """
        STUDENT ANSWER
        \"\"\"
        \(transcript)
        \"\"\"

        CHECKS (never copy words from this list)
        \(batch.map { "\($0.id): \($0.text)" }.joined(separator: "\n"))

        For each check ID, copy the words from the STUDENT ANSWER above that show the check is met.
        Copy them exactly as the student wrote them, at most 30 words. Never copy words from the CHECKS list.
        If the student's words do not show it, write NONE.

        Reply with one line per ID, in the form ID: copied words
        """
        do {
            let session = LanguageModelSession(model: .default, instructions: proofInstructions)
            let response = try await session.respond(
                to: Prompt(prompt),
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 20 + 50 * batch.count)
            )
            let criteria = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0.text) })
            return (parseProofs(response.content, ids: batch.map(\.id), transcript: transcript, criteria: criteria), seconds(since: start))
        } catch {
            errorTally["pass 2: \(error)", default: 0] += 1
            return (Dictionary(uniqueKeysWithValues: batch.map { ($0.id, (Proof.failed, nil)) }), seconds(since: start))
        }
    }
    #endif

    // MARK: - Parsing

    static func parseStates(_ text: String, ids: [String]) -> [String: State] {
        var states: [String: State] = [:]
        for id in ids {
            let pattern = "\"\(NSRegularExpression.escapedPattern(for: id))\"\\s*:\\s*\"?(true|false)"
            if let value = firstCapture(pattern, in: text) {
                states[id] = value.lowercased() == "true" ? .yes : .no
            } else {
                states[id] = .uncertain
            }
        }
        return states
    }

    static func parseProofs(_ text: String, ids: [String], transcript: String, criteria: [String: String] = [:]) -> [String: (proof: Proof, quote: String?)] {
        var proofs: [String: (proof: Proof, quote: String?)] = [:]
        for id in ids {
            let pattern = "(?m)^[^A-Za-z0-9_\\n]*\(NSRegularExpression.escapedPattern(for: id))[^A-Za-z0-9_:\\n]*:\\s*(.+)$"
            guard let raw = firstCapture(pattern, in: text) else {
                proofs[id] = (.unparsed, nil)
                continue
            }
            let quote = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’`,"))
            if quote.uppercased().hasPrefix("NONE") {
                proofs[id] = (Proof.none, nil)
            } else if quoteIsGenuine(quote, in: transcript) {
                proofs[id] = (.genuine, quote)
            } else if let criterion = criteria[id], quoteIsClose(quote, in: criterion) {
                proofs[id] = (.copiedCriterion, quote)
            } else {
                proofs[id] = (quoteIsClose(quote, in: transcript) ? .close : .invented, quote)
            }
        }
        return proofs
    }

    /// Version 4.0 change 1: a quote counts only if, after normalising, it appears in the
    /// transcript and is at least four words long (or the whole answer, if that is shorter).
    static func quoteIsGenuine(_ quote: String, in transcript: String) -> Bool {
        let q = normalise(quote)
        let t = normalise(transcript)
        let minWords = min(4, t.split(separator: " ").count)
        return !q.isEmpty && q.split(separator: " ").count >= minWords && t.contains(q)
    }

    /// Looser variant measured in M0: at least four words, 80% of them found in the transcript.
    static func quoteIsClose(_ quote: String, in transcript: String) -> Bool {
        let words = normalise(quote).split(separator: " ")
        let transcriptWords = Set(normalise(transcript).split(separator: " "))
        guard words.count >= min(4, transcriptWords.count), !words.isEmpty else { return false }
        return Double(words.filter(transcriptWords.contains).count) / Double(words.count) >= 0.8
    }

    private static func normalise(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Report

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[max(0, Int((p * Double(sorted.count)).rounded(.up)) - 1)]
    }

    private static func pct(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "–" : String(format: "%.1f%%", 100 * Double(part) / Double(whole))
    }

    private static func secs(_ value: Double) -> String {
        String(format: "%.1f s", value)
    }

    static var deviceDescription: String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let machine = String(cString: model)
        #else
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #endif
        return "\(machine), \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    private static func markdown(_ results: [ConfigResult]) -> String {
        var md = "# M0 benchmark\n\n"
        md += "- Device: \(deviceDescription)\n"
        md += "- Run: \(Date().formatted(date: .abbreviated, time: .shortened))\n"
        md += "- Labels: written for M0 only; skipped labels are excluded.\n\n"
        md += "**False yes** = the model said yes when the label is no (as a share of all \"no\" labels). "
        md += "**False no** = the model said no when the label is yes. **Uncertain** = the model left the ID out.\n\n"

        for result in results {
            let rows = result.rows
            md += "## \(result.config.name)\n\n"
            md += "Answers: \(result.answerSeconds.count) · model calls: \(result.callSeconds.count) · failed calls: \(result.failedCalls)\n\n"

            md += "### Accuracy by check kind\n\n| Kind | Labels yes / no | Accuracy | False yes | False no | Uncertain |\n|---|---|---|---|---|---|\n"
            for kind in Kind.allCases + [nil] {
                let subset = kind.map { k in rows.filter { $0.kind == k } } ?? rows
                md += accuracyRow(kind?.rawValue ?? "**all**", subset)
            }

            md += "\n### Accuracy by answer category\n\n| Category | Labels yes / no | Accuracy | False yes | False no | Uncertain |\n|---|---|---|---|---|---|\n"
            for category in ["textbook", "paraphrase", "incomplete", "misconception", "offtopic"] {
                md += accuracyRow(category, rows.filter { $0.category == category })
            }

            md += "\n### Time\n\n| Measure | Typical (p50) | Slowest 5% (p95) | Max |\n|---|---|---|---|\n"
            md += "| One model call | \(secs(percentile(result.callSeconds, 0.5))) | \(secs(percentile(result.callSeconds, 0.95))) | \(secs(result.callSeconds.max() ?? 0)) |\n"
            md += "| Pass 1 per answer | \(secs(percentile(result.answerSeconds, 0.5))) | \(secs(percentile(result.answerSeconds, 0.95))) | \(secs(result.answerSeconds.max() ?? 0)) |\n"
            if result.config.proofPass {
                md += "| Pass 2 per answer | \(secs(percentile(result.proofAnswerSeconds, 0.5))) | \(secs(percentile(result.proofAnswerSeconds, 0.95))) | \(secs(result.proofAnswerSeconds.max() ?? 0)) |\n"
                md += proofSection(rows)
            }
            md += "\n"
        }
        if !errorTally.isEmpty {
            md += "## Model call errors\n\n"
            for (description, count) in errorTally.sorted(by: { $0.value > $1.value }) {
                md += "- \(count) × `\(description.prefix(200))`\n"
            }
        }
        return md
    }

    private static func accuracyRow(_ name: String, _ rows: [Row]) -> String {
        let positives = rows.filter(\.expected)
        let negatives = rows.filter { !$0.expected }
        let correct = rows.filter { ($0.got == .yes) == $0.expected && $0.got != .uncertain }.count
        let falseYes = negatives.filter { $0.got == .yes }.count
        let falseNo = positives.filter { $0.got == .no }.count
        let uncertain = rows.filter { $0.got == .uncertain }.count
        return "| \(name) | \(positives.count) / \(negatives.count) | \(pct(correct, rows.count)) | \(falseYes) (\(pct(falseYes, negatives.count))) | \(falseNo) (\(pct(falseNo, positives.count))) | \(uncertain) |\n"
    }

    /// Pass 2 trade-off: how many correct pass 1 yeses it wrongly removes, and how many false
    /// pass 1 yeses it catches.
    private static func proofSection(_ rows: [Row]) -> String {
        var md = "\n### Pass 2 (quote check) on pass 1 yeses\n\n"
        md += "| Kind | Correct yeses kept (exact) | Kept (80% words) | False yeses caught (exact) | Caught (80% words) |\n|---|---|---|---|---|\n"
        for kind in [Kind.keyPoint, .misconception] {
            let proven = rows.filter { $0.kind == kind && $0.proof != nil }
            let truePositives = proven.filter(\.expected)
            let falsePositives = proven.filter { !$0.expected }
            let kept = truePositives.filter { $0.proof == .genuine }.count
            let keptClose = truePositives.filter { $0.proof == .genuine || $0.proof == .close }.count
            let caught = falsePositives.filter { $0.proof != .genuine }.count
            let caughtClose = falsePositives.filter { $0.proof != .genuine && $0.proof != .close }.count
            md += "| \(kind.rawValue) | \(kept) of \(truePositives.count) (\(pct(kept, truePositives.count))) | \(keptClose) (\(pct(keptClose, truePositives.count))) | \(caught) of \(falsePositives.count) | \(caughtClose) of \(falsePositives.count) |\n"
        }
        let proven = rows.filter { $0.proof != nil }
        md += "\nWhy quotes were rejected: "
        md += [Proof.close, .invented, .copiedCriterion, .none, .unparsed, .failed].map { kind in
            "\(kind.rawValue) \(proven.filter { $0.proof == kind }.count)"
        }.joined(separator: " · ")
        let paraphrase = proven.filter { $0.category == "paraphrase" && $0.expected }
        md += "\n\nCorrect paraphrase yeses kept: \(paraphrase.filter { $0.proof == .genuine }.count) of \(paraphrase.count)\n"
        return md
    }

    private static func csv(_ results: [ConfigResult]) -> String {
        var lines = ["config,answer,concept,category,check,kind,expected,got,proof,quote"]
        for row in results.flatMap(\.rows) {
            lines.append([row.config, row.answerId, row.conceptId, row.category, row.checkId, row.kind.rawValue,
                          row.expected ? "yes" : "no", row.got.rawValue, row.proof?.rawValue ?? "",
                          "\"" + (row.quote ?? "").replacingOccurrences(of: "\"", with: "'") + "\""].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
#endif
