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
