//
//  OnDeviceFlashcardGenerator.swift
//
//  Short revision cards for a topic, written by Apple's on-device model (FoundationModels) from the chapter's own
//  textbook passage. The model gets the passage as its only source and is told to answer in telegraph-style bullets.
//  Its reply is checked in code before it is shown: a key term or figure the passage does not contain is dropped, so
//  a card never cites something the textbook text does not. When the model is unavailable (Simulator, unsupported
//  hardware, Apple Intelligence off) or fails, the passage itself is cut into short single-line bullets instead.
//

import Foundation
import FoundationModels

// MARK: - What the model is asked to produce

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedCard {
    @Guide(description: "Short sub-topic title, at most 4 words.")
    var title: String

    @Guide(description: "Revision notes as 2 to 3 short bullet points, one per line, each starting with '• ' and at most 12 words. Use an arrow (→) for reactions, changes of state and colour changes. Use only facts stated in the passage.")
    var conciseContent: String

    @Guide(description: "1 to 3 core keywords copied from the passage, for highlighting.", .maximumCount(3))
    var keyTerms: [String]

    @Guide(description: "One short active-recall question that this card's notes answer.")
    var promptQuestion: String

    @Guide(description: "The textbook figure cited in the passage for this card, for example 'Fig 2.1: Reaction of zinc granules with dilute sulphuric acid'. Empty when the passage cites no figure for this card.")
    var figureReference: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedFlashcardDeck {
    @Guide(description: "2 to 4 cards that together cover the passage's main ideas, without repeating each other.", .maximumCount(4))
    var cards: [GeneratedCard]
}

// MARK: - Generator

@MainActor
public final class OnDeviceFlashcardGenerator {
    public static let shared = OnDeviceFlashcardGenerator()

    private init() {}

    /// The longest a bullet may be. A longer one is dropped or split at a clause, never cut off mid-sentence.
    nonisolated static let maxBulletCharacters = 140

    static let instructions = """
    You are an NCERT revision coach for Class 9 and 10 students. Turn the textbook passage you are given into short revision cards.
    Rules:
    - Use only facts that the passage states. Never add facts from elsewhere.
    - Never write a paragraph. Write telegraph-style bullets: 2 to 3 per card, at most 12 words each.
    - Use an arrow (→) for chemical reactions, changes of state and indicator colour changes.
    - Cite a textbook figure (for example "Fig 2.1: ...") only when the passage itself mentions that figure.
    - Give each card a short title and one question a student could answer from memory.
    """

    /// Cards for a topic from its textbook passage. `contextText` should be the chapter's compiled NCERT text for the topic.
    public func generateFlashcards(
        topic: String,
        contextText: String = "",
        subject: String = "SCIENCE",
        focus: [String] = []
    ) async -> [FlashcardItem] {
        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTopic = cleanTopic.isEmpty ? "this topic" : cleanTopic
        let passage = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !passage.isEmpty else { return [] }

        // The ideas the student missed (from the engine's report, which comes from the compiled curriculum). The student's own
        // transcript is deliberately not sent: it may hold wrong statements the cards must not repeat.
        let gaps = focus.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(4)
        let focusText = gaps.isEmpty ? "" : "\n\nThe student missed these ideas. Make the cards about them, using only the passage:\n" + gaps.map { "- \($0)" }.joined(separator: "\n")

        if #available(iOS 26.0, macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let session = LanguageModelSession(model: SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations),
                                                   instructions: Self.instructions)
                let prompt = "Subject: \(subject.capitalized)\nTopic: \(effectiveTopic)\n\nNCERT passage:\n\(passage)" + focusText
                let response = try await session.respond(to: prompt, generating: GeneratedFlashcardDeck.self,
                                                         options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 600))
                let cards = Self.items(from: response.content.cards, passage: passage, topic: effectiveTopic)
                if !cards.isEmpty { return cards }
            } catch {
                // Structured output keeps the default guardrails, which refuse passages about conflict or discrimination
                // (Civics chapters on Sri Lanka, Belgium, caste). Plain text allows the permissive setting, so try that.
                if let card = await plainCard(topic: effectiveTopic, passage: passage, subject: subject, focusText: focusText) {
                    let cards = Self.items(from: [card], passage: passage, topic: effectiveTopic)
                    if !cards.isEmpty { return cards }
                }
            }
        }
        return Self.fallbackCards(topic: effectiveTopic, passage: passage)
    }

    /// One card as plain text, parsed here. Used when structured output is refused.
    @available(iOS 26.0, macOS 26.0, *)
    private func plainCard(topic: String, passage: String, subject: String, focusText: String) async -> GeneratedCard? {
        let format = "\n\nReply in exactly this format and nothing else:\nTITLE: <at most 4 words>\n• <bullet, at most 12 words>\n• <bullet, at most 12 words>\n• <bullet, at most 12 words>\nTERMS: <1 to 3 keywords from the passage, comma separated>\nQUESTION: <one short recall question>\nFIGURE: <figure cited in the passage, or none>"
        do {
            let session = LanguageModelSession(model: SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations),
                                               instructions: Self.instructions + format)
            let prompt = "Subject: \(subject.capitalized)\nTopic: \(topic)\n\nNCERT passage:\n\(passage)" + focusText
            let reply = try await session.respond(to: prompt, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 300)).content
            return Self.parsePlainCard(reply)
        } catch {
            return nil
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    nonisolated static func parsePlainCard(_ reply: String) -> GeneratedCard? {
        var title = "", question = "", figure = "", terms: [String] = [], bullets: [String] = []
        for raw in reply.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            func value(_ key: String) -> String? {
                line.uppercased().hasPrefix(key) ? String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces) : nil
            }
            if let v = value("TITLE:") { title = v }
            else if let v = value("TERMS:") { terms = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            else if let v = value("QUESTION:") { question = v }
            else if let v = value("FIGURE:") { figure = v.lowercased() == "none" ? "" : v }
            else if line.hasPrefix("•") || line.hasPrefix("-") { bullets.append(line) }
        }
        guard !bullets.isEmpty else { return nil }
        return GeneratedCard(title: title, conciseContent: bullets.joined(separator: "\n"), keyTerms: terms,
                             promptQuestion: question, figureReference: figure)
    }

    // MARK: Checking the model's reply

    /// Cards from the model's reply, with anything the passage does not support removed.
    @available(iOS 26.0, macOS 26.0, *)
    static func items(from generated: [GeneratedCard], passage: String, topic: String) -> [FlashcardItem] {
        let passageText = passage.lowercased()
        let passageWords = Set(words(in: passage) + words(in: topic))
        var items: [FlashcardItem] = []
        for (index, card) in generated.enumerated() {
            // The model sometimes wraps bullets in brackets or puts several on one line: split on the bullet mark too
            let bullets = card.conciseContent
                .replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                .components(separatedBy: CharacterSet(charactersIn: "•\n"))
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-–→ \t.")) }
                .filter { !$0.isEmpty && $0.count <= maxBulletCharacters && isGrounded($0, in: passageWords) }
                .prefix(3)
                .map { "• " + $0 }
            guard !bullets.isEmpty else { continue }
            // A question about something the passage does not say would have no answer on the card
            let question = card.promptQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isGrounded(question, in: passageWords, minimum: 0.6) else { continue }

            // Only terms the passage really contains may be highlighted
            let terms = card.keyTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && passageText.contains($0.lowercased()) }

            var content = bullets.joined(separator: "\n")
            // A figure is shown only when the passage itself names that figure number
            let figure = card.figureReference.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = figureNumber(in: figure), passageText.contains(number) {
                content += "\n" + figure
            }

            let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(FlashcardItem(
                id: "gen_\(topic)_\(index)",
                title: title.isEmpty ? topic : String(title.split(separator: " ").prefix(4).joined(separator: " ")),
                content: content,
                highlightedTerms: Array(terms.prefix(3)),
                promptQuestion: question
            ))
        }
        return items
    }

    /// Lowercased words of 4 or more letters, and every number, with a plural "s" dropped.
    nonisolated static func words(in text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { $0.count >= 4 || $0.contains(where: \.isNumber) }
            .map { $0.count > 4 && $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0 }
    }

    /// True when most of the line's words and numbers appear in the passage. A model that invents a fact (a step, a
    /// number, a name) brings words the passage does not have, and the line is dropped instead of shown.
    nonisolated static func isGrounded(_ line: String, in passageWords: Set<String>, minimum: Double = 0.75) -> Bool {
        let wanted = words(in: line)
        guard !wanted.isEmpty else { return true }
        let found = wanted.filter { passageWords.contains($0) }.count
        return Double(found) / Double(wanted.count) >= minimum
    }

    /// "fig 2.1" from "Fig 2.1: Reaction of ...", or nil when no figure number is given.
    nonisolated static func figureNumber(in text: String) -> String? {
        guard let range = text.range(of: #"(?i)fig(?:ure)?\.?\s*\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        let found = String(text[range]).lowercased()
        let digits = found.drop { !$0.isNumber }
        return "\(digits)".isEmpty ? nil : String(digits)
    }

    // MARK: Fallback

    /// Short single-line bullets straight from the passage: its first sentences, each cut at a word boundary.
    static func fallbackCards(topic: String, passage: String) -> [FlashcardItem] {
        let tokenizer = NLTokenizerShim.sentences(passage)
        let bullets = tokenizer.flatMap(wholeLines).map { "• " + $0 }
        guard !bullets.isEmpty else { return [] }
        var cards: [FlashcardItem] = []
        var start = 0
        var number = 1
        while start < bullets.count, cards.count < 4 {
            let slice = bullets[start..<min(start + 3, bullets.count)]
            cards.append(FlashcardItem(
                id: "fallback_\(topic)_\(number)",
                title: number == 1 ? String(topic.split(separator: " ").prefix(4).joined(separator: " ")) : "Key points \(number)",
                content: slice.joined(separator: "\n"),
                highlightedTerms: [],
                promptQuestion: "Explain \(topic) in your own words."
            ))
            start += 3
            number += 1
        }
        return cards
    }

    /// A sentence as complete lines: whole when it fits, otherwise split after a semicolon or a ", which" / ", and" /
    /// ", but" so that every line is a full statement. Nothing is ever cut off with an ellipsis.
    nonisolated static func wholeLines(_ sentence: String) -> [String] {
        let trimmed = sentence.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t"))
        guard trimmed.count > maxBulletCharacters else { return [trimmed] }
        for separator in ["; ", ", which ", ", and ", ", but ", ", while ", ", so "] {
            if let range = trimmed.range(of: separator) {
                let head = String(trimmed[..<range.lowerBound])
                let tail = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if head.count >= 25, tail.count >= 25 {
                    let tailLine = separator.hasPrefix(",") ? tail.prefix(1).uppercased() + tail.dropFirst() : tail.prefix(1).uppercased() + tail.dropFirst()
                    return [head] + wholeLines(String(tailLine))
                }
            }
        }
        return [trimmed]
    }
}

import NaturalLanguage

/// Sentence splitting, kept apart so the rest of the file does not depend on NaturalLanguage.
nonisolated enum NLTokenizerShim {
    static func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 15 }
    }
}
