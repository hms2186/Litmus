//
//  F1WidgetSync.swift
//  Keeps the Home Screen widgets up to date: the flashcards of what was studied lately, and the week's streak.
//  Called when the app opens or goes to the background and when a session or an explanation ends.
//

import Foundation
import UIKit
import WidgetKit

@MainActor
enum F1WidgetSync {
    /// - Parameter fallback: the topic to take flashcards from before anything has been studied
    static func refresh(fallback: NCERTTopic?) {
        let progress = F1SessionProgressManager.shared
        var topics: [LitmusRevisionTopic] = []
        var seen = Set<String>()

        func add(_ topic: NCERTTopic) {
            guard seen.insert(topic.title).inserted else { return }
            let cards = F1FlashcardLibrary.cards(for: topic)
            let cover = cards.first(where: { $0.imageName != nil })?.imageName.flatMap(saveCover)
            topics.append(LitmusRevisionTopic(id: topic.title, topic: topic.title, chapter: topic.chapter, subject: topic.subject, cover: cover, cardCount: cards.count))
        }

        for record in progress.recentTopics(days: 14, limit: 6) {
            if let topic = CurriculumCatalog.shared.topic(withTitle: record.topic) { add(topic) }
        }
        if topics.isEmpty, let fallback { add(fallback) }

        LitmusWidgetStore.save(LitmusWidgetSnapshot(
            topics: topics,
            weeklyStreaks: progress.weeklyStreaks,
            streakDays: progress.streakDays,
            coins: progress.coins,
            updated: Date()
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Writes a small copy of a cover image where the widget can read it. Returns its file name.
    private static func saveCover(_ imageName: String) -> String? {
        guard let folder = LitmusWidgetStore.coversFolder else { return nil }
        let fileName = imageName + ".jpg"
        let url = folder.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) { return fileName }
        guard let image = UIImage(named: imageName) else { return nil }
        let width: CGFloat = 520
        let size = CGSize(width: width, height: width * image.size.height / max(1, image.size.width))
        let small = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = small.jpegData(compressionQuality: 0.85) else { return nil }
        try? data.write(to: url)
        return fileName
    }
}
