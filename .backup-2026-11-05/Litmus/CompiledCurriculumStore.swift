//
//  CompiledCurriculumStore.swift
//  Loads the compiled chapters (Litmus/Compiled/*.compiled.json, written by
//  Tools/compile_curriculum.py) from the app bundle. A file written by an unsupported compiler
//  version or schema revision is refused as a whole, so no chapter is ever half-understood.
//

import Foundation

nonisolated final class CompiledCurriculumStore: Sendable {

    static let shared = CompiledCurriculumStore(bundle: .main)

    /// Compiler versions this app can read: same major version.
    static let supportedCompilerMajor = 1
    static let supportedSchemaRevision = 1

    struct Entry: Sendable {
        let concept: CompiledConcept
        let chapter: CompiledChapter
    }

    /// Keyed by concept label, which is what the topic picker shows (labels are unique; the compiler checks).
    let entriesByLabel: [String: Entry]
    let entriesById: [String: Entry]
    /// File name and reason, for each file that was refused.
    let refused: [(file: String, reason: String)]

    convenience init(bundle: Bundle) {
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "json", subdirectory: "Compiled") ?? [])
        self.init(urls: urls.filter { $0.lastPathComponent.hasSuffix(".compiled.json") })
    }

    init(urls: [URL]) {
        var byLabel: [String: Entry] = [:]
        var byId: [String: Entry] = [:]
        var refused: [(String, String)] = []
        var seen = Set<String>()
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where seen.insert(url.lastPathComponent).inserted {
            let name = url.lastPathComponent
            do {
                let chapter = try JSONDecoder().decode(CompiledChapter.self, from: Data(contentsOf: url))
                if let reason = Self.unsupported(chapter) {
                    refused.append((name, reason))
                    continue
                }
                for concept in chapter.concepts {
                    let entry = Entry(concept: concept, chapter: chapter)
                    byLabel[concept.label] = entry
                    byId[concept.conceptId] = entry
                }
            } catch {
                refused.append((name, "could not be read: \(error.localizedDescription)"))
            }
        }
        entriesByLabel = byLabel
        entriesById = byId
        self.refused = refused
        #if DEBUG
        for (file, reason) in refused { print("⚠️ [CompiledCurriculumStore] Refused \(file): \(reason)") }
        #endif
    }

    func entry(forLabel label: String) -> Entry? { entriesByLabel[label] }

    static func unsupported(_ chapter: CompiledChapter) -> String? {
        let major = Int(chapter.compilerVersion.split(separator: ".").first ?? "") ?? -1
        if major != supportedCompilerMajor {
            return "compiler version \(chapter.compilerVersion) is not supported (this app reads \(supportedCompilerMajor).x)"
        }
        if chapter.schemaRevision != supportedSchemaRevision {
            return "schema revision \(chapter.schemaRevision) is not supported (this app reads \(supportedSchemaRevision))"
        }
        return nil
    }
}
