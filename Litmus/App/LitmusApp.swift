//
//  LitmusApp.swift
//  Litmus
//
//  Created by user@82 on 24/09/26.
//

import SwiftUI
import SwiftData

@main
struct LitmusApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(LitmusAppDelegate.self) private var appDelegate

    /// One store for the interface and for background work.
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: ConceptProgress.self, AttemptRecord.self, ProvisionalRecord.self)
        } catch {
            print("⚠️ Progress store could not be opened (\(error)); using a temporary one for this session.")
            return try! ModelContainer(for: ConceptProgress.self, AttemptRecord.self, ProvisionalRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }()

    /// Each profile after the first keeps its own progress store, so two learners never share answers or mastery.
    @MainActor private static var profileContainers: [String: ModelContainer] = [:]

    @MainActor static func container(for storageKey: String) -> ModelContainer {
        if storageKey.isEmpty { return container }
        if let existing = profileContainers[storageKey] { return existing }
        let schema = Schema([ConceptProgress.self, AttemptRecord.self, ProvisionalRecord.self])
        let made: ModelContainer
        do {
            made = try ModelContainer(for: schema, configurations: ModelConfiguration(storageKey, schema: schema))
        } catch {
            print("⚠️ Profile store could not be opened (\(error)); using a temporary one for this session.")
            made = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        profileContainers[storageKey] = made
        return made
    }

    /// Reset App: every learner's answers and mastery are removed, from the main store and from each profile's own.
    @MainActor static func eraseAllStudyData() {
        var stores = [container]
        stores.append(contentsOf: profileContainers.values)
        for store in stores {
            let context = ModelContext(store)
            try? context.delete(model: ConceptProgress.self)
            try? context.delete(model: AttemptRecord.self)
            try? context.delete(model: ProvisionalRecord.self)
            try? context.save()
        }
    }

    @StateObject private var profiles = ProfileStore.shared

    /// The on-device model on iPadOS 26 and later; keyword grading on iPadOS 18 to 25.
    static let transport: any ModelTransport = makeDefaultModelTransport()

    init() {
        AppMaintenance.registerBackgroundTask(container: Self.container, transport: Self.transport)
        // A lap does not survive the app being closed, so a shield left behind by one is lifted at launch
        ScreenTimeManager.shared.reconcileShield(coldLaunch: true)
    }

    var body: some Scene {
        WindowGroup {
            // The shell stays put; only the dashboard is rebuilt for another learner (see LaunchScene)
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            let active = Self.container(for: profiles.activeStorageKey)
            switch phase {
            case .active:
                ScreenTimeManager.shared.reconcileShield(coldLaunch: false)
                Task { await PushRegistration.registerIfAuthorized() }
                Task { await AppMaintenance.shared.run(container: active, transport: Self.transport) }
            case .background:
                AppMaintenance.scheduleBackgroundTask(container: active)
            default:
                break
            }
        }
    }
}


/// The dashboard, with the launch animation on top of it until it has played. The dashboard settles in
/// from slightly behind as the animation zooms away, so the animation seems to open onto it.
struct LaunchContainer: View {
    /// The animation plays once per launch, not again when the learner is switched.
    @MainActor static var splashShown = false

    /// Changes when the app is reset, so the whole scene is built again exactly as on a first launch.
    @State private var sceneID = UUID()

    var body: some View {
        LaunchScene()
            .id(sceneID)
            .onReceive(NotificationCenter.default.publisher(for: .litmusDidReset)) { _ in
                LaunchContainer.splashShown = false
                sceneID = UUID()
            }
    }
}

extension Notification.Name {
    /// Posted when Reset App has erased everything.
    static let litmusDidReset = Notification.Name("litmusDidReset")
}

private struct LaunchScene: View {
    @State private var showSplash = !LaunchContainer.splashShown && !ProcessInfo.processInfo.arguments.contains("-skipSplash")
    /// The dashboard is built only once the animation has fully appeared: building it takes the main thread for a
    /// while on a device, and the animation would otherwise be skipped past while it waited.
    @State private var showDashboard = LaunchContainer.splashShown || ProcessInfo.processInfo.arguments.contains("-skipSplash")
    @State private var dashboardReady = false
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        // Text size, Bold Text, Reduce Motion and Haptic Feedback from Settings > Accessibility reach every screen from here
        AccessibilityHost {
        ZStack {
            Color.black.ignoresSafeArea()
            if showDashboard {
                MainTabView()
                    // The other learner's own progress store, and a new identity so no state carries over; the old
                    // dashboard fades out as the new one fades in, inside the switch's single animation
                    .modelContainer(LitmusApp.container(for: profiles.activeStorageKey))
                    .id(profiles.activeID)
                    .transition(.opacity)
                    // Ready only after the first layout pass (tab bar, nav bar, video) has settled behind the splash,
                    // so nothing shifts while the splash fades out. No transform on the router: it would animate layout.
                    .task {
                        try? await Task.sleep(for: .seconds(0.15))
                        dashboardReady = true
                    }
            }
            if showSplash {
                LitmusSplashView(onHold: { showDashboard = true }, dashboardReady: $dashboardReady) { showSplash = false; LaunchContainer.splashShown = true }
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .zIndex(1)
            }
        }
        // Full screen: no system clock or date over the app
        .persistentSystemOverlays(.hidden)
        .scaledToDevice()
        }
    }
}
