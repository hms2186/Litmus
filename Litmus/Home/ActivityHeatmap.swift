//
//  ActivityHeatmap.swift
//  A GitHub-style heatmap of the last six months: one square per day, weeks as columns (Sunday on top), and the
//  square gets brighter with every concept explained that day; five concepts is the brightest. Also the flame
//  shape used for completed days in Weekly Streaks.
//

import SwiftUI

/// The green scale: nothing is a quiet grey; one to five concepts climb from deep green to the brightest.
enum HeatPalette {
    static let empty = Color.white.opacity(0.13)
    static let levels: [Color] = [
        Color(red: 0/255, green: 109/255, blue: 50/255),
        Color(red: 22/255, green: 140/255, blue: 60/255),
        Color(red: 38/255, green: 166/255, blue: 65/255),
        Color(red: 46/255, green: 196/255, blue: 78/255),
        Color(red: 61/255, green: 224/255, blue: 90/255),
    ]
    /// Concepts explained on the day to square colour (nil = none)
    static func color(forConcepts count: Int) -> Color {
        guard count > 0 else { return empty }
        return levels[min(count, levels.count) - 1]
    }
}

struct ActivityHeatmap: View {
    @ObservedObject var progress: StudyProgressManager
    /// The day whose count is shown above the grid
    @State private var picked: Date?

    private let calendar = Calendar.current
    private let months = 6

    /// First column's Sunday back to the week that holds the date four months ago, through this week.
    private var weeks: [[Date?]] {
        let today = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .month, value: -months, to: today),
              var cursor = calendar.dateInterval(of: .weekOfYear, for: from)?.start else { return [] }
        var result: [[Date?]] = []
        while cursor <= today {
            let week: [Date?] = (0..<7).map { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: cursor), day <= today else { return nil }
                return day
            }
            result.append(week)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    var body: some View {
        let columns = weeks
        GeometryReader { geo in
            let gap: CGFloat = geo.size.width < 420 ? 3 : 5
            let labelWidth: CGFloat = 26
            let monthRow: CGFloat = 18
            let count = max(columns.count, 1)
            // A little extra room before the first week of each month, so the months read as separate blocks
            let monthGap: CGFloat = 12
            let starts = Set(columns.indices.filter { $0 > 0 && !monthLabel(columns, $0).isEmpty })
            let byWidth = (geo.size.width - labelWidth - 8 - gap * CGFloat(count - 1) - monthGap * CGFloat(starts.count)) / CGFloat(count)
            let byHeight = (geo.size.height - monthRow - 8 - gap * 6) / 7
            let cell = max(8, min(byWidth, byHeight, 27))
            VStack(alignment: .leading, spacing: 8) {
                // Month names over the first week of each month
                HStack(spacing: gap) {
                    Color.clear.frame(width: labelWidth, height: monthRow)
                    ForEach(columns.indices, id: \.self) { index in
                        Text(monthLabel(columns, index))
                            .scaledFont(size: 12, weight: .medium)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: cell, height: monthRow, alignment: .leading)
                            .padding(.leading, starts.contains(index) ? monthGap : 0)
                    }
                }
                HStack(alignment: .top, spacing: gap) {
                    VStack(alignment: .trailing, spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            Text(["S", "M", "T", "W", "T", "F", "S"][row])
                                .scaledFont(size: 11, weight: .medium)
                                .foregroundStyle(.white.opacity(0.65))
                                .frame(width: labelWidth, height: cell, alignment: .trailing)
                        }
                    }
                    ForEach(columns.indices, id: \.self) { column in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                square(columns[column][row], size: cell)
                            }
                        }
                        .padding(.leading, starts.contains(column) ? monthGap : 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .animation(.smooth(duration: 0.25), value: picked)
        .accessibilityElement(children: .contain)
    }

    private func monthLabel(_ columns: [[Date?]], _ index: Int) -> String {
        guard let first = columns[index].compactMap({ $0 }).first else { return "" }
        let month = calendar.component(.month, from: first)
        if index == 0 { return first.formatted(.dateTime.month(.abbreviated)) }
        let previous = columns[index - 1].compactMap { $0 }.first.map { calendar.component(.month, from: $0) }
        return month == previous ? "" : first.formatted(.dateTime.month(.abbreviated))
    }

    @ViewBuilder
    private func square(_ day: Date?, size: CGFloat) -> some View {
        if let day {
            let concepts = progress.concepts(on: day)
            let isToday = calendar.isDateInToday(day)
            let shape = RoundedRectangle(cornerRadius: max(2.5, size * 0.22), style: .continuous)
            shape
                .fill(HeatPalette.color(forConcepts: concepts))
                .frame(width: size, height: size)
                .overlay { if isToday { shape.strokeBorder(.white.opacity(0.9), lineWidth: 1.5) } }
                .overlay { if picked.map({ calendar.isDate($0, inSameDayAs: day) }) == true { shape.strokeBorder(.white, lineWidth: 2) } }
                .contentShape(Rectangle())
                .onTapGesture { picked = day }
                .accessibilityElement()
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(concepts) \(concepts == 1 ? "concept" : "concepts")")
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    /// "Wed 18 Nov · 3 concepts" for the tapped day, or a hint
    var caption: String {
        guard let picked else { return "Concepts explained each day" }
        let n = progress.concepts(on: picked)
        return picked.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " · \(n) \(n == 1 ? "concept" : "concepts")"
    }
}

/// The less-to-more key under the grid
struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Less").scaledFont(size: 12, weight: .medium).foregroundStyle(.white.opacity(0.75))
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(HeatPalette.empty).frame(width: 13, height: 13)
            ForEach(HeatPalette.levels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(HeatPalette.levels[index]).frame(width: 13, height: 13)
            }
            Text("5+ concepts").scaledFont(size: 12, weight: .medium).foregroundStyle(.white.opacity(0.75))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brighter squares mean more concepts explained; five or more is the brightest")
    }
}

/// A flame with a tall main tongue, a curl on the left and a round belly. Fills its frame.
struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }
        var path = Path()
        path.move(to: p(0.50, 1.00))
        path.addCurve(to: p(0.05, 0.64), control1: p(0.20, 1.00), control2: p(0.05, 0.84))     // belly, left
        path.addCurve(to: p(0.22, 0.30), control1: p(0.05, 0.50), control2: p(0.14, 0.40))     // up the left side
        path.addCurve(to: p(0.38, 0.44), control1: p(0.24, 0.40), control2: p(0.32, 0.46))     // the curl at the left shoulder
        path.addCurve(to: p(0.60, 0.00), control1: p(0.30, 0.24), control2: p(0.46, 0.08))     // up to the tip
        path.addCurve(to: p(0.95, 0.64), control1: p(0.62, 0.26), control2: p(0.95, 0.36))     // down the right side
        path.addCurve(to: p(0.50, 1.00), control1: p(0.95, 0.86), control2: p(0.80, 1.00))     // belly, right
        path.closeSubpath()
        return path
    }
}

/// The streak flame: a red outer flame with a smaller orange flame inside it, and the day letter at its heart.
struct StreakFlame: View {
    let letter: String
    var outer = Color(red: 232/255, green: 38/255, blue: 44/255)
    var inner = Color(red: 255/255, green: 149/255, blue: 0/255)
    var letterColor = Color.white
    var size: CGFloat = 50

    var body: some View {
        ZStack(alignment: .bottom) {
            FlameShape()
                .fill(LinearGradient(colors: [outer.opacity(0.95), outer], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.92, height: size)
            FlameShape()
                .fill(inner)
                .frame(width: size * 0.56, height: size * 0.58)
                .padding(.bottom, size * 0.07)
            Text(letter)
                .scaledFont(size: size * 0.32, weight: .heavy)
                .foregroundStyle(letterColor)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .padding(.bottom, size * 0.14)
        }
        .frame(width: size * 0.92, height: size)
        .shadow(color: outer.opacity(0.4), radius: 6, y: 2)
    }
}
