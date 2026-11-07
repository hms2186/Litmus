//
//  FeedbackViewModel.swift
//  Feynman Tutor Engine - Layer 5 (Presentation)
//
//  Topics from compiled v4.1 chapters are graded by the architecture v4.0 engine: Phase 2 sorting,
//  the attempt state machine, GradingCoordinator, then SwiftData progress. Every other topic keeps
//  the legacy ConceptEvaluator path and its three feedback strings.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class FeedbackViewModel: ObservableObject {

    // MARK: Legacy path

    @Published private(set) var result: SemanticEvaluationResult?
    @Published private(set) var isEvaluating = false

    /// Bound by the legacy feedback rows; empty strings hide their row.
    var report: FeedbackReport {
        result?.feedback ?? FeedbackReport(missing: "", vague: "", right: "")
    }

    // MARK: Engine path

    /// True while the current topic is graded by the engine.
    @Published private(set) var engineTopicActive = false
    @Published private(set) var machine = AttemptMachine()
    @Published private(set) var decision: Decision?
    @Published private(set) var lastLog: GradingLog?
    /// A background re-grade found a problem with a saved answer for the current concept.
    @Published private(set) var reviewCard: ReviewCardInfo?
    /// A saved answer could not be re-graded: ask a quick live review question.
    @Published private(set) var revisitPending = false

    /// Set by the view, so finished attempts can be saved.
    var modelContext: ModelContext?
    let transport: any ModelTransport

    private var activeEntry: CompiledCurriculumStore.Entry?
    private var lastGrading: GradingOutcome?
    private var attemptId = UUID()
    private var evaluationTask: Task<Void, Never>?

    init(transport: (any ModelTransport)? = nil) {
        #if canImport(FoundationModels)
        self.transport = transport ?? FoundationModelsTransport()
        #else
        self.transport = transport ?? UnavailableTransport()
        #endif
    }

    func isEngineTopic(_ topic: NCERTTopic) -> Bool {
        CompiledCurriculumStore.shared.entry(forLabel: topic.title) != nil
    }

    /// Loads what the current concept needs before the student answers: a review card or revisit
    /// flag from earlier work, and the recogniser's vocabulary hints.
    func prepare(topic: NCERTTopic) {
        reviewCard = nil
        revisitPending = false
        guard let entry = CompiledCurriculumStore.shared.entry(forLabel: topic.title), let modelContext else { return }
        let conceptId = entry.concept.conceptId
        if let record = ProvisionalMaintenance.reviewCard(for: conceptId, in: modelContext) {
            reviewCard = ReviewCardInfo(conceptLabel: entry.concept.label, answeredOn: record.createdAt,
                                        transcripts: record.transcripts, notes: record.reviewNotes,
                                        outcome: record.regradeOutcome ?? "")
        }
        let progress = try? modelContext.fetch(FetchDescriptor<ConceptProgress>(predicate: #Predicate { $0.conceptId == conceptId })).first
        revisitPending = progress?.pendingRevisit == true
    }

    /// The review card has been read: its stored transcript is deleted.
    func dismissReviewCard(topic: NCERTTopic) {
        guard let entry = CompiledCurriculumStore.shared.entry(forLabel: topic.title), let modelContext,
              let record = ProvisionalMaintenance.reviewCard(for: entry.concept.conceptId, in: modelContext) else {
            reviewCard = nil
            return
        }
        ProvisionalMaintenance.dismissReviewCard(record, in: modelContext)
        reviewCard = nil
    }

    /// Chapter terms and the concept's evidence phrases, to prime speech recognition.
    func speechHints(for topic: NCERTTopic) -> [String] {
        guard let entry = CompiledCurriculumStore.shared.entry(forLabel: topic.title) else { return [] }
        var seen = Set<String>()
        return (entry.concept.keyPoints.flatMap(\.requiredEvidence) + entry.chapter.chapterVocabulary)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(100)
            .map { $0 }
    }

    /// `confidence`: mean speech confidence of the final results, nil for typed answers.
    func evaluate(_ text: String, topic: NCERTTopic, confidence: Double? = nil) {
        if let entry = CompiledCurriculumStore.shared.entry(forLabel: topic.title) {
            evaluateWithEngine(text, entry: entry, confidence: confidence)
            return
        }
        engineTopicActive = false
        evaluationTask?.cancel()
        result = nil
        isEvaluating = true
        evaluationTask = Task {
            let evaluation = await ConceptEvaluator.evaluate(text: text, topic: topic.title, topicObject: topic)
            guard !Task.isCancelled else { return }
            result = evaluation
            isEvaluating = false
        }
    }

    func reset() {
        evaluationTask?.cancel()
        evaluationTask = nil
        result = nil
        isEvaluating = false
        GradingActivity.isGrading = false
        machine.handle(.reset)
        decision = nil
        lastGrading = nil
        lastLog = nil
        activeEntry = nil
        engineTopicActive = false
    }

    private func evaluateWithEngine(_ text: String, entry: CompiledCurriculumStore.Entry, confidence: Double?) {
        if activeEntry?.concept.conceptId != entry.concept.conceptId {
            reset()
            activeEntry = entry
        }
        engineTopicActive = true
        let sorting = AnswerSorter.sort(text, confidence: confidence, concept: entry.concept, vocabulary: entry.chapter.chapterVocabulary)
        machine.handle(.submit(sorting))
        guard case .grading(let followUp) = machine.state else { return }

        let previous = followUp ? lastGrading : nil
        if previous == nil {
            attemptId = UUID()
            lastGrading = nil
        }
        decision = nil
        isEvaluating = true
        GradingActivity.isGrading = true
        // Until the drift check has passed on this OS build, the best outcome is Likely mastered.
        let coordinator = GradingCoordinator(transport: transport,
                                             settings: GradingSettings(provisionalOnly: DriftMonitor.shared.provisionalOnly()))
        evaluationTask = Task {
            let graded: GradingResult
            if let previous {
                graded = await coordinator.gradeFollowUp(answer: text, previous: previous, concept: entry.concept, chapter: entry.chapter)
            } else {
                graded = await coordinator.grade(answer: text, concept: entry.concept, chapter: entry.chapter)
            }
            guard !Task.isCancelled else { return }
            isEvaluating = false
            GradingActivity.isGrading = false
            switch graded {
            case .blocked:
                lastGrading = nil
                machine.handle(.graded(nil))
            case .graded(let outcome):
                lastGrading = outcome
                decision = outcome.decision
                lastLog = outcome.log
                machine.handle(.graded(outcome.decision.outcome))
                #if DEBUG
                print("🧪 [Engine] \(entry.concept.conceptId) round \(outcome.answers.count): \(outcome.decision.outcome) | model ready \(transport.isReady) | "
                      + "\(outcome.log.modelCalls) calls, \(String(format: "%.1f", outcome.log.seconds)) s, failed \(outcome.log.failedBatches) | "
                      + outcome.decision.trace.joined(separator: " | "))
                #endif
                if let modelContext {
                    ProgressRecorder.record(outcome, concept: entry.concept, schemaRevision: entry.chapter.schemaRevision,
                                            attemptId: attemptId, in: modelContext)
                }
            }
        }
    }

    /// The Radio Box line before the first answer when there is earlier work to revisit.
    func reviewPrompt(for topic: NCERTTopic) -> String? {
        guard let entry = CompiledCurriculumStore.shared.entry(forLabel: topic.title) else { return nil }
        if let reviewCard {
            return "Let's revisit \(reviewCard.conceptLabel). Here's what you said on \(reviewCard.answeredOn.formatted(date: .abbreviated, time: .omitted))."
        }
        if revisitPending {
            return "Let's quickly revisit \(entry.concept.label). \(entry.concept.probe)"
        }
        return nil
    }

    // MARK: What Aarushi says

    var isSuccess: Bool {
        if case .finished(let outcome) = machine.state {
            return outcome == .mastered || outcome == .likelyMastered
        }
        return false
    }

    /// The Radio Box line for the engine path.
    var radioPrompt: String {
        let concept = activeEntry?.concept
        switch machine.state {
        case .ready:
            if let reviewCard {
                return "Let's revisit \(reviewCard.conceptLabel). Here's what you said on \(reviewCard.answeredOn.formatted(date: .abbreviated, time: .omitted))."
            }
            if revisitPending {
                return "Let's quickly revisit \(concept?.label ?? "this concept"). \(concept?.probe ?? "")"
            }
            return concept?.probe ?? ""
        case .reprompt(let reason, _):
            let line: String
            switch reason {
            case .empty: line = "I didn't catch that. Please speak up."
            case .unintelligible: line = "Could you repeat that clearly?"
            case .dontKnow: line = "That's okay. Here's a hint: \(concept?.hint ?? "")"
            case .tooShort: line = "Can you say a bit more?"
            }
            return machine.offerKeyboard ? line + " You can also type your answer." : line
        case .grading:
            return "Checking your explanation…"
        case .awaitingFollowUp:
            return decision?.report.followUp ?? concept?.hint ?? ""
        case .correcting:
            return "Let's fix one idea. Try explaining it again."
        case .offTopic:
            return "That sounds like a different topic. \(concept?.probe ?? "")"
        case .blocked:
            return "Let's get back to \(concept?.label ?? "the topic"). \(concept?.probe ?? "")"
        case .finished(let outcome):
            switch outcome {
            case .mastered: return "Brilliant! You've got it."
            case .likelyMastered: return "That looks right. I'll double-check it when the AI tutor is ready."
            case .partial(let almostThere): return almostThere ? "Almost there!" : "Good start. Here's what's missing."
            case .notYet: return "Let's try that again."
            case .notGradable: return "I can't check this topic right now."
            default: return ""
            }
        }
    }
}

/// What a review card shows: the student's own earlier words beside what to fix.
struct ReviewCardInfo: Equatable {
    let conceptLabel: String
    let answeredOn: Date
    let transcripts: [String]
    let notes: [String]
    let outcome: String
}

#if !canImport(FoundationModels)
/// Platforms without FoundationModels: everything is graded by the keyword fallback.
nonisolated struct UnavailableTransport: ModelTransport {
    var isReady: Bool { false }
    func respond(instructions: String, prompt: String, maximumTokens: Int) async throws -> String {
        throw TransportError.unavailable
    }
}
#endif
