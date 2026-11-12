//
//  F1Layout.swift
//  Layout that stays calm while the window changes size.
//
//  When the sidebar opens or closes, the system animates the width of the content frame by frame. A layout that
//  reads that width into state would be rebuilt on every one of those frames. `onSettledWidth` reports the width
//  once it has stopped changing, so a screen switches layout once, and eases into it, instead of fighting the
//  system's own motion.
//

import SwiftUI

private struct SettledWidth: ViewModifier {
    let delay: Duration
    let action: (CGFloat) -> Void

    @State private var width: CGFloat = 0
    @State private var reported = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: width) {
                guard width > 0 else { return }
                // The first width is reported at once; later ones when the size has held still
                if reported {
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                }
                reported = true
                action(width)
            }
    }
}

extension View {
    /// Calls `action` with this view's width when it first appears, then each time it settles after a change.
    func onSettledWidth(delay: Duration = .milliseconds(140), perform action: @escaping (CGFloat) -> Void) -> some View {
        modifier(SettledWidth(delay: delay, action: action))
    }
}
