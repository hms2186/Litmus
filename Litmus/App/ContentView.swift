//
//  ContentView.swift
//  Litmus
//
//  Created by user@48 on 06/11/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        LaunchContainer()
    }
}

#Preview("App", traits: .landscapeLeft) {
    ContentView()
        .modelContainer(for: [ConceptProgress.self, AttemptRecord.self, ProvisionalRecord.self], inMemory: true)
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
}

#Preview("Launch animation") {
    LitmusSplashView(dashboardReady: .constant(true)) {}
}

#Preview("Dashboard", traits: .landscapeLeft) {
    MainTabView()
        .modelContainer(for: [ConceptProgress.self, AttemptRecord.self, ProvisionalRecord.self], inMemory: true)
        .preferredColorScheme(.dark)
}
