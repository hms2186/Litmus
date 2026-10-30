//
//  F1FocusLapActivityAttributes.swift
//  What the focus timer's Live Activity shows. The app starts and updates it; the widget extension draws it.
//  This file is part of both targets.
//

import Foundation
import ActivityKit

public struct F1FocusLapActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Seconds left when this state was written (what a paused timer shows)
        public var secondsRemaining: Int
        public var totalSeconds: Int
        public var lapProgress: Double
        public var currentStint: String
        public var isPaused: Bool
        public var topicTitle: String
        /// The whole timer's start and end, so the countdown and the sector bars run on their own, with the app in the background
        public var startTime: Date
        public var endTime: Date

        public init(
            secondsRemaining: Int,
            totalSeconds: Int,
            lapProgress: Double,
            currentStint: String,
            isPaused: Bool,
            topicTitle: String,
            startTime: Date = Date(),
            endTime: Date? = nil
        ) {
            self.secondsRemaining = secondsRemaining
            self.totalSeconds = totalSeconds
            self.lapProgress = lapProgress
            self.currentStint = currentStint
            self.isPaused = isPaused
            self.topicTitle = topicTitle
            self.startTime = startTime
            self.endTime = endTime ?? startTime.addingTimeInterval(Double(secondsRemaining))
        }
    }

    public var driverName: String
    public var driverNumber: Int
    public var tyreCompound: String
    /// The subject being studied (Physics, Civics…), named on the Live Activity.
    public var subject: String

    public init(driverName: String, driverNumber: Int, tyreCompound: String, subject: String = "") {
        self.driverName = driverName
        self.driverNumber = driverNumber
        self.tyreCompound = tyreCompound
        self.subject = subject
    }
}
