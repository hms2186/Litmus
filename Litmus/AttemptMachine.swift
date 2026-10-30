//
//  AttemptMachine.swift
//  Architecture v4.0, Phase 2 (sorting the answer) and change 6 (one attempt moves through fixed
//  states). Pure: the view model feeds events in and reads the state out, so every transition can be
//  tested without the model or the interface.
//

import Foundation

// MARK: - Phase 2: sorting the answer

/// Why an answer is not sent for grading.
nonisolated enum Reprompt: Equatable, Sendable {
    case empty
    case unintelligible
    case dontKnow
    case tooShort
}

nonisolated enum AnswerSorting: Equatable, Sendable {
    case gradable(keywordOverlap: Int)
    case notGradable(Reprompt)
}

nonisolated enum AnswerSorter {
    /// Mean speech confidence below this counts as unintelligible (final results only).
    static let confidenceFloor = 0.4
    static let shortAnswerWords = 5

    static let dontKnowPhrases = ["i don't know", "i dont know", "i do not know", "no idea", "not sure",
                                  "don't remember", "dont remember", "i forgot", "no clue"]

    /// Keyword overlap only tags an answer; it never rejects a full answer (v3.1). A short answer with
    /// no overlap is asked for more before any model time is spent.
    static func sort(_ text: String, confidence: Double?, concept: CompiledConcept, vocabulary: [String]) -> AnswerSorting {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        if trimmed.isEmpty { return .notGradable(.empty) }
        if let confidence, confidence < confidenceFloor { return .notGradable(.unintelligible) }
        let lowered = trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
        if words <= 8 && dontKnowPhrases.contains(where: lowered.contains) { return .notGradable(.dontKnow) }
        let overlap = CodeGrader.keywordOverlap(trimmed, concept: concept, vocabulary: vocabulary)
        if words < shortAnswerWords && overlap == 0 { return .notGradable(.tooShort) }
        return .gradable(keywordOverlap: overlap)
    }
}

// MARK: - The attempt

nonisolated enum AttemptState: Equatable, Sendable {
    /// Waiting for a first answer.
    case ready
    /// The answer was not sent for grading. `followUpPending` keeps a clarification or correction alive.
    case reprompt(Reprompt, followUpPending: Bool)
    case grading(followUp: Bool)
    /// Needs clarification: the next answer is graded as a follow-up.
    case awaitingFollowUp(targetCheckId: String)
    /// Needs correction: the next answer is a correction retry, graded as a follow-up.
    case correcting
    /// Redirected; the next answer starts a fresh attempt.
    case offTopic
    /// The guardrails refused the student's words: not graded, not stored. The next answer starts fresh.
    case blocked
    /// A final outcome. The next answer starts a fresh attempt.
    case finished(EvaluationOutcome)
}

nonisolated enum AttemptEvent: Equatable, Sendable {
    case submit(AnswerSorting)
    /// The grading result: an outcome, or nil when the guardrails refused the answer.
    case graded(EvaluationOutcome?)
    /// The student left the concept or started over: any work in flight is dropped.
    case reset
}

nonisolated struct AttemptMachine: Equatable, Sendable {
    private(set) var state: AttemptState = .ready
    /// Re-prompts in a row; after two the keyboard is offered.
    private(set) var consecutiveReprompts = 0

    static let repromptsBeforeKeyboard = 2

    var offerKeyboard: Bool { consecutiveReprompts >= Self.repromptsBeforeKeyboard }

    var isGrading: Bool {
        if case .grading = state { return true }
        return false
    }

    /// Whether a gradable answer submitted now continues the current attempt.
    var nextAnswerIsFollowUp: Bool {
        switch state {
        case .awaitingFollowUp, .correcting: true
        case .reprompt(_, let followUpPending): followUpPending
        default: false
        }
    }

    mutating func handle(_ event: AttemptEvent) {
        switch (state, event) {
        case (_, .reset):
            state = .ready
            consecutiveReprompts = 0
        case (.grading, .submit):
            break  // one grading at a time
        case (_, .submit(.notGradable(let reason))):
            state = .reprompt(reason, followUpPending: nextAnswerIsFollowUp)
            consecutiveReprompts += 1
        case (_, .submit(.gradable)):
            state = .grading(followUp: nextAnswerIsFollowUp)
            consecutiveReprompts = 0
        case (.grading, .graded(nil)):
            state = .blocked
        case (.grading, .graded(let outcome?)):
            switch outcome {
            case .needsClarification(let target): state = .awaitingFollowUp(targetCheckId: target)
            case .needsCorrection: state = .correcting
            case .offTopic: state = .offTopic
            default: state = .finished(outcome)
            }
        case (_, .graded):
            break  // a late result for an attempt that was reset is dropped
        }
    }
}
