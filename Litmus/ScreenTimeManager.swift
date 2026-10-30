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
//  - Provides seamless simulator fallback so full UI and timer workflows can be validated in Xcode Simulator.
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
    @Published public var isPickerPresented: Bool = false

    /// Master user preference to activate app blocking during focus stints
    @AppStorage("settings_app_blocking") public var isAppBlockingEnabled: Bool = true

    /// Strict mode preference (disallows early stint cancellation)
    @AppStorage("settings_app_blocking_strict") public var isStrictMode: Bool = false

    #if targetEnvironment(simulator)
    private let simulatorAuthKey = "dev.bongo.Litmus.SimulatorAuthorized"
    private let simulatorCountKey = "dev.bongo.Litmus.SimulatedSelectionCount"

    @Published public var simulatedSelectionCount: Int = 0 {
        didSet {
            UserDefaults.standard.set(simulatedSelectionCount, forKey: simulatorCountKey)
        }
    }
    @Published public var isSimulatorAuthorized: Bool = false {
        didSet {
            UserDefaults.standard.set(isSimulatorAuthorized, forKey: simulatorAuthKey)
        }
    }
    #endif

    // MARK: - Private Storage & Store

    private let store: ManagedSettingsStore
    private let selectionKey = "dev.bongo.Litmus.FamilyActivitySelection.v2"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    public var isAuthorized: Bool {
        #if targetEnvironment(simulator)
        if isSimulatorAuthorized { return true }
        #endif
        return status == .approved || status == .approvedWithDataAccess
    }

    public var hasSelection: Bool {
        let hasRealSelection = !selection.applicationTokens.isEmpty ||
                               !selection.categoryTokens.isEmpty ||
                               !selection.webDomainTokens.isEmpty
        #if targetEnvironment(simulator)
        if hasRealSelection { return true }
        if simulatedSelectionCount > 0 { return true }
        #endif
        return hasRealSelection
    }

    public var selectionCount: Int {
        let realCount = selection.applicationTokens.count +
                        selection.categoryTokens.count +
                        selection.webDomainTokens.count
        #if targetEnvironment(simulator)
        if realCount > 0 { return realCount }
        if simulatedSelectionCount > 0 { return simulatedSelectionCount }
        #endif
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

        #if targetEnvironment(simulator)
        if UserDefaults.standard.bool(forKey: simulatorAuthKey) ||
           UserDefaults.standard.bool(forKey: "settings_app_blocking") {
            self.isSimulatorAuthorized = true
            self.status = .approved
            self.statusMessage = "Screen Time access granted (Simulator Mode)."
        }
        let savedSimCount = UserDefaults.standard.integer(forKey: simulatorCountKey)
        if savedSimCount > 0 {
            self.simulatedSelectionCount = savedSimCount
        } else if self.isSimulatorAuthorized {
            self.simulatedSelectionCount = 3
        }
        #endif

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
        #if targetEnvironment(simulator)
        if isSimulatorAuthorized {
            self.status = .approved
            self.statusMessage = "Screen Time access granted (Simulator Mode)."
            return
        }
        #endif

        self.status = newStatus
        switch newStatus {
        case .approved, .approvedWithDataAccess:
            self.statusMessage = "Screen Time access authorized."
        case .denied:
            self.statusMessage = "Screen Time permission denied. Enable in Settings."
        case .notDetermined:
            self.statusMessage = "Screen Time authorization required."
        @unknown default:
            self.statusMessage = "Screen Time status unknown."
        }
    }

    /// Requests Screen Time authorization using Apple's official FamilyControls framework.
    /// Strictly requests `.individual` authorization to adhere to App Store Review Guideline 2.5.1.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        isRequestingAuth = true
        defer { isRequestingAuth = false }

        #if targetEnvironment(simulator)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            if AuthorizationCenter.shared.authorizationStatus == .approved ||
               AuthorizationCenter.shared.authorizationStatus == .approvedWithDataAccess {
                handleStatusUpdate(AuthorizationCenter.shared.authorizationStatus)
                return true
            } else {
                isSimulatorAuthorized = true
                status = .approved
                if simulatedSelectionCount == 0 {
                    simulatedSelectionCount = 3
                }
                statusMessage = "Screen Time access granted (Simulator Mode)."
                return true
            }
        } catch {
            // CoreSimulator lacks interactive Touch ID / Face ID FamilyControls prompt daemon.
            // Catch error and grant simulator authorization for seamless testing.
            isSimulatorAuthorized = true
            status = .approved
            if simulatedSelectionCount == 0 {
                simulatedSelectionCount = 3
            }
            statusMessage = "Screen Time access granted (Simulator Mode)."
            return true
        }
        #else
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
        #endif
    }

    // MARK: - Shield Activation & Deactivation

    /// Applies native shields to selected applications, categories, and web domains for the active focus lap.
    public func startBlocking() {
        guard isAppBlockingEnabled else { return }
        guard isAuthorized, hasSelection else { return }

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
        store.clearAllSettings()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        isShieldActive = false
    }

    /// Clears selected applications and restores normal device access.
    public func clearSelection() {
        selection = FamilyActivitySelection()
        #if targetEnvironment(simulator)
        simulatedSelectionCount = 0
        #endif
        saveSelection()
        if isShieldActive {
            stopBlocking()
        }
    }

    /// Toggles shield for developer and testing verification.
    public func toggleShieldTest() {
        if isShieldActive {
            stopBlocking()
        } else {
            if !isAppBlockingEnabled {
                isAppBlockingEnabled = true
            }
            startBlocking()
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
public typealias F1AppBlocker = ScreenTimeManager
