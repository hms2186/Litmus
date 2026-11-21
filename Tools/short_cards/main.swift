// Precomputes the short revision card of every compiled concept with the app's own generator, so the Revise deck
// shows a few bullets instead of the whole textbook passage. Writes Litmus/short_cards.json, resumable.
import Foundation

public struct FlashcardItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: String, title: String, content: String, highlightedTerms: [String], promptQuestion: String
    public init(id: String, title: String, content: String, highlightedTerms: [String] = [], promptQuestion: String = "") {
        self.id = id; self.title = title; self.content = content; self.highlightedTerms = highlightedTerms; self.promptQuestion = promptQuestion
    }
}
struct ShortCard: Codable { var bullets: [String]; var terms: [String]; var source: String }

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = root.appending(path: "Litmus/short_cards.json")
let urls = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Litmus/Compiled"), includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasSuffix(".compiled.json") }
let store = CompiledCurriculumStore(urls: urls)
var done: [String: ShortCard] = (try? JSONDecoder().decode([String: ShortCard].self, from: Data(contentsOf: outURL))) ?? [:]
let limit = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? Int.max : Int.max

func save() {
    let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]
    try? enc.encode(done).write(to: outURL)
}
var n = 0
for id in store.entriesById.keys.sorted() where done[id] == nil {
    if n >= limit { break }
    let e = store.entriesById[id]!
    let passage = e.concept.cardText
    var cards = await OnDeviceFlashcardGenerator.shared.generateFlashcards(topic: e.concept.label, contextText: passage, subject: e.chapter.subject)
    var source = "model"
    if cards.isEmpty || cards.first?.id.hasPrefix("fallback") == true { source = "fallback" }
    var bullets: [String] = [], terms: [String] = []
    for c in cards {
        for line in c.content.split(whereSeparator: \.isNewline) {
            let l = String(line).trimmingCharacters(in: .whitespaces)
            // A card's figure line is kept after its bullets; everything else is a "• " bullet
            if !bullets.contains(l) { bullets.append(l) }
        }
        for t in c.highlightedTerms where !terms.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { terms.append(t) }
    }
    // A deck card holds at most 4 bullets: the first of each generated card, then the rest in order
    var picked: [String] = []
    for c in cards { if let first = c.content.split(whereSeparator: \.isNewline).first.map(String.init), !picked.contains(first) { picked.append(first) } }
    for b in bullets where picked.count < 4 && !picked.contains(b) { picked.append(b) }
    done[id] = ShortCard(bullets: Array(picked.prefix(4)), terms: Array(terms.prefix(4)), source: source)
    n += 1
    if n % 10 == 0 { save(); print("done \(done.count)/\(store.entriesById.count)"); fflush(stdout) }
}
save()
let fb = done.values.filter { $0.source == "fallback" }.count
print("finished: \(done.count) cards, \(fb) on fallback")
