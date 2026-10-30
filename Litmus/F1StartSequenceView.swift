//
//  F1StartSequenceView.swift
//  The start lights. Five lights come on one by one, left to right, in a crisp glowing red on the deep
//  red-to-black backdrop. The moment the fifth one is on, the sequence ends and the focus timer begins.
//  (Sequence rules: one light every 0.6 s, each with a haptic tick; nothing else on screen.)
//

import SwiftUI

struct F1StartSequenceView: View {
    /// The topic chosen for this timer, named above the lights.
    var topic: String = ""
    /// Called the moment the fifth light is on.
    var onComplete: () -> Void

    @Environment(\.f1ReduceMotion) private var reduceMotion
    @State private var lit = 0
    @State private var appeared = false

    private let count = 5
    private let red = Color(red: 255/255, green: 28/255, blue: 36/255)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.03, blue: 0.06), Color(red: 0.04, green: 0.0, blue: 0.01), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 44) {
                if !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // SF Pro Display (the system font from 20 pt up)
                    Text(topic)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 60)
                        .padding(.bottom, -8)
                }
                HStack(spacing: 34) {
                    ForEach(0..<count, id: \.self) { index in
                        light(isOn: index < lit)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 30)
                .background(Color.black.opacity(0.35), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))

                VStack(spacing: 8) {
                    Text("Let's Start Studying...")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("No distractions")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .multilineTextAlignment(.center)
            }
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .f1Feedback(.impact(weight: .medium), trigger: lit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start lights: \(lit) of \(count) on")
        .task { await run() }
    }

    private func light(isOn: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.09))
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1.5))
            // The glow around the light
            Circle()
                .fill(red)
                .blur(radius: 26)
                .opacity(isOn ? 0.75 : 0)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.5), red, Color(red: 0.7, green: 0.0, blue: 0.05)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 2, endRadius: 52))
                .padding(7)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 96, height: 96)
        .scaleEffect(isOn ? 1.0 : 0.96)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
    }

    private func run() async {
        withAnimation(.smooth(duration: 0.5)) { appeared = true }
        try? await Task.sleep(for: .seconds(0.5))
        let clock = ContinuousClock()
        let start = clock.now
        // The recording's five beeps (a second apart) are the five lights: each light comes on with its beep, and the
        // timer screen opens only after the beeps are over and the lights have gone out.
        if F1StartLightsSound.shared.startSequence() {
            for index in 0..<count {
                try? await clock.sleep(until: start + .seconds(0.3 + Double(index)))
                guard !Task.isCancelled else { return }
                lit = index + 1
            }
            try? await clock.sleep(until: start + .seconds(0.3 + Double(count - 1) + 1.5))
        } else {
            let step = reduceMotion ? 0.3 : 0.6
            for _ in 0..<count {
                guard !Task.isCancelled else { return }
                lit += 1
                F1StartLightsSound.shared.light(lit)
                if lit < count { try? await Task.sleep(for: .seconds(step)) }
            }
            try? await Task.sleep(for: .seconds(0.5))
            F1StartLightsSound.shared.lightsOut()
        }
        withAnimation(.easeOut(duration: 0.12)) { lit = 0 }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 0.55))
        onComplete()
    }
}

#Preview {
    F1StartSequenceView {}
}
