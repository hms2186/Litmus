//
//  F1FlashcardLibrary.swift
//  Flashcards for the Revise, Study Deck and Flashcards screens.
//
//  A card comes from the topic's own curriculum text: schema 4 concepts use their NCERT card text
//  and misconception fixes; the other Class 10 science topics use their curated cards, which carry the
//  NCERT textbook diagrams stored in the asset catalog.
//

import Foundation

struct F1DeckCard: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    /// An NCERT textbook diagram from the asset catalog, when the card has one.
    let imageName: String?
    /// "Key pitfall to avoid", shown from the bulb on the Revise screen.
    let pitfall: String?
    /// Key terms of the topic, shown in bold gold in the text.
    var keywords: [String] = []
}

/// The Class 9 Social Science textbook comes in two parts.
enum F1SocialPart: String, CaseIterable, Identifiable {
    case one = "Part 1", two = "Part 2"
    var id: String { rawValue }
}

/// The four books of the Class 10 Social Science course.
enum F1SocialBranch: String, CaseIterable, Identifiable {
    case history = "History", geography = "Geography", civics = "Civics", economics = "Economics"
    var id: String { rawValue }

    /// Whether a curriculum subject ("Civics" is filed as "Political Science" in some files) belongs to this book.
    func contains(subject: String) -> Bool {
        let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .civics: return s == "Civics" || s == "Political Science"
        default: return s == rawValue
        }
    }
}

struct F1DeckChapter: Identifiable, Hashable {
    let id: String
    let title: String
    let subject: String
    let cards: [F1DeckCard]

    /// The chapter's cover picture when it has one of its own, else the first diagram in the chapter.
    var coverImage: String? { Self.covers[title] ?? cards.first(where: { $0.imageName != nil })?.imageName }

    /// Which cover (in Assets, `cover_…`) belongs to which Class 9 Science chapter.
    private static let covers: [String: String] = [
        "Exploration: Entering the World of Secondary Science": "cover_ch1",
        "Cell: The Building Block of Life": "cover_ch2",
        "Tissues in Action": "cover_ch3",
        "Describing Motion Around Us": "cover_ch4",
        "Exploring Mixtures and their Separation": "cover_ch5",
        "How Forces Affect Motion": "cover_ch6",
        "Work, Energy, and Simple Machines": "cover_ch7",
        "Journey Inside the Atom": "cover_ch8",
        "Atomic Foundations of Matter": "cover_ch9",
        "Sound Waves: Characteristics and Applications": "cover_ch10",
        "Reproduction: How Life Continues": "cover_ch11",
        "Patterns in Life: Diversity and Classification": "cover_ch12",
        "Earth as a System: Energy, Matter, and Life": "cover_ch13",
        "Chemical Reactions and Equations": "cover_c10_ch1",
        "Acids, Bases and Salts": "cover_c10_ch2",
        "Metals and Non-metals": "cover_c10_ch3",
        "Carbon and its Compounds": "cover_c10_ch4",
        "Life Processes": "cover_c10_ch5",
        "Control and Coordination": "cover_c10_ch6",
        "How do Organisms Reproduce?": "cover_c10_ch7",
        "Heredity": "cover_c10_ch8",
        "Light – Reflection and Refraction": "cover_c10_ch9",
        "The Human Eye and the Colourful World": "cover_c10_ch10",
        "Electricity": "cover_c10_ch11",
        "Magnetic Effects of Electric Current": "cover_c10_ch12",
        "Our Environment": "cover_c10_ch13",
        // Class 9 Social Science
        "Understanding Social Science": "cover_ss9_ch1",
        "Shaping of the Earth’s Surface": "cover_ss9_ch2",
        "Atmosphere and Climate": "cover_ss9_ch3",
        "Early Humans and Beginning of Civilisation": "cover_ss9_ch4",
        "State and Society up to 1000 CE": "cover_ss9_ch5",
        "Democracy": "cover_ss9_ch6",
        "Elections": "cover_ss9_ch7",
        "Building Blocks in Economics: The Problem of Choice": "cover_ss9_ch8",
        "Market and Prices": "cover_ss9_ch9",
        // Class 9 Social Science, Part 2
        "Oceans and Life": "cover_ss2_ch1",
        "Life on Earth": "cover_ss2_ch2",
        "Resistance and Resilience (1000–1700 CE)": "cover_ss2_ch3",
        "Governance and Public Policy": "cover_ss2_ch4",
        "Managing Your Personal Finances": "cover_ss2_ch5",
        "From Ideas to Startups": "cover_ss2_ch6",
        // Class 10 Social Science
        "Resources and Development": "cover_ss10_geo_ch1",
        "Forest and Wildlife Resources": "cover_ss10_geo_ch2",
        "Water Resources": "cover_ss10_geo_ch3",
        "Agriculture": "cover_ss10_geo_ch4",
        "Minerals and Energy Resources": "cover_ss10_geo_ch5",
        "Manufacturing Industries": "cover_ss10_geo_ch6",
        "Lifelines of National Economy": "cover_ss10_geo_ch7",
        "The Rise of Nationalism in Europe": "cover_ss10_his_ch1",
        "Nationalism in India": "cover_ss10_his_ch2",
        "The Making of a Global World": "cover_ss10_his_ch3",
        "The Age of Industrialisation": "cover_ss10_his_ch4",
        "Print Culture and the Modern World": "cover_ss10_his_ch5",
        "Development": "cover_ss10_eco_ch1",
        "Sectors of the Indian Economy": "cover_ss10_eco_ch2",
        "Money and Credit": "cover_ss10_eco_ch3",
        "Globalisation and the Indian Economy": "cover_ss10_eco_ch4",
        "Consumer Rights": "cover_ss10_eco_ch5",
        "Power-sharing": "cover_ss10_civ_ch1",
        "Federalism": "cover_ss10_civ_ch2",
        "Gender, Religion and Caste": "cover_ss10_civ_ch3",
        "Political Parties": "cover_ss10_civ_ch4",
        "Outcomes of Democracy": "cover_ss10_civ_ch5"
    ]

    /// The six chapters of the Class 9 Social Science book, Part 2, in textbook order.
    static let socialPart2: [String] = [
        "Oceans and Life", "Life on Earth", "Resistance and Resilience (1000–1700 CE)",
        "Governance and Public Policy", "Managing Your Personal Finances", "From Ideas to Startups"
    ]

    /// Where a Social Science chapter sits in the textbook: Part 1 chapters by the number on their cover, then Part 2 in its own order.
    static func bookOrder(_ chapterTitle: String) -> Int {
        if let index = socialPart2.firstIndex(of: chapterTitle) { return 200 + index }
        guard let cover = covers[chapterTitle], cover.hasPrefix("cover_ss9_ch"), let number = Int(cover.dropFirst("cover_ss9_ch".count)) else { return 100 }
        return number
    }

    /// Whether the chapter is in the chosen part of the Class 9 Social Science book.
    static func isInPart(_ chapterTitle: String, part: F1SocialPart) -> Bool {
        (bookOrder(chapterTitle) >= 200) == (part == .two)
    }

    /// The cover is a finished picture with the chapter's name on it.
    var coverHasTitle: Bool { Self.covers[title] != nil }
    static func coverHasTitle(_ chapterTitle: String) -> Bool { covers[chapterTitle] != nil }
}

@MainActor
enum F1FlashcardLibrary {

    static func isInPart(_ chapterTitle: String, part: F1SocialPart) -> Bool {
        F1DeckChapter.isInPart(chapterTitle, part: part)
    }

    /// The Class 10 Social Science book a chapter is in.
    static func branch(of chapterTitle: String, grade: String = "Class 10") -> F1SocialBranch? {
        guard let chapter = CurriculumCatalog.shared.allChapters.first(where: { $0.chapterName == chapterTitle && $0.normalizedGrade == grade }) else { return nil }
        return F1SocialBranch.allCases.first { $0.contains(subject: chapter.subject) }
    }

    static func cards(for topic: NCERTTopic) -> [F1DeckCard] {
        let terms = keywords(for: topic)
        if let concept = CompiledCurriculumStore.shared.entry(forLabel: topic.title)?.concept {
            // Every topic has a key pitfall: the curriculum's own misconception, else the question the topic is checked on
            let pitfall = concept.misconceptions.first.map { "\($0.wrong) — \($0.fix)" }
                ?? "Don't just repeat the card: explain it in your own words with an example. \(concept.probe)"
            // The textbook diagrams of the concept: the first on its own card, each other on a card of its own
            let diagrams = F1ConceptDiagrams.diagrams(for: concept.conceptId)
            var cards = [F1DeckCard(id: concept.conceptId, title: concept.label, body: concept.cardText, imageName: diagrams.first?.image, pitfall: pitfall, keywords: terms)]
            for (index, diagram) in diagrams.dropFirst().enumerated() {
                cards.append(F1DeckCard(id: "\(concept.conceptId)#fig\(index + 2)", title: diagram.title, body: diagram.note, imageName: diagram.image, pitfall: pitfall, keywords: terms))
            }
            return cards
        }
        let set = ConceptEvaluator.dualPillarCards(for: topic.title, topicObject: topic)
        let pitfall = "Don't stop at the definition. Be ready to answer: \(topic.prompt.replacingOccurrences(of: "Radio check: ", with: ""))"
        return set.allCards.enumerated().map { index, card in
            F1DeckCard(id: "\(topic.id)#\(index)", title: card.title, body: card.content, imageName: card.imageName, pitfall: pitfall,
                       keywords: terms + derivedTerms(title: card.title, body: card.content))
        }
    }

    /// Terms the curriculum lists don't cover: the card title's own words and the long technical words in the text.
    private static func derivedTerms(title: String, body: String) -> [String] {
        let skip: Set<String> = ["through", "because", "between", "during", "together", "multicellular", "environment", "temporary", "extensions", "impossible"]
        func words(_ text: String) -> [String] {
            text.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 5 }
        }
        let fromTitle = words(title)
        let fromBody = words(body).filter { $0.count >= 9 && !skip.contains($0.lowercased()) }
        var seen = Set<String>()
        return (fromTitle + fromBody).filter { seen.insert($0.lowercased()).inserted }.prefix(12).map { $0 }
    }

    /// The topic's key terms: the evidence phrases the engine looks for, or the curriculum's own term lists.
    static func keywords(for topic: NCERTTopic) -> [String] {
        var raw: [String]
        if let entry = CompiledCurriculumStore.shared.entry(forLabel: topic.title) {
            raw = entry.concept.keyPoints.flatMap(\.requiredEvidence) + entry.chapter.chapterVocabulary
        } else {
            raw = (topic.ib.groups + topic.parakh.groups).flatMap(\.terms)
        }
        var seen = Set<String>()
        return raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && seen.insert($0.lowercased()).inserted }
            .sorted { $0.count > $1.count }           // longest first, so a phrase wins over its words
            .prefix(40).map { $0 }
    }

    /// Chapters for the Study Deck. `subject` is "Science" or "Social Science".
    private static var chapterCache: [String: [F1DeckChapter]] = [:]

    /// Built once per subject and grade: it reads the whole curriculum, so it is kept after the first time.
    static func chapters(subject: String, grade: String) -> [F1DeckChapter] {
        let key = subject + "|" + grade
        if let cached = chapterCache[key] { return cached }
        let built = buildChapters(subject: subject, grade: grade)
        chapterCache[key] = built
        return built
    }

    private static func buildChapters(subject: String, grade: String) -> [F1DeckChapter] {
        let catalog = CurriculumCatalog.shared
        var seen = Set<String>()
        let source: [ChapterData]
        if subject == "Science" {
            source = catalog.chapters(forGrade: grade, subject: "Science")
        } else {
            source = catalog.socialBranches.flatMap { catalog.chapters(forGrade: grade, subject: "Social Science", branch: $0) }
        }
        return source
            .filter { seen.insert($0.chapterName).inserted }
            .enumerated()
            .sorted { (a, b) in
                let x = F1DeckChapter.bookOrder(a.element.chapterName), y = F1DeckChapter.bookOrder(b.element.chapterName)
                return x == y ? a.offset < b.offset : x < y
            }
            .map(\.element)
            .map { chapter in
                let cards = catalog.topics(forChapter: chapter).flatMap { cards(for: $0) }
                return F1DeckChapter(id: "\(grade)-\(chapter.chapterName)", title: chapter.chapterName, subject: subject, cards: cards)
            }
            .filter { !$0.cards.isEmpty }
    }
}
