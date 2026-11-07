//
//  F1SessionProgressManager.swift
//  The single store for what a study session earns and records:
//  - coins: 10 to start; a focus lap gives 1 at the half-way point and 1 when the session is done,
//    and hints are paid for with coins;
//  - weekly streaks and study minutes, which reset each week and are written when a session is done.
//

import SwiftUI
import Combine

/// One finished focus session, shown in About You.
public struct F1SessionRecord: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var topic: String
    public var chapter: String
    public var subject: String
    public var date: Date
    public var seconds: Int
    /// What to work on, when the explanation after the session needed more.
    public var reviewNote: String?
}

public final class F1SessionProgressManager: ObservableObject {
    public static let shared = F1SessionProgressManager()

    public static let startingCoins = 10
    public static let hintCost = 3

    // MARK: - Published state
    @Published public private(set) var coins: Int
    @Published public private(set) var weeklyStreaks: [Bool]            // [S, M, T, W, Th, F, Sa]
    @Published public private(set) var dailyStudyMinutes: [Double]      // [S, M, T, W, Th, F, Sa]
    @Published public private(set) var sessions: [F1SessionRecord]

    /// Consecutive active days ending today (or yesterday), across weeks.
    public var streakDays: Int {
        let calendar = Calendar.current
        let activeDays = Set(activeDates)
        var day = calendar.startOfDay(for: Date())
        if !activeDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), activeDays.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while activeDays.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// One badge per full week of streak days.
    public var badgesCount: Int { streakDays / 7 }

    // One award per checkpoint per lap
    private var awardedKeys: Set<String> = []
    private var currentLapId = UUID().uuidString
    private var activeDates: [Date]

    private enum Key {
        static let coins = "f1_coin_balance_v3"
        static let streaks = "f1_weekly_streaks_v3"
        static let minutes = "f1_daily_study_minutes_v3"
        static let weekStart = "f1_progress_week_start_v3"
        static let activeDates = "f1_active_dates_v3"
        static let sessions = "f1_sessions_v3"
    }

    /// Which learner's data is loaded: empty for the first profile (the keys it has always used), else a suffix.
    private var namespace = ""

    private func k(_ base: String) -> String { namespace.isEmpty ? base : base + "_" + namespace }

    private init() {
        sessions = []
        coins = Self.startingCoins
        activeDates = []
        weeklyStreaks = Array(repeating: false, count: 7)
        dailyStudyMinutes = Array(repeating: 0, count: 7)
        load()
    }

    private func load() {
        let defaults = UserDefaults.standard
        sessions = (defaults.data(forKey: k(Key.sessions)).flatMap { try? JSONDecoder().decode([F1SessionRecord].self, from: $0) }) ?? []
        coins = defaults.object(forKey: k(Key.coins)) == nil ? Self.startingCoins : defaults.integer(forKey: k(Key.coins))
        activeDates = (defaults.array(forKey: k(Key.activeDates)) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
        weeklyStreaks = defaults.array(forKey: k(Key.streaks)) as? [Bool] ?? Array(repeating: false, count: 7)
        dailyStudyMinutes = defaults.array(forKey: k(Key.minutes)) as? [Double] ?? Array(repeating: 0, count: 7)
        if weeklyStreaks.count != 7 { weeklyStreaks = Array(repeating: false, count: 7) }
        if dailyStudyMinutes.count != 7 { dailyStudyMinutes = Array(repeating: 0, count: 7) }
        resetWeekIfNeeded()
    }

    /// Another learner on the same iPad: their coins, streaks, study minutes and sessions replace the current ones.
    public func switchProfile(namespace: String) {
        guard namespace != self.namespace else { return }
        self.namespace = namespace
        awardedKeys.removeAll()
        load()
    }

    /// The streak row and study chart show the current week (Sunday first); a new week starts empty.
    private func resetWeekIfNeeded() {
        let defaults = UserDefaults.standard
        let calendar = Calendar(identifier: .gregorian)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return }
        let saved = defaults.object(forKey: k(Key.weekStart)) as? Date
        if saved != weekStart {
            weeklyStreaks = Array(repeating: false, count: 7)
            dailyStudyMinutes = Array(repeating: 0, count: 7)
            defaults.set(weekStart, forKey: k(Key.weekStart))
            defaults.set(weeklyStreaks, forKey: k(Key.streaks))
            defaults.set(dailyStudyMinutes, forKey: k(Key.minutes))
        }
    }

    // MARK: - Focus lap

    /// Call when a lap begins: its checkpoints can be awarded once each.
    public func startNewLap() {
        currentLapId = UUID().uuidString
        awardedKeys.removeAll()
    }

    /// Awards one coin for a lap checkpoint ("HALF" or "DONE"), once per lap.
    @discardableResult
    public func awardLapCoin(_ checkpoint: String) -> Bool {
        let key = "\(currentLapId)_\(checkpoint)"
        guard awardedKeys.insert(key).inserted else { return false }
        coins += 1
        UserDefaults.standard.set(coins, forKey: k(Key.coins))
        return true
    }

    /// Pays for something with coins. Returns false, and changes nothing, when there are too few.
    @discardableResult
    public func spend(_ amount: Int) -> Bool {
        guard amount > 0, coins >= amount else { return false }
        coins -= amount
        UserDefaults.standard.set(coins, forKey: k(Key.coins))
        return true
    }

    // MARK: - Session done

    /// A focus session is done: today's streak lights up and the minutes studied join today's bar.
    public func recordSession(studiedSeconds: Int, topic: String = "", chapter: String = "", subject: String = "") {
        resetWeekIfNeeded()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayIndex = max(0, min(6, calendar.component(.weekday, from: today) - 1))

        weeklyStreaks[dayIndex] = true
        dailyStudyMinutes[dayIndex] += Double(max(0, studiedSeconds)) / 60.0
        if !activeDates.contains(today) { activeDates.append(today) }

        if !topic.isEmpty {
            sessions.insert(F1SessionRecord(topic: topic, chapter: chapter, subject: subject, date: Date(), seconds: studiedSeconds), at: 0)
            sessions = Array(sessions.prefix(60))
        }

        let defaults = UserDefaults.standard
        defaults.set(weeklyStreaks, forKey: k(Key.streaks))
        defaults.set(dailyStudyMinutes, forKey: k(Key.minutes))
        defaults.set(activeDates.map(\.timeIntervalSince1970), forKey: k(Key.activeDates))
        saveSessions()
    }

    /// The explanation after a session is done: its time joins today's bar. The streak is lit by the focus session alone.
    /// The topic's session of today (from the focus lap) takes the time too; without a lap it gets a record.
    public func recordExplanation(seconds: Int, topic: String, chapter: String, subject: String) {
        resetWeekIfNeeded()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayIndex = max(0, min(6, calendar.component(.weekday, from: today) - 1))
        // Explaining adds its time to today's bar, but only a completed focus session lights the streak
        dailyStudyMinutes[dayIndex] += Double(max(0, seconds)) / 60.0
        if let index = sessions.firstIndex(where: { $0.topic == topic && calendar.isDate($0.date, inSameDayAs: Date()) }) {
            sessions[index].seconds += max(0, seconds)
        } else {
            sessions.insert(F1SessionRecord(topic: topic, chapter: chapter, subject: subject, date: Date(), seconds: seconds), at: 0)
            sessions = Array(sessions.prefix(60))
        }
        let defaults = UserDefaults.standard
        defaults.set(dailyStudyMinutes, forKey: k(Key.minutes))
        saveSessions()
    }

    /// The topics studied in the last `days` days, newest first, each once.
    public func recentTopics(days: Int = 5, limit: Int = 5) -> [F1SessionRecord] {
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) else { return [] }
        var seen = Set<String>()
        return sessions.filter { $0.date >= from && seen.insert($0.topic).inserted }.prefix(limit).map { $0 }
    }

    // MARK: - History for About You

    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) { UserDefaults.standard.set(data, forKey: k(Key.sessions)) }
    }

    /// After the explanation: remember what to revisit for the topic's latest session (nil when it went well).
    public func noteExplanationResult(topic: String, reviewNote: String?) {
        guard let index = sessions.firstIndex(where: { $0.topic == topic }) else { return }
        sessions[index].reviewNote = reviewNote
        saveSessions()
    }

    public var studiedMinutesToday: Double {
        dailyStudyMinutes[max(0, min(6, Calendar.current.component(.weekday, from: Date()) - 1))]
    }

    public var sessionsThisWeek: Int {
        guard let start = Calendar(identifier: .gregorian).dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        return sessions.filter { $0.date >= start }.count
    }

    /// Topics whose latest session still has something to work on.
    public var topicsToRevisit: Int {
        var seen = Set<String>()
        var count = 0
        for record in sessions where seen.insert(record.topic).inserted {
            if record.reviewNote != nil { count += 1 }
        }
        return count
    }

    /// Clears the activity history (streaks, study minutes, sessions). Coins stay.
    public func clearStudyData() {
        weeklyStreaks = Array(repeating: false, count: 7)
        dailyStudyMinutes = Array(repeating: 0, count: 7)
        sessions = []
        activeDates = []
        let defaults = UserDefaults.standard
        defaults.set(weeklyStreaks, forKey: k(Key.streaks))
        defaults.set(dailyStudyMinutes, forKey: k(Key.minutes))
        defaults.set([Double](), forKey: k(Key.activeDates))
        saveSessions()
    }
}
