//
//  ShortCards.swift
//  The few-bullet text of each deck card. short_cards.json is made offline by Tools/short_cards/run.sh with the same
//  generator and checks the Explain screen uses (every bullet's words are found in the textbook passage). A concept
//  without an entry gets the first sentences of its passage cut to single lines, so a card is never the whole passage.
//

import Foundation

nonisolated struct ShortCard: Codable, Sendable {
    var bullets: [String]
    var terms: [String]
    var source: String
}

nonisolated enum ShortCards {
    static let all: [String: ShortCard] = {
        guard let url = Bundle.main.url(forResource: "short_cards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cards = try? JSONDecoder().decode([String: ShortCard].self, from: data) else { return [:] }
        return cards
    }()

    /// The card text, one bullet per sentence ending in a full stop (the deck reads and highlights it sentence by sentence),
    /// and the terms to highlight.
    static func text(conceptId: String, label: String, passage: String) -> (body: String, terms: [String]) {
        var bullets = all[conceptId]?.bullets ?? []
        let terms = all[conceptId]?.terms ?? []
        if bullets.isEmpty {
            // Whole sentences (a long one split at a clause), never cut off with an ellipsis
            bullets = Array(NLTokenizerShim.sentences(passage).flatMap(OnDeviceFlashcardGenerator.wholeLines).prefix(4))
        }
        let lines = bullets.map { line -> String in
            var text = line.trimmingCharacters(in: CharacterSet(charactersIn: "•- \t"))
            if let last = text.last, !".!?…".contains(last) { text += "." }
            return text
        }
        return (lines.isEmpty ? passage : lines.joined(separator: " "), terms)
    }
}
