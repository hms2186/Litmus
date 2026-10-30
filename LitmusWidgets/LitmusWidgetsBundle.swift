//
//  LitmusWidgetsBundle.swift
//  The Litmus widget extension: the Revise and Weekly Streak widgets for the Home Screen, and the focus timer's Live
//  Activity, which runs on its own while the app is in the background.
//

import WidgetKit
import SwiftUI

@main
struct LitmusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LitmusReviseWidget()
        LitmusStreakWidget()
        LitmusFocusLiveActivity()
    }
}
