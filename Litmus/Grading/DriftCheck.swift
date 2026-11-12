//
//  DriftCheck.swift
//  Architecture v4.0 change 8: the on-device model changes with OS updates and nothing tells the app.
//  After the OS build changes, 30 labelled answers (drift_set.json) are graded again (pass 1 only) and
//  the agreement is compared with the baseline shipped in the same file. Until the check passes on
//  the current build, grading is provisional-only, so a silent model change can never award Mastered.
//

import Foundation

nonisolated struct DriftSet: Codable, Sendable {
    let version: Int
    let note: String?
    let baseline: DriftBaseline?
    let answers: [DriftAnswer]

    static var bundled: DriftSet? {
        guard let url = Bundle.main.url(forResource: "drift_set", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DriftSet.self, from: data)
    }
}

nonisolated struct DriftBaseline: Codable, Sendable, Equatable {
    let agreement: Double
    let checks: Int
    let measuredOn: String
    let osBuild: String
}

nonisolated struct DriftAnswer: Codable, Sendable {
    let id: String
    let conceptId: String
    let category: String
    let text: String
    let yes: [String]
    let skip: [String]
}

nonisolated enum DriftCheck {
    /// Pass when agreement is at least 95% of the baseline.
    static let tolerance = 0.95

    struct Measurement: Codable, Sendable, Equatable {
        let agreement: Double
        let checks: Int
        let answers: Int
        let failedBatches: Int
        var totalBatches = 0

        /// Too many model calls failed for the agreement to mean anything (for example the Simulator,
        /// where calls fail in the safety layer): record nothing and try again later.
        var isInconclusive: Bool { totalBatches > 0 && failedBatches * 2 > totalBatches }
    }

    /// Grades every answer with pass 1 (the compiled topic, A and B batches) and returns the share of
    /// labelled checks the model got right. An answer is started only when `isBusy` is false, so a
    /// student's own grading goes first. Nil when the model is not ready.
    static func measure(_ set: DriftSet, store: CompiledCurriculumStore, transport: any ModelTransport,
                        perBatchSeconds: Double = 8, isBusy: @escaping @Sendable () async -> Bool = { false }) async -> Measurement? {
        guard transport.isReady else { return nil }
        let grader = ModelGrader(transport: transport)
        var correct = 0
        var total = 0
        var answered = 0
        var failedBatches = 0
        var totalBatches = 0
        for answer in set.answers {
            while await isBusy() {
                try? await Task.sleep(for: .seconds(5))
            }
            if Task.isCancelled { return nil }
            guard let concept = store.entriesById[answer.conceptId]?.concept else { continue }
            let catalog = GradingCoordinator.catalog(concept)
            let batches = concept.batches.topic.map { ($0, BatchStyle.topic) }
                + (concept.batches.a + concept.batches.b).map { ($0, BatchStyle.screening) }
            var states: [String: CheckState] = [:]
            for (ids, style) in batches {
                let checks = ids.compactMap { catalog[$0] }
                guard !checks.isEmpty else { continue }
                totalBatches += 1
                do {
                    let results = try await GradingCoordinator.withTimeout(perBatchSeconds) {
                        try await grader.grade(checks, style: style, answers: [answer.text])
                    }
                    for (id, result) in results { states[id] = result.state }
                } catch {
                    failedBatches += 1
                }
            }
            let expected = Set(answer.yes)
            let skipped = Set(answer.skip)
            for id in catalog.keys where !skipped.contains(id) {
                total += 1
                let got = states[id] ?? .uncertain
                if got != .uncertain && (got == .yes) == expected.contains(id) { correct += 1 }
            }
            answered += 1
        }
        guard total > 0 else { return nil }
        return Measurement(agreement: Double(correct) / Double(total), checks: total, answers: answered,
                           failedBatches: failedBatches, totalBatches: totalBatches)
    }

    static func passes(_ measurement: Measurement, baseline: DriftBaseline?) -> Bool {
        guard let baseline else { return true }  // nothing shipped to compare with
        return measurement.agreement >= tolerance * baseline.agreement
    }
}

/// Remembers, per OS build, whether the drift check passed.
@MainActor
final class DriftMonitor {
    static let shared = DriftMonitor(defaults: .standard)

    private let defaults: UserDefaults
    private enum Key {
        static let checkedBuild = "drift.checkedBuild"
        static let passed = "drift.passed"
        static let agreement = "drift.agreement"
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    nonisolated static var currentBuild: String { ProcessInfo.processInfo.operatingSystemVersionString }

    func isChecked(build: String = DriftMonitor.currentBuild) -> Bool {
        defaults.string(forKey: Key.checkedBuild) == build
    }

    /// Provisional-only until the check has passed on this OS build.
    func provisionalOnly(build: String = DriftMonitor.currentBuild) -> Bool {
        !(isChecked(build: build) && defaults.bool(forKey: Key.passed))
    }

    var lastAgreement: Double? {
        defaults.object(forKey: Key.agreement) as? Double
    }

    func record(_ measurement: DriftCheck.Measurement, baseline: DriftBaseline?, build: String = DriftMonitor.currentBuild) {
        defaults.set(build, forKey: Key.checkedBuild)
        defaults.set(DriftCheck.passes(measurement, baseline: baseline), forKey: Key.passed)
        defaults.set(measurement.agreement, forKey: Key.agreement)
    }

    /// Runs the check if this build has not been checked. Returns true if a check ran.
    @discardableResult
    func runIfNeeded(set: DriftSet, store: CompiledCurriculumStore, transport: any ModelTransport,
                     build: String = DriftMonitor.currentBuild, isBusy: @escaping @Sendable () async -> Bool) async -> Bool {
        guard !isChecked(build: build),
              let measurement = await DriftCheck.measure(set, store: store, transport: transport, isBusy: isBusy) else { return false }
        guard !measurement.isInconclusive else {
            #if DEBUG
            print("🧪 [Drift] build \(build): inconclusive (\(measurement.failedBatches) of \(measurement.totalBatches) batches failed); still provisional-only")
            #endif
            return false
        }
        record(measurement, baseline: set.baseline, build: build)
        #if DEBUG
        print("🧪 [Drift] build \(build): agreement \(String(format: "%.3f", measurement.agreement)) over \(measurement.checks) checks, "
              + "baseline \(set.baseline.map { String(format: "%.3f", $0.agreement) } ?? "none"), passed \(!provisionalOnly(build: build))")
        #endif
        return true
    }
}
