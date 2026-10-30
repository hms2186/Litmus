//
//  F1NotificationManager.swift
//  Notifications, kept to the few that are useful, and sent only when they are needed (HIG: Notifications).
//
//  - Timer finished: scheduled when a session starts, so it arrives with the app in the background. It is cancelled
//    when the session ends with the app open, and never shown as a banner over the app itself.
//  - Revisit: one reminder, a day after an explanation that left a gap, and only if Study Reminders is on in Settings.
//  - Revise reminders: with Study Reminders on, a few gentle nudges at growing intervals (1, 3 and 7 days), each naming one
//    topic that was studied lately; tapping one opens that topic's flashcards. Opening the app clears them.
//  - Study Reminders (Settings): a daily reminder at the time the person turned it on. See F1StudyReminder.
//
//  Nothing is sent otherwise, there are no streak alerts or motivational messages, and permission is asked for in
//  context: the first time a timer starts, not when the app opens.
//

import Foundation
import UserNotifications
import UIKit

@MainActor
final class F1NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = F1NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let timerID = "litmus_timer_finished"

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: Timer finished

    /// Schedules "Timer finished" for when the session ends. The first time, this is where permission is asked for.
    func scheduleTimerFinished(topic: String, after seconds: TimeInterval) async {
        guard await authorizedOrAsk() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer finished"
        content.body = topic.isEmpty ? "Open Litmus to collect your coins." : "\(topic) is done. Open Litmus to collect your coins."
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
        content.body = "Explaining it again takes about a minute."
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
            content.title = "Time to revise"
            content.body = "\(topic.topic) · \(topic.cardCount) flashcards"
            content.sound = .default
            content.userInfo = ["url": LitmusShared.deckURL(chapter: topic.chapter, subject: topic.subject).absoluteString]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(days) * 24 * 60 * 60, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reviseIDs[index], content: content, trigger: trigger))
        }
    }

    func cancelReviseReminders() {
        center.removePendingNotificationRequests(withIdentifiers: reviseIDs)
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
