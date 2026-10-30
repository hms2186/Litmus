//
//  F1AppBlocker.swift
//  App blocking with the Screen Time API (FamilyControls + ManagedSettings). With App Blocking on in Settings, the apps and
//  categories the learner picked are shielded for as long as a focus timer runs, and released when it ends.
//
//  Needs the Family Controls capability (entitlement `com.apple.developer.family-controls`) on the app's identifier, and
//  runs on a real iPad: the simulator does not support Screen Time authorisation.
//

import SwiftUI
import Combine
import FamilyControls
import ManagedSettings

@MainActor
final class F1AppBlocker: ObservableObject {
    static let shared = F1AppBlocker()

    @Published private(set) var status: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published var selection: FamilyActivitySelection {
        didSet { saveSelection() }
    }

    private let store = ManagedSettingsStore(named: .init("litmus.focus"))
    private let selectionKey = "app_blocking_selection_v1"

    var isAuthorized: Bool { status == .approved }
    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }
    var selectionCount: Int { selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count }

    private init() {
        if let data = UserDefaults.standard.data(forKey: selectionKey),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        } else {
            selection = FamilyActivitySelection()
        }
    }

    /// Asks for Screen Time access (the system shows its own prompt). True when it was approved.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            print("Screen Time: authorisation failed: \(error.localizedDescription)")
        }
        status = AuthorizationCenter.shared.authorizationStatus
        return isAuthorized
    }

    /// Shields the chosen apps, categories and websites. Does nothing until access is approved and something is chosen.
    func startBlocking() {
        guard UserDefaults.standard.object(forKey: "settings_app_blocking") as? Bool ?? false else { return }
        status = AuthorizationCenter.shared.authorizationStatus
        guard isAuthorized, hasSelection else { return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    /// Lifts the shield: the timer has ended or was stopped.
    func stopBlocking() {
        store.clearAllSettings()
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: selectionKey)
        }
    }
}
