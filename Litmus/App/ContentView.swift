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
        .tint(F1Theme.accent)
        .preferredColorScheme(.dark)
}

#Preview("Launch animation") {
    LitmusSplashView(dashboardReady: .constant(true)) {}
}

#Preview("Dashboard", traits: .landscapeLeft) {
    F1AppRouter()
        .modelContainer(for: [ConceptProgress.self, AttemptRecord.self, ProvisionalRecord.self], inMemory: true)
        .preferredColorScheme(.dark)
}
