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
}

struct ReviseProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReviseEntry {
        ReviseEntry(date: .now, topic: LitmusRevisionTopic(id: "p", topic: "Acids, Bases and Salts", chapter: "Acids, Bases and Salts", subject: "Science", cover: nil, cardCount: 4))
    }

    func getSnapshot(in context: Context, completion: @escaping (ReviseEntry) -> Void) {
        completion(entries(from: LitmusWidgetStore.load()).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReviseEntry>) -> Void) {
        completion(Timeline(entries: entries(from: LitmusWidgetStore.load()), policy: .atEnd))
    }

    /// One topic at a time, a new one every few hours, so the widget has something fresh to say without being busy.
    private func entries(from snapshot: LitmusWidgetSnapshot) -> [ReviseEntry] {
        guard !snapshot.topics.isEmpty else { return [ReviseEntry(date: .now, topic: nil)] }
        let start = Calendar.current.ordinality(of: .hour, in: .day, for: .now) ?? 0
        return (0..<min(snapshot.topics.count * 2, 12)).map { offset in
            ReviseEntry(date: .now.addingTimeInterval(Double(offset) * 3 * 3600), topic: snapshot.topics[(start / 3 + offset) % snapshot.topics.count])
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

    /// The textbook diagram of the topic's chapter, on a light panel like the Revise tile in the app
    private func cover(_ topic: LitmusRevisionTopic) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 250/255, green: 232/255, blue: 210/255), Color(red: 214/255, green: 228/255, blue: 252/255)], startPoint: .top, endPoint: .bottom)
            if let name = topic.cover, let url = LitmusWidgetStore.coverURL(name), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit().padding(8)
            } else {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 36)).foregroundStyle(Color(red: 0.25, green: 0.4, blue: 0.8).opacity(0.55))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func label(_ topic: LitmusRevisionTopic) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Revise", systemImage: "rectangle.stack.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Palette.red)
            Text(topic.topic)
                .font(.system(size: family == .systemSmall ? 13 : 18, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(family == .systemSmall ? 2 : 3)
                .minimumScaleFactor(0.8)
            if family != .systemSmall {
                Text("\(topic.cardCount) flashcards")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.yellow)
            }
        }
    }

    @ViewBuilder
    private func content(_ topic: LitmusRevisionTopic) -> some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                cover(topic)
                label(topic)
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 12) {
                cover(topic)
                label(topic)
            }
        default:
            HStack(spacing: 14) {
                cover(topic).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    label(topic)
                    Spacer(minLength: 0)
                    Label("Open deck", systemImage: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        StaticConfiguration(kind: "LitmusRevise", provider: ReviseProvider()) { entry in
            ReviseWidgetView(entry: entry)
        }
        .configurationDisplayName("Revise")
        .description("The topics you studied lately. Tap one to open its flashcards.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Streak

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: LitmusWidgetSnapshot
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, snapshot: LitmusWidgetSnapshot(weeklyStreaks: [false, true, true, false, false, false, false], streakDays: 2, coins: 18))
    }
    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("\(entry.snapshot.streakDays)", systemImage: "flame.fill")
                    .font(.system(size: family == .systemSmall ? 24 : 28, weight: .heavy))
                    .foregroundStyle(Palette.yellow)
                Text(entry.snapshot.streakDays == 1 ? "day" : "days")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 4)
                if family != .systemSmall {
                    Label("\(entry.snapshot.coins)", systemImage: "dollarsign.circle.fill")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.yellow)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassEffect(.regular, in: Capsule())
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: family == .systemSmall ? 4 : 8) {
                ForEach(0..<7, id: \.self) { index in
                    let done = entry.snapshot.weeklyStreaks.indices.contains(index) && entry.snapshot.weeklyStreaks[index]
                    Text(days[index])
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(index == today ? Color.black.opacity(0.8) : .white)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Circle().fill(index == today ? Palette.yellow : (done ? Palette.teal : Color.white.opacity(0.12))))
                        .overlay(alignment: .topTrailing) {
                            if done { Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(.white, Palette.teal).offset(x: 3, y: -3) }
                        }
                }
            }
        }
        .containerBackground(for: .widget) { Palette.background }
    }
}

struct LitmusStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LitmusStreak", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Weekly Streak")
        .description("Your study week at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
