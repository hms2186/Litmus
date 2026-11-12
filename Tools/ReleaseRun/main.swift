//
//  Release evaluation runner (Milestone 6). Grades every answer in a release set with the app's own
//  GradingCoordinator, once on the model path (the real on-device model) and once on the fallback
//  path (no model: keyword grading only), and writes one CSV row per answer and path.
//
//  Usage: release-run <repo root> <release_set.json> <results.csv> [--path model|fallback|both] [--limit N]
//  Re-running continues where it stopped: rows already in the CSV are skipped.
//

import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    print("usage: release-run <repo root> <release_set.json> <results.csv> [--path model|fallback|both] [--limit N]")
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1])
let setURL = URL(fileURLWithPath: arguments[2])
let resultsURL = URL(fileURLWithPath: arguments[3])
var pathChoice = "both"
var limit = Int.max
var index = 4
while index < arguments.count {
    switch arguments[index] {
    case "--path": pathChoice = arguments[index + 1]; index += 2
    case "--limit": limit = Int(arguments[index + 1]) ?? Int.max; index += 2
    default: index += 1
    }
}

struct ReleaseAnswer: Decodable {
    let id: String
    let conceptId: String
    let text: String
}
struct ReleaseSet: Decodable { let answers: [ReleaseAnswer] }

let releaseSet = try JSONDecoder().decode(ReleaseSet.self, from: Data(contentsOf: setURL))
let compiled = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Litmus/Compiled"), includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasSuffix(".compiled.json") }
let store = CompiledCurriculumStore(urls: compiled)

nonisolated struct NoModelTransport: ModelTransport {
    var isReady: Bool { false }
    func respond(instructions: String, prompt: String, maximumTokens: Int) async throws -> String { throw TransportError.unavailable }
}

func name(_ outcome: EvaluationOutcome) -> String {
    switch outcome {
    case .notGradable: "notGradable"
    case .offTopic: "offTopic"
    case .needsCorrection: "needsCorrection"
    case .mastered: "mastered"
    case .likelyMastered: "likelyMastered"
    case .needsClarification: "needsClarification"
    case .partial(let almostThere): almostThere ? "almostThere" : "partial"
    case .notYet: "notYet"
    }
}

func csvField(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "'") + "\"" }

var done = Set<String>()
if let existing = try? String(contentsOf: resultsURL, encoding: .utf8) {
    for line in existing.split(separator: "\n").dropFirst() {
        let parts = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count >= 2 { done.insert("\(parts[0]),\(parts[1])") }
    }
} else {
    try "id,path,outcome,seconds,modelCalls,failedBatches,trace\n".write(to: resultsURL, atomically: true, encoding: .utf8)
}
let handle = try FileHandle(forWritingTo: resultsURL)
handle.seekToEndOfFile()

let paths: [(String, any ModelTransport)] = {
    var list: [(String, any ModelTransport)] = []
    #if canImport(FoundationModels)
    if pathChoice != "fallback" { list.append(("model", FoundationModelsTransport())) }
    #endif
    if pathChoice != "model" { list.append(("fallback", NoModelTransport())) }
    return list
}()

for (pathName, transport) in paths {
    if pathName == "model" && !transport.isReady {
        print("The on-device model is not available on this Mac; the model path cannot run.")
        exit(1)
    }
    // Default settings: this is the release candidate. The drift check is about OS updates, not this run.
    let coordinator = GradingCoordinator(transport: transport, settings: GradingSettings())
    var graded = 0
    for answer in releaseSet.answers.prefix(limit) where !done.contains("\(answer.id),\(pathName)") {
        guard let entry = store.entriesById[answer.conceptId] else {
            print("concept \(answer.conceptId) is not in the compiled chapters"); exit(1)
        }
        let started = ContinuousClock.now
        let result = await coordinator.grade(answer: answer.text, concept: entry.concept, chapter: entry.chapter)
        let seconds = GradingCoordinator.seconds(since: started)
        let row: String
        switch result {
        case .blocked:
            row = "\(answer.id),\(pathName),blocked,\(String(format: "%.2f", seconds)),0,0,\"refused by guardrails\""
        case .graded(let outcome):
            row = "\(answer.id),\(pathName),\(name(outcome.decision.outcome)),\(String(format: "%.2f", seconds)),"
                + "\(outcome.log.modelCalls),\(outcome.log.failedBatches.count),\(csvField(outcome.decision.trace.last ?? ""))"
        }
        handle.write((row + "\n").data(using: .utf8)!)
        graded += 1
        if graded % 10 == 0 { print("\(pathName): \(graded) graded") }
    }
    print("\(pathName): done (\(graded) new rows)")
}
try handle.close()
