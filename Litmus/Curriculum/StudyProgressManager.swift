//
//  StudyProgressManager.swift
//  The single store for what a study session earns and records:
//  - coins: 10 to start; a focus lap gives 1 at the half-way point and 1 when the session is done,
//    and hints are paid for with coins;
//  - weekly streaks and study minutes, which reset each week and are written when a session is done.
//

import SwiftUI
import Combine

/// One finished focus session, shown in About You.
public struct StudySession: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var topic: String
    public var chapter: String
    public var subject: String
    public var date: Date
    public var seconds: Int
    /// What to work on, when the explanation after the session needed more.
    public var reviewNote: String?
}

/// What one calendar day held: every topic studied (a focus session or an explanation) and the concepts explained.
public struct DayRecord: Codable, Hashable {
    public var topics: [String] = []
    /// Topics explained that day; each one is a concept completed, and five make the brightest heatmap square.
    public var explained: [String] = []
}

public final class StudyProgressManager: ObservableObject {
    public static let shared = StudyProgressManager()

    public static let startingCoins = 10
    public static let hintCost = 3

    // MARK: - Published state
    @Published public private(set) var coins: Int
    @Published public private(set) var weeklyStreaks: [Bool]            // [S, M, T, W, Th, F, Sa]
    @Published public private(set) var dailyStudyMinutes: [Double]      // [S, M, T, W, Th, F, Sa]
    @Published public private(set) var sessions: [StudySession]
    /// Per day history (keys "yyyy-MM-dd"), kept for a year and a bit: the heatmap and the calendar read it.
    @Published public private(set) var dayLog: [String: DayRecord] = [:]
    /// Streak freezes in hand: one is earned for every 7 days in a row, and one is used on its own when a day is missed.
    @Published public private(set) var freezesAvailable = 0
    /// Days a freeze kept the streak alive.
    @Published public private(set) var frozenDays: Set<String> = []
    /// How many full weeks of streak have already earned their freeze.
    private var freezeMilestone = 0

    public static let conceptsForFullHeat = 5
    public static let maxFreezes = 2

    public static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public func record(for date: Date) -> DayRecord? { dayLog[Self.dayKey(date)] }
    /// Concepts explained on that day.
    public func concepts(on date: Date) -> Int { dayLog[Self.dayKey(date)]?.explained.count ?? 0 }
    public func isFrozen(_ date: Date) -> Bool { frozenDays.contains(Self.dayKey(date)) }

    /// Something was studied today, so today's streak is safe.
    public var studiedToday: Bool {
        Set(activeDates).contains(Calendar.current.startOfDay(for: Date()))
    }

    /// Consecutive active days ending today (or yesterday), across weeks. A day a freeze covered keeps the streak going without adding to it.
    public var streakDays: Int {
        let calendar = Calendar.current
        let activeDays = Set(activeDates)
        func held(_ day: Date) -> Bool { activeDays.contains(day) || frozenDays.contains(Self.dayKey(day)) }
        var day = calendar.startOfDay(for: Date())
        if !held(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), held(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while held(day) {
            if activeDays.contains(day) { count += 1 }
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
    /// What was finished each day this week; the streak tick needs both a focus session and an explanation.
    private var focusDone = Array(repeating: false, count: 7)
    private var explainDone = Array(repeating: false, count: 7)

    private enum Key {
        static let coins = "f1_coin_balance_v3"
        static let streaks = "f1_weekly_streaks_v3"
        static let minutes = "f1_daily_study_minutes_v3"
        static let weekStart = "f1_progress_week_start_v3"
        static let activeDates = "f1_active_dates_v3"
        static let sessions = "f1_sessions_v3"
        static let focusDone = "f1_focus_done_v1"
        static let explainDone = "f1_explain_done_v1"
        static let dayLog = "f1_day_log_v1"
        static let freezes = "f1_streak_freezes_v1"
        static let frozen = "f1_frozen_days_v1"
        static let milestone = "f1_freeze_milestone_v1"
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
        sessions = (defaults.data(forKey: k(Key.sessions)).flatMap { try? JSONDecoder().decode([StudySession].self, from: $0) }) ?? []
        coins = defaults.object(forKey: k(Key.coins)) == nil ? Self.startingCoins : defaults.integer(forKey: k(Key.coins))
        activeDates = (defaults.array(forKey: k(Key.activeDates)) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
        weeklyStreaks = defaults.array(forKey: k(Key.streaks)) as? [Bool] ?? Array(repeating: false, count: 7)
        dailyStudyMinutes = defaults.array(forKey: k(Key.minutes)) as? [Double] ?? Array(repeating: 0, count: 7)
        if weeklyStreaks.count != 7 { weeklyStreaks = Array(repeating: false, count: 7) }
        focusDone = defaults.array(forKey: k(Key.focusDone)) as? [Bool] ?? Array(repeating: false, count: 7)
        explainDone = defaults.array(forKey: k(Key.explainDone)) as? [Bool] ?? Array(repeating: false, count: 7)
        if focusDone.count != 7 { focusDone = Array(repeating: false, count: 7) }
        if explainDone.count != 7 { explainDone = Array(repeating: false, count: 7) }
        if dailyStudyMinutes.count != 7 { dailyStudyMinutes = Array(repeating: 0, count: 7) }
        dayLog = defaults.data(forKey: k(Key.dayLog)).flatMap { try? JSONDecoder().decode([String: DayRecord].self, from: $0) } ?? [:]
        if dayLog.isEmpty { for record in sessions { addTopic(record.topic, explained: false, on: record.date) } }
        freezesAvailable = defaults.integer(forKey: k(Key.freezes))
        frozenDays = Set(defaults.stringArray(forKey: k(Key.frozen)) ?? [])
        freezeMilestone = defaults.integer(forKey: k(Key.milestone))
        resetWeekIfNeeded()
        coverMissedDayIfNeeded()
        syncFreezeAward()
    }

    // MARK: - Day log and freezes

    private func addTopic(_ topic: String, explained: Bool, on date: Date) {
        guard !topic.isEmpty else { return }
        let key = Self.dayKey(date)
        var record = dayLog[key] ?? DayRecord()
        if !record.topics.contains(topic) { record.topics.append(topic) }
        if explained, !record.explained.contains(topic) { record.explained.append(topic) }
        dayLog[key] = record
    }

    private func saveDayLog() {
        // A year and a bit is kept; older days are dropped
        if let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: Date()) {
            let limit = Self.dayKey(cutoff)
            dayLog = dayLog.filter { $0.key >= limit }
            frozenDays = frozenDays.filter { $0 >= limit }
        }
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(dayLog) { defaults.set(data, forKey: k(Key.dayLog)) }
        defaults.set(Array(frozenDays), forKey: k(Key.frozen))
        defaults.set(freezesAvailable, forKey: k(Key.freezes))
        defaults.set(freezeMilestone, forKey: k(Key.milestone))
    }

    /// Every 7 days in a row earns a freeze (two can be kept); a broken streak starts counting again.
    private func syncFreezeAward() {
        let weeks = streakDays / 7
        if weeks > freezeMilestone { freezesAvailable = min(Self.maxFreezes, freezesAvailable + (weeks - freezeMilestone)) }
        freezeMilestone = weeks
        saveDayLog()
    }

    /// Yesterday was missed but the day before had the streak going: a freeze, if one is in hand, covers it.
    private func coverMissedDayIfNeeded() {
        guard freezesAvailable > 0 else { return }
        let calendar = Calendar.current
        let active = Set(activeDates)
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let before = calendar.date(byAdding: .day, value: -2, to: today) else { return }
        func held(_ d: Date) -> Bool { active.contains(d) || frozenDays.contains(Self.dayKey(d)) }
        guard !held(today), !held(yesterday), held(before) else { return }
        frozenDays.insert(Self.dayKey(yesterday))
        freezesAvailable -= 1
    }

    /// Another learner on the same iPad: their coins, streaks, study minutes and sessions replace the current ones.
    public func switchProfile(namespace: String) {
        guard namespace != self.namespace else { return }
        self.namespace = namespace
        awardedKeys.removeAll()
        load()
    }

    /// Call when the app comes back to the front: a new week (or a profile change) starts the row empty.
    public func refreshWeek() { resetWeekIfNeeded(); coverMissedDayIfNeeded(); syncFreezeAward() }

    /// The streak row and study chart show the current week (Sunday first); a new week starts empty.
    private func resetWeekIfNeeded() {
        let defaults = UserDefaults.standard
        let calendar = Calendar(identifier: .gregorian)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return }
        let saved = defaults.object(forKey: k(Key.weekStart)) as? Date
        if saved != weekStart {
            weeklyStreaks = Array(repeating: false, count: 7)
            focusDone = Array(repeating: false, count: 7)
            explainDone = Array(repeating: false, count: 7)
            defaults.set(focusDone, forKey: k(Key.focusDone))
            defaults.set(explainDone, forKey: k(Key.explainDone))
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

    /// A focus session is done: it counts toward today's tick and the minutes studied join today's bar.
    public func recordSession(studiedSeconds: Int, topic: String = "", chapter: String = "", subject: String = "") {
        resetWeekIfNeeded()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayIndex = max(0, min(6, calendar.component(.weekday, from: today) - 1))

        focusDone[dayIndex] = true
        weeklyStreaks[dayIndex] = focusDone[dayIndex] && explainDone[dayIndex]
        UserDefaults.standard.set(focusDone, forKey: k(Key.focusDone))
        dailyStudyMinutes[dayIndex] += Double(max(0, studiedSeconds)) / 60.0
        if !activeDates.contains(today) { activeDates.append(today) }

        if !topic.isEmpty {
            sessions.insert(StudySession(topic: topic, chapter: chapter, subject: subject, date: Date(), seconds: studiedSeconds), at: 0)
            sessions = Array(sessions.prefix(60))
            addTopic(topic, explained: false, on: Date())
        }

        let defaults = UserDefaults.standard
        defaults.set(weeklyStreaks, forKey: k(Key.streaks))
        defaults.set(dailyStudyMinutes, forKey: k(Key.minutes))
        defaults.set(activeDates.map(\.timeIntervalSince1970), forKey: k(Key.activeDates))
        saveSessions()
        syncFreezeAward()
    }

    /// The explanation after a session is done: its time joins today's bar, and with a focus session the same day it earns the streak tick.
    /// The topic's session of today (from the focus lap) takes the time too; without a lap it gets a record.
    public func recordExplanation(seconds: Int, topic: String, chapter: String, subject: String) {
        resetWeekIfNeeded()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayIndex = max(0, min(6, calendar.component(.weekday, from: today) - 1))
        // Explaining adds its time to today's bar; the tick needs a focus session the same day too
        dailyStudyMinutes[dayIndex] += Double(max(0, seconds)) / 60.0
        explainDone[dayIndex] = true
        weeklyStreaks[dayIndex] = focusDone[dayIndex] && explainDone[dayIndex]
        UserDefaults.standard.set(explainDone, forKey: k(Key.explainDone))
        UserDefaults.standard.set(weeklyStreaks, forKey: k(Key.streaks))
        if let index = sessions.firstIndex(where: { $0.topic == topic && calendar.isDate($0.date, inSameDayAs: Date()) }) {
            sessions[index].seconds += max(0, seconds)
        } else {
            sessions.insert(StudySession(topic: topic, chapter: chapter, subject: subject, date: Date(), seconds: seconds), at: 0)
            sessions = Array(sessions.prefix(60))
        }
        addTopic(topic, explained: true, on: Date())
        let defaults = UserDefaults.standard
        defaults.set(dailyStudyMinutes, forKey: k(Key.minutes))
        saveSessions()
        syncFreezeAward()
    }

    /// The topics studied in the last `days` days, newest first, each once.
    public func recentTopics(days: Int = 5, limit: Int = 5) -> [StudySession] {
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
        focusDone = Array(repeating: false, count: 7)
        explainDone = Array(repeating: false, count: 7)
        UserDefaults.standard.set(focusDone, forKey: k(Key.focusDone))
        UserDefaults.standard.set(explainDone, forKey: k(Key.explainDone))
        dailyStudyMinutes = Array(repeating: 0, count: 7)
        sessions = []
        activeDates = []
        dayLog = [:]
        frozenDays = []
        freezesAvailable = 0
        freezeMilestone = 0
        saveDayLog()
        let defaults = UserDefaults.standard
        defaults.set(weeklyStreaks, forKey: k(Key.streaks))
        defaults.set(dailyStudyMinutes, forKey: k(Key.minutes))
        defaults.set([Double](), forKey: k(Key.activeDates))
        saveSessions()
    }
}
