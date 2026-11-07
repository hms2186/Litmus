//
//  ProgressStore.swift
//  Architecture v4.0, change 9: progress is stored with SwiftData and written only from the
//  EvaluationOutcome's own properties, so the interface can never save a provisional result as
//  confirmed mastery. Transcripts are stored only in ProvisionalRecord, on this device.
//

import Foundation
import SwiftData

@Model
final class ConceptProgress {
    @Attribute(.unique) var conceptId: String
    /// The latest saved outcome (EvaluationOutcome.storageName).
    var status: String
    var isProvisional: Bool
    var needsReview: Bool
    /// Mastered after correcting a misconception: revisit later.
    var revisitLater: Bool
    /// Mastered (confirmed) at least once.
    var everMastered: Bool
    /// A saved provisional answer could not be re-graded (expired, or the concept changed): ask a
    /// quick live review question next time. Cleared by the next saved attempt.
    var pendingRevisit: Bool = false
    var attempts: Int
    var lastAttemptAt: Date

    init(conceptId: String, status: String, isProvisional: Bool, needsReview: Bool, revisitLater: Bool,
         everMastered: Bool, attempts: Int, lastAttemptAt: Date) {
        self.conceptId = conceptId
        self.status = status
        self.isProvisional = isProvisional
        self.needsReview = needsReview
        self.revisitLater = revisitLater
        self.everMastered = everMastered
        self.attempts = attempts
        self.lastAttemptAt = lastAttemptAt
    }
}

/// One finished attempt. No transcripts or quotes.
@Model
final class AttemptRecord {
    var attemptId: UUID
    var conceptId: String
    var conceptHash: String
    var outcome: String
    var passedWeight: Int
    var scoredWeight: Int
    var rounds: Int
    var createdAt: Date

    init(attemptId: UUID, conceptId: String, conceptHash: String, outcome: String, passedWeight: Int,
         scoredWeight: Int, rounds: Int, createdAt: Date) {
        self.attemptId = attemptId
        self.conceptId = conceptId
        self.conceptHash = conceptHash
        self.outcome = outcome
        self.passedWeight = passedWeight
        self.scoredWeight = scoredWeight
        self.rounds = rounds
        self.createdAt = createdAt
    }
}

/// A Likely mastered attempt, kept so it can be re-graded once the model can confirm it (M5).
/// Holds the student's words: deleted when the concept is confirmed or superseded, and after 30 days.
@Model
final class ProvisionalRecord {
    @Attribute(.unique) var attemptId: UUID
    var conceptId: String
    var conceptHash: String
    var schemaRevision: Int
    var evaluatorVersion: String
    var transcripts: [String]
    /// The ResultSet, JSON-encoded.
    var results: Data
    var createdAt: Date
    /// Set once a background re-grade found a problem (EvaluationOutcome.storageName): the record is
    /// then a review card, kept until it is shown or expires.
    var regradeOutcome: String? = nil
    /// What the review card shows after the student's own words: corrections, then what was missing.
    var reviewNotes: [String] = []
    var regradedAt: Date? = nil
    /// The OS build of the last re-grade that left the answer Likely mastered. The same model gives the
    /// same answer, so it is tried again only after the build changes.
    var lastTriedBuild: String? = nil

    init(attemptId: UUID, conceptId: String, conceptHash: String, schemaRevision: Int, evaluatorVersion: String,
         transcripts: [String], results: Data, createdAt: Date) {
        self.attemptId = attemptId
        self.conceptId = conceptId
        self.conceptHash = conceptHash
        self.schemaRevision = schemaRevision
        self.evaluatorVersion = evaluatorVersion
        self.transcripts = transcripts
        self.results = results
        self.createdAt = createdAt
    }
}

extension EvaluationOutcome {
    /// Stable name for storage.
    nonisolated var storageName: String {
        switch self {
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
}

enum ProgressRecorder {
    /// Stored with each provisional record; the background re-grade (M5) checks it.
    static let evaluatorVersion = "m4.1"

    static let schema: [any PersistentModel.Type] = [ConceptProgress.self, AttemptRecord.self, ProvisionalRecord.self]

    /// Saves a graded attempt. Does nothing unless the outcome says it saves progress.
    @discardableResult
    static func record(_ graded: GradingOutcome, concept: CompiledConcept, schemaRevision: Int, attemptId: UUID,
                       in context: ModelContext, now: Date = .now) -> Bool {
        let outcome = graded.decision.outcome
        guard outcome.savesProgress else { return false }

        context.insert(AttemptRecord(attemptId: attemptId, conceptId: concept.conceptId, conceptHash: concept.conceptHash,
                                     outcome: outcome.storageName, passedWeight: graded.decision.passedWeight,
                                     scoredWeight: graded.decision.scoredWeight, rounds: graded.answers.count, createdAt: now))

        let conceptId = concept.conceptId
        let existing = try? context.fetch(FetchDescriptor<ConceptProgress>(predicate: #Predicate { $0.conceptId == conceptId })).first
        let progress = existing ?? ConceptProgress(conceptId: conceptId, status: outcome.storageName, isProvisional: false,
                                                   needsReview: false, revisitLater: false, everMastered: false,
                                                   attempts: 0, lastAttemptAt: now)
        if existing == nil { context.insert(progress) }
        progress.status = outcome.storageName
        progress.isProvisional = outcome.isProvisional
        progress.needsReview = outcome.requiresReview || graded.decision.revisitLater
        progress.revisitLater = graded.decision.revisitLater
        progress.everMastered = progress.everMastered || outcome == .mastered
        progress.pendingRevisit = false
        progress.attempts += 1
        progress.lastAttemptAt = now

        // Any newer saved outcome supersedes an earlier provisional one, whose transcripts go with it.
        let older = (try? context.fetch(FetchDescriptor<ProvisionalRecord>(predicate: #Predicate { $0.conceptId == conceptId }))) ?? []
        older.forEach(context.delete)
        if outcome.isProvisional {
            let results = (try? JSONEncoder().encode(graded.results)) ?? Data()
            context.insert(ProvisionalRecord(attemptId: attemptId, conceptId: conceptId, conceptHash: concept.conceptHash,
                                             schemaRevision: schemaRevision, evaluatorVersion: evaluatorVersion,
                                             transcripts: graded.answers, results: results, createdAt: now))
        }
        try? context.save()
        return true
    }
}

// MARK: - Background re-grade and cleanup

nonisolated struct MaintenanceReport: Equatable, Sendable {
    var confirmed: [String] = []
    var reviewCards: [String] = []
    var stillProvisional: [String] = []
    var expired: [String] = []
    var conceptChanged: [String] = []
    var skippedModelNotReady = 0
}

enum ProvisionalMaintenance {
    static let retentionDays = 30
    /// Evaluator versions whose saved results the current grader can re-grade.
    static let compatibleEvaluatorVersions: Set<String> = ["m4.1"]

    /// Expires old records, then re-grades pending ones when the model can confirm them. Each record
    /// is acted on once: confirmed records are deleted, review cards are no longer pending, and a
    /// record that is still Likely mastered is not tried again until the OS build changes.
    @MainActor
    static func run(context: ModelContext, store: CompiledCurriculumStore, coordinator: GradingCoordinator,
                    osBuild: String, now: Date = .now) async -> MaintenanceReport {
        var report = MaintenanceReport()
        let records = (try? context.fetch(FetchDescriptor<ProvisionalRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)

        for record in records {
            let conceptId = record.conceptId
            if record.createdAt < cutoff {
                if record.regradeOutcome == nil { revisit(conceptId, in: context) }
                report.expired.append(conceptId)
                context.delete(record)
                continue
            }
            guard record.regradeOutcome == nil else { continue }  // a review card waiting to be shown
            guard let entry = store.entriesById[conceptId], entry.concept.conceptHash == record.conceptHash,
                  entry.chapter.schemaRevision == record.schemaRevision,
                  compatibleEvaluatorVersions.contains(record.evaluatorVersion),
                  let previous = try? JSONDecoder().decode(ResultSet.self, from: record.results) else {
                revisit(conceptId, in: context)
                report.conceptChanged.append(conceptId)
                context.delete(record)
                continue
            }
            guard coordinator.transport.isReady, !coordinator.settings.provisionalOnly else {
                report.skippedModelNotReady += 1
                continue
            }
            guard record.lastTriedBuild != osBuild else {
                report.stillProvisional.append(conceptId)
                continue
            }

            guard case .graded(let regraded) = await coordinator.regrade(transcripts: record.transcripts, previous: previous,
                                                                         concept: entry.concept, chapter: entry.chapter) else {
                record.lastTriedBuild = osBuild  // refused by the guardrails: leave it provisional
                report.stillProvisional.append(conceptId)
                continue
            }
            let outcome = regraded.decision.outcome
            let progress = try? context.fetch(FetchDescriptor<ConceptProgress>(predicate: #Predicate { $0.conceptId == conceptId })).first
            switch outcome {
            case .mastered:
                progress?.status = outcome.storageName
                progress?.isProvisional = false
                progress?.everMastered = true
                progress?.needsReview = progress?.revisitLater ?? false
                context.insert(AttemptRecord(attemptId: record.attemptId, conceptId: conceptId, conceptHash: record.conceptHash,
                                             outcome: outcome.storageName, passedWeight: regraded.decision.passedWeight,
                                             scoredWeight: regraded.decision.scoredWeight, rounds: record.transcripts.count, createdAt: now))
                context.delete(record)
                report.confirmed.append(conceptId)
            case .likelyMastered:
                record.lastTriedBuild = osBuild
                report.stillProvisional.append(conceptId)
            default:
                // Found a problem: a review card shows the student's own words beside what to fix.
                record.regradeOutcome = outcome.storageName
                record.reviewNotes = regraded.decision.report.corrections + regraded.decision.report.missing
                record.regradedAt = now
                progress?.status = outcome.storageName
                progress?.isProvisional = false
                progress?.needsReview = true
                report.reviewCards.append(conceptId)
            }
        }
        try? context.save()
        return report
    }

    /// The review card waiting for a concept, if any.
    @MainActor
    static func reviewCard(for conceptId: String, in context: ModelContext) -> ProvisionalRecord? {
        try? context.fetch(FetchDescriptor<ProvisionalRecord>(
            predicate: #Predicate { $0.conceptId == conceptId && $0.regradeOutcome != nil })).first
    }

    /// The review card has been shown: its transcript is no longer needed.
    @MainActor
    static func dismissReviewCard(_ record: ProvisionalRecord, in context: ModelContext) {
        context.delete(record)
        try? context.save()
    }

    @MainActor
    private static func revisit(_ conceptId: String, in context: ModelContext) {
        guard let progress = try? context.fetch(FetchDescriptor<ConceptProgress>(predicate: #Predicate { $0.conceptId == conceptId })).first else { return }
        progress.pendingRevisit = true
        progress.needsReview = true
    }
}
