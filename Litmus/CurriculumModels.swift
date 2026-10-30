import Foundation

// MARK: - Core Evaluation & Rubric Models

struct EvaluationResult {
    let score: Int
    let feedback: String
    let passedIB: Bool
    let passedParakh: Bool
}

struct ConceptGroup: Codable {
    let label: String      // Shown in Race Engineer feedback when this sub-idea is missing
    let terms: [String]    // Single-word lemmas or multi-word phrases
}

struct PillarRule: Codable {
    let groups: [ConceptGroup]
    let minGroups: Int
    let anchors: [String]
    let stripPhrases: [String]   // Negated/prompt-trap phrases removed before matching
    let missingHint: String
    var floorSimilarity: Double = 0.25
    var strongSimilarity: Double = 0.68
}

// MARK: - Unified NCERTTopic Model (Supports Sample Data & JSON Decoding)

struct NCERTTopic: Codable, Identifiable {
    var id: String { title }
    let className: String
    let subject: String
    let chapter: String
    let title: String      // Subtopic / Concept
    let prompt: String
    let coreIdeaIB: String
    let causeEffectParakh: String
    let samplePassAnswer: String
    let sampleIncompleteAnswer: String
    let sampleParakhOnlyAnswer: String
    let ib: PillarRule
    let parakh: PillarRule
    
    /// Maps raw JSON Chapter data into UI-ready NCERTTopics for dynamic loading
    static func topics(from chapterData: ChapterData, className: String = "Class 10") -> [NCERTTopic] {
        let cleanGrade = chapterData.normalizedGrade.isEmpty ? className : chapterData.normalizedGrade
        let cleanSubject = chapterData.normalizedSubject
        
        return chapterData.topics.map { jsonTopic in
            // Our NotebookLM prompt generates 1 comprehensive pillar per topic
            let p1 = jsonTopic.pillars.first
            
            // Extract the generated examples to feed directly to NLTagger
            let extractedExamples = p1?.examples.isEmpty == false ? p1!.examples : [jsonTopic.title.lowercased()]
            
            // Rule 1: The IB Rule evaluates the Core Theory (requiredConcept)
            let ibRule = PillarRule(
                groups: [ConceptGroup(label: "Theoretical Concept", terms: [jsonTopic.title.lowercased()])],
                minGroups: 1,
                anchors: [p1?.requiredConcept ?? jsonTopic.title],
                stripPhrases: [],
                missingHint: "the core mechanism"
            )
            
            // Rule 2: The PARAKH Rule evaluates the Application (expected_examples)
            let parakhRule = PillarRule(
                groups: [ConceptGroup(label: "Real-World Application", terms: extractedExamples)],
                minGroups: 1,
                anchors: extractedExamples, // Sets the examples as semantic anchors
                stripPhrases: [],
                missingHint: p1?.gapQuestion ?? "a real-world example"
            )
            
            return NCERTTopic(
                className: cleanGrade,
                subject: cleanSubject,
                chapter: chapterData.chapterName,
                title: jsonTopic.title,
                prompt: p1?.gapQuestion ?? "Explain \(jsonTopic.title).",
                coreIdeaIB: p1?.requiredConcept ?? "",
                causeEffectParakh: p1?.successMessage ?? "",
                samplePassAnswer: p1?.successMessage ?? "Complete accurate explanation covering all required pillars.",
                sampleIncompleteAnswer: p1?.requiredConcept ?? "Partial explanation.",
                sampleParakhOnlyAnswer: extractedExamples.joined(separator: ", "),
                ib: ibRule,
                parakh: parakhRule
            )
        }
    }
    
    /// Loads all 10 standard NCERT curriculum topics from topics_curriculum.json
    static func loadAllCurriculumTopics() -> [NCERTTopic] {
        if let url = Bundle.main.url(forResource: "topics_curriculum", withExtension: "json") ?? Bundle(for: DeterministicStorageBridge.self).url(forResource: "topics_curriculum", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let topics = try? JSONDecoder().decode([NCERTTopic].self, from: data),
           !topics.isEmpty {
            return topics
        }
        return sampleChapter
    }
    
    // Fallback sample data (Your 10 detailed concepts)
    static let sampleChapter: [NCERTTopic] = [
        // 1. Money and Credit -> Double Coincidence of Wants
        NCERTTopic(
            className: "Class 10",
            subject: "Social Science",
            chapter: "Money and Credit",
            title: "Double Coincidence of Wants",
            prompt: "Radio check: Explain why trading goods directly without money is difficult, and how money solves it.",
            coreIdeaIB: "In a direct trade (barter), both people must simultaneously want the exact item the other person is offering.",
            causeEffectParakh: "Because finding a two-way match is hard, money acts as an intermediate medium of exchange so anyone can buy or sell freely.",
            samplePassAnswer: "If I have extra shoes and want apples, the apple seller must also want my shoes at the same time or we can't trade. Money solves this because I can sell my shoes for cash and buy apples from anyone.",
            sampleIncompleteAnswer: "If I have extra shoes and want apples, the apple seller must also want my shoes at the same time or we can't trade.",
            sampleParakhOnlyAnswer: "Money acts as an easy medium of exchange in the middle so I can sell my goods for cash and buy whatever I need from anyone.",
            ib: PillarRule(
                groups: [
                    ConceptGroup(label: "that each person wants or needs a specific item", terms: ["want", "need", "desire", "willing", "wish", "demand", "require"]),
                    ConceptGroup(label: "that both parties must want each other's goods at the same time", terms: ["both", "each other", "other person", "mutual", "same time", "simultaneously", "double coincidence"]),
                    ConceptGroup(label: "that direct barter gets stuck or fails without that match", terms: ["cannot", "stuck", "difficult", "hard", "unless", "fail", "impossible"])
                ],
                minGroups: 3,
                anchors: ["Both parties have to agree to sell and buy each other's commodities at the same time."],
                stripPhrases: ["trading goods directly without money is difficult"],
                missingHint: "why direct barter gets stuck"
            ),
            parakh: PillarRule(
                groups: [
                    ConceptGroup(label: "using money or cash as a medium of exchange", terms: ["money", "cash", "currency", "rupee", "medium", "intermediate"]),
                    ConceptGroup(label: "being able to sell your goods for cash and buy from anyone", terms: ["sell", "buy", "anyone", "purchase", "exchange", "freely"])
                ],
                minGroups: 2,
                anchors: ["Money acts as an intermediate step and medium of exchange."],
                stripPhrases: ["without money", "no money"],
                missingHint: "how money solves this"
            )
        )
        // Add additional sample topics if needed
    ]
}
