//
//  GradingCoordinator.swift
//  Architecture v4.0, Phase 3 orchestration: turns one answer (or one follow-up) into a Decision.
//
//  Order: code checks -> topic batch + group A (parallel) -> group B -> second try for omitted IDs
//  -> keyword-stuffing guard -> pass 2 quote check -> RuleEngine. A batch that throws, times out or
//  returns nothing usable is graded by the keyword fallback instead. Every model call is bounded by
//  the per-batch limit and by the total budget for the answer.
//

import Foundation
import os

nonisolated struct GradingSettings: Sendable, Equatable {
    var perBatchSeconds = 8.0
    var totalSeconds = 15.0
    /// Pass 2 on the deciding checks of a would-be Mastered answer (M0 decision D5). Misconception
    /// yeses are always checked (D4).
    var quoteCheckMastery = true
    /// M0 decision D6: re-measure on the iPad set.
    var minimumQuoteWords = 4
    /// Sentences before and after a mastery quote that are read with it when confirming it. Misconception
    /// quotes are always read on their own.
    var confirmContextSentences = 1
    /// Ask a blocking model "no" again, alone and in lenient wording, when that is all that stands between the
    /// answer and mastery (Milestone 6). The flipped yes must still survive a genuine quote and its confirmation.
    var recheckNoResults = true
    static let maxRechecks = 3
    var clarificationRounds = 1
    /// Set when the drift check fails after an OS update: the best outcome is Likely mastered.
    var provisionalOnly = false
}

nonisolated struct GradingLog: Sendable, Equatable {
    var modelCalls = 0
    /// "a[0]: timeout", "topic[0]: guardrail", "b[1]: skipped, time budget spent"
    var failedBatches: [String] = []
    /// Checks graded by the keyword fallback.
    var fallbackChecks: [String] = []
    var retried: [String] = []
    var stillOmitted: [String] = []
    var proofRequested: [String] = []
    /// "chk_x: invented"
    var proofRejected: [String] = []
    /// The quote check could not run for these (time budget spent, a guardrail refusal or an error).
    var proofNotChecked: [String] = []
    /// Misconceptions whose quote was genuine but, read on its own, did not state the wrong idea.
    var misconceptionNotConfirmed: [String] = []
    /// Mastery checks whose quote was genuine but, read on its own, did not state the check (found by the
    /// Milestone 6 dry run: a real sentence about per capita income was accepted as proof of a World Bank check).
    var quoteNotConfirmed: [String] = []
    /// Blocking model "no" results asked again, and the ones that became yes after surviving the quote checks.
    var rechecked: [String] = []
    var recheckFlipped: [String] = []
    /// Flagged misconceptions ruled out because the student's own words explicitly reject or correct them.
    var misconceptionRuledOut: [String] = []
    var keywordStuffing = false
    var seconds = 0.0
}

nonisolated struct GradingOutcome: Sendable {
    /// Answer 1, then one entry per follow-up.
    let answers: [String]
    let results: ResultSet
    let context: AttemptContext
    let decision: Decision
    let events: [RuleEngine.MergeEvent]
    let log: GradingLog
}

nonisolated enum GradingResult: Sendable {
    case graded(GradingOutcome)
    /// The guardrails refused the student's words: not graded and not stored (v4.0 change 9).
    case blocked
}

nonisolated struct GradingCoordinator: Sendable {
    let transport: any ModelTransport
    var settings: GradingSettings

    private static let signposter = OSSignposter(subsystem: "Litmus", category: "Grading")

    init(transport: any ModelTransport, settings: GradingSettings = GradingSettings()) {
        self.transport = transport
        self.settings = settings
    }

    // MARK: - First answer

    func grade(answer: String, concept: CompiledConcept, chapter: CompiledChapter) async -> GradingResult {
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .seconds(settings.totalSeconds))
        let catalog = Self.catalog(concept)
        var log = GradingLog()
        var results = CodeGrader.articulation(chapter.articulationChecks, transcript: answer, vocabulary: chapter.chapterVocabulary)
        let overlap = CodeGrader.keywordOverlap(answer, concept: concept, vocabulary: chapter.chapterVocabulary)

        let groupA = jobs(concept.batches.topic, style: .topic, label: "topic", catalog: catalog)
            + jobs(concept.batches.a, style: .screening, label: "a", catalog: catalog)
        let groupB = jobs(concept.batches.b, style: .screening, label: "b", catalog: catalog)

        if transport.isReady {
            let interval = Self.signposter.beginInterval("pass1")
            let first = await run(groupA, answers: [answer], deadline: deadline)
            let second = await run(groupB, answers: [answer], deadline: deadline)
            Self.signposter.endInterval("pass1", interval)
            let attempted = first.attempted + second.attempted
            if attempted > 0 && first.guardrails + second.guardrails == attempted {
                return .blocked
            }
            for batch in [first, second] { absorb(batch, into: &results, log: &log) }
            await secondTry(&results, catalog: catalog, answers: [answer], deadline: deadline, log: &log)
        } else {
            let all = (groupA + groupB).flatMap(\.checks)
            results.merge(LexicalGrader.grade(all, transcript: answer)) { _, new in new }
            log.fallbackChecks += all.map(\.id)
            log.failedBatches.append("all: model unavailable")
        }

        guardAgainstKeywordStuffing(&results, concept: concept, transcript: answer, log: &log)
        let context = AttemptContext(clarificationRoundsLeft: settings.clarificationRounds, keywordOverlap: overlap,
                                     provisionalOnly: settings.provisionalOnly)
        await recheckBlockingNos(&results, concept: concept, chapter: chapter, catalog: catalog, context: context,
                                 transcript: answer, deadline: deadline, log: &log)
        await proveDecisiveYeses(&results, concept: concept, chapter: chapter, catalog: catalog, context: context,
                                 transcript: answer, deadline: deadline, log: &log)

        let decision = RuleEngine.decide(concept, results: results, context: context, articulationChecks: chapter.articulationChecks)
        log.seconds = Self.seconds(since: start)
        return .graded(GradingOutcome(answers: [answer], results: results, context: context, decision: decision, events: [], log: log))
    }

    // MARK: - Follow-up

    /// Grades the answer to a clarification question, or a retry after Needs correction, and merges it
    /// into the earlier results. Resolve checks are graded on Answer 2 alone; corrections and
    /// contradictions compare the answers. A retry after Needs correction aims at the keyPoints linked
    /// to the stated misconceptions and does not use up a clarification round.
    func gradeFollowUp(answer: String, previous: GradingOutcome, concept: CompiledConcept, chapter: CompiledChapter) async -> GradingResult {
        let target: String
        var startingContext = previous.context
        switch previous.decision.outcome {
        case .needsClarification(let targetCheckId):
            target = targetCheckId
        case .needsCorrection:
            target = ""
            startingContext.clarificationRoundsLeft += 1  // merge takes one off; a correction retry is not a clarification
        default:
            return .graded(previous)
        }
        let correctingKeyPoints = Set(RuleEngine.statedMisconceptions(concept, results: previous.results).flatMap(\.keyPointIds))
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .seconds(settings.totalSeconds))
        let catalog = Self.catalog(concept)
        let answers = previous.answers + [answer]
        let combined = answers.joined(separator: "\n")
        let prior = previous.results
        var log = GradingLog()

        let targeted = target == concept.relevanceCheck.id
            ? concept.keyPoints
            : concept.keyPoints.filter { keyPoint in
                keyPoint.checks.contains { $0.id == target } || correctingKeyPoints.contains(keyPoint.id)
                    || previous.decision.keyPointOutcomes[keyPoint.id] == .clarify
            }
        let targetedChecks = targeted.flatMap(\.checks)
        let targetedIds = Set(targetedChecks.map(\.id))
        let isOpen: (String) -> Bool = { prior[$0]?.state != .yes }

        var resolveIds = targetedChecks.map(\.id).filter(isOpen)
        resolveIds += concept.causeLinks.filter { isOpen($0.id) && !targetedIds.isDisjoint(with: $0.linksChecks) }.map(\.id)
        resolveIds += concept.misconceptions.map(\.checkId)
        if target == concept.relevanceCheck.id { resolveIds.append(concept.relevanceCheck.id) }
        let resolveChecks = resolveIds.compactMap { catalog[$0] }
        let topicStyle = resolveChecks.filter { $0.kind == .relevance || $0.kind == .misconception }
        let screeningStyle = resolveChecks.filter { $0.kind == .keyPoint || $0.kind == .causeLink }

        var comparisonChecks = concept.misconceptions
            .filter { prior[$0.checkId]?.state == .yes && prior[$0.checkId]?.corrected != true }
            .map { GradableCheck(id: $0.fixCheckId, criterion: $0.fixCheckCriterion, kind: .misconceptionFix, lexical: .never, evidence: []) }
        comparisonChecks += targetedChecks.filter { prior[$0.id]?.state == .yes }.map {
            GradableCheck(id: "ctr_" + $0.id, criterion: "Answer 2 contradicts this earlier point: \($0.criterion)",
                          kind: .contradiction, lexical: .never, evidence: [])
        }

        var resolved: ResultSet = [:]
        var fixes: [String: CheckState] = [:]
        var contradictions: [String: CheckState] = [:]
        if transport.isReady {
            let resolveJobs = chunked(topicStyle, style: .topic, label: "topic") + chunked(screeningStyle, style: .screening, label: "resolve")
            let resolveRun = await run(resolveJobs, answers: [answer], deadline: deadline)
            let compareRun = await run(chunked(comparisonChecks, style: .comparison, label: "compare"), answers: answers,
                                       deadline: deadline, fallback: false)
            let attempted = resolveRun.attempted + compareRun.attempted
            if attempted > 0 && resolveRun.guardrails + compareRun.guardrails == attempted {
                return .blocked
            }
            absorb(resolveRun, into: &resolved, log: &log)
            await secondTry(&resolved, catalog: catalog, answers: [answer], deadline: deadline, log: &log)
            log.modelCalls += compareRun.calls
            log.failedBatches += compareRun.failures
            for (id, result) in compareRun.results where result.source == .model {
                if id.hasPrefix("ctr_") { contradictions[id] = result.state } else { fixes[id] = result.state }
            }
        } else {
            resolved = LexicalGrader.grade(resolveChecks, transcript: answer)
            log.fallbackChecks += resolveChecks.map(\.id)
            log.failedBatches.append("all: model unavailable")
        }

        let grading = RuleEngine.FollowUpGrading(resolved: resolved, fixes: fixes, contradictions: contradictions)
        var (results, context, events) = RuleEngine.merge(prior, context: startingContext, followUp: grading, concept: concept)
        results.merge(CodeGrader.articulation(chapter.articulationChecks, transcript: combined, vocabulary: chapter.chapterVocabulary)) { _, new in new }
        context.keywordOverlap = max(context.keywordOverlap, CodeGrader.keywordOverlap(combined, concept: concept, vocabulary: chapter.chapterVocabulary))
        guardAgainstKeywordStuffing(&results, concept: concept, transcript: answer, log: &log)
        await recheckBlockingNos(&results, concept: concept, chapter: chapter, catalog: catalog, context: context,
                                 transcript: combined, deadline: deadline, log: &log)
        await proveDecisiveYeses(&results, concept: concept, chapter: chapter, catalog: catalog, context: context,
                                 transcript: combined, deadline: deadline, log: &log)

        let decision = RuleEngine.decide(concept, results: results, context: context, articulationChecks: chapter.articulationChecks)
        log.seconds = Self.seconds(since: start)
        return .graded(GradingOutcome(answers: answers, results: results, context: context, decision: decision,
                                      events: previous.events + events, log: log))
    }

    // MARK: - Background re-grade (provisional records)

    /// Re-grades a saved Likely mastered attempt once the model can confirm it (v3.2). Only checks that
    /// are uncertain or came from the keyword fallback go back to the model, on all the saved answers
    /// together; a check the model already graded keeps its result. A model result replaces a keyword
    /// result, because the fallback only ever stood in for the model. If the model fails, the earlier
    /// result stays. No clarification is asked: the student is not there.
    func regrade(transcripts: [String], previous: ResultSet, concept: CompiledConcept, chapter: CompiledChapter) async -> GradingResult {
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .seconds(settings.totalSeconds))
        let catalog = Self.catalog(concept)
        let combined = transcripts.joined(separator: "\n")
        var log = GradingLog()
        var results = previous

        let open = catalog.keys.sorted().compactMap { id -> GradableCheck? in
            guard let check = catalog[id] else { return nil }
            let result = previous[id]
            return result == nil || result?.source == .lexical || result?.source == .omitted || result?.state == .uncertain ? check : nil
        }
        if transport.isReady && !open.isEmpty {
            let jobs = chunked(open.filter { $0.kind == .relevance || $0.kind == .misconception }, style: .topic, label: "regrade-topic")
                + chunked(open.filter { $0.kind == .keyPoint || $0.kind == .causeLink }, style: .screening, label: "regrade")
            let regraded = await run(jobs, answers: [combined], deadline: deadline, fallback: false)
            if regraded.attempted > 0 && regraded.guardrails == regraded.attempted {
                return .blocked
            }
            log.modelCalls += regraded.calls
            log.failedBatches += regraded.failures
            for (id, result) in regraded.results where result.source == .model {
                var updated = result
                updated.round = previous[id]?.round ?? 0
                updated.history = (previous[id]?.history ?? []) + [CheckHistoryEntry(round: updated.round, state: result.state,
                                                                                     source: result.source, event: .newEvidence)]
                results[id] = updated
            }
            for (id, result) in regraded.results where result.source == .omitted && previous[id]?.source == .lexical {
                results[id] = result  // the model now ran but left it out: the second try below asks again
            }
            await secondTry(&results, catalog: catalog, answers: [combined], deadline: deadline, log: &log)
        }

        results.merge(CodeGrader.articulation(chapter.articulationChecks, transcript: combined, vocabulary: chapter.chapterVocabulary)) { _, new in new }
        guardAgainstKeywordStuffing(&results, concept: concept, transcript: combined, log: &log)
        let context = AttemptContext(clarificationRoundsLeft: 0,
                                     keywordOverlap: CodeGrader.keywordOverlap(combined, concept: concept, vocabulary: chapter.chapterVocabulary),
                                     provisionalOnly: settings.provisionalOnly)
        await recheckBlockingNos(&results, concept: concept, chapter: chapter, catalog: catalog, context: context,
                                 transcript: combined, deadline: deadline, log: &log)
        await proveDecisiveYeses(&results, concept: concept, chapter: chapter, catalog: catalog, context: context,
                                 transcript: combined, deadline: deadline, log: &log)
        let decision = RuleEngine.decide(concept, results: results, context: context, articulationChecks: chapter.articulationChecks)
        log.seconds = Self.seconds(since: start)
        return .graded(GradingOutcome(answers: transcripts, results: results, context: context, decision: decision, events: [], log: log))
    }

    // MARK: - Batches

    private struct Job: Sendable {
        let label: String
        let checks: [GradableCheck]
        let style: BatchStyle
        var strictFormat = false
    }

    private struct BatchRun: Sendable {
        var results: ResultSet = [:]
        var calls = 0
        var attempted = 0
        var guardrails = 0
        var failures: [String] = []
        var fallbackChecks: [String] = []
    }

    private func jobs(_ batches: [[String]], style: BatchStyle, label: String, catalog: [String: GradableCheck]) -> [Job] {
        batches.enumerated().map { index, ids in
            Job(label: "\(label)[\(index)]", checks: ids.compactMap { catalog[$0] }, style: style)
        }.filter { !$0.checks.isEmpty }
    }

    private func chunked(_ checks: [GradableCheck], style: BatchStyle, label: String, strictFormat: Bool = false) -> [Job] {
        stride(from: 0, to: checks.count, by: 6).enumerated().map { index, offset in
            Job(label: "\(label)[\(index)]", checks: Array(checks[offset..<min(offset + 6, checks.count)]), style: style,
                strictFormat: strictFormat)
        }
    }

    /// Runs batches in parallel. A batch that fails, times out or is skipped because the budget is
    /// spent is graded by the keyword fallback (when `fallback`), on the newest answer.
    private func run(_ jobs: [Job], answers: [String], deadline: ContinuousClock.Instant, fallback: Bool = true) async -> BatchRun {
        var batchRun = BatchRun()
        let grader = ModelGrader(transport: transport)
        let perBatch = settings.perBatchSeconds
        await withTaskGroup(of: (Job, Result<ResultSet, TransportError>?, Int).self) { group in
            for job in jobs {
                group.addTask {
                    let remaining = Self.seconds(until: deadline)
                    guard remaining > 0 else { return (job, nil, 0) }
                    do {
                        let results = try await Self.withTimeout(min(perBatch, remaining)) {
                            try await grader.grade(job.checks, style: job.style, answers: answers, strictFormat: job.strictFormat)
                        }
                        return (job, .success(results), 0)
                    } catch {
                        let failure = error as? TransportError ?? .other(String(describing: error))
                        // A refusal or an unusable reply often depends on the combination of checks in the batch
                        // (a refusal on one worded check, a reply in the wrong shape): try each check on its own
                        // before giving up on the batch.
                        if job.checks.count > 1, failure == .guardrail || failure == .unusableReply {
                            let singles = await Self.gradeSingly(job, answers: answers, grader: grader, deadline: deadline, perBatch: perBatch)
                            if !singles.results.isEmpty { return (job, .success(singles.results), singles.calls) }
                        }
                        return (job, .failure(failure), 0)
                    }
                }
            }
            for await (job, outcome, extraCalls) in group {
                batchRun.calls += extraCalls
                switch outcome {
                case .success(let results)?:
                    batchRun.attempted += 1
                    batchRun.calls += 1
                    batchRun.results.merge(results) { _, new in new }
                    if extraCalls > 0 { batchRun.failures.append("\(job.label): graded check by check after a failed batch") }
                    let missing = job.checks.filter { results[$0.id] == nil }
                    if fallback, !missing.isEmpty {
                        batchRun.results.merge(LexicalGrader.grade(missing, transcript: answers.last ?? "")) { _, new in new }
                        batchRun.fallbackChecks += missing.map(\.id)
                    }
                    continue
                case .failure(let error)?:
                    batchRun.attempted += 1
                    batchRun.calls += 1
                    if error == .guardrail { batchRun.guardrails += 1 }
                    batchRun.failures.append("\(job.label): \(error)")
                case nil:
                    batchRun.failures.append("\(job.label): skipped, time budget spent")
                }
                if fallback {
                    batchRun.results.merge(LexicalGrader.grade(job.checks, transcript: answers.last ?? "")) { _, new in new }
                    batchRun.fallbackChecks += job.checks.map(\.id)
                }
            }
        }
        return batchRun
    }

    /// Each check of a failed batch on its own, in parallel. Checks whose call fails again are left out.
    private static func gradeSingly(_ job: Job, answers: [String], grader: ModelGrader, deadline: ContinuousClock.Instant,
                                    perBatch: Double) async -> (results: ResultSet, calls: Int) {
        var results: ResultSet = [:]
        await withTaskGroup(of: ResultSet?.self) { group in
            for check in job.checks {
                group.addTask {
                    let remaining = Self.seconds(until: deadline)
                    guard remaining > 0 else { return nil }
                    return try? await Self.withTimeout(min(perBatch, remaining)) {
                        try await grader.grade([check], style: job.style, answers: answers, strictFormat: true)
                    }
                }
            }
            for await single in group { if let single { results.merge(single) { _, new in new } } }
        }
        return (results, job.checks.count)
    }

    private func absorb(_ batchRun: BatchRun, into results: inout ResultSet, log: inout GradingLog) {
        results.merge(batchRun.results) { _, new in new }
        log.modelCalls += batchRun.calls
        log.failedBatches += batchRun.failures
        log.fallbackChecks += batchRun.fallbackChecks
    }

    /// v3.2: IDs the model left out are sent once more, with the same answer. Anything still missing
    /// stays uncertain with source `.omitted`.
    private func secondTry(_ results: inout ResultSet, catalog: [String: GradableCheck], answers: [String],
                           deadline: ContinuousClock.Instant, log: inout GradingLog) async {
        let omitted = results.filter { $0.value.source == .omitted }.map(\.key).sorted().compactMap { catalog[$0] }
        guard !omitted.isEmpty else { return }
        let interval = Self.signposter.beginInterval("retry")
        let retryJobs = chunked(omitted.filter { $0.kind == .relevance || $0.kind == .misconception }, style: .topic, label: "retry-topic", strictFormat: true)
            + chunked(omitted.filter { $0.kind == .keyPoint || $0.kind == .causeLink }, style: .screening, label: "retry", strictFormat: true)
        let retry = await run(retryJobs, answers: answers, deadline: deadline, fallback: false)
        Self.signposter.endInterval("retry", interval)
        log.modelCalls += retry.calls
        log.failedBatches += retry.failures
        log.retried += omitted.map(\.id)
        for (id, result) in retry.results where result.source == .model {
            results[id] = result
        }
        log.stillOmitted += omitted.map(\.id).filter { results[$0]?.source == .omitted }
    }

    private func guardAgainstKeywordStuffing(_ results: inout ResultSet, concept: CompiledConcept, transcript: String, log: inout GradingLog) {
        guard CodeGrader.isKeywordStuffing(transcript) else { return }
        log.keywordStuffing = true
        // A list of terms connects nothing (complete_sentences is already no from CodeGrader).
        for link in concept.causeLinks {
            results[link.id] = CheckResult(state: .no, source: .code)
        }
    }

    // MARK: - Recheck of blocking "no" results

    /// A model "no" can be a false no (the Milestone 6 dry run refused "villagers form a committee and guard it along with
    /// the forest department" as an explanation of village institutions). When model "no" results are the only thing
    /// between the answer and mastery, each is asked again alone in lenient wording. A "yes" now counts only if it survives
    /// what every mastery yes survives: a genuine quote that, read with its neighbouring sentences, states the check.
    /// Measured on the Milestone 0 labels this recovers 6 of 19 false no's and wrongly flips 5 of 306 real no's
    /// (a bare recheck flips about 1 real no in 10, which is why the quote checks are not optional).
    private func recheckBlockingNos(_ results: inout ResultSet, concept: CompiledConcept, chapter: CompiledChapter,
                                    catalog: [String: GradableCheck], context: AttemptContext, transcript: String,
                                    deadline: ContinuousClock.Instant, log: inout GradingLog) async {
        guard settings.recheckNoResults, transport.isReady, !log.keywordStuffing else { return }
        var candidates: [GradableCheck] = []
        for keyPoint in concept.keyPoints where keyPoint.role == .core {
            guard RuleEngine.keyPointOutcome(keyPoint, concept: concept, results: results) == .fail else { continue }
            let blockers = keyPoint.checks.filter { check in
                results[check.id]?.state == .no && results[check.id]?.source == .model
                    && (check.isRequired || keyPoint.passRule != .allRequired)
            }
            // A failing core keyPoint with no model "no" to blame (a stated misconception, say) cannot be rescued.
            guard !blockers.isEmpty else { return }
            candidates += blockers.compactMap { catalog[$0.id] }
        }
        guard (1...GradingSettings.maxRechecks).contains(candidates.count) else { return }
        var assumed = results
        for check in candidates { assumed[check.id]?.state = .yes }
        let outcome = RuleEngine.decide(concept, results: assumed, context: context, articulationChecks: chapter.articulationChecks).outcome
        guard outcome == .mastered || outcome == .likelyMastered else { return }

        log.rechecked += candidates.map(\.id)
        let grader = ModelGrader(transport: transport)
        let perBatch = settings.perBatchSeconds
        let minimumWords = settings.minimumQuoteWords
        let contextSentences = settings.confirmContextSentences
        var flipped: [String: String] = [:]
        await withTaskGroup(of: (String, String)?.self) { group in
            for check in candidates {
                group.addTask {
                    func left() -> Double { Self.seconds(until: deadline) }
                    guard left() > 0,
                          let again = try? await Self.withTimeout(min(perBatch, left()), {
                              try await grader.grade([check], style: .screening, answers: [transcript], strictFormat: true, lenient: true)
                          }), again[check.id]?.state == .yes,
                          left() > 0,
                          let verdicts = try? await Self.withTimeout(left(), {
                              try await grader.prove([check], transcript: transcript, minimumWords: minimumWords)
                          }), case .genuine(let quote)? = verdicts[check.id], left() > 0 else { return nil }
                    let excerpt = ModelGrader.excerpt(around: quote, in: transcript, contextSentences: contextSentences)
                    guard let confirmed = try? await Self.withTimeout(left(), {
                        try await grader.grade([check], style: .screening, answers: [excerpt])
                    }), confirmed[check.id]?.state == .yes else { return nil }
                    return (check.id, quote)
                }
            }
            for await result in group { if let result { flipped[result.0] = result.1 } }
        }
        log.modelCalls += candidates.count * 3
        for (id, quote) in flipped {
            var result = CheckResult(state: .yes, source: .model, quoteCheck: .proven, quote: quote)
            result.round = results[id]?.round ?? 0
            result.history = (results[id]?.history ?? []) + [CheckHistoryEntry(round: result.round, state: .yes, source: .model, event: .recheck)]
            results[id] = result
            log.recheckFlipped.append(id)
        }
    }

    // MARK: - Pass 2

    /// v4.0 change 1: every misconception yes, and the deciding checks of a would-be Mastered answer,
    /// must be backed by the student's own words. Not backed: uncertain (never no). Not checked in
    /// time: a misconception becomes uncertain (no one is accused without proof); a mastery check is
    /// marked timed out, which caps the outcome at Likely mastered.
    ///
    /// A genuine quote only proves the words exist. A misconception quote is therefore read on its own
    /// once more: only if that quote alone states the wrong idea is the student held to it (M3 live test:
    /// a real sentence about something else had been accepted as proof). A flag that cannot be backed
    /// is ruled out only when the student's own words explicitly reject or correct the wrong idea.
    private func proveDecisiveYeses(_ results: inout ResultSet, concept: CompiledConcept, chapter: CompiledChapter,
                                    catalog: [String: GradableCheck], context: AttemptContext, transcript: String,
                                    deadline: ContinuousClock.Instant, log: inout GradingLog) async {
        guard transport.isReady else { return }
        let misconceptionIds = concept.misconceptions.map(\.checkId).filter {
            results[$0]?.state == .yes && results[$0]?.source == .model && results[$0]?.quoteCheck != .proven
        }
        var masteryIds: [String] = []
        if settings.quoteCheckMastery {
            // As if the pending flags will be ruled out, so the mastery evidence is checked in parallel
            // with them; if a flag is confirmed instead, the outcome is Needs correction anyway.
            var assumed = results
            for id in misconceptionIds { assumed[id]?.state = .no }
            let provisional = RuleEngine.decide(concept, results: assumed, context: context, articulationChecks: chapter.articulationChecks)
            if provisional.outcome == .mastered {
                for keyPoint in concept.keyPoints where keyPoint.role == .core {
                    masteryIds += RuleEngine.decidingChecks(keyPoint, results: assumed).filter {
                        results[$0]?.source == .model && results[$0]?.quoteCheck != .proven
                    }
                }
            }
        }
        let ids = misconceptionIds + masteryIds.filter { !misconceptionIds.contains($0) }
        guard !ids.isEmpty else { return }
        log.proofRequested += ids

        let interval = Self.signposter.beginInterval("pass2")
        // Misconception quotes go in their own batches: guardrail refusals seen in testing were triggered
        // by misconception content and would otherwise take the mastery quotes down with them.
        let verdicts = await quotes(for: [("proof-misconception", misconceptionIds.compactMap { catalog[$0] }),
                                          ("proof", masteryIds.filter { !misconceptionIds.contains($0) }.compactMap { catalog[$0] })],
                                    transcript: transcript, deadline: deadline, log: &log)
        let misconceptionSet = Set(misconceptionIds)
        // A genuine quote only proves the words exist. Each quote is read on its own: a misconception is held
        // against the student, and a mastery check counts, only if that quote alone states it.
        let contextSentences = settings.confirmContextSentences
        let confirmed = await confirm(ids.compactMap { id -> (GradableCheck, String, BatchStyle)? in
            guard case .genuine(let quote)? = verdicts[id], let check = catalog[id] else { return nil }
            if misconceptionSet.contains(id) { return (check, quote, .topic) }
            return (check, ModelGrader.excerpt(around: quote, in: transcript, contextSentences: contextSentences), .screening)
        }, deadline: deadline, log: &log)

        for id in ids {
            switch verdicts[id] {
            case .genuine(let quote)? where misconceptionSet.contains(id) && !confirmed.contains(id):
                log.misconceptionNotConfirmed.append(id)
                results[id]?.state = .uncertain
                results[id]?.quote = quote
            case .genuine(let quote)? where !confirmed.contains(id):
                log.quoteNotConfirmed.append(id)
                results[id]?.state = .uncertain
                results[id]?.quote = quote
            case .genuine(let quote)?:
                results[id]?.quoteCheck = .proven
                results[id]?.quote = quote
            case nil:
                log.proofNotChecked.append(id)
                if misconceptionSet.contains(id) {
                    results[id]?.state = .uncertain
                } else {
                    results[id]?.quoteCheck = .timedOut
                }
            case let verdict?:
                log.proofRejected.append("\(id): \(verdict)")
                results[id]?.state = .uncertain
            }
        }

        // A flagged misconception the model could not back up is ruled out only when the student's
        // own words explicitly reject or correct it: a genuine quote that, read on its own, states the
        // correct idea. Finding some quote in the answer is not enough; anything less stays uncertain.
        // This step can only upgrade Likely mastered to Mastered, so it is skipped when less than a quarter of the
        // time budget is left (in the Milestone 6 dry run it ran to the deadline for answers that were already accepted).
        let unresolved = concept.misconceptions.filter { misconceptionSet.contains($0.checkId) && results[$0.checkId]?.state == .uncertain }
        if !unresolved.isEmpty, Self.seconds(until: deadline) >= 0.25 * settings.totalSeconds {
            let rejections = Dictionary(uniqueKeysWithValues: unresolved.map { misconception in
                (misconception.checkId, GradableCheck(
                    id: "mrej_" + misconception.id,
                    criterion: "Rejects or corrects the wrong idea \"\(misconception.wrong)\" by stating the correct idea: \(misconception.fix)",
                    kind: .misconceptionFix, lexical: .never, evidence: []))
            })
            let rejectionVerdicts = await quotes(for: [("rejection", rejections.keys.sorted().compactMap { rejections[$0] })],
                                                 transcript: transcript, deadline: deadline, log: &log)
            let quotesByCheck = rejections.compactMapValues { check -> String? in
                if case .genuine(let quote)? = rejectionVerdicts[check.id] { return quote }
                return nil
            }
            let verified = await confirm(quotesByCheck.compactMap { checkId, quote in rejections[checkId].map { ($0, quote, BatchStyle.screening) } },
                                         deadline: deadline, log: &log)
            for misconception in unresolved {
                guard let check = rejections[misconception.checkId], verified.contains(check.id),
                      let quote = quotesByCheck[misconception.checkId] else { continue }
                results[misconception.checkId]?.state = .no
                results[misconception.checkId]?.quoteCheck = .proven
                results[misconception.checkId]?.quote = quote
                log.misconceptionRuledOut.append(misconception.checkId)
            }
        }
        Self.signposter.endInterval("pass2", interval)
    }

    /// Asks for the student's exact words behind each check, in batches of up to six per group, all in
    /// parallel within the budget. A batch that fails or runs out of time is left out and logged.
    private func quotes(for groups: [(label: String, checks: [GradableCheck])], transcript: String,
                        deadline: ContinuousClock.Instant, log: inout GradingLog) async -> [String: QuoteVerdict] {
        let grader = ModelGrader(transport: transport)
        let minimumWords = settings.minimumQuoteWords
        let jobs = groups.flatMap { chunked($0.checks, style: .screening, label: $0.label) }
        var verdicts: [String: QuoteVerdict] = [:]
        await withTaskGroup(of: (verdicts: [String: QuoteVerdict], failure: String?).self) { group in
            for job in jobs {
                group.addTask {
                    let remaining = Self.seconds(until: deadline)
                    guard remaining > 0 else { return ([:], "\(job.label): skipped, time budget spent") }
                    do {
                        return (try await Self.withTimeout(remaining) {
                            try await grader.prove(job.checks, transcript: transcript, minimumWords: minimumWords)
                        }, nil)
                    } catch {
                        return ([:], "\(job.label): \(error)")
                    }
                }
            }
            for await batch in group {
                verdicts.merge(batch.verdicts) { _, new in new }
                if let failure = batch.failure { log.failedBatches.append(failure) }
            }
        }
        log.modelCalls += jobs.count

        // The model sometimes answers NONE (or leaves a line out) for one check of a batch although the answer
        // plainly states it (Milestone 6 dry run: "power is split between the top level and the lower levels").
        // Ask for those quotes once more, one check per call; the quote still has to be genuine and confirmed.
        let again = groups.flatMap(\.checks).filter { verdicts[$0.id] == QuoteVerdict.none || verdicts[$0.id] == .unparsed }
        if !again.isEmpty {
            var recovered: [String: QuoteVerdict] = [:]
            await withTaskGroup(of: [String: QuoteVerdict].self) { group in
                for check in again {
                    group.addTask {
                        let remaining = Self.seconds(until: deadline)
                        guard remaining > 0 else { return [:] }
                        return (try? await Self.withTimeout(remaining) {
                            try await grader.prove([check], transcript: transcript, minimumWords: minimumWords)
                        }) ?? [:]
                    }
                }
                for await single in group { recovered.merge(single) { _, new in new } }
            }
            log.modelCalls += again.count
            for (id, verdict) in recovered {
                if case .genuine = verdict { verdicts[id] = verdict }
            }
        }
        return verdicts
    }

    /// Reads each text on its own (a misconception's bare quote, or a mastery quote with its neighbouring
    /// sentences) and keeps the checks that text alone states.
    private func confirm(_ pairs: [(GradableCheck, String, BatchStyle)], deadline: ContinuousClock.Instant,
                         log: inout GradingLog) async -> Set<String> {
        guard !pairs.isEmpty else { return [] }
        let grader = ModelGrader(transport: transport)
        var confirmed: Set<String> = []
        await withTaskGroup(of: String?.self) { group in
            for (check, quote, style) in pairs {
                group.addTask {
                    let remaining = Self.seconds(until: deadline)
                    guard remaining > 0, let result = try? await Self.withTimeout(remaining, {
                        try await grader.grade([check], style: style, answers: [quote])
                    }) else { return nil }
                    return result[check.id]?.state == .yes ? check.id : nil
                }
            }
            for await id in group { if let id { confirmed.insert(id) } }
        }
        log.modelCalls += pairs.count
        return confirmed
    }

    // MARK: - Helpers

    /// Every check the model can grade for this concept, keyed by ID.
    static func catalog(_ concept: CompiledConcept) -> [String: GradableCheck] {
        var catalog: [String: GradableCheck] = [:]
        let relevance = concept.relevanceCheck
        catalog[relevance.id] = GradableCheck(id: relevance.id, criterion: relevance.criterion, kind: .relevance, lexical: .never, evidence: [])
        for keyPoint in concept.keyPoints {
            for check in keyPoint.checks {
                // The evidence phrases the check itself names; otherwise all of its keyPoint's.
                let criterionTokens = LexicalGrader.tokenize(check.criterion)
                let named = keyPoint.requiredEvidence.filter { phrase in
                    let words = LexicalGrader.tokenize(phrase)
                    return !words.isEmpty && words.count <= criterionTokens.count
                        && (0...(criterionTokens.count - words.count)).contains { Array(criterionTokens[$0..<$0 + words.count]) == words }
                }
                catalog[check.id] = GradableCheck(id: check.id, criterion: check.criterion, kind: .keyPoint, lexical: check.lexical,
                                                  evidence: named.isEmpty ? keyPoint.requiredEvidence : named)
            }
        }
        for link in concept.causeLinks {
            catalog[link.id] = GradableCheck(id: link.id, criterion: link.criterion, kind: .causeLink, lexical: .never, evidence: [])
        }
        for misconception in concept.misconceptions {
            catalog[misconception.checkId] = GradableCheck(id: misconception.checkId, criterion: misconception.checkCriterion,
                                                           kind: .misconception, lexical: .never, evidence: [])
        }
        return catalog
    }

    static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    static func seconds(until deadline: ContinuousClock.Instant) -> Double {
        -seconds(since: deadline)
    }

    /// Returns at the time limit even if the operation ignores cancellation; its late result is dropped.
    static func withTimeout<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let once = ResumeOnce(continuation)
            let work = Task { try await operation() }
            let timer = Task {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                work.cancel()
                once.resume(.failure(TransportError.timeout))
            }
            Task {
                do {
                    let value = try await work.value
                    timer.cancel()
                    once.resume(.success(value))
                } catch {
                    timer.cancel()
                    once.resume(.failure(error))
                }
            }
        }
    }
}

/// Resumes a continuation exactly once, whichever of the work or the timer finishes first.
nonisolated private final class ResumeOnce<T: Sendable>: Sendable {
    private let resumed = OSAllocatedUnfairLock(initialState: false)
    private let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        let first = resumed.withLock { done -> Bool in
            if done { return false }
            done = true
            return true
        }
        if first { continuation.resume(with: result) }
    }
}
