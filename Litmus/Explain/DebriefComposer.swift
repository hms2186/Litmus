//
//  DebriefComposer.swift
//  Feynman Tutor Engine - Layer 5 (Presentation)
//
//  The three lines of the review screen (what was missing, vague and right), made from the Rule Engine's report, the
//  compiled concept (its stored criteria, hint and misconception fixes) and the student's own words. Nothing here is
//  invented: every idea named comes from the compiled file, every quote is a sentence the student actually said, and an
//  empty list is never covered by a generic line that could be true of any topic.
//

import Foundation
import NaturalLanguage

nonisolated struct DebriefRows: Equatable, Sendable {
    var missing: String
    var vague: String
    var right: String
}

nonisolated enum DebriefComposer {

    static func rows(report: EvaluationReport, outcome: EvaluationOutcome?, concept: CompiledConcept?, answers: [String]) -> DebriefRows {
        let passing: Bool
        switch outcome {
        case .mastered?, .likelyMastered?: passing = true
        default: passing = false
        }
        return DebriefRows(
            missing: missingLine(report, passing: passing, concept: concept, answers: answers),
            vague: vagueLine(report, passing: passing, concept: concept),
            right: rightLine(report, concept: concept, answers: answers)
        )
    }

    // MARK: Right

    private static func rightLine(_ report: EvaluationReport, concept: CompiledConcept?, answers: [String]) -> String {
        guard let first = report.right.first else {
            // Nothing was clearly stated: say so, and show where the student began so the line is about this answer
            if let gist = answers.last.flatMap(firstSentence) {
                return "None of the key ideas for this topic was clearly stated yet. You began with “\(shorten(gist, 70))”."
            }
            return "None of the key ideas for this topic was clearly stated yet."
        }
        var line = FeedbackPhrasing.right(first)
        if let quote = quote(matching: [first] + evidence(for: first, in: concept), in: answers) {
            line += " You said: “\(shorten(quote, 90))”"
        }
        let extra = report.right.count - 1
        if extra > 0 { line += " (and \(extra) more ideas)" }
        return line
    }

    // MARK: Missing

    private static func missingLine(_ report: EvaluationReport, passing: Bool, concept: CompiledConcept?, answers: [String]) -> String {
        if let fix = report.corrections.first {
            // The student stated a wrong idea: show their own sentence, then the stored correction
            let wrong = concept?.misconceptions.first { $0.fix == fix }?.wrong
            var line = ""
            if let wrong, let said = quote(matching: [wrong], in: answers) {
                line = "You said “\(shorten(said, 100))”. "
            }
            line += "Remember: \(fix)"
            if report.corrections.count > 1 { line += " (and \(report.corrections.count - 1) more to fix)" }
            return line
        }
        let gaps = report.missing + report.conflicts
        if !gaps.isEmpty {
            return FeedbackPhrasing.summary(gaps, phrase: FeedbackPhrasing.missing, more: "ideas to cover")
        }
        if passing { return "Nothing missing: you covered every key idea for this topic." }
        return "One idea still needs a clearer answer. The question below is the place to start."
    }

    // MARK: Vague

    private static func vagueLine(_ report: EvaluationReport, passing: Bool, concept: CompiledConcept?) -> String {
        if let question = report.followUp { return "Think about this: \(question)" }
        if !report.vague.isEmpty {
            return FeedbackPhrasing.summary(report.vague, phrase: { "Be more specific: " + FeedbackPhrasing.missing($0).replacingOccurrences(of: "Try to ", with: "") }, more: "points")
        }
        if passing { return "Nothing vague: your explanation was clear." }
        // Not finished and nothing vague to point at: the topic's own hint from the compiled file
        if let hint = concept?.hint, !hint.isEmpty { return "Think about this: \(hint)" }
        return "Say it in your own words, step by step."
    }

    // MARK: The student's own words

    /// The sentence of the student's answers that shares the most content words with `texts` (at least two), so a
    /// quote is only shown when it really is about that idea. Later answers win a tie. Nil when nothing matches.
    static func quote(matching texts: [String], in answers: [String]) -> String? {
        let wanted = Set(texts.flatMap(significant))
        guard !wanted.isEmpty else { return nil }
        var best: (score: Int, sentence: String)?
        for answer in answers {
            for sentence in sentences(of: answer) {
                let shared = Set(significant(sentence)).intersection(wanted).count
                if shared >= 2, shared >= (best?.score ?? 0) { best = (shared, sentence) }
            }
        }
        return best.map { shorten($0.sentence, 140) }
    }

    /// The textbook evidence phrases of the key point that owns this criterion: the words a student would use for it.
    private static func evidence(for criterion: String, in concept: CompiledConcept?) -> [String] {
        concept?.keyPoints.first { $0.checks.contains { $0.criterion == criterion } }?.requiredEvidence ?? []
    }

    private static func significant(_ text: String) -> [String] {
        LexicalGrader.tokenize(text).filter { $0.count >= 4 }
    }

    private static func sentences(of text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func firstSentence(_ text: String) -> String? { sentences(of: text).first }

    /// Cut at a word boundary so a long sentence stays readable; the words kept are still the student's, in order.
    private static func shorten(_ text: String, _ limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " .\n"))
        guard trimmed.count > limit else { return trimmed }
        let cut = String(trimmed.prefix(limit - 1))
        let atWord = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
        return atWord + "…"
    }
}
