//
//  F1BackButton.swift
//  One back button for every screen that is not pushed on a navigation stack (full-screen covers and overlays):
//  the system's back chevron on a Liquid Glass circle, at least 44 points, with the pointer hover lift.
//  Pushed screens use the navigation stack's own back button instead.
//

import SwiftUI

struct F1BackButton: View {
    /// Where it sits on every screen: this far from the leading and top edges
    static let leading: CGFloat = 32
    static let top: CGFloat = 36

    var label = "Back"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.f1Spring)
        .hoverEffect(.lift)
        .accessibilityLabel(label)
    }
}
