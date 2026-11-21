//
//  LitmusSplashView.swift
//  The launch animation: on the deep red-to-black backdrop LITMUS comes into focus at the centre of the screen,
//  the tagline unspools beneath it, and the whole scene zooms and fades to show the dashboard underneath.
//
//  Storyboard (about 2 s):
//   1  The dashboard is built behind the still backdrop, so nothing animates while the main thread is busy.
//   2  The light warms the room and LITMUS fades in and settles.
//   3  A filament runs out from the word and the tagline fades in: Focus. Explain. Revise.
//   4  After a moment to read it, the scene fades into the dashboard.
//  With Reduce Motion on, it is a short fade.
//

import SwiftUI

struct LitmusSplashView: View {
    /// The name and tagline are showing: the dashboard can be built now, while the scene holds.
    var onHold: () -> Void = {}
    /// The dashboard has been built and is on screen underneath.
    @Binding var dashboardReady: Bool
    var onFinished: () -> Void

    @Environment(\.appReduceMotion) private var reduceMotion

    @State private var backdropIn = false
    @State private var locked = false
    @State private var titleIn = false
        @State private var filament = false
    @State private var taglineIn = false
    @State private var leaving = false
    /// Scales the lock-up down on narrow windows (Split View, Slide Over) so the name is never cut off
    @State private var fit: CGFloat = 1

    private let letters = Array("LITMUS")
    private let words = ["Focus", "Explain", "Revise"]

    private let amber = Color(red: 255/255, green: 200/255, blue: 61/255)
    private let ember = Color(red: 255/255, green: 82/255, blue: 40/255)

    var body: some View {
        ZStack {
            background

            VStack(spacing: 22) {
                title
                tagline
            }
            .scaleEffect(fit)
            // Leaves in place: a soft fade with a barely-there swell, so the name never travels off its spot
            .scaleEffect(leaving ? 1.04 : 1)
            .opacity(leaving ? 0 : 1)
        }
        // The lock-up is pinned to the middle of the full screen from the first frame
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(leaving ? 0 : 1)
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { min(1, $0.size.width / 700) } action: { fit = $0 }
        .haptic(.impact(weight: .light), trigger: locked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Litmus. Focus. Explain. Revise.")
        .task { await play() }
    }

    // MARK: - Layers

    /// Deep red falling to black; the light warms it as the name appears.
    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.03, blue: 0.06), Color(red: 0.04, green: 0.0, blue: 0.01), .black],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [ember.opacity(0.30), Color(red: 0.5, green: 0.05, blue: 0.05).opacity(0.14), .clear],
                           center: UnitPoint(x: 0.5, y: 0.5), startRadius: 0, endRadius: 760)
                .opacity(locked ? 1 : 0)
                .animation(.easeOut(duration: 0.8), value: locked)
        }
        // Solid from the first frame, so the dashboard never shows through; it comes up out of black
        .overlay(Color.black.opacity(backdropIn ? 0 : 1))
        .opacity(leaving ? 0 : 1)
    }

    /// The name fades in and settles from a touch smaller. No blur: a blurred layer is soft while it animates and
    /// redrawn every frame, which made the old reveal look hazy and stutter. The glow is fixed, only its opacity moves.
    private var title: some View {
        Text("LITMUS")
            .font(.system(size: 92, weight: .heavy).width(.expanded))
            .tracking(8)
            // Tracking adds space after the last letter; balance it so the name is optically centred
            .padding(.leading, 8)
            .foregroundStyle(LinearGradient(colors: [.white, Color(red: 1, green: 0.88, blue: 0.7)], startPoint: .top, endPoint: .bottom))
            .fixedSize()
            .shadow(color: ember.opacity(0.45), radius: 24)
            .scaleEffect(titleIn ? 1 : 0.94)
            .opacity(titleIn ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: titleIn)
    }

    /// A thin filament runs out from the word, and the tagline fades in along it, word by word.
    private var tagline: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [.clear, amber, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 420, height: 2)
                .scaleEffect(x: filament ? 1 : 0.02, anchor: .center)
                .opacity(filament ? (taglineIn ? 0.35 : 1) : 0)
                .offset(y: -26)

            HStack(spacing: 16) {
                ForEach(words.indices, id: \.self) { index in
                    Text(words[index])
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .tracking(2)
                        .opacity(taglineIn ? 1 : 0)
                        .offset(y: taglineIn ? 0 : 8)
                        .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.08), value: taglineIn)
                }
            }
        }
        .frame(height: 44)
    }

    // MARK: - The sequence

    private func play() async {
        if reduceMotion {
            onHold()
            withAnimation(.easeIn(duration: 0.3)) { backdropIn = true; locked = true; titleIn = true; taglineIn = true; filament = true }
            try? await Task.sleep(for: .seconds(0.6))
            while !dashboardReady && !Task.isCancelled { try? await Task.sleep(for: .seconds(0.1)) }
            withAnimation(.easeOut(duration: 0.4)) { leaving = true }
            try? await Task.sleep(for: .seconds(0.4))
            onFinished()
            return
        }

        // 1. Build the dashboard first, while only the still backdrop is on screen: building it takes the main thread, and
        // an animation running meanwhile drops frames. Then the animation has the thread to itself.
        onHold()
        withAnimation(.easeOut(duration: 0.2)) { backdropIn = true }
        let waitStart = Date()
        while !dashboardReady && !Task.isCancelled && Date().timeIntervalSince(waitStart) < 2 { try? await Task.sleep(for: .seconds(0.03)) }

        // 2. The light warms the room and the name appears
        withAnimation(.easeOut(duration: 0.5)) { locked = true; titleIn = true }
        try? await Task.sleep(for: .seconds(0.4))

        // 3. The filament and the tagline
        withAnimation(.easeOut(duration: 0.35)) { filament = true }
        try? await Task.sleep(for: .seconds(0.12))
        withAnimation(.easeOut(duration: 0.35)) { taglineIn = true }
        try? await Task.sleep(for: .seconds(0.75))

        // 4. Fade into the dashboard
        withAnimation(.easeInOut(duration: 0.3)) { leaving = true }
        try? await Task.sleep(for: .seconds(0.3))
        onFinished()
    }
}

#Preview {
    LitmusSplashView(dashboardReady: .constant(true)) {}
}
