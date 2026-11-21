//
//  Compat.swift
//  Litmus
//
//  Lets the app run on iPadOS 18 and later while using Liquid Glass where the system has it (iPadOS 26 and later).
//  On iPadOS 18 to 25 the same calls draw a system material, so one screen works on every supported system.
//
//  Use these instead of calling `glassEffect`, `.buttonStyle(.glass)` or `scrollEdgeEffectStyle` directly: those
//  exist only on iPadOS 26 and later and would not compile for the app's iPadOS 18 deployment target.
//  This file is in Shared/ because both the app and the widget extension draw glass.
//
//  The helpers carry a `litmus` prefix (litmusGlass, litmusGlassButton, litmusProminentGlassButton, litmusGlassStyle,
//  litmusGlassBackdrop, litmusSoftScrollEdge) so they are not mistaken for Apple's own APIs.
//

import SwiftUI
import UIKit

@available(iOS 26.0, *)
private func makeGlass(clear: Bool, tint: Color?, interactive: Bool) -> Glass {
    var glass: Glass = clear ? .clear : .regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// Liquid Glass on iPadOS 26 and later; a blurred system material before that.
    /// `interactive` is for controls that respond to touch. `clear` is the more transparent variant.
    /// Follows the device's Reduce Transparency (an opaque fill) and Increase Contrast (a clear outline); the default look is unchanged.
    func litmusGlass<S: Shape>(interactive: Bool = false, clear: Bool = false, tint: Color? = nil, in shape: S) -> some View {
        modifier(AdaptiveGlass(interactive: interactive, clear: clear, tint: tint, shape: shape))
    }

    /// Glass drawn as its own layer behind the content, instead of wrapping it. Use it for a glass shelf that holds tiles
    /// with a zoom transition: on iPadOS 26 a glass effect that wraps its content is rendered together with it, so the whole
    /// shelf zoomed with the tile and its glass came back late. As a separate background the tiles are left to the transition.
    func litmusGlassBackdrop<S: Shape>(clear: Bool = false, in shape: S) -> some View {
        background { Color.clear.litmusGlass(clear: clear, in: shape) }
    }

    /// The glass button style on iPadOS 26 and later (it draws its own pointer hover); the bordered style before that.
    @ViewBuilder
    func litmusGlassButton() -> some View {
        // White labels: the app's blue accent stays for prominent buttons and selection, not for button text
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass).tint(.white)
        } else {
            self.buttonStyle(.bordered).tint(.white).pointerHighlight()
        }
    }

    /// The prominent glass button style on iPadOS 26 and later (filled with the accent, since the app-wide tint is white); the prominent bordered style before that.
    @ViewBuilder
    func litmusProminentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(Color(red: 10/255, green: 132/255, blue: 255/255))
        } else {
            self.buttonStyle(.borderedProminent).tint(Color(red: 10/255, green: 132/255, blue: 255/255)).pointerHighlight()
        }
    }

    /// The system's soft scroll edge effect (`ScrollEdgeEffectStyle.soft`) on iPadOS 26 and later; nothing before that.
    @ViewBuilder
    func litmusSoftScrollEdge(for edges: Edge.Set) -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }

    /// Pointer hover for a capsule or circular button: the highlight is cut to the button's own outline (a capsule on a
    /// square frame is a circle), so it lines up with the glass instead of the label.
    func pointerHighlight() -> some View {
        self.contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
    }

    /// The soft scroll edge under the bar on iPadOS 26 and later; nothing before that.
    @ViewBuilder
    func litmusSoftTopEdge() -> some View {
        if #available(iOS 26.0, *) { self.scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }

    /// The glass button style with the label in red, for a destructive action (a destructive-role button in glass).
    @ViewBuilder
    func litmusDestructiveGlassButton() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glass).tint(.red) } else { self.buttonStyle(.bordered).tint(.red) }
    }

    /// Chooses between the glass and the prominent glass button style, for a button that is the chosen one only some of the time.
    @ViewBuilder
    func litmusGlassStyle(prominent: Bool) -> some View {
        if prominent { litmusProminentGlassButton() } else { litmusGlassButton() }
    }
}


/// SwiftUI has no modifier for the chevron-only back button short of `toolbarRole(.editor)`, which also moves the title to the
/// leading edge. UIKit's own `backButtonDisplayMode = .minimal` gives the chevron alone and leaves the title centred.
private struct MinimalBackButton: UIViewControllerRepresentable {
    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); apply() }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); apply() }
        private func apply() {
            var controller: UIViewController? = parent
            while let current = controller {
                // Only when it differs: touching the navigation item makes the bar lay its title out again
                if current.navigationItem.backButtonDisplayMode != .minimal { current.navigationItem.backButtonDisplayMode = .minimal }
                controller = current.parent
            }
        }
    }
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
}

extension View {
    /// A pushed screen's title, native: the bar's inline title, centred, with the back button showing only its chevron.
    func centeredTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background { MinimalBackButton().frame(width: 0, height: 0) }
    }

    /// A pushed screen whose content scrolls: the large title at the left under the bar, which collapses into the centred
    /// inline title as the content scrolls.
    func largeTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .background { MinimalBackButton().frame(width: 0, height: 0) }
    }

    /// Chevron-only back button on a pushed screen that sets its own title elsewhere.
    func minimalBackButton() -> some View {
        self.background { MinimalBackButton().frame(width: 0, height: 0) }
    }
}


private struct AdaptiveGlass<S: Shape>: ViewModifier {
    let interactive: Bool
    let clear: Bool
    let tint: Color?
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(white: 0.17), in: shape)
                .background(tint ?? .clear, in: shape)
                .overlay(shape.stroke(Color.white.opacity(contrast == .increased ? 0.7 : 0.25), lineWidth: contrast == .increased ? 1.5 : 1))
        } else if contrast == .increased {
            glass(content).overlay(shape.stroke(Color.white.opacity(0.7), lineWidth: 1.5))
        } else {
            glass(content)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(makeGlass(clear: clear, tint: tint, interactive: interactive), in: shape)
        } else if let tint {
            content.background(clear ? .ultraThinMaterial : .thinMaterial, in: shape).background(tint, in: shape)
        } else {
            content.background(clear ? .ultraThinMaterial : .thinMaterial, in: shape)
        }
    }
}
