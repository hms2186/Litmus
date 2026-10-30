//
//  FeynmanTutorPipeline.swift
//  Feynman Tutor Engine - Unified Dual-Tier Validation Pipeline
//
//  Orchestrates Layers 1–5: Apple Speech/Text -> NaturalLanguage Guardrails ->
//  Deterministic Storage -> Cognitive Engine -> Presentation Layer.
//

import Foundation

public final class FeynmanTutorPipeline: Sendable {
    
    public static let shared = FeynmanTutorPipeline()
    
    private let guardrailLayer = ParakhGuardrailLayer.shared
    private let storageBridge = DeterministicStorageBridge.shared
    
    public init() {}
    
    // MARK: - Full End-to-End Evaluation Pipeline
    public func processEvaluation(
        studentId: String = "STU_10948",
        gradeLevel: Int = 8,
        conceptTopic: String,
        frameworkStandard: String = "PARAKH_Competency_v1.2",
        transcript: String
    ) async throws -> (input: SessionInput, output: EvaluationOutput) {
        
        // 1. Layer 2: Compute Guardrail Telemetry via Apple NaturalLanguage
        let telemetry = guardrailLayer.calculateTelemetry(
            transcript: transcript,
            conceptTopic: conceptTopic
        )
        
        // 2. Layer 3: Package & Serialize session_input.json to sandbox
        let session = try storageBridge.packageSession(
            studentId: studentId,
            gradeLevel: gradeLevel,
            conceptTopic: conceptTopic,
            frameworkStandard: frameworkStandard,
            telemetry: telemetry,
            rawTranscript: transcript
        )
        
        // 3. Layer 4: Deterministic PARAKH Matrix (chapters without schemaVersion 4 checks).
        // Schema 4 concepts go through ConceptEvaluator and FeynmanCognitiveEngine.evaluateChecklist.
        let evaluation = ParakhRubricMatrix.evaluate(session: session)
        
        // 4. Layer 3: Serialize evaluation_output.json to sandbox
        try storageBridge.saveEvaluationOutput(evaluation)
        
        return (session, evaluation)
    }
    
    // MARK: - Synchronous Evaluation for Unit Testing & Offline Verification
    public func evaluateSynchronously(
        studentId: String = "STU_10948",
        gradeLevel: Int = 8,
        conceptTopic: String,
        transcript: String
    ) -> (input: SessionInput, output: EvaluationOutput) {
        let telemetry = guardrailLayer.calculateTelemetry(
            transcript: transcript,
            conceptTopic: conceptTopic
        )
        let context = SystemContext(
            studentId: studentId,
            gradeLevel: gradeLevel,
            conceptTopic: conceptTopic,
            frameworkStandard: "PARAKH_Competency_v1.2"
        )
        let session = SessionInput(
            systemContext: context,
            linguisticTelemetry: telemetry,
            payload: SessionPayload(rawTranscript: transcript)
        )
        let output = ParakhRubricMatrix.evaluate(session: session)
        return (session, output)
    }
}
