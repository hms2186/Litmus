//
//  FeynmanContracts.swift
//  Feynman Tutor Engine - Antigravity Production Specification
//
//  Strict Data Interchange Contracts conforming to PARAKH Competency v1.2.
//

import Foundation

// MARK: - Root Curriculum Contract (schemaVersion 4)
// Percentage scoring was removed: the JSON "scoring" block is ignored on decode.
struct FeynmanCurriculum: Codable, Sendable {
    let schemaVersion: Int
    let framework: String
    let gradeLevel: String
    let subject: String
    let chapterName: String
    let sourceStatus: String
    let articulationChecks: [ArticulationCheck]
    let chapterVocabulary: [String]
    let topics: [FeynmanTopic]
}

// Articulation checks share the boolean check shape: id, criterion, isRequired.
typealias ArticulationCheck = FeynmanCheck

// MARK: - Topic & Concept Breakdown
struct FeynmanTopic: Codable, Sendable {
    let topicId: String
    let title: String
    let concepts: [FeynmanConcept]
}

struct FeynmanConcept: Codable, Sendable {
    let conceptId: String
    let label: String
    let headingType: String?
    let sourcePages: [Int]

    // AI Grading Logic
    let keyPoints: [FeynmanKeyPoint]
    let causeChain: String
    let causeLinks: [FeynmanCauseLink]
    let acceptedExamples: [String]
    let extraExamplesOk: [String]
    let misconceptions: [FeynmanMisconception]

    // UI & Pedagogy Presentation
    let cardText: String
    let hint: String
    let probe: String
    let verify: [FeynmanVerifyEntry]

    /// Every keyPoint check, in curriculum order.
    var allChecks: [FeynmanCheck] {
        keyPoints.flatMap { $0.assessment.checks }
    }
}

/// A boolean check that the student connected two facts (cause -> effect).
struct FeynmanCauseLink: Codable, Sendable {
    let id: String
    let linksChecks: [String]
    let criterion: String
    let isRequired: Bool
}

struct FeynmanMisconception: Codable, Sendable {
    let id: String
    let wrong: String
    let fix: String
}

/// Source traceability: the NCERT page and quote that support one or more keyPoints.
struct FeynmanVerifyEntry: Codable, Sendable {
    let page: Int
    let quote: String
    let supports: [String]
}

// MARK: - Atomic Grading Criteria (The Hybrid Core)
struct FeynmanKeyPoint: Codable, Sendable {
    let id: String
    let weight: Int
    let text: String
    let assessment: FeynmanAssessment
}

struct FeynmanAssessment: Codable, Sendable {
    let requiredEvidence: [String]
    /// "allRequired", "anyOf" or "minCount:N"
    let passRule: String
    let checks: [FeynmanCheck]
    let misconceptionIds: [String]?
}

struct FeynmanCheck: Codable, Sendable {
    let id: String
    let criterion: String
    let isRequired: Bool
}

// MARK: - Qualitative Feedback Output (UI)
/// The three strings the feedback panel renders. An empty string means "nothing to show".
public struct FeedbackReport: Equatable, Sendable {
    public let missing: String
    public let vague: String
    public let right: String

    public init(missing: String, vague: String, right: String) {
        self.missing = missing
        self.vague = vague
        self.right = right
    }
}

// MARK: - Core Pipeline Input: session_input.json

public struct SystemContext: Codable, Equatable, Sendable {
    public let studentId: String
    public let gradeLevel: Int
    public let conceptTopic: String
    public let frameworkStandard: String
    
    public init(
        studentId: String = "STU_10948",
        gradeLevel: Int = 8,
        conceptTopic: String,
        frameworkStandard: String = "PARAKH_Competency_v1.2"
    ) {
        self.studentId = studentId
        self.gradeLevel = gradeLevel
        self.conceptTopic = conceptTopic
        self.frameworkStandard = frameworkStandard
    }
}

public struct LinguisticTelemetry: Codable, Equatable, Sendable {
    public let nounToVerbRatio: Double
    public let semanticSimilarityToAnalogy: Double
    public let semanticSimilarityToTextbook: Double
    public let isKeywordStuffingSuspected: Bool
    
    // Enhanced PARAKH Dual-Pillar Metrics (from the Litmus integration)
    public var pillar1Passed: Bool?
    public var pillar2Passed: Bool?
    public var continuousScore: Int?
    
    public init(
        nounToVerbRatio: Double,
        semanticSimilarityToAnalogy: Double,
        semanticSimilarityToTextbook: Double,
        isKeywordStuffingSuspected: Bool,
        pillar1Passed: Bool? = nil,
        pillar2Passed: Bool? = nil,
        continuousScore: Int? = nil
    ) {
        self.nounToVerbRatio = nounToVerbRatio
        self.semanticSimilarityToAnalogy = semanticSimilarityToAnalogy
        self.semanticSimilarityToTextbook = semanticSimilarityToTextbook
        self.isKeywordStuffingSuspected = isKeywordStuffingSuspected
        self.pillar1Passed = pillar1Passed
        self.pillar2Passed = pillar2Passed
        self.continuousScore = continuousScore
    }
}

public struct SessionPayload: Codable, Equatable, Sendable {
    public let rawTranscript: String
    
    public init(rawTranscript: String) {
        self.rawTranscript = rawTranscript
    }
}

public struct SessionInput: Codable, Equatable, Sendable {
    public let systemContext: SystemContext
    public let linguisticTelemetry: LinguisticTelemetry
    public let payload: SessionPayload
    
    public init(
        systemContext: SystemContext,
        linguisticTelemetry: LinguisticTelemetry,
        payload: SessionPayload
    ) {
        self.systemContext = systemContext
        self.linguisticTelemetry = linguisticTelemetry
        self.payload = payload
    }
    
    public func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    
    public func toJSONString() throws -> String {
        let data = try toJSONData()
        guard let str = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "FeynmanContracts", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode UTF-8 string"])
        }
        return str
    }
    
    public static func fromJSONData(_ data: Data) throws -> SessionInput {
        let decoder = JSONDecoder()
        return try decoder.decode(SessionInput.self, from: data)
    }
}

// MARK: - Core Pipeline Output: evaluation_output.json

public enum ConceptualClarityTier: String, Codable, Sendable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
}

public struct ParakhAssessment: Codable, Equatable, Sendable {
    public var conceptualClarity: ConceptualClarityTier
    public var roteLearningDetected: Bool
    public var evaluationTelemetrySummary: String
    
    // Continuous Clarity Score (0-100%) for UI speedometers, dials, & video triggers
    public var clarityScore: Int?
    
    public init(
        conceptualClarity: ConceptualClarityTier,
        roteLearningDetected: Bool,
        evaluationTelemetrySummary: String,
        clarityScore: Int? = nil
    ) {
        self.conceptualClarity = conceptualClarity
        self.roteLearningDetected = roteLearningDetected
        self.evaluationTelemetrySummary = evaluationTelemetrySummary
        self.clarityScore = clarityScore
    }
}

public struct FeynmanAnalysis: Codable, Equatable, Sendable {
    public var feynmanGapExplanation: String
    public var nextGuidingQuestion: String
    
    public init(
        feynmanGapExplanation: String,
        nextGuidingQuestion: String
    ) {
        self.feynmanGapExplanation = feynmanGapExplanation
        self.nextGuidingQuestion = nextGuidingQuestion
    }
}

public struct EvaluationOutput: Codable, Equatable, Sendable {
    public var parakhAssessment: ParakhAssessment
    public var feynmanAnalysis: FeynmanAnalysis
    
    public init(
        parakhAssessment: ParakhAssessment,
        feynmanAnalysis: FeynmanAnalysis
    ) {
        self.parakhAssessment = parakhAssessment
        self.feynmanAnalysis = feynmanAnalysis
    }
    
    public func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    
    public func toJSONString() throws -> String {
        let data = try toJSONData()
        guard let str = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "FeynmanContracts", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode UTF-8 string"])
        }
        return str
    }
    
    public static func fromJSONData(_ data: Data) throws -> EvaluationOutput {
        let decoder = JSONDecoder()
        return try decoder.decode(EvaluationOutput.self, from: data)
    }
}
