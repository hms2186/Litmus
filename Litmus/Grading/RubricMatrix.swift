//
//  RubricMatrix.swift
//  Feynman Tutor Engine - PARAKH proficiency levels, decided by evidence in the student's own words.
//
//  PARAKH Rashtriya Sarvekshan 2024 (Analysis Framework, section 6.2) reports three proficiency levels:
//    Basic       - partial knowledge and skills
//    Proficient  - solid understanding and ability to apply core concepts
//    Advanced    - high competence, including application and synthesis
//  The framework gives the levels and their descriptors, not a scoring recipe for spoken answers, so the mapping
//  below is this app's own, stated here so it can be reviewed:
//    Basic       <- .partial, .notYet (some key ideas stated, the core not yet)
//    Proficient  <- .likelyMastered   (every core key point is evidenced and the 70% bar is met, but at least one
//                                      idea is supported by the student's own words only, not confirmed by the model)
//    Advanced    <- .mastered         (every core key point is confirmed by the model with a verified quote)
//
//  The on-device model can say "no" to an idea the student did state (a false no). The Rule Engine's pass bar is
//  strict, so one false no on a core idea sent correct explanations to the review screen. This file lets the
//  textbook evidence the compiled curriculum already lists for each idea overrule such a "no", and only when the
//  student really said it: the phrase is in the answer, not negated, and the answer is not a list of keywords.
//  An evidence-supported idea is stored with source .lexical, so the Rule Engine can never turn it into Mastered:
//  the best result it can give is Likely mastered (Proficient). Nothing here calls the model.
//

import Foundation
import NaturalLanguage

nonisolated enum ParakhLevel: String, Sendable, Equatable {
    case basic, proficient, advanced
}

nonisolated enum RubricMatrix {

    /// The proficiency level an outcome stands for, or nil when the answer was not graded on its merits.
    static func level(of outcome: EvaluationOutcome) -> ParakhLevel? {
        switch outcome {
        case .mastered: .advanced
        case .likelyMastered: .proficient
        case .partial, .notYet, .needsClarification, .needsCorrection: .basic
        case .notGradable, .offTopic: nil
        }
    }

    private static func sentences(of text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }
    }

    /// Turns a model "no" or "uncertain" on an evidence check into a yes when the student's own words contain the
    /// textbook evidence for it. Returns the IDs it changed.
    ///
    /// Only checks the curriculum compiler marked as checkable by evidence (`lexical == .evidence`) are eligible;
    /// relevance, cause links and misconception checks never are. A stated misconception on the same key point
    /// blocks it, and nothing changes when the answer reads as a list of keywords.
    @discardableResult
    static func supportWithEvidence(
        _ results: inout ResultSet,
        concept: CompiledConcept,
        catalog: [String: GradableCheck],
        transcript: String,
        keywordStuffing: Bool,
        round: Int = 0
    ) -> [String] {
        guard !keywordStuffing else { return [] }
        // Evidence counts only inside a statement: a sentence that has a verb. A phrase in a list of terms proves nothing.
        let statements = sentences(of: transcript).filter(CodeGrader.hasFiniteVerb)
        guard !statements.isEmpty else { return [] }
        let tokens = statements.flatMap(LexicalGrader.tokenize)
        var changed: [String] = []
        for keyPoint in concept.keyPoints {
            let statedMisconception = concept.misconceptions.contains { misconception in
                misconception.keyPointIds.contains(keyPoint.id)
                    && results[misconception.checkId]?.state == .yes
                    && results[misconception.checkId]?.corrected != true
            }
            if statedMisconception { continue }
            for check in keyPoint.checks {
                guard let current = results[check.id], current.state != .yes,
                      current.source == .model || current.source == .omitted,
                      let gradable = catalog[check.id], gradable.kind == .keyPoint, gradable.lexical == .evidence,
                      LexicalGrader.evidence(gradable.evidence, in: tokens) == .found
                else { continue }
                var supported = CheckResult(state: .yes, source: .lexical, round: round)
                supported.history = current.history + [
                    CheckHistoryEntry(round: round, state: .yes, source: .lexical, event: .newEvidence)
                ]
                results[check.id] = supported
                changed.append(check.id)
            }
        }
        return changed
    }

    // MARK: - Phrasing support

    /// Lifts a model "no" or "uncertain" on an opted-in check (compiled `acceptedPhrasings`) to a lexical yes when ONE statement
    /// of the answer (a sentence with a finite verb) contains every anchor group of one accepted phrasing. Same guards as
    /// `supportWithEvidence`: nothing on a keyword list, a stated and uncorrected misconception on the key point blocks it, and
    /// the result is `.lexical`, so the outcome can reach Likely mastered but never Mastered. Returns the IDs it changed.
    @discardableResult
    static func supportWithPhrasing(
        _ results: inout ResultSet,
        concept: CompiledConcept,
        catalog: [String: GradableCheck],
        transcript: String,
        keywordStuffing: Bool,
        round: Int = 0
    ) -> [String] {
        // The coordinator passes its own keyword-stuffing verdict; checking again (and refusing a term list, which can meet no criterion) keeps this safe when called alone.
        guard !keywordStuffing, !CodeGrader.isKeywordStuffing(transcript), !CodeGrader.isTermList(transcript) else { return [] }
        let statements = sentences(of: transcript).filter(CodeGrader.hasFiniteVerb).map(LexicalGrader.tokenize)
        guard !statements.isEmpty else { return [] }
        var changed: [String] = []
        for keyPoint in concept.keyPoints {
            let statedMisconception = concept.misconceptions.contains { misconception in
                misconception.keyPointIds.contains(keyPoint.id)
                    && results[misconception.checkId]?.state == .yes
                    && results[misconception.checkId]?.corrected != true
            }
            if statedMisconception { continue }
            for check in keyPoint.checks {
                guard let current = results[check.id], current.state != .yes,
                      current.source == .model || current.source == .omitted,
                      let gradable = catalog[check.id], gradable.kind == .keyPoint, !gradable.phrasings.isEmpty,
                      statements.contains(where: { tokens in gradable.phrasings.contains { matches($0, in: tokens) } })
                else { continue }
                var supported = CheckResult(state: .yes, source: .lexical, round: round)
                supported.history = current.history + [
                    CheckHistoryEntry(round: round, state: .yes, source: .lexical, event: .newEvidence)
                ]
                results[check.id] = supported
                changed.append(check.id)
            }
        }
        return changed
    }

    /// Every anchor group needs a phrase in this one sentence, and that occurrence must not have a negation word in the
    /// words just before it (the window `LexicalGrader.evidence` uses).
    static func matches(_ rule: PhrasingRule, in tokens: [String]) -> Bool {
        // A sentence that names an excluded phrase (an opposite idea) never lifts the check
        for phrase in rule.exclude ?? [] {
            let words = LexicalGrader.tokenize(phrase)
            if !words.isEmpty, words.count <= tokens.count,
               (0...(tokens.count - words.count)).contains(where: { Array(tokens[$0..<$0 + words.count]) == words }) { return false }
        }
        return !rule.all.isEmpty && rule.all.allSatisfy { group in
            group.contains { phrase in
                let words = LexicalGrader.tokenize(phrase)
                guard !words.isEmpty, words.count <= tokens.count else { return false }
                return (0...(tokens.count - words.count)).contains { start in
                    Array(tokens[start..<start + words.count]) == words
                        && !tokens[max(0, start - LexicalGrader.negationWindow)..<start].contains(where: LexicalGrader.negations.contains)
                }
            }
        }
    }

    // MARK: - Meaning support (NLEmbedding)

    /// How close, in Apple's English sentence-embedding space, a statement must be to a check's criterion to count as saying
    /// it. Cosine distance: 0 is the same meaning. Chosen on the labelled answers (see Tools/model_experiments, mode "semdist").
    static var semanticDistanceLimit: Double = 0.55

    /// The closest cosine distance between the criterion and any statement of the answer (nil without an embedding).
    static func semanticDistance(criterion: String, statements: [String]) -> Double? {
        // NLEmbedding is not safe for concurrent use, so each call makes its own instance
        guard !statements.isEmpty, let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        var best: Double?
        for statement in statements {
            let distance = embedding.distance(between: criterion, and: statement, distanceType: .cosine)
            if distance.isFinite, best == nil || distance < best! { best = distance }
        }
        return best
    }

    /// Like `supportWithEvidence`, for a student who explained an idea in everyday words: a model "no" or "uncertain" becomes a
    /// yes when one of the student's statements (a sentence with a verb, and no negation) means nearly the same as the
    /// criterion according to `NLEmbedding.sentenceEmbedding`. Same limits as the evidence support: only evidence-checkable
    /// key points, nothing when a misconception on that key point was stated, nothing for a list of keywords, and the result has
    /// source `.lexical`, so it can reach Likely mastered at best and never Mastered.
    @discardableResult
    static func supportWithMeaning(
        _ results: inout ResultSet,
        concept: CompiledConcept,
        catalog: [String: GradableCheck],
        transcript: String,
        keywordStuffing: Bool,
        round: Int = 0
    ) -> [String] {
        guard !keywordStuffing else { return [] }
        let statements = sentences(of: transcript).filter(CodeGrader.hasFiniteVerb).filter { sentence in
            !LexicalGrader.tokenize(sentence).contains(where: LexicalGrader.negations.contains)
        }
        guard !statements.isEmpty else { return [] }
        var changed: [String] = []
        for keyPoint in concept.keyPoints {
            let statedMisconception = concept.misconceptions.contains { misconception in
                misconception.keyPointIds.contains(keyPoint.id)
                    && results[misconception.checkId]?.state == .yes
                    && results[misconception.checkId]?.corrected != true
            }
            if statedMisconception { continue }
            for check in keyPoint.checks {
                guard let current = results[check.id], current.state != .yes,
                      current.source == .model || current.source == .omitted,
                      let gradable = catalog[check.id], gradable.kind == .keyPoint, gradable.lexical == .evidence,
                      let distance = semanticDistance(criterion: gradable.criterion, statements: statements),
                      distance <= semanticDistanceLimit
                else { continue }
                var supported = CheckResult(state: .yes, source: .lexical, round: round)
                supported.history = current.history + [
                    CheckHistoryEntry(round: round, state: .yes, source: .lexical, event: .newEvidence)
                ]
                results[check.id] = supported
                changed.append(check.id)
            }
        }
        return changed
    }
}
