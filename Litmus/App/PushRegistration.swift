//
//  PushRegistration.swift
//  Groundwork for remote push (APNs), so notifications can later be sent from a server.
//
//  The app registers for remote notifications once the student has allowed notifications, and keeps the device token
//  (hex) in UserDefaults under `PushRegistration.tokenKey`, ready to be sent to a backend together with the profile's
//  name, grade and curriculum so messages can be personalised on the server.
//
//  To turn it on: add the Push Notifications capability to the Litmus target (this adds `aps-environment` to the
//  entitlements; it needs a team that offers push, so it is left out of the project until the team is settled).
//  Until then registration fails quietly and everything runs on the on-device reminders in NotificationManager.
//

import UIKit
import UserNotifications

final class LitmusAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: PushRegistration.tokenKey)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected until the Push Notifications capability is added; on-device reminders still work
        print("Remote push not available yet: \(error.localizedDescription)")
    }
}

enum PushRegistration {
    static let tokenKey = "push_device_token"

    /// Registers with APNs when notifications are allowed. Asking for permission stays with NotificationManager,
    /// in context, so this never shows a prompt.
    @MainActor
    static func registerIfAuthorized() async {
        // Only when the student has the Notifications switch on in Settings
        guard NotificationManager.isEnabled else { return }
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }
}
