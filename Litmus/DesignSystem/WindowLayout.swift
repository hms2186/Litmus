//
//  WindowLayout.swift
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

// MARK: - One design, every iPad
//
// The app is drawn for the 11-inch iPad (1194 x 834 pt, landscape). On the 13-inch iPad Pro and the iPad mini the same
// drawing is laid out in a proportionally scaled window and shown at that scale, so every size, gap and line of text
// keeps its proportion and nothing is redrawn or moved. The extra (or missing) room is only the difference in aspect ratio.

private struct DesignScaled: ViewModifier {
    /// The 11-inch iPad the screens are drawn for
    static let landscape = CGSize(width: 1194, height: 834)
    /// Within this much of the 11-inch size nothing is scaled
    static let tolerance: CGFloat = 0.04
    /// A small or split window shrinks the drawing only so far; below this the layouts adapt on their own
    static let limits: ClosedRange<CGFloat> = 0.85...1.25

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                              height: geo.size.height + insets.top + insets.bottom)
            let reference = full.width >= full.height ? Self.landscape : CGSize(width: Self.landscape.height, height: Self.landscape.width)
            let raw = min(full.width / reference.width, full.height / reference.height)
            let scale = abs(raw - 1) <= Self.tolerance ? 1 : min(max(raw, Self.limits.lowerBound), Self.limits.upperBound)
            if scale == 1 {
                content
            } else {
                content
                    .safeAreaPadding(EdgeInsets(top: insets.top / scale, leading: insets.leading / scale, bottom: insets.bottom / scale, trailing: insets.trailing / scale))
                    .frame(width: full.width / scale, height: full.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: full.width, height: full.height, alignment: .topLeading)
                    .offset(x: -insets.leading, y: -insets.top)
            }
        }
    }
}

extension View {
    /// Shows the 11-inch design in proportion on the 13-inch iPad and the iPad mini.
    func scaledToDevice() -> some View { modifier(DesignScaled()) }
}
