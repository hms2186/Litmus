import Foundation
import SwiftUI
import Combine

// MARK: - Codable Models matching your JSON structure

struct ChapterData: Codable, Identifiable {
    var id: String { chapterName }
    let framework: String
    let gradeLevel: String
    let subject: String
    let chapterName: String
    let topics: [ChapterTopic]
    
    var normalizedGrade: String {
        gradeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var isScience: Bool {
        let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("Political") || s.contains("Social") {
            return false
        }
        return s.contains("Science")
    }
    
    var mainSubject: String {
        isScience ? "Science" : "Social Science"
    }
    
    var normalizedSubject: String {
        CurriculumLoader.normalizeSubject(subject)
    }
}

extension ChapterData {
    /// Presents a schema 4 chapter through the existing topic UI: one topic per concept.
    init(feynman curriculum: FeynmanCurriculum) {
        self.init(
            framework: curriculum.framework,
            gradeLevel: curriculum.gradeLevel,
            subject: curriculum.subject,
            chapterName: curriculum.chapterName,
            topics: curriculum.topics.flatMap(\.concepts).map { concept in
                ChapterTopic(
                    topicId: concept.conceptId,
                    title: concept.label,
                    pillars: [ChapterPillar(
                        requiredConcept: concept.cardText,
                        expected_examples: concept.acceptedExamples,
                        successMessage: concept.causeChain,
                        gapQuestion: concept.probe
                    )]
                )
            }
        )
    }
}

/// Schema 4 concepts, keyed by the topic title the UI shows (the concept label).
enum FeynmanConceptRegistry {
    struct Entry {
        let concept: FeynmanConcept
        let articulationChecks: [ArticulationCheck]
        let chapterVocabulary: [String]
    }

    private static var entries: [String: Entry] = [:]

    static func register(_ curriculum: FeynmanCurriculum) {
        for concept in curriculum.topics.flatMap(\.concepts) {
            entries[concept.label] = Entry(
                concept: concept,
                articulationChecks: curriculum.articulationChecks,
                chapterVocabulary: curriculum.chapterVocabulary
            )
        }
    }

    static func entry(forTopicTitle title: String) -> Entry? {
        entries[title]
    }
}

struct ChapterTopic: Codable, Identifiable {
    var id: String { topicId }
    let topicId: String
    let title: String
    let pillars: [ChapterPillar]
}

struct ChapterPillar: Codable {
    let requiredConcept: String
    let expected_examples: [String]? // Optional to support all chapter variations
    let successMessage: String
    let gapQuestion: String
    
    var examples: [String] {
        expected_examples ?? []
    }
}

// MARK: - Curriculum Loader Helper

class CurriculumLoader {
    
    /// Normalizes raw subject strings across curriculum variations
    static func normalizeSubject(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("Science (") || trimmed == "Science" {
            return "Science"
        }
        return trimmed
    }
    
    // List of your chapter JSON filenames (without the .json extension)
    static let chapterFiles = [
        
        // ==========================================
        // MARK: - CLASS 9 CURRICULUM
        // ==========================================
        
        // Science Class 9
        "ncert_science_9_ch1",
        "ncert_science_9_ch2",
        "ncert_science_9_ch3",
        "ncert_science_9_ch4",
        "ncert_science_9_ch5",
        "ncert_science_9_ch6",
        "ncert_science_9_ch7",
        "ncert_science_9_ch8",
        "ncert_science_9_ch9",
        "ncert_science_9_ch10",
        "ncert_science_9_ch11",
        "ncert_science_9_ch12",
        "ncert_science_9_ch13",
        
        // Social Science Class 9 (Part 1)
        "ncert_ss_9_ch1",
        "ncert_ss_9_ch2",
        "ncert_ss_9_ch3",
        "ncert_ss_9_ch4",
        "ncert_ss_9_ch5",
        "ncert_ss_9_ch6",
        "ncert_ss_9_ch7",
        "ncert_ss_9_ch8",
        "ncert_ss_9_ch9",
        
        // Social Science Class 9 (Part 2)
        "ncert_ss2_9_ch1",
        "ncert_ss2_9_ch2",
        "ncert_ss2_9_ch3",
        "ncert_ss2_9_ch4",
        "ncert_ss2_9_ch5",
        "ncert_ss2_9_ch6",

        // ==========================================
        // MARK: - CLASS 10 CURRICULUM
        // ==========================================
        
        // Science Class 10
        "ncert_science_10_ch1",
        "ncert_science_10_ch2",
        "ncert_science_10_ch3",
        "ncert_science_10_ch4",
        "ncert_science_10_ch5",
        "ncert_science_10_ch6",
        "ncert_science_10_ch7",
        "ncert_science_10_ch8",
        "ncert_science_10_ch9",
        "ncert_science_10_ch10",
        "ncert_science_10_ch11",
        "ncert_science_10_ch12",
        "ncert_science_10_ch13",
        
        // Civics Class 10
        "ncert_Civics_10_ch1",
        "ncert_Civics_10_ch2",
        "ncert_Civics_10_ch3",
        "ncert_Civics_10_ch4",
        "ncert_Civics_10_ch5",
        
        // Economics Class 10
        "ncert_Economics_10_ch1",
        "ncert_Economics_10_ch2",
        "ncert_Economics_10_ch3",
        "ncert_Economics_10_ch4",
        "ncert_Economics_10_ch5",
        
        // Geography Class 10
        "ncert_Geography_10_ch1",
        "ncert_Geography_10_ch2",
        "ncert_Geography_10_ch3",
        "ncert_Geography_10_ch4",
        "ncert_Geography_10_ch5",
        "ncert_Geography_10_ch6",
        "ncert_Geography_10_ch7",
        
        // History Class 10
        "ncert_History_10_ch1",
        "ncert_History_10_ch2",
        "ncert_History_10_ch3",
        "ncert_History_10_ch4",
        "ncert_History_10_ch5"
    ]
    
    /// Loads and decodes a specific chapter JSON file from the app bundle
    static func loadChapter(named filename: String) -> ChapterData? {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: filename, withExtension: "json") ??
                        Bundle(for: DeterministicStorageBridge.self).url(forResource: filename, withExtension: "json") else {
            print("❌ FILE NOT FOUND: \(filename).json is missing.")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let rawString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                print("⚠️ Could not decode string from \(filename)")
                return nil
            }
            
            // Clean markdown code blocks (```json ... ```) or comments before the root object
            guard let firstBrace = rawString.firstIndex(of: "{"),
                  let lastBrace = rawString.lastIndex(of: "}") else {
                print("⚠️ No root JSON braces found in \(filename)")
                return nil
            }
            
            let jsonSub = String(rawString[firstBrace...lastBrace])
            guard let cleanData = jsonSub.data(using: .utf8) else {
                return nil
            }
            
            // Schema 4 chapters (keyPoints + boolean checks) register their concepts for grading
            // and are shown in the UI as one topic per concept.
            if jsonSub.contains("\"keyPoints\"") {
                let curriculum = try JSONDecoder().decode(FeynmanCurriculum.self, from: cleanData)
                FeynmanConceptRegistry.register(curriculum)
                return ChapterData(feynman: curriculum)
            }

            let chapter = try JSONDecoder().decode(ChapterData.self, from: cleanData)
            return chapter
        } catch let DecodingError.keyNotFound(key, context) {
            print("⚠️ JSON SCHEMA ERROR in \(filename): Missing expected key '\(key.stringValue)'. Path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
        } catch let DecodingError.typeMismatch(type, context) {
            print("⚠️ JSON TYPE ERROR in \(filename): Expected \(type) but found something else. Path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
        } catch let DecodingError.dataCorrupted(context) {
            print("⚠️ JSON CORRUPTED in \(filename): Invalid JSON format. Details: \(context.debugDescription)")
        } catch {
            print("⚠️ UNKNOWN ERROR in \(filename): \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Loads all available chapters into an array
    static func loadAllChapters() -> [ChapterData] {
        return chapterFiles.compactMap { loadChapter(named: $0) }
    }
}

// MARK: - Central Curriculum Catalog & Dropdown Indexer

class CurriculumCatalog: ObservableObject {
    static let shared = CurriculumCatalog()
    
    @Published var allChapters: [ChapterData] = []
    @Published var grades: [String] = ["Class 10", "Class 9"]
    @Published var mainSubjects: [String] = ["Science", "Social Science"]
    @Published var socialBranches: [String] = ["History", "Political Science", "Geography", "Civics", "Economics"]
    
    private var topicsByChapterName: [String: [NCERTTopic]] = [:]
    private var allTopicsByTitle: [String: NCERTTopic] = [:]
    
    init() {
        loadData()
    }
    
    func loadData() {
        let loaded = CurriculumLoader.loadAllChapters()
        self.allChapters = loaded
        
        var chapterTopicsMap: [String: [NCERTTopic]] = [:]
        var titleMap: [String: NCERTTopic] = [:]
        
        for chapter in loaded {
            let grade = chapter.normalizedGrade.isEmpty ? "Class 10" : chapter.normalizedGrade
            let topics = NCERTTopic.topics(from: chapter, className: grade)
            chapterTopicsMap[chapter.chapterName] = topics
            for t in topics {
                titleMap[t.title] = t
            }
        }
        
        self.topicsByChapterName = chapterTopicsMap
        self.allTopicsByTitle = titleMap
    }
    
    /// Returns chapters filtered by Grade, Main Subject (Science / Social Science), and Social Science Branch
    func chapters(forGrade grade: String, subject: String, branch: String = "History") -> [ChapterData] {
        return allChapters.filter { ch in
            guard ch.normalizedGrade == grade else { return false }
            if subject == "Science" {
                return ch.isScience
            } else {
                guard !ch.isScience else { return false }
                let s = ch.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                if branch == "Civics" || branch == "Political Science" {
                    return s == "Civics" || s == "Political Science"
                } else if branch == "History" {
                    return s == "History" || s == "Social Science"
                } else if branch == "Geography" {
                    return s == "Geography"
                } else if branch == "Economics" {
                    return s == "Economics"
                }
                return false
            }
        }
    }
    
    /// Returns all topics for a given Chapter
    func topics(forChapter chapter: ChapterData) -> [NCERTTopic] {
        return topicsByChapterName[chapter.chapterName] ?? NCERTTopic.topics(from: chapter, className: chapter.normalizedGrade)
    }
    
    func topic(withTitle title: String) -> NCERTTopic? {
        if let direct = allTopicsByTitle[title] {
            return direct
        }
        let lower = title.lowercased()
        return allTopicsByTitle.first(where: { $0.key.lowercased().contains(lower) || lower.contains($0.key.lowercased()) })?.value
    }
}
