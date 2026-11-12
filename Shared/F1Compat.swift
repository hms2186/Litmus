//
//  F1Compat.swift
//  Litmus
//
//  Lets the app run on iPadOS 18 and later while using Liquid Glass where the system has it (iPadOS 26 and later).
//  On iPadOS 18 to 25 the same calls draw a system material, so one screen works on every supported system.
//
//  Use these instead of calling `glassEffect`, `.buttonStyle(.glass)` or `scrollEdgeEffectStyle` directly: those
//  exist only on iPadOS 26 and later and would not compile for the app's iPadOS 18 deployment target.
//  This file is in Shared/ because both the app and the widget extension draw glass.
//

import SwiftUI
import UIKit

@available(iOS 26.0, *)
private func f1MakeGlass(clear: Bool, tint: Color?, interactive: Bool) -> Glass {
    var glass: Glass = clear ? .clear : .regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// Liquid Glass on iPadOS 26 and later; a blurred system material before that.
    /// `interactive` is for controls that respond to touch. `clear` is the more transparent variant.
    @ViewBuilder
    func f1Glass<S: Shape>(interactive: Bool = false, clear: Bool = false, tint: Color? = nil, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(f1MakeGlass(clear: clear, tint: tint, interactive: interactive), in: shape)
        } else if let tint {
            self.background(clear ? .ultraThinMaterial : .thinMaterial, in: shape).background(tint, in: shape)
        } else {
            self.background(clear ? .ultraThinMaterial : .thinMaterial, in: shape)
        }
    }

    /// The glass button style on iPadOS 26 and later; the bordered style before that.
    @ViewBuilder
    func f1GlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// The prominent glass button style on iPadOS 26 and later; the prominent bordered style before that.
    @ViewBuilder
    func f1GlassProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// The system's scroll edge effect on iPadOS 26 and later; nothing before that.
    @ViewBuilder
    func f1ScrollEdgeEffect(for edges: Edge.Set) -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.automatic, for: edges)
        } else {
            self
        }
    }

    /// Chooses between the glass and the prominent glass button style, for a button that is the chosen one only some of the time.
    @ViewBuilder
    func f1GlassStyle(prominent: Bool) -> some View {
        if prominent { f1GlassProminentButtonStyle() } else { f1GlassButtonStyle() }
    }
}


/// SwiftUI has no modifier for the chevron-only back button short of `toolbarRole(.editor)`, which also moves the title to the
/// leading edge. UIKit's own `backButtonDisplayMode = .minimal` gives the chevron alone and leaves the title centred.
private struct F1MinimalBackButton: UIViewControllerRepresentable {
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
    func f1CenteredTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background { F1MinimalBackButton().frame(width: 0, height: 0) }
    }

    /// A pushed screen whose content scrolls: the large title at the left under the bar, which collapses into the centred
    /// inline title as the content scrolls.
    func f1LargeTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .background { F1MinimalBackButton().frame(width: 0, height: 0) }
    }

    /// Chevron-only back button on a pushed screen that sets its own title elsewhere.
    func f1MinimalBackButton() -> some View {
        self.background { F1MinimalBackButton().frame(width: 0, height: 0) }
    }
}
