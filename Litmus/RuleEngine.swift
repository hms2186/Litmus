//
//  RuleEngine.swift
//  Architecture v4.0, Phase 4 (fixed rules for the result) and Phase 5b (merging a follow-up).
//
//  Pure: no I/O, no async, no clock and no model. The graders produce checked results; this file
//  turns them into one EvaluationOutcome and a report, always the same way for the same input.
//  Tools/run_engine_tests.sh checks the invariants against every compiled concept.
//

import Foundation

// MARK: - Check results

nonisolated enum CheckState: String, Codable, Sendable {
    case yes, no, uncertain
}

nonisolated enum CheckSource: String, Codable, Sendable {
    /// Graded by the on-device model.
    case model
    /// Graded by the keyword fallback, which can only say yes or uncertain.
    case lexical
    /// Worked out in code (sentences, chapter terms).
    case code
    /// The model ran but left this ID out, even after the second try.
    case omitted
}

/// Pass 2, the quote check, for a decisive yes (architecture v4.0 change 1).
nonisolated enum QuoteCheck: String, Codable, Sendable {
    /// Not a decisive yes, or the quote check is switched off.
    case notRequired
    /// The model quoted the student's own words.
    case proven
    /// The time budget ran out before it was checked, so mastery is capped at Likely mastered.
    case timedOut
}

nonisolated enum MergeEventKind: String, Codable, Sendable {
    /// An uncertain check was resolved.
    case newEvidence
    /// A no became yes, or a stated misconception was explicitly corrected.
    case correction
    /// A follow-up contradicted an earlier yes. The yes is kept and a conflict is recorded.
    case contradiction
    /// A later answer settled a recorded conflict.
    case conflictResolved
    /// A misconception check that was no became yes in a follow-up.
    case misconceptionStated
    /// The only thing blocking mastery was a model "no", asked again alone in lenient wording; it became yes only
    /// after a genuine quote that, read with its neighbouring sentences, states the check.
    case recheck
}

nonisolated struct CheckHistoryEntry: Codable, Sendable, Equatable {
    let round: Int
    let state: CheckState
    let source: CheckSource
    let event: MergeEventKind
}

nonisolated struct CheckResult: Codable, Sendable, Equatable {
    var state: CheckState
    var source: CheckSource
    var quoteCheck: QuoteCheck = .notRequired
    var quote: String? = nil
    var round = 0
    /// Misconception checks only: the student explicitly corrected this idea in a follow-up.
    var corrected = false
    /// Every change after the first answer, with the event that allowed it.
    var history: [CheckHistoryEntry] = []
}

typealias ResultSet = [String: CheckResult]

nonisolated struct Conflict: Codable, Sendable, Equatable {
    let checkId: String
    let round: Int
}

nonisolated struct AttemptContext: Codable, Sendable, Equatable {
    var clarificationRoundsLeft: Int
    /// Lemmatised matches against the concept's evidence and the chapter vocabulary (Phase 2).
    var keywordOverlap: Int
    /// Set when the drift check fails after an OS update: the best outcome is Likely mastered.
    var provisionalOnly = false
    var conflicts: [Conflict] = []
    /// 0 for the first answer, then one more for each follow-up.
    var round = 0
}

// MARK: - Outcome

nonisolated enum ReportList: String, Codable, Sendable {
    case corrections, right, missing, vague, conflicts
}

nonisolated enum EvaluationOutcome: Equatable, Sendable {
    case notGradable
    case offTopic
    case needsCorrection
    case mastered
    case likelyMastered
    case needsClarification(targetCheckId: String)
    case partial(almostThere: Bool)
    case notYet

    /// Finished: neither a follow-up question nor a redirect.
    var isTerminal: Bool {
        switch self {
        case .needsClarification, .offTopic: false
        default: true
        }
    }

    var savesProgress: Bool { isTerminal && self != .notGradable }

    /// Saved as provisional and confirmed later by a background re-grade.
    var isProvisional: Bool { self == .likelyMastered }

    /// Unlocks the next concept. Partial does, with a review flag.
    var canAdvance: Bool {
        switch self {
        case .mastered, .likelyMastered, .partial: true
        default: false
        }
    }

    var requiresReview: Bool {
        switch self {
        case .needsCorrection, .partial, .notYet: true
        default: false
        }
    }

    /// The only lists the interface may show for this outcome.
    var visibleLists: [ReportList] {
        switch self {
        case .notGradable, .offTopic: []
        case .needsClarification: [.right]
        case .mastered, .likelyMastered: [.corrections, .right, .vague]
        case .needsCorrection: [.corrections, .right, .missing, .conflicts]
        case .partial, .notYet: [.corrections, .right, .missing, .vague, .conflicts]
        }
    }
}

nonisolated enum KeyPointOutcome: String, Codable, Sendable {
    case pass, fail, clarify
    /// A linked misconception was stated and not corrected. Counts as a failure.
    case misconception
}

nonisolated struct EvaluationReport: Equatable, Sendable {
    /// The fix for each misconception the student stated and did not correct.
    var corrections: [String] = []
    /// The fix for each misconception the student corrected in a follow-up ("You fixed this").
    var fixedByStudent: [String] = []
    /// Every check and cause link that came back yes, even inside a keyPoint that failed.
    var right: [String] = []
    var missing: [String] = []
    var vague: [String] = []
    /// Earlier points the follow-up contradicted.
    var conflicts: [String] = []
    /// The question to ask, for Needs clarification only.
    var followUp: String? = nil
}

nonisolated struct Decision: Equatable, Sendable {
    let outcome: EvaluationOutcome
    let report: EvaluationReport
    let keyPointOutcomes: [String: KeyPointOutcome]
    let passedWeight: Int
    let scoredWeight: Int
    /// Mastered after correcting a misconception: schedule a later revisit.
    let revisitLater: Bool
    /// Which rule fired and why, for debugging and test failures.
    let trace: [String]
}

// MARK: - Rules

nonisolated enum RuleEngine {

    /// Mastery bar: passed weight / scored weight >= 7/10, in whole numbers so there is no rounding.
    static let masteryNumerator = 7
    static let masteryDenominator = 10

    static func decide(
        _ concept: CompiledConcept,
        results: ResultSet,
        context: AttemptContext,
        articulationChecks: [CompiledArticulationCheck] = []
    ) -> Decision {
        var trace: [String] = []
        func state(_ id: String) -> CheckState { results[id]?.state ?? .uncertain }

        var outcomes: [String: KeyPointOutcome] = [:]
        for keyPoint in concept.keyPoints {
            outcomes[keyPoint.id] = keyPointOutcome(keyPoint, concept: concept, results: results)
        }

        let scored = concept.keyPoints.filter(\.scored)
        let core = concept.keyPoints.filter { $0.role == .core }
        let scoredWeight = scored.reduce(0) { $0 + $1.weight }
        let passedWeight = scored.filter { outcomes[$0.id] == .pass }.reduce(0) { $0 + $1.weight }
        let openWeight = scored.filter { outcomes[$0.id] == .clarify }.reduce(0) { $0 + $1.weight }
        let meetsBar = masteryDenominator * passedWeight >= masteryNumerator * scoredWeight
        let canReachBar = masteryDenominator * (passedWeight + openWeight) >= masteryNumerator * scoredWeight
        let coreAllPass = !core.isEmpty && core.allSatisfy { outcomes[$0.id] == .pass }
        let coreFailed = core.contains { outcomes[$0.id] == .fail || outcomes[$0.id] == .misconception }

        let keyPointCheckIds = concept.keyPoints.flatMap { $0.checks.map(\.id) }
        let anyKeyPointYes = keyPointCheckIds.contains { state($0) == .yes }
        let anyKeyPointUncertain = keyPointCheckIds.contains { state($0) == .uncertain }
        // Only the model can judge an answer irrelevant; anything else leaves relevance open.
        let relevanceNo = results[concept.relevanceCheck.id].map { $0.state == .no && $0.source == .model } ?? false
        let stated = statedMisconceptions(concept, results: results)
        let hasConflicts = !context.conflicts.isEmpty
        trace.append("score \(passedWeight)/\(scoredWeight), open \(openWeight), coreAllPass \(coreAllPass), coreFailed \(coreFailed)")

        let outcome: EvaluationOutcome
        if scoredWeight == 0 {
            trace.append("row 0: scored weight is 0")
            outcome = .notGradable
        } else if relevanceNo && context.keywordOverlap == 0 && !anyKeyPointYes && !anyKeyPointUncertain {
            trace.append("row 1: model says irrelevant, no keyword overlap, no keyPoint check yes or uncertain")
            outcome = .offTopic
        } else if !stated.isEmpty {
            trace.append("row 2: misconception stated: \(stated.map(\.id).joined(separator: ", "))")
            outcome = .needsCorrection
        } else if coreAllPass && meetsBar && !hasConflicts {
            let gaps = evidenceGaps(concept, results: results, context: context)
            if gaps.isEmpty {
                trace.append("row 3: all core pass, bar met, evidence complete")
                outcome = .mastered
            } else {
                trace.append("row 4: all core pass, bar met, but " + gaps.joined(separator: "; "))
                outcome = .likelyMastered
            }
        } else if context.clarificationRoundsLeft > 0 && !coreFailed,
                  let target = clarificationTarget(
                      concept, outcomes: outcomes, results: results, context: context,
                      coreAllPass: coreAllPass, meetsBar: meetsBar, canReachBar: canReachBar,
                      relevanceNo: relevanceNo, anyKeyPointUncertain: anyKeyPointUncertain) {
            trace.append("row 5: clarification about \(target)")
            outcome = .needsClarification(targetCheckId: target)
        } else if passedWeight > 0 {
            trace.append("row 6: partial")
            outcome = .partial(almostThere: coreAllPass)
        } else {
            trace.append("row 7: nothing scored passed")
            outcome = .notYet
        }

        let report = buildReport(concept, outcome: outcome, outcomes: outcomes, results: results,
                                 context: context, articulationChecks: articulationChecks)
        let corrected = concept.misconceptions.contains { results[$0.checkId]?.corrected == true }
        return Decision(outcome: outcome, report: report, keyPointOutcomes: outcomes,
                        passedWeight: passedWeight, scoredWeight: scoredWeight,
                        revisitLater: outcome == .mastered && corrected, trace: trace)
    }

    /// Phase 4a: one keyPoint, by its own passRule. A stated misconception overrides everything.
    static func keyPointOutcome(_ keyPoint: CompiledKeyPoint, concept: CompiledConcept, results: ResultSet) -> KeyPointOutcome {
        let misconceptionStated = concept.misconceptions.contains { misconception in
            misconception.keyPointIds.contains(keyPoint.id)
                && results[misconception.checkId]?.state == .yes
                && results[misconception.checkId]?.corrected != true
        }
        if misconceptionStated { return .misconception }
        let states = keyPoint.checks.map { results[$0.id]?.state ?? .uncertain }
        switch keyPoint.passRule {
        case .allRequired:
            let required = keyPoint.checks.filter(\.isRequired).map { results[$0.id]?.state ?? .uncertain }
            if required.contains(.no) { return .fail }
            return required.allSatisfy { $0 == .yes } ? .pass : .clarify
        case .anyOf:
            if states.contains(.yes) { return .pass }
            return states.allSatisfy { $0 == .no } ? .fail : .clarify
        case .minCount(let n):
            let yes = states.filter { $0 == .yes }.count
            let uncertain = states.filter { $0 == .uncertain }.count
            if yes >= n { return .pass }
            return yes + uncertain < n ? .fail : .clarify
        }
    }

    /// The yes results that made a passing keyPoint pass.
    static func decidingChecks(_ keyPoint: CompiledKeyPoint, results: ResultSet) -> [String] {
        switch keyPoint.passRule {
        case .allRequired:
            return keyPoint.checks.filter(\.isRequired).map(\.id)
        case .anyOf, .minCount:
            return keyPoint.checks.filter { results[$0.id]?.state == .yes }.map(\.id)
        }
    }

    static func statedMisconceptions(_ concept: CompiledConcept, results: ResultSet) -> [CompiledMisconception] {
        concept.misconceptions.filter { results[$0.checkId]?.state == .yes && results[$0.checkId]?.corrected != true }
    }

    /// Why Mastered cannot be confirmed yet (row 3 vs row 4). Empty means the evidence is complete.
    static func evidenceGaps(_ concept: CompiledConcept, results: ResultSet, context: AttemptContext) -> [String] {
        var gaps: [String] = []
        if context.provisionalOnly {
            gaps.append("provisional-only mode")
        }
        for keyPoint in concept.keyPoints where keyPoint.role == .core {
            for id in decidingChecks(keyPoint, results: results) {
                guard let result = results[id] else { continue }
                if result.source != .model && result.source != .code {
                    gaps.append("\(id) came from \(result.source.rawValue)")
                } else if result.quoteCheck == .timedOut {
                    gaps.append("\(id) quote not checked in time")
                }
            }
        }
        for misconception in concept.misconceptions where misconception.isRequired {
            let result = results[misconception.checkId]
            let ruledOut = result?.corrected == true || (result?.state == .no && result?.source == .model)
            if !ruledOut {
                gaps.append("\(misconception.checkId) not ruled out by the model")
            }
        }
        return gaps
    }

    /// Row 5: what to ask about, or nil when a question cannot lead anywhere. Order: a conflict, the
    /// heaviest uncertain core keyPoint, the heaviest uncertain scored keyPoint that could lift the
    /// score to the bar, then relevance when the model judged an answer with open checks irrelevant.
    static func clarificationTarget(
        _ concept: CompiledConcept,
        outcomes: [String: KeyPointOutcome],
        results: ResultSet,
        context: AttemptContext,
        coreAllPass: Bool,
        meetsBar: Bool,
        canReachBar: Bool,
        relevanceNo: Bool,
        anyKeyPointUncertain: Bool
    ) -> String? {
        func firstOpenCheck(_ keyPoint: CompiledKeyPoint) -> String? {
            let open = keyPoint.checks.filter { (results[$0.id]?.state ?? .uncertain) == .uncertain }
            return (open.first(where: \.isRequired) ?? open.first)?.id
        }
        func heaviestOpen(_ keyPoints: [CompiledKeyPoint]) -> String? {
            keyPoints.enumerated()
                .filter { outcomes[$0.element.id] == .clarify }
                .sorted { ($0.element.weight, -$0.offset) > ($1.element.weight, -$1.offset) }
                .lazy.compactMap { firstOpenCheck($0.element) }.first
        }
        if canReachBar, let conflict = context.conflicts.first {
            return conflict.checkId
        }
        if canReachBar, let target = heaviestOpen(concept.keyPoints.filter { $0.role == .core }) {
            return target
        }
        if coreAllPass && !meetsBar && canReachBar, let target = heaviestOpen(concept.keyPoints.filter(\.scored)) {
            return target
        }
        if relevanceNo && context.keywordOverlap == 0 && anyKeyPointUncertain {
            return concept.relevanceCheck.id
        }
        return nil
    }

    // MARK: Report

    static func buildReport(
        _ concept: CompiledConcept,
        outcome: EvaluationOutcome,
        outcomes: [String: KeyPointOutcome],
        results: ResultSet,
        context: AttemptContext,
        articulationChecks: [CompiledArticulationCheck]
    ) -> EvaluationReport {
        func state(_ id: String) -> CheckState { results[id]?.state ?? .uncertain }
        var report = EvaluationReport()
        let allChecks = concept.keyPoints.flatMap(\.checks)

        report.corrections = statedMisconceptions(concept, results: results).map(\.fix)
        report.fixedByStudent = concept.misconceptions.filter { results[$0.checkId]?.corrected == true }.map(\.fix)
        report.right = allChecks.filter { state($0.id) == .yes }.map(\.criterion)
            + concept.causeLinks.filter { state($0.id) == .yes }.map(\.criterion)

        if outcome.isTerminal {
            for keyPoint in concept.keyPoints {
                let missingState: CheckState
                switch outcomes[keyPoint.id] {
                case .fail, .misconception: missingState = .no
                case .clarify: missingState = .uncertain  // no round left to resolve it
                default: continue
                }
                let candidates = keyPoint.checks.filter { state($0.id) == missingState }
                if case .allRequired = keyPoint.passRule {
                    report.missing += candidates.filter(\.isRequired).map(\.criterion)
                } else {
                    report.missing += candidates.prefix(2).map(\.criterion)
                }
            }
        }

        report.vague = concept.causeLinks.filter { $0.isRequired && state($0.id) == .no }.map(\.criterion)
            + articulationChecks.filter { results[$0.id]?.state == .no }.map(\.criterion)
            + concept.keyPoints.filter { outcomes[$0.id] == .pass }
                .flatMap { $0.checks.filter { !$0.isRequired && state($0.id) == .no } }
                .map(\.criterion)

        report.conflicts = context.conflicts.compactMap { conflict in
            allChecks.first { $0.id == conflict.checkId }?.criterion
        }

        if case .needsClarification(let target) = outcome {
            report.followUp = target == concept.relevanceCheck.id
                ? concept.probe
                : allChecks.first { $0.id == target }?.followUp ?? concept.hint
        }
        return report
    }

    // MARK: - Follow-up merge (Phase 5b)

    /// The follow-up grading. Resolve checks are graded on Answer 2; fix and contradiction checks
    /// compare Answer 2 with Answer 1.
    nonisolated struct FollowUpGrading: Sendable {
        /// The targeted checks and every misconception check.
        var resolved: ResultSet = [:]
        /// mfix_<misconceptionId>: Answer 2 explicitly states the correct idea.
        var fixes: [String: CheckState] = [:]
        /// ctr_<checkId>: Answer 2 contradicts that earlier yes.
        var contradictions: [String: CheckState] = [:]
    }

    nonisolated struct MergeEvent: Equatable, Sendable {
        let kind: MergeEventKind
        let checkId: String
        let from: CheckState
        let to: CheckState
    }

    /// Merges a follow-up into the earlier results. A yes or no is never overwritten unless an event
    /// explains it: a no can become yes (correction), a stated misconception can be corrected, and a
    /// conflict can be resolved. A yes is never turned into no; a contradiction is recorded instead.
    static func merge(
        _ results: ResultSet,
        context: AttemptContext,
        followUp: FollowUpGrading,
        concept: CompiledConcept
    ) -> (results: ResultSet, context: AttemptContext, events: [MergeEvent]) {
        var merged = results
        var updated = context
        var events: [MergeEvent] = []
        let round = context.round + 1
        updated.round = round
        updated.clarificationRoundsLeft = max(0, context.clarificationRoundsLeft - 1)
        let misconceptionChecks = Set(concept.misconceptions.map(\.checkId))

        func record(_ id: String, _ new: CheckResult, _ kind: MergeEventKind) {
            let old = merged[id]
            var result = new
            result.round = round
            result.corrected = old?.corrected ?? false
            result.history = (old?.history ?? []) + [CheckHistoryEntry(round: round, state: new.state, source: new.source, event: kind)]
            merged[id] = result
            events.append(MergeEvent(kind: kind, checkId: id, from: old?.state ?? .uncertain, to: new.state))
        }

        for id in followUp.resolved.keys.sorted() {
            guard let new = followUp.resolved[id], new.state != .uncertain else { continue }
            let oldState = merged[id]?.state ?? .uncertain
            if let index = updated.conflicts.firstIndex(where: { $0.checkId == id }) {
                record(id, new, .conflictResolved)
                updated.conflicts.remove(at: index)
                continue
            }
            switch (oldState, new.state) {
            case (.uncertain, _):
                record(id, new, .newEvidence)
            case (.no, .yes):
                record(id, new, misconceptionChecks.contains(id) ? .misconceptionStated : .correction)
            default:
                // A yes or no stays. Not repeating a point, or not repeating a misconception, proves nothing.
                continue
            }
        }

        // Corrections and contradictions compare Answer 2 with Answer 1, so they apply only to results
        // that existed before this follow-up, never to something Answer 2 itself just established.
        for misconception in concept.misconceptions {
            guard results[misconception.checkId]?.state == .yes,
                  var result = merged[misconception.checkId], result.state == .yes, !result.corrected,
                  followUp.fixes[misconception.fixCheckId] == .yes else { continue }
            result.corrected = true
            result.history.append(CheckHistoryEntry(round: round, state: .yes, source: result.source, event: .correction))
            merged[misconception.checkId] = result
            events.append(MergeEvent(kind: .correction, checkId: misconception.checkId, from: .yes, to: .yes))
        }

        for key in followUp.contradictions.keys.sorted() where followUp.contradictions[key] == .yes && key.hasPrefix("ctr_") {
            let id = String(key.dropFirst(4))
            guard results[id]?.state == .yes, var result = merged[id], result.state == .yes,
                  !updated.conflicts.contains(where: { $0.checkId == id }) else { continue }
            updated.conflicts.append(Conflict(checkId: id, round: round))
            result.history.append(CheckHistoryEntry(round: round, state: .yes, source: result.source, event: .contradiction))
            merged[id] = result
            events.append(MergeEvent(kind: .contradiction, checkId: id, from: .yes, to: .yes))
        }
        return (merged, updated, events)
    }
}
