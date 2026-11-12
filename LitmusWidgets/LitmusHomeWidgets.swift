//
//  LitmusHomeWidgets.swift
//  The Home Screen widgets.
//
//  - Revise: a flashcard from what was studied lately, a new one every half hour; tapping it opens the flashcards in the app.
//  - Streak: the week at a glance, with the streak and the coins.
//  Both draw on carbon and red, like the app, with Liquid Glass chips; the app writes what they show into an App Group.
//

import WidgetKit
import SwiftUI

private enum Palette {
    static let red = Color(red: 255/255, green: 38/255, blue: 48/255)
    static let yellow = Color(red: 255/255, green: 204/255, blue: 20/255)
    static let teal = Color(red: 26/255, green: 188/255, blue: 156/255)
    static let ink = Color(red: 12/255, green: 12/255, blue: 14/255)

    static var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 40/255, green: 6/255, blue: 10/255), ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [red.opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
        }
    }
}

// MARK: - Revise

struct ReviseEntry: TimelineEntry {
    let date: Date
    let topic: LitmusRevisionTopic?
    /// Position among the topics, for the page dots under the tile
    var index = 0
    var total = 1
}

struct ReviseProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReviseEntry {
        ReviseEntry(date: .now, topic: LitmusRevisionTopic(id: "p", topic: "Acids, Bases and Salts", chapter: "Acids, Bases and Salts", subject: "Science", cover: nil, cardCount: 4))
    }

    func getSnapshot(in context: Context, completion: @escaping (ReviseEntry) -> Void) {
        // The widget gallery shows a sample, so its preview is never empty or stale
        if context.isPreview { completion(placeholder(in: context)); return }
        completion(entries(from: LitmusWidgetStore.load()).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReviseEntry>) -> Void) {
        completion(Timeline(entries: entries(from: LitmusWidgetStore.load()), policy: .atEnd))
    }

    /// The tile slides to the next topic every couple of minutes, like the Revise tile in the app; the system decides when it really redraws.
    private func entries(from snapshot: LitmusWidgetSnapshot) -> [ReviseEntry] {
        guard !snapshot.topics.isEmpty else { return [ReviseEntry(date: .now, topic: nil)] }
        let count = snapshot.topics.count
        let start = Int(Date.now.timeIntervalSince1970 / 120)
        return (0..<30).map { offset in
            let index = (start + offset) % count
            return ReviseEntry(date: .now.addingTimeInterval(Double(offset) * 120), topic: snapshot.topics[index], index: index, total: count)
        }
    }
}

struct ReviseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReviseEntry

    var body: some View {
        Group {
            if let topic = entry.topic { content(topic) } else { empty }
        }
        .widgetURL(entry.topic.map { LitmusShared.deckURL(chapter: $0.chapter, subject: $0.subject) })
        .containerBackground(for: .widget) { Palette.background }
    }

    /// The textbook diagram of the topic's chapter fills the tile, with page dots, like the Revise tile in the app
    private func cover(_ topic: LitmusRevisionTopic) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 250/255, green: 232/255, blue: 210/255), Color(red: 214/255, green: 228/255, blue: 252/255)], startPoint: .top, endPoint: .bottom)
            if let name = topic.cover, let url = LitmusWidgetStore.coverURL(name), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 36)).foregroundStyle(Color(red: 0.25, green: 0.4, blue: 0.8).opacity(0.55))
            }
            if entry.total > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<min(entry.total, 6), id: \.self) { dot in
                        Circle().fill(dot == entry.index % 6 ? Color.white : Color.white.opacity(0.45)).frame(width: 5, height: 5)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.black.opacity(0.35), in: Capsule())
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .center))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Each topic slides in from the side as the entry changes
        .id(topic.id)
        .transition(.push(from: .trailing))
    }

    /// The Revise tile from the app's Home screen: the chapter's cover fills the widget, "REVISE" and the topic over its top,
    /// page dots under it. It slides to the next topic on its own.
    @ViewBuilder
    private func content(_ topic: LitmusRevisionTopic) -> some View {
        ZStack(alignment: .topLeading) {
            cover(topic)
            VStack(alignment: .leading, spacing: 2) {
                Text("REVISE")
                    .font(.system(size: family == .systemMedium ? 22 : 30, weight: .black))
                    .foregroundStyle(Palette.red)
                Text(topic.topic)
                    .font(.system(size: family == .systemMedium ? 17 : 26, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("\(topic.cardCount) flashcards")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.yellow)
            }
            .shadow(color: .black.opacity(0.7), radius: 4)
            .padding(14)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Revise", systemImage: "rectangle.stack.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Palette.red)
            Text("Study a topic and it will appear here.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
    }
}

struct LitmusReviseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LitmusReviseV2", provider: ReviseProvider()) { entry in
            ReviseWidgetView(entry: entry)
        }
        .configurationDisplayName("Revise")
        .description("The topics you studied lately. Tap one to open its flashcards.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Streak

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: LitmusWidgetSnapshot
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, snapshot: LitmusWidgetSnapshot(weeklyStreaks: [false, true, true, true, false, false, false], streakDays: 3, coins: 18))
    }
    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        completion(StreakEntry(date: .now, snapshot: LitmusWidgetStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        // Refreshed at the start of the next day, so today's circle moves on
        let next = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400)
        completion(Timeline(entries: [StreakEntry(date: .now, snapshot: LitmusWidgetStore.load())], policy: .after(next)))
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    private let days = ["S", "M", "T", "W", "T", "F", "S"]
    private var today: Int { Calendar.current.component(.weekday, from: entry.date) - 1 }

    /// The saved week only counts while it is still that week; after midnight on Sunday the row starts empty
    private var streaks: [Bool] {
        let calendar = Calendar(identifier: .gregorian)
        let sameWeek = calendar.isDate(entry.snapshot.updated, equalTo: entry.date, toGranularity: .weekOfYear)
        return sameWeek ? entry.snapshot.weeklyStreaks : Array(repeating: false, count: 7)
    }

    var body: some View {
        Group {
            if family == .systemSmall { activeDays } else { weeklyStreaks }
        }
        .containerBackground(for: .widget) { Palette.background }
    }

    /// Small: the streak as a flame and a number, "Active Days" (Figma "Active Days")
    private var activeDays: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.system(size: 40, weight: .bold)).foregroundStyle(Palette.yellow)
                Text("\(entry.snapshot.streakDays)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.yellow)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
            Text("Active Days")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// Medium: "Weekly Streaks", the seven days over their circles, the engineer sitting at the right (Figma "streaks medium")
    private var weeklyStreaks: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Weekly Streaks")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let done = streaks.indices.contains(index) && streaks[index]
                        VStack(spacing: 6) {
                            Text(days[index]).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            Circle()
                                .fill(done ? Palette.teal : (index == today ? Palette.yellow : Color.white.opacity(0.18)))
                                .overlay(Circle().strokeBorder(index == today ? Palette.yellow : .white.opacity(0.25), lineWidth: index == today ? 2.5 : 1))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white) }
                                }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
            }
            Image("racer_license_thinking")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 110)
                .accessibilityHidden(true)
        }
    }
}

struct LitmusStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LitmusWeeklyStreakV2", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Weekly Streaks")
        .description("The days you studied this week.")
        .supportedFamilies([.systemMedium])
    }
}

struct LitmusActiveDaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LitmusActiveDaysV2", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Active Days")
        .description("How many days in a row you have studied.")
        .supportedFamilies([.systemSmall])
    }
}
