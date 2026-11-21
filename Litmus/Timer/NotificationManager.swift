//
//  NotificationManager.swift
//  Notifications, kept to the few that are useful, and sent only when they are needed (HIG: Notifications).
//
//  - Timer finished: scheduled when a session starts, so it arrives with the app in the background. It is cancelled
//    when the session ends with the app open, and never shown as a banner over the app itself.
//  - Revisit: one reminder, a day after an explanation that left a gap, and only if Study Reminders is on in Settings.
//  - Revise reminders: with Study Reminders on, a few gentle nudges at growing intervals (1, 3 and 7 days), each naming one
//    topic that was studied lately; tapping one opens that topic's flashcards. Opening the app clears them.
//  - Study Reminders (Settings): a daily reminder at 5 pm, addressed to the student and naming their last topic, and
//    a "streak at risk" nudge at 8 pm on days with no study. See StudyReminder and refreshPersonalReminders.
//
//  Nothing is sent otherwise, there are no streak alerts or motivational messages, and permission is asked for in
//  context: the first time a timer starts, not when the app opens.
//

import Foundation
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let timerID = "litmus_timer_finished"

    private override init() {
        super.init()
        center.delegate = self
    }

    /// The Notifications switch in Settings. Every notification the app sends checks it first.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "settings_study_reminders") }

    /// The switch was turned off: nothing already scheduled may still arrive, and nothing shown stays in the list.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: Timer finished

    /// Schedules "Timer finished" for when the session ends. The first time, this is where permission is asked for.
    func scheduleTimerFinished(topic: String, after seconds: TimeInterval) async {
        guard Self.isEnabled else { return }
        guard await authorizedOrAsk() else { return }
        let content = UNMutableNotificationContent()
        let minutes = max(1, Int((seconds / 60).rounded()))
        content.title = topic.isEmpty ? "Focus lap complete" : "\(topic) lap complete"
        content.subtitle = "\(minutes) min of focus"
        content.body = "Nice work. Open Litmus to collect your coins, then explain what you learned in your own words."
        content.threadIdentifier = "litmus.session"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: timerID, content: content, trigger: trigger))
    }

    func cancelTimerFinished() {
        center.removePendingNotificationRequests(withIdentifiers: [timerID])
    }

    // MARK: Revisit

    /// One reminder a day after an explanation that missed something, for people who turned Study Reminders on.
    func scheduleRevisit(topic: String) async {
        guard UserDefaults.standard.bool(forKey: "settings_study_reminders") else { return }
        guard await authorizedOrAsk() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Revisit \(topic)"
        content.subtitle = "A gap from yesterday's explanation"
        content.body = "Explain it again in your own words. It takes about a minute and locks it in."
        content.threadIdentifier = "litmus.revisit"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 24 * 60 * 60, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "litmus_revisit_\(topic)", content: content, trigger: trigger))
    }

    func cancelRevisit(topic: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["litmus_revisit_\(topic)"])
    }

    // MARK: Revise reminders

    private let reviseIDs = (1...3).map { "litmus_revise_\($0)" }

    /// Sets up the nudges for the topics studied lately; each interval names a different topic when there are several.
    func scheduleReviseReminders(topics: [LitmusRevisionTopic]) async {
        cancelReviseReminders()
        guard UserDefaults.standard.bool(forKey: "settings_study_reminders"), !topics.isEmpty else { return }
        guard await authorizedOrAsk() else { return }
        for (index, days) in [1, 3, 7].enumerated() {
            let topic = topics[index % topics.count]
            let content = UNMutableNotificationContent()
            content.title = "Revise \(topic.topic)"
            content.subtitle = [topic.subject, topic.chapter].filter { !$0.isEmpty }.joined(separator: " · ")
            let streak = StudyProgressManager.shared.streakDays
            let lead = days == 1 ? "Fresh in your mind from yesterday." : (days == 3 ? "Three days on is when memories start to fade." : "A week later is the best moment to test yourself.")
            content.body = "\(lead) \(topic.cardCount) flashcards are ready" + (streak > 1 ? ", and your \(streak)-day streak is waiting." : ".")
            content.threadIdentifier = "litmus.revise"
            content.sound = .default
            content.userInfo = ["url": LitmusShared.deckURL(chapter: topic.chapter, subject: topic.subject).absoluteString]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(days) * 24 * 60 * 60, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reviseIDs[index], content: content, trigger: trigger))
        }
    }

    func cancelReviseReminders() {
        center.removePendingNotificationRequests(withIdentifiers: reviseIDs)
    }

    // MARK: Personal reminders

    private let streakIDs = (0...2).map { "litmus_streak_risk_\($0)" }

    /// Called as the app leaves the screen: rewrites the daily reminder with the student's name and last topic, and lines
    /// up "streak at risk" evening nudges (8 pm) for today, if nothing has been studied yet, and the next two days.
    /// Studying cancels today's (see `clearStreakRisk`). Only with Study Reminders on, and only once permission was given.
    func refreshPersonalReminders(name: String, topic: String?) async {
        guard UserDefaults.standard.bool(forKey: "settings_study_reminders") else { return }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        _ = await StudyReminder.schedule(name: name, topic: topic)

        center.removePendingNotificationRequests(withIdentifiers: streakIDs)
        let progress = StudyProgressManager.shared
        let streak = progress.streakDays
        let first = name.trimmingCharacters(in: .whitespaces)
        let calendar = Calendar.current
        for offset in 0...2 {
            if offset == 0 && progress.studiedToday { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()),
                  let fire = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day), fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            let atStake = streak
            if atStake >= 2 {
                content.title = first.isEmpty ? "Your \(atStake)-day streak is at risk" : "\(first), your \(atStake)-day streak is at risk"
                content.body = "A 10-minute session before bed keeps it alive."
            } else {
                content.title = first.isEmpty ? "No study yet today" : "\(first), no study yet today"
                content.body = "A short focus session today starts a streak."
            }
            content.threadIdentifier = "litmus.streak"
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: streakIDs[offset], content: content, trigger: trigger))
        }
    }

    /// The app is open or something was studied: tonight's nudge is not needed.
    func clearStreakRisk() {
        center.removePendingNotificationRequests(withIdentifiers: streakIDs)
    }

    // MARK: Permission

    /// True when notifications are allowed. Asks once, the first time it is needed, and never again after an answer.
    private func authorizedOrAsk() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        default: return false
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// With the app open there is nothing to announce: the screen already shows it.
    /// Tapping a revise reminder opens the topic's flashcards.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: text) else { return }
        await MainActor.run { UIApplication.shared.open(url) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}
