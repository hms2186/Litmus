//
//  F1LiveActivityManager.swift
//  Prototype
//
//  Native Apple ActivityKit controller for Live Focus Stint Activities.
//  Provides real-time lock screen & Dynamic Island telemetry tracking.
//

import Foundation
import SwiftUI
import ActivityKit
import Combine

// MARK: - Native ActivityKit Manager
@MainActor
public final class F1LiveActivityManager: ObservableObject {
    public static let shared = F1LiveActivityManager()
    
    @Published public private(set) var activeActivityID: String?
    @Published public private(set) var isActivityActive: Bool = false
    
    private var currentActivity: Activity<F1FocusLapActivityAttributes>?
    
    private init() {}
    
    public func startFocusActivity(
        driverName: String,
        driverNumber: Int,
        tyreCompound: String,
        topicTitle: String,
        subject: String = "",
        totalSeconds: Int,
        secondsRemaining: Int
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("ActivityKit: Live Activities are not enabled on this device/simulator.")
            return
        }
        
        endFocusActivity()
        
        let attributes = F1FocusLapActivityAttributes(
            driverName: driverName,
            driverNumber: driverNumber,
            tyreCompound: tyreCompound,
            subject: subject
        )
        
        let contentState = Self.state(secondsRemaining: secondsRemaining, totalSeconds: totalSeconds, stint: tyreCompound, isPaused: false, topic: topicTitle)
        
        do {
            let activity = try Activity<F1FocusLapActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: contentState.endTime)
            )
            self.currentActivity = activity
            self.activeActivityID = activity.id
            self.isActivityActive = true
            print("ActivityKit: Successfully started live activity \(activity.id)")
        } catch {
            print("ActivityKit Error: \(error.localizedDescription)")
        }
    }
    
    public func updateFocusActivity(
        secondsRemaining: Int,
        totalSeconds: Int,
        isPaused: Bool,
        topicTitle: String
    ) {
        guard let activity = currentActivity else { return }
        let updatedState = Self.state(secondsRemaining: secondsRemaining, totalSeconds: totalSeconds, stint: activity.attributes.tyreCompound, isPaused: isPaused, topic: topicTitle)
        Task { @MainActor in
            await activity.update(.init(state: updatedState, staleDate: isPaused ? nil : updatedState.endTime))
        }
    }

    /// The timer as the widget needs it: when the whole timer began and when it ends, worked out from the time left now.
    private static func state(secondsRemaining: Int, totalSeconds: Int, stint: String, isPaused: Bool, topic: String) -> F1FocusLapActivityAttributes.ContentState {
        let now = Date()
        let progress = max(0.0, min(1.0, 1.0 - Double(secondsRemaining) / Double(max(1, totalSeconds))))
        return F1FocusLapActivityAttributes.ContentState(
            secondsRemaining: secondsRemaining,
            totalSeconds: totalSeconds,
            lapProgress: progress,
            currentStint: stint,
            isPaused: isPaused,
            topicTitle: topic,
            startTime: now.addingTimeInterval(-Double(totalSeconds - secondsRemaining)),
            endTime: now.addingTimeInterval(Double(secondsRemaining))
        )
    }

    public func endFocusActivity() {
        guard let activity = currentActivity else { return }
        Task { @MainActor in
            await activity.end(nil, dismissalPolicy: .immediate)
            self.currentActivity = nil
            self.activeActivityID = nil
            self.isActivityActive = false
            print("ActivityKit: Live activity ended")
        }
    }
    
    // MARK: - Convenient Lap Lifecycle Helpers
    public func startLapActivity(
        topicTitle: String,
        subject: String = "",
        durationMinutes: Double,
        tyreCompound: String = "Medium"
    ) {
        let total = Int(max(1.0, durationMinutes) * 60)
        startFocusActivity(
            driverName: "Driver",
            driverNumber: 13,
            tyreCompound: tyreCompound,
            topicTitle: topicTitle,
            subject: subject,
            totalSeconds: total,
            secondsRemaining: total
        )
    }
    
    public func updateLapProgress(
        remainingSeconds: Int,
        totalMinutes: Double,
        isPaused: Bool = false,
        topicTitle: String = ""
    ) {
        let totalSecs = Int(max(1.0, totalMinutes) * 60)
        let title = topicTitle.isEmpty ? (currentActivity?.content.state.topicTitle ?? "Double Coincidence of Wants") : topicTitle
        updateFocusActivity(
            secondsRemaining: remainingSeconds,
            totalSeconds: totalSecs,
            isPaused: isPaused,
            topicTitle: title
        )
    }
    
    public func endLapActivity() {
        endFocusActivity()
    }
}
