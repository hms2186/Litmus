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

    @StateObject private var profiles = F1ProfileStore.shared

    #if canImport(FoundationModels)
    static let transport: any ModelTransport = FoundationModelsTransport()
    #else
    static let transport: any ModelTransport = UnavailableTransport()
    #endif

    init() {
        AppMaintenance.registerBackgroundTask(container: Self.container, transport: Self.transport)
    }

    var body: some Scene {
        WindowGroup {
            // A new identity rebuilds the app for the other learner, with their own progress store
            LaunchContainer()
                .id(profiles.activeID)
                .modelContainer(Self.container(for: profiles.activeStorageKey))
        }
        .onChange(of: scenePhase) { _, phase in
            let active = Self.container(for: profiles.activeStorageKey)
            switch phase {
            case .active:
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
private struct LaunchContainer: View {
    /// The animation plays once per launch, not again when the learner is switched.
    @MainActor static var splashShown = false

    @State private var showSplash = !LaunchContainer.splashShown && !ProcessInfo.processInfo.arguments.contains("-skipSplash")
    /// The dashboard is built only once the animation has fully appeared: building it takes the main thread for a
    /// while on a device, and the animation would otherwise be skipped past while it waited.
    @State private var showDashboard = LaunchContainer.splashShown || ProcessInfo.processInfo.arguments.contains("-skipSplash")
    @State private var dashboardReady = false

    var body: some View {
        // Text size, Bold Text, Reduce Motion and Haptic Feedback from Settings > Accessibility reach every screen from here
        F1AccessibilityHost {
        ZStack {
            Color.black.ignoresSafeArea()
            if showDashboard {
                F1AppRouter()
                    .scaleEffect(showSplash ? 0.97 : 1)
                    .animation(.smooth(duration: 0.9), value: showSplash)
                    .onAppear { dashboardReady = true }
            }
            if showSplash {
                LitmusSplashView(onHold: { showDashboard = true }, dashboardReady: $dashboardReady) { showSplash = false; LaunchContainer.splashShown = true }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // Full screen: no system clock or date over the app
        .persistentSystemOverlays(.hidden)
        // One scroll edge style for every scroll view in the app, covers and sheets included
        .scrollEdgeEffectStyle(.automatic, for: .all)
        }
    }
}
