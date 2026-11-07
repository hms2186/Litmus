//
//  LitmusWidgetData.swift
//  What the app hands to its widgets: a few flashcards to revise and the week's streak. The app writes it into an App
//  Group the widgets can read; this file is part of both targets.
//

import Foundation

enum LitmusShared {
    static let appGroup = "group.dev.Hemanth.Litmus"
    /// Opens the flashcard deck of a chapter: litmus://deck?chapter=...&subject=...
    static func deckURL(chapter: String, subject: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "litmus"
        parts.host = "deck"
        parts.queryItems = [URLQueryItem(name: "chapter", value: chapter), URLQueryItem(name: "subject", value: subject)]
        return parts.url ?? URL(string: "litmus://deck")!
    }

    static func deckRequest(from url: URL) -> (chapter: String, subject: String)? {
        guard url.scheme == "litmus", url.host == "deck",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let chapter = items.first(where: { $0.name == "chapter" })?.value else { return nil }
        return (chapter, items.first(where: { $0.name == "subject" })?.value ?? "Science")
    }
}

/// A topic the widget offers to revise: its cover (the chapter's textbook diagram) and where tapping it goes.
struct LitmusRevisionTopic: Codable, Hashable, Identifiable {
    var id: String
    var topic: String
    var chapter: String
    var subject: String
    /// File name of the cover in the App Group's covers folder, when the chapter has a diagram
    var cover: String?
    var cardCount: Int
}

struct LitmusWidgetSnapshot: Codable {
    var topics: [LitmusRevisionTopic] = []
    /// Sunday first, as in the app
    var weeklyStreaks: [Bool] = Array(repeating: false, count: 7)
    var streakDays = 0
    var coins = 0
    var updated = Date()

    static let empty = LitmusWidgetSnapshot()
}

enum LitmusWidgetStore {
    private static let key = "litmus_widget_snapshot_v1"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: LitmusShared.appGroup) }

    /// Where the covers are kept, so the widget can draw them (it cannot reach the app's own images)
    static var coversFolder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LitmusShared.appGroup)?.appendingPathComponent("Covers", isDirectory: true)
    }

    static func coverURL(_ name: String) -> URL? { coversFolder?.appendingPathComponent(name) }

    static func save(_ snapshot: LitmusWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> LitmusWidgetSnapshot {
        guard let data = defaults?.data(forKey: key), let snapshot = try? JSONDecoder().decode(LitmusWidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }
}
