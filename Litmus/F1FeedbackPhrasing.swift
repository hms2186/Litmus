//
//  F1FeedbackPhrasing.swift
//  Turns the engine's check descriptions ("States that ...", "Defines X as ...") into sentences that
//  speak to the student: what they could still say, and what they already got right.
//

import Foundation

enum F1FeedbackPhrasing {

    private static let past: [String: String] = [
        "states": "stated", "explains": "explained", "defines": "defined", "describes": "described",
        "names": "named", "lists": "listed", "identifies": "identified", "gives": "gave",
        "connects": "connected", "says": "said", "mentions": "mentioned", "compares": "compared",
        "distinguishes": "distinguished", "recognises": "recognised", "relates": "related",
        "notes": "noted", "uses": "used", "shows": "showed", "links": "linked", "contrasts": "contrasted"
    ]

    private static func split(_ criterion: String) -> (verb: String, rest: String)? {
        let trimmed = criterion.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let space = trimmed.firstIndex(of: " ") else { return nil }
        let verb = String(trimmed[..<space])
        guard verb.lowercased().hasSuffix("s"), verb.first?.isUppercase == true else { return nil }
        return (verb, String(trimmed[trimmed.index(after: space)...]))
    }

    private static func baseForm(of verb: String) -> String {
        let v = verb.lowercased()
        if v.hasSuffix("ies") { return String(v.dropLast(3)) + "y" }
        for ending in ["shes", "ches", "sses", "xes"] where v.hasSuffix(ending) { return String(v.dropLast(2)) }
        return String(v.dropLast())
    }

    /// "States that force is a push" -> "Try to state that force is a push."
    static func missing(_ criterion: String) -> String {
        guard let (verb, rest) = split(criterion) else { return sentence(criterion) }
        return "Try to \(baseForm(of: verb)) \(rest)."
    }

    /// "States that force is a push" -> "You stated that force is a push."
    static func right(_ criterion: String) -> String {
        guard let (verb, rest) = split(criterion), let done = past[verb.lowercased()] else { return sentence(criterion) }
        return "You \(done) \(rest)."
    }

    /// A short note for the review list: the idea without its leading verb, kept to one line.
    static func shortNote(_ criterion: String) -> String {
        let text = split(criterion)?.rest ?? criterion
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let note = cleaned.hasPrefix("that ") ? String(cleaned.dropFirst(5)) : cleaned
        return note.count > 70 ? String(note.prefix(67)) + "…" : note
    }

    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        let capitalised = first.uppercased() + trimmed.dropFirst()
        return capitalised.hasSuffix(".") || capitalised.hasSuffix("?") || capitalised.hasSuffix("!") ? capitalised : capitalised + "."
    }

    /// The first item, plus how many more there are.
    static func summary(_ items: [String], phrase: (String) -> String, more noun: String) -> String {
        guard let first = items.first else { return "" }
        let extra = items.count - 1
        return phrase(first) + (extra > 0 ? " (and \(extra) more \(noun))" : "")
    }
}
