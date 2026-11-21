//
//  TranscriptCleaner.swift
//  Speech recognisers hear the topic's own words wrongly ("Photo-industrialization" for "proto-industrialisation",
//  "pheasants" for "peasants"), and the model then cannot tell whether the student defined the term, so a correct spoken
//  answer lands on the review screen while the same words typed pass. This puts such near-misses back to the term the
//  chapter itself uses, before grading. It only ever changes a word to a word of this chapter's compiled vocabulary, and
//  only when the two are one or two letters apart; everything else the student said is left as it was.
//

import Foundation

nonisolated enum TranscriptCleaner {

    /// The words of the concept's label, its evidence phrases and the chapter vocabulary (lowercased, 5+ letters).
    static func terms(concept: CompiledConcept, vocabulary: [String]) -> Set<String> {
        var phrases = vocabulary + concept.keyPoints.flatMap(\.requiredEvidence) + [concept.label]
        phrases += concept.misconceptions.map(\.wrong)
        var result = Set<String>()
        for phrase in phrases {
            for raw in phrase.lowercased().split(whereSeparator: { $0.isWhitespace }) {
                let word = raw.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "-")))
                if word.count >= 5 { result.insert(word) }
            }
        }
        return result
    }

    private static let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
                                   "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth",
                                   "eighteenth", "nineteenth", "twentieth"]

    /// "17th" -> "seventeenth": recognisers write ordinals as digits, the textbook (and its checks) spell them out.
    static func spellOutOrdinals(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})(?:st|nd|rd|th)\b"#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let digits = Range(match.range(at: 1), in: text),
                  let n = Int(text[digits]), (1...20).contains(n) else { continue }
            result.replaceSubrange(whole, with: ordinals[n - 1])
        }
        return result
    }

    static func clean(_ text: String, concept: CompiledConcept, vocabulary: [String]) -> String {
        let text = spellOutOrdinals(text)
        let known = terms(concept: concept, vocabulary: vocabulary)
        guard !known.isEmpty else { return text }
        let byFirstLetter = Dictionary(grouping: known, by: { $0.first! })
        var out: [String] = []
        for piece in text.split(separator: " ", omittingEmptySubsequences: false) {
            out.append(snap(String(piece), known: known, byFirstLetter: byFirstLetter))
        }
        return out.joined(separator: " ")
    }

    private static func snap(_ piece: String, known: Set<String>, byFirstLetter: [Character: [String]]) -> String {
        // Keep the punctuation around the word
        let letters = CharacterSet.letters.union(CharacterSet(charactersIn: "-"))
        guard let start = piece.firstIndex(where: { $0.unicodeScalars.allSatisfy(letters.contains) }),
              let end = piece.lastIndex(where: { $0.unicodeScalars.allSatisfy(letters.contains) }), start <= end else { return piece }
        let prefix = String(piece[..<start]), core = String(piece[start...end]), suffix = String(piece[piece.index(after: end)...])
        let lower = core.lowercased()
        guard lower.count >= 6, !known.contains(lower), let first = lower.first, let candidates = byFirstLetter[first] else { return piece }
        let allowed = lower.count >= 12 ? 2 : (lower.count >= 8 ? 1 : 1)
        var best: (term: String, distance: Int)?
        for term in candidates where abs(term.count - lower.count) <= 2 {
            let d = distance(spelling(lower), spelling(term))
            if d <= allowed, d < (best?.distance ?? Int.max) { best = (term, d) }
        }
        guard let match = best else { return piece }
        let replaced = core.first?.isUppercase == true ? match.term.prefix(1).uppercased() + match.term.dropFirst() : match.term
        return prefix + replaced + suffix
    }

    /// "industrialization" and "industrialisation" are the same word here.
    private static func spelling(_ word: String) -> String {
        word.replacingOccurrences(of: "ization", with: "isation").replacingOccurrences(of: "ize", with: "ise")
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[y.count]
    }
}
