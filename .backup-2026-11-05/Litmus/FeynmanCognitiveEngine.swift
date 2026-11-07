//
//  FeynmanCognitiveEngine.swift
//  Feynman Tutor Engine - Layer 4 (Cognitive Engine: Apple FoundationModels)
//
//  Asks Apple's on-device SystemLanguageModel one true/false question per check ID and
//  returns a flat [String: Bool] checklist. The model never scores, grades or writes
//  feedback; ConceptEvaluator turns the checklist into the qualitative FeedbackReport.
//

import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

public final class FeynmanCognitiveEngine: Sendable {

    public static let shared = FeynmanCognitiveEngine()

    public init() {}

    private static let instructionsText = """
    You check a student's explanation against a fixed list of criteria from an NCERT chapter.
    For each criterion ID, answer true only if the transcript clearly states that idea, in the student's own words or with the same meaning.
    Answer false if the idea is missing, stated wrongly, or only named as a keyword without being explained.
    Judge only what the transcript says. Do not use outside knowledge to fill gaps.
    Do not score, grade, summarise or give feedback. Answer only true or false for every ID.
    """

    private struct Criterion {
        let id: String
        let text: String
    }

    // MARK: - Checklist Entry Point

    /// Returns checkId -> Bool for every keyPoint check, cause link and articulation check
    /// of `concept`. Falls back to a deterministic lexical matcher when the on-device model
    /// is unavailable or fails.
    func evaluateChecklist(
        transcript: String,
        concept: FeynmanConcept,
        articulationChecks: [ArticulationCheck],
        chapterVocabulary: [String],
        telemetry: LinguisticTelemetry
    ) async -> [String: Bool] {
        // Start from the lexical fallback; every batch the model answers overwrites its IDs.
        var checklist = LexicalChecklistFallback.evaluate(
            transcript: transcript,
            concept: concept,
            articulationChecks: articulationChecks,
            chapterVocabulary: chapterVocabulary
        )

        #if canImport(FoundationModels)
        if SystemLanguageModel.default.isAvailable {
            // One small batch per call: the on-device model misses facts when given ~20 criteria at once.
            let batches = Self.criteriaBatches(for: concept, articulationChecks: articulationChecks)
            await withTaskGroup(of: [String: Bool]?.self) { group in
                for batch in batches {
                    group.addTask {
                        do {
                            return try await self.checklistFromModel(transcript: transcript, criteria: batch)
                        } catch {
                            #if DEBUG
                            print("⚠️ [FeynmanCognitiveEngine] Batch \(batch.map(\.id)) failed (\(error.localizedDescription)). Using lexical fallback for it.")
                            #endif
                            return nil
                        }
                    }
                }
                for await results in group {
                    if let results {
                        checklist.merge(results) { _, modelValue in modelValue }
                    }
                }
            }
        }
        #endif

        // Telemetry enforcement priority: a keyword list has no sentences and links nothing.
        if telemetry.isKeywordStuffingSuspected || telemetry.nounToVerbRatio >= 3.8 {
            for link in concept.causeLinks {
                checklist[link.id] = false
            }
            for check in articulationChecks where check.id.contains("complete_sentences") {
                checklist[check.id] = false
            }
        }
        return checklist
    }

    /// Whole keyPoints packed into batches of at most `maxBatchSize` checks, then the cause links
    /// and articulation checks together. Each batch is one model call.
    private static let maxBatchSize = 6

    private static func criteriaBatches(for concept: FeynmanConcept, articulationChecks: [ArticulationCheck]) -> [[Criterion]] {
        var batches: [[Criterion]] = []
        var current: [Criterion] = []
        for keyPoint in concept.keyPoints {
            let checks = keyPoint.assessment.checks.map { Criterion(id: $0.id, text: $0.criterion) }
            if !current.isEmpty && current.count + checks.count > maxBatchSize {
                batches.append(current)
                current = []
            }
            current += checks
        }
        if !current.isEmpty { batches.append(current) }
        let closing = concept.causeLinks.map { Criterion(id: $0.id, text: $0.criterion) }
            + articulationChecks.map { Criterion(id: $0.id, text: $0.criterion) }
        if !closing.isEmpty { batches.append(closing) }
        return batches
    }

    #if canImport(FoundationModels)
    /// Plain-text generation of a flat JSON object, parsed strictly. Guided generation with a
    /// runtime DynamicGenerationSchema is rejected by the default guardrails ("May contain
    /// sensitive content") even for neutral criteria, so it is not used.
    private func checklistFromModel(transcript: String, criteria: [Criterion]) async throws -> [String: Bool] {
        let promptText = """
        CRITERIA (ID: criterion)
        \(criteria.map { "\($0.id): \($0.text)" }.joined(separator: "\n"))

        IDs starting with "lnk_" are true only if the student connects the two ideas as cause and effect, not if they only state both.

        STUDENT TRANSCRIPT
        \"\"\"
        \(transcript)
        \"\"\"

        Reply with only a JSON object that maps every ID above to true or false.
        """

        let session = LanguageModelSession(model: .default, instructions: Self.instructionsText)
        // ~12 tokens per `"chk_id": false,` pair; the cap stops greedy decoding from looping.
        let response = try await session.respond(
            to: Prompt(promptText),
            options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 20 + 16 * criteria.count)
        )
        return try Self.parseChecklist(response.content, expectedIDs: criteria.map(\.id))
    }
    #endif

    /// Reads `"id": true|false` pairs for the expected IDs only, so a ```json fence or a reply cut
    /// off by the token cap still parses. Any ID the model left out counts as false.
    static func parseChecklist(_ text: String, expectedIDs: [String]) throws -> [String: Bool] {
        var checklist: [String: Bool] = [:]
        var foundAny = false
        for id in expectedIDs {
            let pattern = "\"\(NSRegularExpression.escapedPattern(for: id))\"\\s*:\\s*\"?(true|false)"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let valueRange = Range(match.range(at: 1), in: text) {
                checklist[id] = text[valueRange].lowercased() == "true"
                foundAny = true
            } else {
                checklist[id] = false
            }
        }
        guard foundAny else {
            throw NSError(domain: "FeynmanCognitiveEngine", code: 500, userInfo: [NSLocalizedDescriptionKey: "Model reply contained none of the check IDs"])
        }
        return checklist
    }
}

// MARK: - Deterministic Fallback

/// Stand-in for when Apple Intelligence is unavailable (Simulator, unsupported devices, or
/// Apple Intelligence turned off). Coarse by design: it matches phrases, it does not understand.
enum LexicalChecklistFallback {

    private static let stopWords: Set<String> = [
        "the", "that", "this", "with", "from", "their", "they", "them", "were", "was", "have", "has",
        "into", "about", "such", "only", "also", "which", "when", "where", "there", "both", "each",
        "other", "more", "than", "will", "would", "could", "should", "does", "between", "among",
        "student", "answer", "states", "mentions", "names", "explains", "notes", "defines",
        "describes", "gives", "connects", "contrasts", "uses", "distinguishes", "lists", "identifies"
    ]

    private static let causalConnectives = [
        "because", "so ", "therefore", "as a result", "led to", "leads to", "lead to", "caused",
        "causes", "resulted", "results in", "which made", "that is why", "due to", "since", "hence"
    ]

    static func evaluate(
        transcript: String,
        concept: FeynmanConcept,
        articulationChecks: [ArticulationCheck],
        chapterVocabulary: [String]
    ) -> [String: Bool] {
        let text = transcript.lowercased()
        let textStems = Set(contentWords(in: text).map(stem))
        var checklist: [String: Bool] = [:]

        for keyPoint in concept.keyPoints {
            let evidenceFound = keyPoint.assessment.requiredEvidence.contains { phrase in
                let stems = contentWords(in: phrase.lowercased()).map(stem)
                return !stems.isEmpty && stems.allSatisfy(textStems.contains)
            }
            for check in keyPoint.assessment.checks {
                let stems = contentWords(in: check.criterion.lowercased()).map(stem)
                let overlap = stems.isEmpty ? 0 : Double(stems.filter(textStems.contains).count) / Double(stems.count)
                checklist[check.id] = evidenceFound && overlap >= 0.4
            }
        }

        let hasConnective = causalConnectives.contains { text.contains($0) }
        for link in concept.causeLinks {
            let factsStated = link.linksChecks.allSatisfy { checklist[$0] == true }
            checklist[link.id] = factsStated && hasConnective
        }

        for check in articulationChecks {
            if check.id.contains("complete_sentences") {
                checklist[check.id] = sentenceCount(in: transcript) >= 2 && transcript.split(separator: " ").count >= 15
            } else if check.id.contains("chapter_terms") {
                checklist[check.id] = chapterVocabulary.contains { text.contains($0.lowercased()) }
            } else {
                checklist[check.id] = false
            }
        }
        return checklist
    }

    private static func contentWords(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    /// Crude stem: the first five letters, so "dominance"/"dominate" and "shares"/"sharing" match.
    private static func stem(_ word: String) -> String {
        String(word.prefix(5))
    }

    private static func sentenceCount(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }
}
