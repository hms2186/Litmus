//
//  F1LiveCockpitHUDView.swift
//  Prototype
//
//  Exact 1:1 Implementation of Figma Node 679:3566 (Active Timer / Focus Screen).
//  Adheres to Apple HIG and user skills:
//  - Arc-length parameterized racetrack with dynamic F1 car position and tangent rotation in 100% lockstep with time progress.
//  - Red progress skid trail following the car along the circuit without desync or gap.
//  - Center countdown timer ("TIME REMAINING MM:SS", "CLICK TIME TO EDIT").
//  - Top-left header: "LIVE FOCUS TRACKER", "Stay on track.", "Work Hard, Stay Focused, Make it happen".
//  - Top-right coin badge ($ 0).
//  - Upper-right circuit indicator: "LAP 1/1 · X% COMPLETE".
//  - Floating bottom glass panel: "Timer Control" with circular Pause & Finish buttons.
//  - Authentic Ferrari Rosso Corsa F1 car model with Pirelli compound rings matching selected tyre.
//

import SwiftUI
import Combine

/// The seconds left in the lap. It is its own object, and the app shell only holds it without watching it,
/// so the one-second ticks redraw the cockpit alone and not every screen behind it.
@MainActor
public final class LapClock: ObservableObject {
    @Published public var remaining: Int

    public init(remaining: Int = 15 * 60) { self.remaining = remaining }
}

public struct F1LiveCockpitHUDView: View {
    @ObservedObject public var clock: LapClock
    private var focusSecondsRemaining: Int { clock.remaining }
    public var focusMinutes: Double
    public var circuit: F1Circuit
    public var tyreCompound: TyreCompound
    @Binding public var isFocusTimerRunning: Bool
    public var onBoxBox: () -> Void
    public var onAddTime: () -> Void
    public var onRedFlag: () -> Void
    public var onFinishLap: () -> Void

    @ObservedObject private var progressManager = F1SessionProgressManager.shared
    @State private var timerPublisher = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    @Environment(\.f1ReduceMotion) private var reduceMotion

    /// The checkpoint coin: 0 none, 1 below the screen, 2 in the middle, 3 on its way to the badge.
    @State private var coinStage = 0
    /// Coins that have been earned but have not landed in the badge yet, so the count rises when the coin arrives.
    @State private var coinsInFlight = 0
    @State private var coinLanded = 0
    @State private var badgeFrame: CGRect = .zero

    // Simplified Smooth Flowing GP Circuit (Figma 679:3566)
    private struct TrackWaypoint {
        let x: CGFloat
        let y: CGFloat
    }

    /// The circuit from the Figma "Circuit" frame, traced as points along its centre line and scaled to a unit box.
    /// It starts on the start/finish line and runs sector 1 (red), sector 2 (blue), sector 3 (yellow).
    private let waypoints: [TrackWaypoint] = [
        TrackWaypoint(x: 0.1715, y: 0.7789),
        TrackWaypoint(x: 0.1321, y: 0.8208),
        TrackWaypoint(x: 0.0895, y: 0.8660),
        TrackWaypoint(x: 0.0469, y: 0.9129),
        TrackWaypoint(x: 0.0096, y: 0.9581),
        TrackWaypoint(x: 0.0000, y: 0.9715),
        TrackWaypoint(x: 0.0085, y: 0.9497),
        TrackWaypoint(x: 0.0192, y: 0.8911),
        TrackWaypoint(x: 0.0309, y: 0.8325),
        TrackWaypoint(x: 0.0522, y: 0.7571),
        TrackWaypoint(x: 0.0735, y: 0.7069),
        TrackWaypoint(x: 0.0937, y: 0.6734),
        TrackWaypoint(x: 0.1193, y: 0.6231),
        TrackWaypoint(x: 0.1480, y: 0.5812),
        TrackWaypoint(x: 0.1768, y: 0.5310),
        TrackWaypoint(x: 0.2013, y: 0.4640),
        TrackWaypoint(x: 0.2279, y: 0.4389),
        TrackWaypoint(x: 0.2545, y: 0.4221),
        TrackWaypoint(x: 0.2780, y: 0.3970),
        TrackWaypoint(x: 0.3024, y: 0.3685),
        TrackWaypoint(x: 0.3344, y: 0.3216),
        TrackWaypoint(x: 0.3770, y: 0.2714),
        TrackWaypoint(x: 0.4196, y: 0.2328),
        TrackWaypoint(x: 0.4835, y: 0.1876),
        TrackWaypoint(x: 0.5687, y: 0.1290),
        TrackWaypoint(x: 0.6645, y: 0.0653),
        TrackWaypoint(x: 0.7338, y: 0.0117),
        TrackWaypoint(x: 0.7551, y: 0.0000),
        TrackWaypoint(x: 0.7764, y: 0.0034),
        TrackWaypoint(x: 0.7923, y: 0.0285),
        TrackWaypoint(x: 0.8083, y: 0.0419),
        TrackWaypoint(x: 0.8296, y: 0.0318),
        TrackWaypoint(x: 0.8669, y: 0.0050),
        TrackWaypoint(x: 0.8882, y: 0.0151),
        TrackWaypoint(x: 0.9148, y: 0.0620),
        TrackWaypoint(x: 0.9521, y: 0.1206),
        TrackWaypoint(x: 0.9894, y: 0.1792),
        TrackWaypoint(x: 1.0000, y: 0.2211),
        TrackWaypoint(x: 0.9925, y: 0.2496),
        TrackWaypoint(x: 0.9734, y: 0.2630),
        TrackWaypoint(x: 0.9521, y: 0.2496),
        TrackWaypoint(x: 0.9255, y: 0.2094),
        TrackWaypoint(x: 0.8935, y: 0.1658),
        TrackWaypoint(x: 0.8562, y: 0.1658),
        TrackWaypoint(x: 0.8030, y: 0.1960),
        TrackWaypoint(x: 0.7284, y: 0.2379),
        TrackWaypoint(x: 0.6645, y: 0.2831),
        TrackWaypoint(x: 0.6432, y: 0.3216),
        TrackWaypoint(x: 0.6379, y: 0.3719),
        TrackWaypoint(x: 0.6454, y: 0.4305),
        TrackWaypoint(x: 0.6624, y: 0.4724),
        TrackWaypoint(x: 0.6858, y: 0.5059),
        TrackWaypoint(x: 0.7231, y: 0.5276),
        TrackWaypoint(x: 0.7710, y: 0.5444),
        TrackWaypoint(x: 0.8190, y: 0.5678),
        TrackWaypoint(x: 0.8616, y: 0.5846),
        TrackWaypoint(x: 0.8754, y: 0.6231),
        TrackWaypoint(x: 0.8722, y: 0.6650),
        TrackWaypoint(x: 0.8669, y: 0.7069),
        TrackWaypoint(x: 0.8829, y: 0.7454),
        TrackWaypoint(x: 0.9201, y: 0.7739),
        TrackWaypoint(x: 0.9627, y: 0.8023),
        TrackWaypoint(x: 0.9894, y: 0.8358),
        TrackWaypoint(x: 0.9925, y: 0.8660),
        TrackWaypoint(x: 0.9787, y: 0.9079),
        TrackWaypoint(x: 0.9681, y: 0.9497),
        TrackWaypoint(x: 0.9521, y: 0.9799),
        TrackWaypoint(x: 0.9255, y: 1.0000),
        TrackWaypoint(x: 0.8935, y: 0.9966),
        TrackWaypoint(x: 0.8509, y: 0.9749),
        TrackWaypoint(x: 0.8083, y: 0.9363),
        TrackWaypoint(x: 0.7657, y: 0.8861),
        TrackWaypoint(x: 0.7284, y: 0.8241),
        TrackWaypoint(x: 0.6912, y: 0.7521),
        TrackWaypoint(x: 0.6699, y: 0.6985),
        TrackWaypoint(x: 0.6379, y: 0.6516),
        TrackWaypoint(x: 0.6006, y: 0.6181),
        TrackWaypoint(x: 0.5580, y: 0.5980),
        TrackWaypoint(x: 0.5261, y: 0.5946),
        TrackWaypoint(x: 0.4941, y: 0.6047),
        TrackWaypoint(x: 0.4622, y: 0.6265),
        TrackWaypoint(x: 0.4196, y: 0.6650),
        TrackWaypoint(x: 0.3876, y: 0.6951),
        TrackWaypoint(x: 0.3610, y: 0.7119),
        TrackWaypoint(x: 0.3291, y: 0.7203),
        TrackWaypoint(x: 0.2918, y: 0.7353),
        TrackWaypoint(x: 0.2567, y: 0.7487),
        TrackWaypoint(x: 0.2460, y: 0.7353),
        TrackWaypoint(x: 0.2460, y: 0.7119),
        TrackWaypoint(x: 0.2386, y: 0.7002),
        TrackWaypoint(x: 0.2300, y: 0.7052),
        TrackWaypoint(x: 0.2119, y: 0.7320)
    ]

    /// Where each sector ends, as a fraction of the lap's length, and the width over height of the whole circuit.
    private let sector1End = 0.3389
    private let sector2End = 0.7294
    private let circuitAspect: CGFloat = 1.5729

    private struct CircuitShape: Shape {
        let samples: [TrackSample]

        func path(in rect: CGRect) -> Path {
            var path = Path()
            guard let first = samples.first else { return path }
            path.move(to: first.point)
            for s in samples.dropFirst() {
                path.addLine(to: s.point)
            }
            path.closeSubpath()
            return path
        }
    }

    public init(
        clock: LapClock,
        focusMinutes: Double,
        circuit: F1Circuit = .silverstone,
        tyreCompound: TyreCompound = .medium,
        isFocusTimerRunning: Binding<Bool> = .constant(true),
        onBoxBox: @escaping () -> Void,
        onAddTime: @escaping () -> Void = {},
        onRedFlag: @escaping () -> Void = {},
        onFinishLap: @escaping () -> Void
    ) {
        self.clock = clock
        self.focusMinutes = focusMinutes
        self.circuit = circuit
        self.tyreCompound = tyreCompound
        self._isFocusTimerRunning = isFocusTimerRunning
        self.onBoxBox = onBoxBox
        self.onAddTime = onAddTime
        self.onRedFlag = onRedFlag
        self.onFinishLap = onFinishLap
    }

    private var tyreColor: Color {
        switch tyreCompound {
        case .soft: return Color(red: 255/255, green: 24/255, blue: 36/255)
        case .medium: return Color(red: 255/255, green: 210/255, blue: 0/255)
        case .hard: return Color.white
        case .intermediate: return Color(red: 57/255, green: 181/255, blue: 74/255)
        case .wet: return Color(red: 0/255, green: 140/255, blue: 255/255)
        }
    }

    private var totalSeconds: Double {
        max(1.0, focusMinutes * 60.0)
    }

    /// Time is split in three equal parts, one for each sector: the car reaches each sector's end exactly at a checkpoint.
    private func trackProgress(_ p: Double) -> Double {
        switch p {
        case ..<(1.0 / 3.0): return p * 3 * sector1End
        case ..<(2.0 / 3.0): return sector1End + (p - 1.0 / 3.0) * 3 * (sector2End - sector1End)
        default: return sector2End + (p - 2.0 / 3.0) * 3 * (1 - sector2End)
        }
    }

    /// Checkpoints reached so far: one third, two thirds, and the whole lap.
    private var checkpointsPassed: Int { min(3, Int(progress * 3 + 1e-9)) }

    private var progress: Double {
        let elapsed = totalSeconds - Double(focusSecondsRemaining)
        return max(0.0, min(1.0, elapsed / totalSeconds))
    }

    private var timeRemainingFormatted: String {
        let m = focusSecondsRemaining / 60
        let s = focusSecondsRemaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Arc-Length Parameterized Track Engine
    private struct TrackSample {
        let point: CGPoint
        let angle: Double
        let cumulativeDistance: CGFloat
    }

    private func computeTrackSamples(in size: CGSize) -> (samples: [TrackSample], totalLength: CGFloat) {
        let steps = 600
        var rawPoints: [CGPoint] = []
        rawPoints.reserveCapacity(steps)

        for s in 0..<steps {
            let t = Double(s) / Double(steps)
            let pt = rawSplinePoint(at: t, in: size)
            rawPoints.append(pt)
        }

        var samples: [TrackSample] = []
        samples.reserveCapacity(steps)
        var totalDist: CGFloat = 0.0
        // The heading is unwrapped as it goes round, so it never jumps by 360 degrees where atan2 changes sign
        // (the animation would turn the car all the way round there, a donut).
        var previousAngle: Double?

        for s in 0..<steps {
            let pt = rawPoints[s]
            let nextPt = rawPoints[(s + 1) % steps]
            let dx = nextPt.x - pt.x
            let dy = nextPt.y - pt.y
            let dist = hypot(dx, dy)
            var angle = atan2(dy, dx) * 180.0 / .pi
            if let previousAngle {
                while angle - previousAngle > 180 { angle -= 360 }
                while angle - previousAngle < -180 { angle += 360 }
            }
            previousAngle = angle

            samples.append(TrackSample(point: pt, angle: angle, cumulativeDistance: totalDist))
            totalDist += dist
        }

        return (samples, totalDist)
    }

    private func rawSplinePoint(at t: Double, in size: CGSize) -> CGPoint {
        let count = waypoints.count
        guard count > 3 else { return CGPoint(x: size.width * 0.5, y: size.height * 0.5) }

        let normalizedT = t.truncatingRemainder(dividingBy: 1.0)
        let totalT = normalizedT * Double(count)
        let i1 = Int(totalT) % count
        let i0 = (i1 - 1 + count) % count
        let i2 = (i1 + 1) % count
        let i3 = (i1 + 2) % count
        let localT = totalT - Double(Int(totalT))

        let p0 = waypoints[i0]
        let p1 = waypoints[i1]
        let p2 = waypoints[i2]
        let p3 = waypoints[i3]

        let t2 = localT * localT
        let t3 = t2 * localT

        let nx = 0.5 * ((2.0 * p1.x) +
                        (-p0.x + p2.x) * localT +
                        (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2 +
                        (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3)

        let ny = 0.5 * ((2.0 * p1.y) +
                        (-p0.y + p2.y) * localT +
                        (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 +
                        (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3)

        // A margin all round, so the track's width and its corner labels stay inside the frame
        return CGPoint(x: (0.05 + nx * 0.90) * size.width, y: (0.06 + ny * 0.88) * size.height)
    }

    // Arc-length evaluate point & angle: 100% in lockstep with Path.trim
    private func evaluateArcLengthTrackPoint(at progress: Double, samples: [TrackSample], totalLength: CGFloat) -> (point: CGPoint, angle: Double) {
        guard !samples.isEmpty, totalLength > 0 else {
            return (CGPoint.zero, 0.0)
        }

        let clampedProgress = max(0.0, min(1.0, progress))
        let targetDist = CGFloat(clampedProgress) * totalLength

        // Binary search to find segment
        var low = 0
        var high = samples.count - 1

        while low <= high {
            let mid = (low + high) / 2
            if samples[mid].cumulativeDistance <= targetDist {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let idx = max(0, min(samples.count - 1, high))
        let nextIdx = (idx + 1) % samples.count

        let current = samples[idx]
        let next = samples[nextIdx]

        let segDist = next.cumulativeDistance > current.cumulativeDistance ? (next.cumulativeDistance - current.cumulativeDistance) : (totalLength - current.cumulativeDistance)
        let delta = targetDist - current.cumulativeDistance
        let fraction = segDist > 0.001 ? max(0.0, min(1.0, delta / segDist)) : 0.0

        let interpolatedPoint = CGPoint(
            x: current.point.x + (next.point.x - current.point.x) * fraction,
            y: current.point.y + (next.point.y - current.point.y) * fraction
        )

        var diff = next.angle - current.angle
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        let interpolatedAngle = current.angle + diff * fraction

        return (interpolatedPoint, interpolatedAngle)
    }

    // Construct SVG-equivalent Path of the complete circuit from sampled points
    private func circuitPath(samples: [TrackSample]) -> Path {
        var path = Path()
        guard let first = samples.first else { return path }

        path.move(to: first.point)
        for s in samples.dropFirst() {
            path.addLine(to: s.point)
        }
        path.closeSubpath()
        return path
    }

    public var body: some View {
        NavigationStack {
        GeometryReader { geo in
            ZStack {
                // Background dark racing canvas
                Color(red: 16/255, green: 16/255, blue: 18/255)
                    .ignoresSafeArea()

                // Main HUD Content Composition
                VStack(spacing: 0) {
                    // Top Bar Row: Header Info & Coin Balance
                    topHeaderRow
                        .padding(.horizontal, geo.safeAreaInsets.leading + 32)
                        .padding(.top, 8)

                    Spacer(minLength: 8)

                    // Track Canvas with Car, Progress Trail, and Center Digital Timer
                    ZStack {
                        // 1. Circuit Track Rendering
                        circuitTrackView(size: trackSize(in: geo.size))
                            .frame(width: trackSize(in: geo.size).width, height: trackSize(in: geo.size).height)

                        // 2. Lap Progress Text (Upper Right)
                        VStack {
                            HStack {
                                Spacer()
                                Text("lap 1/1 · \(Int(progress * 100))% complete")
                                    .f1Font(size: 13, weight: .bold)
                                    .foregroundStyle(Color(white: 0.55))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .padding(.trailing, 24)
                                    .padding(.top, 12)
                            }
                            Spacer()
                        }

                        // 3. Center Digital Countdown Timer (Figma 679:3566)
                        VStack(spacing: 6) {
                            Text(timeRemainingFormatted)
                                .font(.system(size: 76, weight: .regular).monospacedDigit())
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 12)

                    // Floating Bottom Glass Panel: "Timer Control"
                    timerControlPanel
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 20) + 12)
                }

                // The checkpoint coin pops up from below, shows +1 in the middle, then flies to the coin badge
                coinPop(in: geo.size)
            }
            .coordinateSpace(name: "cockpit")
        }
        // The system's back button leaves the lap, in the toolbar where people look for it
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    F1LiveActivityManager.shared.endLapActivity()
                    onBoxBox()
                } label: { Image(systemName: "chevron.backward") }
                .tint(.white)
                .foregroundStyle(.white)
                .accessibilityLabel("Back to Timer Setup")
            }
        }
        }
        .f1Feedback(.success, trigger: coinLanded)
        .onChange(of: checkpointsPassed) { old, new in
            // A coin for each checkpoint: a third of the way, two thirds, and the finish
            if new > old && isFocusTimerRunning { Task { await popCoin() } }
        }
        .onDisappear {
            F1LiveActivityManager.shared.endLapActivity()
        }
        .onReceive(timerPublisher) { _ in
            guard isFocusTimerRunning else { return }
            // The parent owns the clock and the coins: it ends the lap when time runs out.
            if focusSecondsRemaining == 0 {
                F1LiveActivityManager.shared.endLapActivity()
                onFinishLap()
            }
        }
    }

    // MARK: - Top Header Row (Figma 679:3566)
    private var topHeaderRow: some View {
        HStack(alignment: .top) {
            // Left Title Block paired with Native Chevron Back Button
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stay on track.")
                        .f1Font(size: 40, weight: .bold)
                        .foregroundStyle(Color.white)

                    Text("Work Hard, Stay Focused, Make it happen")
                        .f1Font(size: 16, weight: .medium)
                        .foregroundStyle(Color(white: 0.60))
                }
            }

            Spacer()

            // Right Coin Badge ($ 0)
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 255/255, green: 215/255, blue: 0/255),
                                    Color(red: 255/255, green: 165/255, blue: 0/255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                        .shadow(color: Color(red: 255/255, green: 180/255, blue: 0/255).opacity(0.40), radius: 4)

                    Text("$")
                        .f1Font(size: 21, weight: .bold)
                        .foregroundStyle(Color.black.opacity(0.85))
                }

                Text("\(max(0, progressManager.coins - coinsInFlight))")
                    .f1Font(size: 24, weight: .bold)
                    .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                    .contentTransition(.numericText())
            }
            .phaseAnimator([1.0, 1.14, 1.0], trigger: coinLanded) { view, scale in view.scaleEffect(scale) } animation: { _ in .snappy(duration: 0.18) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("cockpit")) } action: { badgeFrame = $0 }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .f1Glass(in: Capsule())
            .contentShape(Capsule())
            .hoverEffect(.highlight)
        }
    }

    // MARK: - Clean, Minimal Track Canvas for Focus (Figma 679:3566 Parity)
    /// The circuit keeps the proportions it has in the design, as large as the screen allows.
    private func trackSize(in screen: CGSize) -> CGSize {
        let height = min(screen.height * 0.62, (screen.width - 96) / circuitAspect)
        return CGSize(width: height * circuitAspect, height: height)
    }

    private func circuitTrackView(size: CGSize) -> some View {
        let trackData = computeTrackSamples(in: size)
        let samples = trackData.samples
        let totalLength = trackData.totalLength

        let arc = trackProgress(progress)
        // Lines, car and labels grow with the track
        let unit = max(1, size.width / 720)
        let currentEval = evaluateArcLengthTrackPoint(at: arc, samples: samples, totalLength: totalLength)
        let startPoint = samples.first?.point ?? CGPoint.zero
        let firstEval = evaluateArcLengthTrackPoint(at: sector1End, samples: samples, totalLength: totalLength)
        let secondEval = evaluateArcLengthTrackPoint(at: sector2End, samples: samples, totalLength: totalLength)
        let red = Color(red: 255/255, green: 24/255, blue: 36/255)
        let blue = Color(red: 28/255, green: 169/255, blue: 236/255)
        let yellow = Color(red: 255/255, green: 196/255, blue: 0/255)

        return ZStack {
            // 1. Dark edge of the track
            CircuitShape(samples: samples)
                .stroke(Color(red: 26/255, green: 26/255, blue: 30/255), style: StrokeStyle(lineWidth: 22 * unit, lineCap: .round, lineJoin: .round))

            // 2. The circuit in its three sector colours, dimmed until the car has driven them
            ForEach(Array(zip([0.0, sector1End, sector2End], [sector1End, sector2End, 1.0]).enumerated()), id: \.offset) { index, range in
                CircuitShape(samples: samples)
                    .trim(from: range.0, to: range.1)
                    .stroke([red, blue, yellow][index].opacity(0.28), style: StrokeStyle(lineWidth: 11 * unit, lineCap: .round, lineJoin: .round))
            }

            // 3. The part already driven, bright, sector by sector
            ForEach(Array(zip([0.0, sector1End, sector2End], [sector1End, sector2End, 1.0]).enumerated()), id: \.offset) { index, range in
                CircuitShape(samples: samples)
                    .trim(from: range.0, to: max(range.0, min(range.1, CGFloat(arc))))
                    .stroke([red, blue, yellow][index], style: StrokeStyle(lineWidth: 11 * unit, lineCap: .round, lineJoin: .round))
                    .shadow(color: [red, blue, yellow][index].opacity(0.6), radius: 5)
            }
            .animation(isFocusTimerRunning ? .linear(duration: 1.0) : .none, value: progress)

            // 4. Start / finish line: the third coin is earned here, at the end of the timer
            checkpointMarker(title: "finish", isPassed: checkpointsPassed >= 3, at: startPoint, yOffset: 44, symbol: "flag.checkered", scale: unit)

            // 5. Checkpoints at the end of sector 1 and sector 2: a coin each
            checkpointMarker(title: "checkpoint 1", isPassed: checkpointsPassed >= 1, at: firstEval.point, yOffset: 42, scale: unit)
            checkpointMarker(title: "checkpoint 2", isPassed: checkpointsPassed >= 2, at: secondEval.point, yOffset: 42, scale: unit)

            // 6. The F1 car on the track
            f1CarSprite
                .scaleEffect(unit)
                .rotationEffect(.degrees(currentEval.angle))
                .position(currentEval.point)
                .animation(isFocusTimerRunning ? .linear(duration: 1.0) : .none, value: progress)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Checkpoint coin

    private func coinPop(in size: CGSize) -> some View {
        let start = CGPoint(x: size.width / 2, y: size.height + 90)
        let middle = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
        let badge = CGPoint(x: badgeFrame.minX + 28, y: badgeFrame.midY)
        let position = coinStage == 1 ? start : (coinStage == 2 ? middle : badge)
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 255/255, green: 215/255, blue: 0/255), Color(red: 255/255, green: 165/255, blue: 0/255)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Color(red: 255/255, green: 180/255, blue: 0/255).opacity(0.6), radius: 18)
                Text("$")
                    .f1Font(size: 54, weight: .bold)
                    .foregroundStyle(Color.black.opacity(0.85))
            }
            .frame(width: 110, height: 110)

            Text("+1")
                .f1Font(size: 46, weight: .bold)
                .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                .opacity(coinStage == 2 ? 1 : 0)
        }
        .scaleEffect(coinStage == 3 ? 0.26 : (coinStage == 2 ? 1 : 0.5))
        .opacity(coinStage == 0 ? 0 : (coinStage == 1 ? 0 : 1))
        .position(position)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A short, precise reward: the coin rises, shows what was earned, then lands in the badge. With Reduce Motion
    /// it fades in and out where it is, and the count still rises.
    private func popCoin() async {
        coinsInFlight = 1
        if reduceMotion {
            withAnimation(.easeIn(duration: 0.2)) { coinStage = 2 }
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeOut(duration: 0.2)) { coinStage = 0 }
            try? await Task.sleep(for: .seconds(0.2))
        } else {
            coinStage = 1
            try? await Task.sleep(for: .seconds(0.05))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { coinStage = 2 }
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeIn(duration: 0.55)) { coinStage = 3 }
            try? await Task.sleep(for: .seconds(0.55))
            withAnimation(.easeOut(duration: 0.15)) { coinStage = 0 }
        }
        withAnimation(.snappy) { coinsInFlight = 0; coinLanded += 1 }
    }

    private func checkpointMarker(title: String, isPassed: Bool, at point: CGPoint, yOffset: CGFloat, symbol: String? = nil, scale: CGFloat = 1) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isPassed ? Color(red: 46/255, green: 204/255, blue: 113/255).opacity(0.25) : Color.black.opacity(0.65))
                    .frame(width: 34, height: 34)

                Circle()
                    .stroke(
                        isPassed ? Color(red: 46/255, green: 204/255, blue: 113/255) : Color(red: 255/255, green: 215/255, blue: 0/255),
                        lineWidth: 3
                    )
                    .frame(width: 31, height: 31)

                if isPassed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(red: 46/255, green: 204/255, blue: 113/255))
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(red: 255/255, green: 215/255, blue: 0/255))
                } else {
                    Text("$")
                        .f1Font(size: 17, weight: .bold)
                        .foregroundStyle(Color(red: 255/255, green: 215/255, blue: 0/255))
                }
            }

            Text(title)
                .f1Font(size: 12, weight: .bold)
                .foregroundStyle(isPassed ? Color(red: 46/255, green: 204/255, blue: 113/255) : Color(white: 0.75))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.black.opacity(0.70)))
        }
        .scaleEffect(scale)
        .position(x: point.x, y: point.y + yOffset * scale)
    }

    // MARK: - F1 car (top-down, drawn as one Canvas layer)
    /// A modern single-seater seen from above, nose to the right: a multi-element front wing, a tapered monocoque, sculpted
    /// sidepods, halo and helmet, wide rear wing with a DRS flap, and four tyres ringed in the chosen compound's colour.
    /// It is one drawing instead of dozens of nested views, so it moves around the track without costing a frame.
    private var f1CarSprite: some View {
        let ring = tyreColor
        let running = isFocusTimerRunning
        return Canvas { context, size in
            // Drawn on a 120 x 54 grid, scaled to the frame
            context.scaleBy(x: size.width / 120, y: size.height / 54)
            let red = Color(red: 225/255, green: 6/255, blue: 0/255)
            let deepRed = Color(red: 150/255, green: 0, blue: 0)
            let carbon = Color(white: 0.09)

            func rrect(_ r: CGRect, _ radius: CGFloat) -> Path { Path(roundedRect: r, cornerRadius: radius, style: .continuous) }

            // Exhaust glow, brighter while the lap runs
            let glow = Path(ellipseIn: CGRect(x: -6, y: 21, width: 34, height: 12))
            context.fill(glow, with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.82, blue: 0).opacity(running ? 0.55 : 0), Color(red: 1, green: 0.1, blue: 0.14).opacity(running ? 0.75 : 0.2), .clear]),
                startPoint: CGPoint(x: 28, y: 27), endPoint: CGPoint(x: -6, y: 27)))

            // Tyres: rear 22 x 10, front 18 x 9, each with the compound ring and a hub
            func tyre(_ r: CGRect) {
                context.fill(rrect(r, 4), with: .color(Color(red: 20/255, green: 20/255, blue: 22/255)))
                context.stroke(rrect(r.insetBy(dx: 1.6, dy: 1.6), 3), with: .color(ring), lineWidth: 1.4)
                context.fill(Path(ellipseIn: CGRect(x: r.midX - 3, y: r.midY - 1.6, width: 6, height: 3.2)), with: .color(Color(white: 0.4)))
            }
            tyre(CGRect(x: 20, y: 3, width: 22, height: 10))
            tyre(CGRect(x: 20, y: 41, width: 22, height: 10))
            tyre(CGRect(x: 78, y: 5, width: 18, height: 9))
            tyre(CGRect(x: 78, y: 40, width: 18, height: 9))

            // Suspension arms
            var arms = Path()
            for y in [13.0, 41.0] { arms.move(to: CGPoint(x: 31, y: y)); arms.addLine(to: CGPoint(x: 46, y: 24 + (y > 27 ? 6 : 0))) }
            for y in [14.0, 40.0] { arms.move(to: CGPoint(x: 87, y: y)); arms.addLine(to: CGPoint(x: 76, y: 24 + (y > 27 ? 6 : 0))) }
            context.stroke(arms, with: .color(Color(white: 0.2)), lineWidth: 1.2)

            // Floor
            context.fill(rrect(CGRect(x: 26, y: 13, width: 66, height: 28), 5), with: .color(carbon))

            // Rear wing: mainplane, DRS flap and red endplates
            context.fill(rrect(CGRect(x: 6, y: 8, width: 9, height: 38), 1.5), with: .color(carbon))
            context.fill(rrect(CGRect(x: 4.5, y: 9, width: 3.2, height: 36), 1), with: .color(Color(white: 0.2)))
            context.fill(rrect(CGRect(x: 5, y: 6.5, width: 11, height: 3.5), 1), with: .color(red))
            context.fill(rrect(CGRect(x: 5, y: 44, width: 11, height: 3.5), 1), with: .color(red))
            context.fill(Path(ellipseIn: CGRect(x: 14.5, y: 25.6, width: 2.8, height: 2.8)), with: .color(Color(red: 1, green: 0.1, blue: 0.14)))

            // Sidepods: wide at the inlets, then sweeping in towards the rear (the "coke bottle")
            func pod(_ sign: CGFloat) -> Path {
                func y(_ v: CGFloat) -> CGFloat { 27 + sign * v }
                var p = Path()
                p.move(to: CGPoint(x: 70, y: y(3.5)))
                p.addQuadCurve(to: CGPoint(x: 62, y: y(12.5)), control: CGPoint(x: 69, y: y(12.5)))
                p.addLine(to: CGPoint(x: 46, y: y(12)))
                p.addQuadCurve(to: CGPoint(x: 26, y: y(5)), control: CGPoint(x: 36, y: y(11)))
                p.addLine(to: CGPoint(x: 26, y: y(3)))
                p.closeSubpath()
                return p
            }
            for sign in [CGFloat(-1), 1] {
                context.fill(pod(sign), with: .linearGradient(Gradient(colors: [red, deepRed]), startPoint: CGPoint(x: 60, y: 14), endPoint: CGPoint(x: 30, y: 40)))
                context.fill(rrect(CGRect(x: 63, y: sign < 0 ? 15.2 : 35.2, width: 5, height: 3.6), 1.5), with: .color(carbon))
            }

            // Monocoque: a tapered body, wide at the engine cover and narrowing to the nose
            var body = Path()
            let top: [(CGFloat, CGFloat)] = [(16, 22.5), (36, 20.5), (54, 21.5), (74, 24), (96, 25.4), (110, 26.2)]
            body.move(to: CGPoint(x: top[0].0, y: top[0].1))
            for pt in top.dropFirst() { body.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
            body.addQuadCurve(to: CGPoint(x: 110, y: 27.8), control: CGPoint(x: 118, y: 27))
            for pt in top.reversed() { body.addLine(to: CGPoint(x: pt.0, y: 54 - pt.1)) }
            body.closeSubpath()
            context.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 250/255, green: 28/255, blue: 18/255), red, deepRed]),
                                                     startPoint: CGPoint(x: 0, y: 20), endPoint: CGPoint(x: 0, y: 34)))
            // A white stripe down the spine
            context.fill(rrect(CGRect(x: 34, y: 26.2, width: 44, height: 1.6), 0.8), with: .color(.white.opacity(0.85)))

            // Engine cover fin running back to the rear wing
            var fin = Path()
            fin.move(to: CGPoint(x: 18, y: 26.4)); fin.addLine(to: CGPoint(x: 54, y: 26.2))
            fin.addLine(to: CGPoint(x: 54, y: 27.8)); fin.addLine(to: CGPoint(x: 18, y: 27.6)); fin.closeSubpath()
            context.fill(fin, with: .color(Color(white: 0.06)))

            // Airbox, cockpit, halo and helmet
            context.fill(rrect(CGRect(x: 46, y: 24.4, width: 9, height: 5.2), 2.6), with: .color(Color(white: 0.14)))
            context.fill(rrect(CGRect(x: 54, y: 23, width: 16, height: 8), 4), with: .color(.black))
            context.fill(Path(ellipseIn: CGRect(x: 56.3, y: 23.8, width: 6.4, height: 6.4)), with: .color(Color(red: 1, green: 0.82, blue: 0)))
            context.fill(rrect(CGRect(x: 60.2, y: 24.6, width: 2.8, height: 4.8), 1), with: .color(Color(white: 0.08)))
            var halo = Path()
            halo.move(to: CGPoint(x: 55, y: 22.6))
            halo.addQuadCurve(to: CGPoint(x: 68.5, y: 27), control: CGPoint(x: 66, y: 22.6))
            halo.addQuadCurve(to: CGPoint(x: 55, y: 31.4), control: CGPoint(x: 66, y: 31.4))
            context.stroke(halo, with: .color(Color(white: 0.3)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // Front wing: three stacked elements across the full width, red endplates, and a pylon to the nose
            context.fill(rrect(CGRect(x: 101, y: 26, width: 8, height: 2), 1), with: .color(carbon))
            context.fill(rrect(CGRect(x: 107, y: 2.5, width: 4, height: 49), 1.5), with: .color(carbon))
            context.fill(rrect(CGRect(x: 111.5, y: 4, width: 2.6, height: 46), 1), with: .color(Color(white: 0.22)))
            context.fill(rrect(CGRect(x: 114.4, y: 6, width: 2, height: 42), 1), with: .color(Color(white: 0.34)))
            context.fill(rrect(CGRect(x: 105, y: 1, width: 12, height: 3.4), 1), with: .color(red))
            context.fill(rrect(CGRect(x: 105, y: 49.6, width: 12, height: 3.4), 1), with: .color(red))
        }
        .frame(width: 72, height: 32)
        .shadow(color: Color.black.opacity(0.6), radius: 4, y: 2)
        .drawingGroup()
    }

    // MARK: - Floating Bottom Panel: Timer Control (Figma 679:3566)
    private var timerControlPanel: some View {
        VStack(spacing: 16) {
            Text("Timer Control")
                .f1Font(size: 28, weight: .bold)
                .foregroundStyle(Color.white)

            HStack(spacing: 24) {
                let notStarted = focusSecondsRemaining >= Int(focusMinutes * 60)
                let startLabel = isFocusTimerRunning ? "Pause" : (notStarted ? "Start" : "Resume")
                Button {
                    isFocusTimerRunning.toggle()
                    F1LiveActivityManager.shared.updateLapProgress(
                        remainingSeconds: focusSecondsRemaining,
                        totalMinutes: focusMinutes,
                        isPaused: !isFocusTimerRunning,
                        topicTitle: "Focus Lap Stint"
                    )
                } label: {
                    Text(startLabel)
                        .f1Font(size: 18, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(width: 116, height: 52)
                }
                .f1GlassProminentButtonStyle()
                .tint(F1Theme.accent)
                .accessibilityLabel("\(startLabel) stint timer")

                Button {
                    onFinishLap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                        Text("Finish")
                    }
                    .f1Font(size: 18, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 130, height: 52)
                }
                .f1GlassButtonStyle()
                .accessibilityLabel("Finish session")
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 22/255, green: 22/255, blue: 26/255).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, y: 10)
    }
}
