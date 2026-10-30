//
//  F1CongratulationsView.swift
//  Shown when the focus lap ends (the timer reaches zero or the student taps Finish).
//  Layout follows the Figma "Congratulations" frame: a dark card with the headline and subtitle on
//  top, the confetti character bottom-left, the question and two actions on the right, and the
//  privacy disclaimer along the bottom.
//

import SwiftUI

public struct F1CongratulationsView: View {
    public var driverName: String
    /// The topic the student chose for this session; the question names it.
    public var topicTitle: String
    public var onMoreTime: () -> Void
    public var onStartRadio: () -> Void

    private let headlineColor = Color(red: 255/255, green: 186/255, blue: 73/255)
    @State private var appeared = false
    @Environment(\.f1ReduceMotion) private var reduceMotion

    public init(
        driverName: String = "Aarushi",
        topicTitle: String = "",
        onMoreTime: @escaping () -> Void,
        onStartRadio: @escaping () -> Void
    ) {
        self.driverName = driverName
        self.topicTitle = topicTitle
        self.onMoreTime = onMoreTime
        self.onStartRadio = onStartRadio
    }

    public var body: some View {
        ZStack {
            AppleMusicDarkGradientBackground()

            card
                .padding(.horizontal, 58)
                .padding(.vertical, 56)
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) { appeared = true }
        }
    }

    /// "It's time to explain <topic>", or the general line when no topic was chosen.
    private var question: String {
        let topic = topicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return topic.isEmpty ? "It’s time to explain what you learned" : "It’s time to explain \(topic)"
    }

    private var card: some View {
        ZStack {
            // Character: bottom-left, allowed to run to the card's edge
            HStack {
                VStack {
                    Spacer()
                    Image("congratulations_character")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 520, maxHeight: 440, alignment: .bottomLeading)
                        .offset(x: appeared ? 0 : -60)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.78).delay(0.1), value: appeared)
                        .accessibilityHidden(true)
                }
                Spacer()
            }

            VStack(spacing: 10) {
                Text("Congratulations \(driverName.isEmpty ? "Driver" : driverName)")
                    .f1Font(size: 52, weight: .semibold)
                    .foregroundStyle(headlineColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("You successfully completed your learning time")
                    .f1Font(size: 36, weight: .regular)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.top, 96)
            .padding(.horizontal, 40)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -18)

            HStack {
                Spacer()
                VStack(spacing: 40) {
                    Text(question)
                        .f1Font(size: 34, weight: .regular)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .minimumScaleFactor(0.7)
                        .lineLimit(4)
                    HStack(spacing: 24) {
                        Button(action: onMoreTime) {
                            Text("No, I want more time!")
                                .f1Font(size: 18, weight: .medium)
                                .foregroundStyle(Color.black.opacity(0.85))
                                .padding(.horizontal, 22)
                                .frame(height: 54)
                                .background(Color.white.opacity(0.55), in: Capsule())
                        }
                        .buttonStyle(.f1Spring)
                        Button(action: onStartRadio) {
                            Text("Yes, Let's Start!")
                                .f1Font(size: 18, weight: .medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 28)
                                .frame(height: 54)
                                .background(Color(red: 10/255, green: 110/255, blue: 255/255), in: Capsule())
                        }
                        .buttonStyle(.f1Spring)
                    }
                }
                .padding(.trailing, 60)
                .padding(.top, 150)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)
                .animation(reduceMotion ? nil : .smooth(duration: 0.8).delay(0.35), value: appeared)
            }

            VStack {
                Spacer()
                Text("Disclaimer: Your voice stays on this iPad.")
                    .f1Font(size: 15)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 22)
            }
        }
        .overlay {
            if !reduceMotion {
                // The burst leaves the popper (about a third across, 70% down) and flies across the card
                ConfettiBurst(origin: UnitPoint(x: 0.34, y: 0.66))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 18/255, green: 18/255, blue: 20/255).opacity(0.94), in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
    }
}


/// Confetti that shoots out of a point and flies across the whole card: a big burst, then two smaller
/// ones. Each piece has its own direction, speed, spin and colour; drag slows it and gravity pulls it down.
struct ConfettiBurst: View {
    let origin: UnitPoint

    private struct Piece {
        let angle: Double, speed: Double, spin: Double, wobble: Double, phase: Double
        let size: CGSize, color: Color, delay: Double, ribbon: Bool
    }

    private let pieces: [Piece]
    private let start = Date()
    private static let lifetime = 4.2
    private static let lastBurstDelay = 3.2
    /// Set once every piece has faded, so the canvas stops redrawing.
    @State private var finished = false

    init(origin: UnitPoint) {
        self.origin = origin
        var generator = SeededGenerator(seed: 7)
        let colors: [Color] = [
            Color(red: 255/255, green: 24/255, blue: 36/255), .white, Color(red: 255/255, green: 193/255, blue: 7/255),
            Color(red: 10/255, green: 132/255, blue: 255/255), Color(red: 255/255, green: 120/255, blue: 24/255)
        ]
        pieces = (0..<150).map { index in
            let burst = index < 90 ? 0 : (index < 120 ? 1 : 2)
            return Piece(
                angle: Double.random(in: -2.7 ... -0.1, using: &generator),           // up, left and right
                speed: Double.random(in: 380...1250, using: &generator),
                spin: Double.random(in: -9...9, using: &generator),
                wobble: Double.random(in: 10...38, using: &generator),
                phase: Double.random(in: 0...6.28, using: &generator),
                size: CGSize(width: Double.random(in: 8...16, using: &generator), height: Double.random(in: 4...8, using: &generator)),
                color: colors.randomElement(using: &generator) ?? .white,
                delay: Double(burst) * 1.6,
                ribbon: Bool.random(using: &generator)
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished)) { context in
            Canvas { canvas, size in
                let elapsed = context.date.timeIntervalSince(start)
                let ox = origin.x * size.width
                let oy = origin.y * size.height
                let drag = 1.5, gravity = 620.0
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0, t < Self.lifetime else { continue }
                    let decay = (1 - exp(-drag * t)) / drag
                    let x = ox + piece.speed * cos(piece.angle) * decay + sin(t * 5 + piece.phase) * piece.wobble * min(t, 1)
                    let y = oy + (piece.speed * sin(piece.angle) - gravity / drag) * decay + gravity / drag * t
                    let fade = t > Self.lifetime - 0.9 ? max(0, (Self.lifetime - t) / 0.9) : 1
                    var layer = canvas
                    layer.opacity = fade
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(piece.spin * t))
                    // Ribbons flip as they tumble
                    layer.scaleBy(x: 1, y: piece.ribbon ? CGFloat(cos(t * 6 + piece.phase)) : 1)
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2, width: piece.size.width, height: piece.size.height)
                    layer.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(piece.color))
                }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.lifetime + Self.lastBurstDelay + 0.5))
            finished = true
        }
    }
}

/// A repeatable random sequence, so the confetti looks the same every time.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
