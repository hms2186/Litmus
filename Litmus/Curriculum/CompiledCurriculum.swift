//
//  CompiledCurriculum.swift
//  The chapter format written by Tools/compile_curriculum.py (Curriculum/compiled/*.compiled.json).
//  Architecture v4.0: the grading engine reads only compiled chapters, so roles, misconception
//  bindings, concept hashes and model batches are settled at build time, not at runtime.
//

import Foundation

nonisolated struct CompiledChapter: Codable, Sendable, Equatable {
    let compilerVersion: String
    let schemaVersion: Int
    let schemaRevision: Int
    let sourceFile: String
    let sourceSha256: String
    let reviewStatus: String
    let framework: String
    let gradeLevel: String
    let subject: String
    let book: String?
    let chapterNumber: Int?
    let chapterName: String
    let articulationChecks: [CompiledArticulationCheck]
    let chapterVocabulary: [String]
    let concepts: [CompiledConcept]
}

nonisolated struct CompiledArticulationCheck: Codable, Sendable, Equatable {
    let id: String
    let criterion: String
    let isRequired: Bool
    let gradedBy: String
}

nonisolated struct CompiledConcept: Codable, Sendable, Equatable {
    let conceptId: String
    let topicId: String
    let topicTitle: String
    let label: String
    let headingType: String?
    let sourcePages: [Int]
    /// SHA-256 of everything that affects grading; a saved Likely mastered answer is re-graded only
    /// while this still matches.
    let conceptHash: String
    let cardText: String
    let hint: String
    let probe: String
    let relevanceCheck: CompiledCriterion
    let keyPoints: [CompiledKeyPoint]
    let causeLinks: [CompiledCauseLink]
    let misconceptions: [CompiledMisconception]
    let weights: CompiledWeights
    let batches: CompiledBatches
}

nonisolated struct CompiledCriterion: Codable, Sendable, Equatable {
    let id: String
    let criterion: String
}

nonisolated enum KeyPointRole: String, Codable, Sendable {
    /// Scored, and must pass for mastery.
    case core
    /// Scored, but never blocks mastery on its own.
    case supporting
    /// Feedback only.
    case extra
}

nonisolated enum PassRule: Codable, Sendable, Equatable {
    case allRequired
    case anyOf
    case minCount(Int)

    private enum CodingKeys: String, CodingKey { case kind, n }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "allRequired": self = .allRequired
        case "anyOf": self = .anyOf
        case "minCount": self = .minCount(try container.decode(Int.self, forKey: .n))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown passRule kind \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allRequired: try container.encode("allRequired", forKey: .kind)
        case .anyOf: try container.encode("anyOf", forKey: .kind)
        case .minCount(let n):
            try container.encode("minCount", forKey: .kind)
            try container.encode(n, forKey: .n)
        }
    }
}

nonisolated enum LexicalPolicy: String, Codable, Sendable {
    /// The keyword fallback may return yes when it finds positive evidence.
    case evidence
    /// The keyword fallback always returns uncertain.
    case never
}

nonisolated struct CompiledKeyPoint: Codable, Sendable, Equatable {
    let id: String
    let role: KeyPointRole
    let weight: Int
    let scored: Bool
    let passRule: PassRule
    let followUp: String?
    let requiredEvidence: [String]
    let checks: [CompiledCheck]
    let misconceptionIds: [String]
}

nonisolated struct CompiledCheck: Codable, Sendable, Equatable {
    let id: String
    let criterion: String
    let isRequired: Bool
    let lexical: LexicalPolicy
    /// Already resolved by the compiler: the check's own follow-up, else its keyPoint's, else the
    /// concept hint. Never contains the answer.
    let followUp: String
}

nonisolated struct CompiledCauseLink: Codable, Sendable, Equatable {
    let id: String
    let linksChecks: [String]
    let criterion: String
    let isRequired: Bool
}

nonisolated struct CompiledMisconception: Codable, Sendable, Equatable {
    let id: String
    let wrong: String
    let fix: String
    /// mchk_<id>: the answer states the wrong idea.
    let checkId: String
    let checkCriterion: String
    /// mfix_<id>: a follow-up answer explicitly states the correct idea.
    let fixCheckId: String
    let fixCheckCriterion: String
    let keyPointIds: [String]
    /// Linked to a core keyPoint: must be ruled out by the model before Mastered.
    let isRequired: Bool
}

nonisolated struct CompiledWeights: Codable, Sendable, Equatable {
    let core: Int
    let scored: Int
}

nonisolated struct CompiledBatches: Codable, Sendable, Equatable {
    /// Relevance and misconception checks, graded with their own instructions (M0 decision D3).
    let topic: [[String]]
    /// Checks of core keyPoints, graded first.
    let a: [[String]]
    /// Supporting and extra keyPoint checks, then cause links.
    let b: [[String]]
}
