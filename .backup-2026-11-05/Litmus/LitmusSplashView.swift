//
//  LitmusSplashView.swift
//  The launch animation: on the deep red-to-black backdrop LITMUS comes into focus at the centre of the screen,
//  the tagline unspools beneath it, and the whole scene zooms and fades to show the dashboard underneath.
//
//  Storyboard:
//   1  0.0 – 0.5 s   The backdrop fades up in the dark.
//   2  0.5 – 1.5 s   The light warms the room and L-I-T-M-U-S comes into focus, letter by letter.
//   3  1.5 – 2.8 s   A filament runs out from the word and the tagline unspools along it:
//                    Focus. Explain. Revise.
//   4  4.8 – 5.7 s   The scene rests, then zooms in softly and fades into the dashboard.
//  With Reduce Motion on, it is a short fade.
//

import SwiftUI

struct LitmusSplashView: View {
    /// The name and tagline are showing: the dashboard can be built now, while the scene holds.
    var onHold: () -> Void = {}
    /// The dashboard has been built and is on screen underneath.
    @Binding var dashboardReady: Bool
    var onFinished: () -> Void

    @Environment(\.f1ReduceMotion) private var reduceMotion

    @State private var backdropIn = false
    @State private var locked = false
    @State private var titleIn = false
    @State private var sheen = false
    @State private var filament = false
    @State private var taglineIn = false
    @State private var leaving = false
    /// Scales the lock-up down on narrow windows (Split View, Slide Over) so the name is never cut off
    @State private var fit: CGFloat = 1

    private let letters = Array("LITMUS")
    private let words = ["Focus.", "Explain.", "Revise."]

    private let amber = Color(red: 255/255, green: 200/255, blue: 61/255)
    private let ember = Color(red: 255/255, green: 82/255, blue: 40/255)

    var body: some View {
        ZStack {
            background

            VStack(spacing: 22) {
                title
                tagline
            }
            .offset(y: taglineIn ? -4 : 0)
            .scaleEffect(fit)
            .scaleEffect(leaving ? 1.6 : 1)
            .opacity(leaving ? 0 : 1)
            .blur(radius: leaving ? 10 : 0)
        }
        .opacity(leaving ? 0 : 1)
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { min(1, $0.size.width / 700) } action: { fit = $0 }
        .f1Feedback(.impact(weight: .light), trigger: locked)
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
                           center: UnitPoint(x: 0.5, y: 0.5), startRadius: 0, endRadius: locked ? 760 : 160)
                .opacity(locked ? 1 : 0)
                .blendMode(.screen)
                .animation(.easeOut(duration: 1.8), value: locked)
        }
        // Solid from the first frame, so the dashboard never shows through; it comes up out of black
        .overlay(Color.black.opacity(backdropIn ? 0 : 1))
        .opacity(leaving ? 0 : 1)
    }

    /// The name comes into focus as one piece (one blur and one tracking animation, not one per letter), then a band of
    /// light crosses it once. It is drawn as a single flattened layer, which keeps the animation light on the GPU.
    private var title: some View {
        let word = Text("LITMUS").font(.system(size: 92, weight: .heavy).width(.expanded))
        return word
            .tracking(titleIn ? 8 : 26)
            .foregroundStyle(LinearGradient(colors: [.white, Color(red: 1, green: 0.88, blue: 0.7)], startPoint: .top, endPoint: .bottom))
            .overlay { sheenBand.mask { word.tracking(8) } }
            .fixedSize()
            .compositingGroup()
            .opacity(titleIn ? 1 : 0)
            .blur(radius: titleIn ? 0 : 16)
            .scaleEffect(titleIn ? 1 : 1.12)
            .shadow(color: ember.opacity(titleIn ? 0.45 : 0), radius: 30)
            .animation(.smooth(duration: 1.2), value: titleIn)
    }

    /// A slow band of light that crosses the word once it has appeared.
    private var sheenBand: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.35)
                .offset(x: sheen ? geo.size.width : -geo.size.width * 0.4)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }

    /// A thin filament runs out from the word, and the tagline unspools along it.
    private var tagline: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [.clear, amber, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 420, height: 2)
                .scaleEffect(x: filament ? 1 : 0.02, anchor: .center)
                .opacity(filament ? (taglineIn ? 0.35 : 1) : 0)
                .offset(y: -26)
                .shadow(color: amber, radius: 8)

            HStack(spacing: 16) {
                ForEach(words.indices, id: \.self) { index in
                    Text(words[index])
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .tracking(taglineIn ? 2 : 14)
                        .opacity(taglineIn ? 1 : 0)
                        .blur(radius: taglineIn ? 0 : 10)
                        .offset(x: taglineIn ? 0 : CGFloat(-60 + index * 20), y: taglineIn ? 0 : -14)
                        .animation(.smooth(duration: 0.9).delay(Double(index) * 0.22), value: taglineIn)
                }
            }
            .mask(
                Rectangle()
                    .scaleEffect(x: taglineIn ? 1 : 0.05, anchor: .leading)
                    .animation(.smooth(duration: 1.2), value: taglineIn)
            )
        }
        .frame(height: 44)
    }

    // MARK: - The sequence

    private func play() async {
        if reduceMotion {
            onHold()
            withAnimation(.easeIn(duration: 0.3)) { backdropIn = true; locked = true; titleIn = true; taglineIn = true; filament = true }
            try? await Task.sleep(for: .seconds(1.2))
            while !dashboardReady && !Task.isCancelled { try? await Task.sleep(for: .seconds(0.1)) }
            withAnimation(.easeOut(duration: 0.4)) { leaving = true }
            try? await Task.sleep(for: .seconds(0.4))
            onFinished()
            return
        }

        // 1. The backdrop fades up
        withAnimation(.smooth(duration: 0.5)) { backdropIn = true }
        try? await Task.sleep(for: .seconds(0.5))

        // 2. The light warms the room and reveals the name
        withAnimation { locked = true; titleIn = true }
        try? await Task.sleep(for: .seconds(1.0))
        withAnimation(.easeInOut(duration: 1.3)) { sheen = true }

        // 3. The filament and the tagline
        try? await Task.sleep(for: .seconds(0.2))
        withAnimation(.smooth(duration: 0.7)) { filament = true }
        try? await Task.sleep(for: .seconds(0.35))
        withAnimation(.smooth(duration: 0.9)) { taglineIn = true }

        // 4. Let the tagline finish and be read before the dashboard is built behind the scene (building it can stall
        // the screen for a moment, which would swallow the animation), then rest a beat, zoom into the light and fade
        try? await Task.sleep(for: .seconds(1.8))
        onHold()
        while !dashboardReady && !Task.isCancelled { try? await Task.sleep(for: .seconds(0.1)) }
        try? await Task.sleep(for: .seconds(0.9))
        withAnimation(.easeIn(duration: 0.85)) { leaving = true }
        try? await Task.sleep(for: .seconds(0.85))
        onFinished()
    }
}

#Preview {
    LitmusSplashView(dashboardReady: .constant(true)) {}
}
