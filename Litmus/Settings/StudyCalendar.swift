//
//  StudyCalendar.swift
//  About You's calendar: today's date with the topics covered (a card), and a month calendar sheet in the style of
//  Apple's Calendar that shows the topics studied on each day instead of events. A year of history is reachable.
//  Streak freezes in hand are shown in both.
//

import SwiftUI

private let calendarAccent = Color(red: 255/255, green: 69/255, blue: 58/255)
private let topicChip = Color(red: 150/255, green: 52/255, blue: 190/255)
private let freezeBlue = Color(red: 120/255, green: 205/255, blue: 255/255)

/// The date as a big calendar tile, the topics of the day under it, and the freezes in hand.
struct CalendarTodayContent: View {
    @ObservedObject var progress: StudyProgressManager

    var body: some View {
        let today = Date()
        let record = progress.record(for: today)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(today.formatted(.dateTime.weekday(.abbreviated)))
                    .foregroundStyle(calendarAccent)
                Text(today.formatted(.dateTime.month(.abbreviated)))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .scaledFont(size: 30, weight: .bold)
            Text(today.formatted(.dateTime.day()))
                .scaledFont(size: 96, weight: .semibold)
                .foregroundStyle(.white.opacity(0.92))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, -14)
            Divider().overlay(Color.white.opacity(0.12))
            if let topics = record?.topics, !topics.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(topics, id: \.self) { topic in
                            HStack(spacing: 10) {
                                Capsule().fill(topicChip).frame(width: 4, height: 22)
                                Text(topic).scaledFont(size: 19).foregroundStyle(.white).lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                Text("Nothing studied yet today.")
                    .scaledFont(size: 18)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            FreezeBadge(count: progress.freezesAvailable, streak: progress.streakDays)
        }
    }
}

/// "1 streak freeze" with a snowflake, and the streak it protects
struct FreezeBadge: View {
    let count: Int
    let streak: Int
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "snowflake")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(freezeBlue)
            VStack(alignment: .leading, spacing: 1) {
                Text(count == 1 ? "1 streak freeze" : "\(count) streak freezes")
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(.white)
                Text(streak > 0 ? "\(streak)-day streak · a freeze is earned every 7 days" : "A freeze is earned every 7 days in a row")
                    .scaledFont(size: 12)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The month calendar. Back through the last 12 months; each day lists what was studied.
struct StudyCalendarSheet: View {
    @ObservedObject private var progress = StudyProgressManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var monthOffset = 0
    @State private var selected: Date? = Date()

    private let calendar = Calendar.current
    private let maxBack = 12

    private var monthStart: Date {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Leading blanks, the month's days, and trailing days of the next month to finish the last week
    private var cells: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: monthStart),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start,
              let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay)?.end else { return [] }
        var days: [Date] = []
        var day = firstWeek
        while day < lastWeek { days.append(day); day = calendar.date(byAdding: .day, value: 1, to: day) ?? lastWeek }
        return days
    }

    /// 12 months back from this one, the present date's year of history
    private var oldestAllowed: Date {
        calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header
                streakStrip
                weekdayRow
                grid
                if sizeClass == .compact || selected != nil { dayDetail }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .background { AppBackground().ignoresSafeArea() }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(36)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            (Text(monthStart.formatted(.dateTime.month(.wide))).fontWeight(.bold) + Text(" " + monthStart.formatted(.dateTime.year())).fontWeight(.regular))
                .scaledFont(size: 34)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
                .litmusGlassButton().buttonBorderShape(.circle)
                .disabled(!canGoBack)
                .accessibilityLabel("Previous month")
            Button { withAnimation(.smooth) { monthOffset = 0; selected = Date() } } label: {
                Text("Today").scaledFont(size: 16, weight: .medium).padding(.horizontal, 6)
            }
            .litmusGlassButton().buttonBorderShape(.capsule)
            Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
                .litmusGlassButton().buttonBorderShape(.circle)
                .disabled(monthOffset >= 0)
                .accessibilityLabel("Next month")
        }
        .foregroundStyle(.white)
    }

    private var canGoBack: Bool {
        guard let previous = calendar.date(byAdding: .month, value: monthOffset - 1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()),
              let end = calendar.dateInterval(of: .month, for: previous)?.end else { return false }
        return end > oldestAllowed
    }

    private func step(_ delta: Int) {
        withAnimation(.smooth(duration: 0.25)) { monthOffset = min(0, monthOffset + delta) }
    }

    private var streakStrip: some View {
        FreezeBadge(count: progress.freezesAvailable, streak: progress.streakDays)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .scaledFont(size: 15, weight: .medium)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        let days = cells
        let rows = max(1, days.count / 7)
        return GeometryReader { geo in
            let rowHeight = geo.size.height / CGFloat(rows)
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            dayCell(days[row * 7 + column])
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: rowHeight)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
                }
            }
        }
        .frame(minHeight: 280)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.smooth(duration: 0.2), value: monthOffset)
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: monthStart, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isFuture = day > Date() && !isToday
        let record = progress.record(for: day)
        let topics = record?.topics ?? []
        let frozen = progress.isFrozen(day)
        let beyondRange = day < oldestAllowed
        return Button {
            guard !isFuture, !beyondRange else { return }
            selected = day
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    if frozen { Image(systemName: "snowflake").font(.system(size: 12, weight: .bold)).foregroundStyle(freezeBlue) }
                    Spacer(minLength: 0)
                    Text(day.formatted(.dateTime.day()))
                        .scaledFont(size: 16, weight: isToday ? .bold : .medium)
                        .foregroundStyle(isToday ? .white : (inMonth ? .white : .white.opacity(0.35)))
                        .frame(minWidth: 28, minHeight: 28)
                        .background(Circle().fill(isToday ? calendarAccent : .clear))
                }
                if sizeClass == .compact {
                    HStack(spacing: 3) {
                        ForEach(0..<min(topics.count, 3), id: \.self) { _ in Circle().fill(topicChip).frame(width: 6, height: 6) }
                    }
                } else {
                    VStack(spacing: 3) {
                        ForEach(topics.count <= 2 ? topics : Array(topics.prefix(1)), id: \.self) { topic in
                            Text(topic)
                                .scaledFont(size: 12, weight: .medium)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(topicChip.opacity(0.75), in: Capsule())
                        }
                        if topics.count > 2 {
                            Text("+\(topics.count - 1) more").scaledFont(size: 11).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .background(isSelected ? Color.white.opacity(0.12) : .clear)
            .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(beyondRange ? 0.3 : 1)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide))
                            + (topics.isEmpty ? ", nothing studied" : ", studied " + topics.joined(separator: ", "))
                            + (frozen ? ", streak freeze used" : ""))
    }

    // MARK: Selected day

    private var dayDetail: some View {
        let day = selected ?? Date()
        let record = progress.record(for: day)
        let concepts = record?.explained.count ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .scaledFont(size: 18, weight: .semibold).foregroundStyle(.white)
                Spacer()
                if concepts > 0 {
                    Text("\(concepts) \(concepts == 1 ? "concept" : "concepts") explained")
                        .scaledFont(size: 14).foregroundStyle(.white.opacity(0.7))
                }
            }
            if let topics = record?.topics, !topics.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(topics, id: \.self) { topic in
                            HStack(spacing: 8) {
                                Circle().fill(topicChip).frame(width: 8, height: 8)
                                Text(topic).scaledFont(size: 16).foregroundStyle(.white).lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxHeight: 88)
            } else {
                Text(progress.isFrozen(day) ? "A streak freeze covered this day." : "Nothing studied this day.")
                    .scaledFont(size: 16).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
