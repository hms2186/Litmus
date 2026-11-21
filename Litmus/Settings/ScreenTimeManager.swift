//
//  ScreenTimeManager.swift
//  Litmus
//
//  Official Apple Screen Time API integration using FamilyControls and ManagedSettings.
//  Shields selected applications, categories, and web domains while a focus session/lap is active,
//  and lifts restrictions as soon as the session finishes or is aborted.
//
//  COMPLIANCE & HIG SPECIFICATIONS:
//  - Strictly adheres to Apple App Store Review Guideline 2.5.1 for Individual Device Management.
//  - Operates exclusively on-device: FamilyActivitySelection and opaque ApplicationTokens are never
//    transmitted, inspected, or synced to any external server.
//  - Uses PropertyListEncoder / PropertyListDecoder for persistent storage of opaque tokens.
//  - Observes live authorization status changes via Combine subscription to AuthorizationCenter.shared.$authorizationStatus.
//

import SwiftUI
import Combine
import FamilyControls
import ManagedSettings

@MainActor
public final class ScreenTimeManager: ObservableObject {
    public static let shared = ScreenTimeManager()

    // MARK: - Published Properties

    @Published public private(set) var status: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published public var selection: FamilyActivitySelection {
        didSet {
            saveSelection()
        }
    }
    @Published public private(set) var isShieldActive: Bool = false
    @Published public private(set) var isRequestingAuth: Bool = false
    @Published public private(set) var statusMessage: String = ""

    /// Master user preference to activate app blocking during focus stints
    @AppStorage("settings_app_blocking") public var isAppBlockingEnabled: Bool = true

    /// Strict mode preference (disallows early stint cancellation)
    @AppStorage("settings_app_blocking_strict") public var isStrictMode: Bool = false


    // MARK: - Private Storage & Store

    private let store: ManagedSettingsStore
    private let selectionKey = "dev.bongo.Litmus.FamilyActivitySelection.v2"
    /// When the running lap's shield should be gone. Shields live in the system, not in the app, so this is how a
    /// shield left behind by a closed app is found and lifted.
    private let shieldEndKey = "dev.bongo.Litmus.ShieldEndsAt"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    public var isAuthorized: Bool { Self.isApproved(status) }

    public var hasSelection: Bool {
        let hasRealSelection = !selection.applicationTokens.isEmpty ||
                               !selection.categoryTokens.isEmpty ||
                               !selection.webDomainTokens.isEmpty
        return hasRealSelection
    }

    public var selectionCount: Int {
        let realCount = selection.applicationTokens.count +
                        selection.categoryTokens.count +
                        selection.webDomainTokens.count
        return realCount
    }

    // MARK: - Initialization

    private init() {
        self.store = ManagedSettingsStore(named: ManagedSettingsStore.Name("dev.bongo.Litmus.FocusShield"))

        // Load saved selection via PropertyListDecoder (required for opaque tokens)
        if let data = UserDefaults.standard.data(forKey: selectionKey),
           let saved = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) {
            self.selection = saved
        } else {
            self.selection = FamilyActivitySelection()
        }


        observeAuthorizationStatus()
    }

    // MARK: - Authorization

    private func observeAuthorizationStatus() {
        AuthorizationCenter.shared.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.handleStatusUpdate(newStatus)
            }
            .store(in: &cancellables)
    }

    private func handleStatusUpdate(_ newStatus: AuthorizationStatus) {

        self.status = newStatus
        // Matched through isApproved, because `approvedWithDataAccess` exists only from iOS 26.4
        if Self.isApproved(newStatus) {
            self.statusMessage = "Screen Time access authorized."
            return
        }
        switch newStatus {
        case .denied:
            self.statusMessage = "Screen Time permission denied. Enable in Settings."
        case .notDetermined:
            self.statusMessage = "Screen Time authorization required."
        default:
            self.statusMessage = "Screen Time status unknown."
        }
    }

    /// Approved, including the variant that also allows data access (iOS 26.4 and later).
    private static func isApproved(_ status: AuthorizationStatus) -> Bool {
        if status == .approved { return true }
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return true }
        return false
    }

    /// Requests Screen Time authorization using Apple's official FamilyControls framework.
    /// Strictly requests `.individual` authorization to adhere to App Store Review Guideline 2.5.1.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        isRequestingAuth = true
        defer { isRequestingAuth = false }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            handleStatusUpdate(AuthorizationCenter.shared.authorizationStatus)
            return isAuthorized
        } catch let authError as FamilyControlsError {
            switch authError {
            case .restricted:
                statusMessage = "Screen Time access is restricted on this iPad."
            case .unavailable:
                statusMessage = "Screen Time is unavailable on this iPad."
            case .invalidArgument:
                statusMessage = "Invalid Screen Time configuration."
            case .invalidAccountType:
                statusMessage = "Screen Time requires a supported Apple account."
            case .authorizationConflict:
                statusMessage = "Screen Time authorization conflict detected."
            case .authorizationCanceled:
                statusMessage = "Screen Time authorization request was canceled."
            case .networkError:
                statusMessage = "Network error during Screen Time verification."
            case .authenticationMethodUnavailable:
                statusMessage = "Biometric authentication is currently unavailable."
            case .unauthorized:
                statusMessage = "Screen Time access was not approved."
            @unknown default:
                statusMessage = "Screen Time authorization failed."
            }
            print("[ScreenTimeManager] FamilyControlsError: \(authError.localizedDescription)")
            return false
        } catch {
            print("[ScreenTimeManager] Authorization error: \(error.localizedDescription)")
            statusMessage = "Authorization failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Shield Activation & Deactivation

    /// Applies native shields to selected applications, categories, and web domains for the active focus lap.
    public func startBlocking(for seconds: TimeInterval? = nil) {
        guard isAppBlockingEnabled else { return }
        guard isAuthorized, hasSelection else { return }
        // Recorded first, so a shield is never applied without a time by which it must be lifted
        let limit = seconds ?? 4 * 3600
        UserDefaults.standard.set(Date().addingTimeInterval(limit + 10).timeIntervalSince1970, forKey: shieldEndKey)

        let applications = selection.applicationTokens
        let categories = selection.categoryTokens
        let webDomains = selection.webDomainTokens

        store.shield.applications = applications.isEmpty ? nil : applications
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        isShieldActive = true
    }

    /// Lifts all shields immediately, restoring normal access to all applications.
    public func stopBlocking() {
        UserDefaults.standard.removeObject(forKey: shieldEndKey)
        store.clearAllSettings()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        isShieldActive = false
    }

    /// Lifts a shield that no lap is using any more. At launch (`coldLaunch`) no lap can be running, because a lap
    /// does not survive the app being closed. While the app is open, a shield is lifted once its time has passed.
    public func reconcileShield(coldLaunch: Bool) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: shieldEndKey) != nil else { return }
        let end = defaults.double(forKey: shieldEndKey)
        if coldLaunch || Date().timeIntervalSince1970 > end { stopBlocking() }
    }

    /// Clears selected applications and restores normal device access.
    public func clearSelection() {
        selection = FamilyActivitySelection()
        saveSelection()
        if isShieldActive {
            stopBlocking()
        }
    }

    /// Opens iPadOS Settings app to allow user to adjust Screen Time permissions.
    public func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Token Serialization

    private func saveSelection() {
        do {
            let data = try PropertyListEncoder().encode(selection)
            UserDefaults.standard.set(data, forKey: selectionKey)
        } catch {
            print("[ScreenTimeManager] PropertyListEncoder error saving selection: \(error)")
        }
    }
}

// MARK: - Compatibility Alias
public typealias AppBlocker = ScreenTimeManager
