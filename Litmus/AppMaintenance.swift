//
//  AppMaintenance.swift
//  Runs the background work of architecture v4.0: the 30-day cleanup, the re-grade of saved Likely
//  mastered answers, and the drift check after an OS update. It runs when the app becomes active and,
//  where the system allows, as a background processing task while the iPad is charging.
//

import Foundation
import SwiftData
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// Whether a student's answer is being graded right now; background model work waits for it.
@MainActor
enum GradingActivity {
    static var isGrading = false
}

@MainActor
final class AppMaintenance {
    static let shared = AppMaintenance()
    static let backgroundTaskIdentifier = "dev.Hemanth.Litmus.maintenance"

    private var running = false
    private(set) var lastReport: MaintenanceReport?

    /// Cleanup and re-grade, then the drift check if this OS build has not been checked, then a
    /// second re-grade pass if the check just passed (re-grades wait for a checked model).
    func run(container: ModelContainer, transport: any ModelTransport) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let context = container.mainContext
        let store = CompiledCurriculumStore.shared
        let build = DriftMonitor.currentBuild

        lastReport = await ProvisionalMaintenance.run(context: context, store: store,
                                                      coordinator: coordinator(transport), osBuild: build)
        let wasProvisionalOnly = DriftMonitor.shared.provisionalOnly(build: build)
        if !DriftMonitor.shared.isChecked(build: build), let set = DriftSet.bundled {
            await DriftMonitor.shared.runIfNeeded(set: set, store: store, transport: transport, build: build,
                                                  isBusy: { await MainActor.run { GradingActivity.isGrading } })
        }
        if wasProvisionalOnly && !DriftMonitor.shared.provisionalOnly(build: build) {
            lastReport = await ProvisionalMaintenance.run(context: context, store: store,
                                                          coordinator: coordinator(transport), osBuild: build)
        }
        #if DEBUG
        if let lastReport { print("🧪 [Maintenance] \(lastReport)") }
        #endif
    }

    private func coordinator(_ transport: any ModelTransport) -> GradingCoordinator {
        GradingCoordinator(transport: transport, settings: GradingSettings(provisionalOnly: DriftMonitor.shared.provisionalOnly()))
    }

    // MARK: Background processing task

    /// Registers the handler; must be called before the app finishes launching.
    static func registerBackgroundTask(container: ModelContainer, transport: any ModelTransport) {
        #if canImport(BackgroundTasks) && !os(macOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            Task { @MainActor in
                let work = Task { await AppMaintenance.shared.run(container: container, transport: transport) }
                task.expirationHandler = { work.cancel() }
                await work.value
                task.setTaskCompleted(success: true)
            }
        }
        #endif
    }

    /// Asks for a run while the iPad is charging, when there is work the model should do.
    static func scheduleBackgroundTask(container: ModelContainer) {
        #if canImport(BackgroundTasks) && !os(macOS)
        let pendingRecords = (try? container.mainContext.fetchCount(
            FetchDescriptor<ProvisionalRecord>(predicate: #Predicate { $0.regradeOutcome == nil }))) ?? 0
        guard !DriftMonitor.shared.isChecked() || pendingRecords > 0 else { return }
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
}
