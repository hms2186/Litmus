//
//  DeterministicStorageBridge.swift
//  Feynman Tutor Engine - Layer 3 (Deterministic Storage Bridge)
//
//  Serializes and packages exact JSON contract files into the local
//  app file sandbox (session_input.json / evaluation_output.json).
//

import Foundation

public final class DeterministicStorageBridge: @unchecked Sendable {
    
    public static let shared = DeterministicStorageBridge()
    
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    
    public init(customDirectory: URL? = nil) {
        if let custom = customDirectory {
            self.baseDirectory = custom
        } else {
            // Use Application Support or Documents directory within the App Sandbox
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let base = paths.first ?? FileManager.default.temporaryDirectory
            self.baseDirectory = base.appendingPathComponent("FeynmanSandbox", isDirectory: true)
        }
        
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
    
    public var sandboxDirectoryURL: URL {
        return baseDirectory
    }
    
    // MARK: - session_input.json Serialization
    @discardableResult
    public func saveSessionInput(
        _ input: SessionInput,
        fileName: String = "session_input.json"
    ) throws -> URL {
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        let data = try input.toJSONData()
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }
    
    public func loadSessionInput(
        fileName: String = "session_input.json"
    ) throws -> SessionInput {
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw NSError(
                domain: "DeterministicStorageBridge",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "File not found: \(fileURL.path)"]
            )
        }
        let data = try Data(contentsOf: fileURL)
        return try SessionInput.fromJSONData(data)
    }
    
    // MARK: - evaluation_output.json Serialization
    @discardableResult
    public func saveEvaluationOutput(
        _ output: EvaluationOutput,
        fileName: String = "evaluation_output.json"
    ) throws -> URL {
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        let data = try output.toJSONData()
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }
    
    public func loadEvaluationOutput(
        fileName: String = "evaluation_output.json"
    ) throws -> EvaluationOutput {
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw NSError(
                domain: "DeterministicStorageBridge",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "File not found: \(fileURL.path)"]
            )
        }
        let data = try Data(contentsOf: fileURL)
        return try EvaluationOutput.fromJSONData(data)
    }
    
    // MARK: - Package Pipeline Helper
    public func packageSession(
        studentId: String,
        gradeLevel: Int,
        conceptTopic: String,
        frameworkStandard: String = "PARAKH_Competency_v1.2",
        telemetry: LinguisticTelemetry,
        rawTranscript: String
    ) throws -> SessionInput {
        let context = SystemContext(
            studentId: studentId,
            gradeLevel: gradeLevel,
            conceptTopic: conceptTopic,
            frameworkStandard: frameworkStandard
        )
        let payload = SessionPayload(rawTranscript: rawTranscript)
        let session = SessionInput(
            systemContext: context,
            linguisticTelemetry: telemetry,
            payload: payload
        )
        try saveSessionInput(session)
        return session
    }
}
