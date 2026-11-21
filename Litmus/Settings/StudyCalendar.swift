//
//  StudyCalendar.swift
//  About You's calendar: today's date with the topics covered (a card), and a month calendar sheet in the style of
//  Apple's Calendar that shows the topics studied on each day instead of events. A year of history is reachable.
//  Streak freezes in hand are shown in both.
//

import SwiftUI

private let calendarAccent = Color.red
/// Custom on purpose: the system purple is too light for white 12 pt text on it (contrast), this one passes
private let topicChip = Color(red: 150/255, green: 52/255, blue: 190/255)
private let freezeBlue = Color.cyan

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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(topics, id: \.self) { topic in
                        HStack(spacing: 10) {
                            Capsule().fill(topicChip).frame(width: 4, height: 22)
                            Text(topic).scaledFont(size: 19).foregroundStyle(.white).lineLimit(2)
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

/// The month calendar sheet, laid out like Apple's Calendar app: a full-width month grid of equal cells, the day number at the
/// top of each cell (today's in a red circle), what was studied inside it, and the chosen day's topics under the grid. The date
/// work is Foundation's `Calendar` (month interval, first weekday, today and day comparisons). A year back and a year ahead.
struct StudyCalendarSheet: View {
    @ObservedObject private var progress = StudyProgressManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var monthOffset = 0
    @State private var selected: Date? = Date()

    private let calendar = Calendar.current
    private let maxBack = 12
    private let maxForward = 12

    private var monthStart: Date {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Six whole weeks starting on the week of the 1st, as Apple's Calendar draws a month: days of the neighbouring months fill the
    /// first and last rows
    private var cells: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: monthStart),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek) }
    }

    private var oldestAllowed: Date {
        calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    private var canGoBack: Bool { monthOffset > -maxBack }
    private var canGoForward: Bool { monthOffset < maxForward }

    private func step(_ delta: Int) {
        withAnimation(.smooth(duration: 0.25)) { monthOffset = max(-maxBack, min(maxForward, monthOffset + delta)) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                header.padding(.horizontal, 20)
                FreezeBadge(count: progress.freezesAvailable, streak: progress.streakDays).padding(.horizontal, 20)
                // The month grid fills the sheet's width, as in Apple's Calendar
                VStack(spacing: 0) {
                    weekdayRow
                    grid
                        // Inset with rounded, outlined corners so all four corners of the grid show inside the sheet
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 0.5) }
                }
                .padding(.horizontal, 12)
                dayDetail.fixedSize(horizontal: false, vertical: true).padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .presentationBackground(.regularMaterial)
    }

    // MARK: Header

    /// The month and year on the left; on the right one control, as in Apple's Calendar: back, Today, forward in a single glass pill
    private var header: some View {
        HStack(spacing: 12) {
            (Text(monthStart.formatted(.dateTime.month(.wide))).fontWeight(.bold) + Text(" " + monthStart.formatted(.dateTime.year())).fontWeight(.regular))
                .scaledFont(size: 34)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            // Back, Today and forward as three independent glass buttons
            HStack(spacing: 10) {
                Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
                    .buttonBorderShape(.circle)
                    .disabled(!canGoBack)
                    .accessibilityLabel("Previous Month")
                Button("Today") { withAnimation(.smooth) { monthOffset = 0; selected = Date() } }
                    .buttonBorderShape(.capsule)
                Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 24) }
                    .buttonBorderShape(.circle)
                    .disabled(!canGoForward)
                    .accessibilityLabel("Next Month")
            }
            .litmusGlassButton()
            .controlSize(.large)
        }
    }

    /// Weekday names in the day numbers' own right-aligned column, as in Apple's Calendar
    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .scaledFont(size: 17)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        let days = cells
        let rows = max(1, days.count / 7)
        return GeometryReader { geo in
            let rowHeight = geo.size.height / CGFloat(rows)
            let cellWidth = geo.size.width / 7
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            dayCell(days[row * 7 + column], isFirstCell: row == 0 && column == 0, cellWidth: cellWidth)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: rowHeight)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.16)).frame(height: 0.5) }
                }
            }
        }
        .frame(minHeight: 300, maxHeight: .infinity)
        .animation(.smooth(duration: 0.2), value: monthOffset)
    }

    private func dayCell(_ day: Date, isFirstCell: Bool, cellWidth: CGFloat) -> some View {
        let inMonth = calendar.isDate(day, equalTo: monthStart, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isFuture = day > Date() && !isToday
        let topics = progress.record(for: day)?.topics ?? []
        let frozen = progress.isFrozen(day)
        let beyondRange = day < oldestAllowed
        // The 1st of a month (and the first cell) carry the month too: "1 Nov", "1 Dec"
        let showsMonth = isFirstCell || calendar.component(.day, from: day) == 1
        let number = showsMonth ? day.formatted(.dateTime.day().month(.abbreviated)) : day.formatted(.dateTime.day())
        return Button {
            guard !isFuture, !beyondRange else { return }
            selected = day
        } label: {
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 4) {
                    if frozen { Image(systemName: "snowflake").font(.system(size: 12, weight: .bold)).foregroundStyle(freezeBlue) }
                    Spacer(minLength: 0)
                    Text(number)
                        .scaledFont(size: 17, weight: isToday ? .semibold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // Today: a number in a red circle; a chosen day: a soft circle; days of other months are dimmed
                        .foregroundStyle(isToday ? Color.white : (inMonth ? Color.white : Color.white.opacity(0.35)))
                        .padding(.horizontal, isToday || isSelected ? 6 : 0)
                        .frame(minWidth: 30, minHeight: 30)
                        .background {
                            if isToday { Circle().fill(calendarAccent) }
                            else if isSelected { Circle().fill(Color.white.opacity(0.22)) }
                        }
                }
                .padding(.trailing, 4)
                if cellWidth < 90 {
                    HStack(spacing: 3) {
                        ForEach(0..<min(topics.count, 3), id: \.self) { _ in Circle().fill(topicChip).frame(width: 6, height: 6) }
                    }
                } else {
                    // What was studied, as a full-width bar across the cell, like an event in Apple's Calendar; any more are counted at its end
                    if let first = topics.first {
                        HStack(spacing: 4) {
                            Text(first).lineLimit(1)
                            if topics.count > 1 { Text("+\(topics.count - 1)").scaledFont(size: 12, weight: .bold).fixedSize() }
                        }
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Color(red: 0.86, green: 0.65, blue: 1.0))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(topicChip.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.horizontal, 3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffectDisabled()
        .opacity(beyondRange ? 0.3 : (isFuture ? 0.6 : 1))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
