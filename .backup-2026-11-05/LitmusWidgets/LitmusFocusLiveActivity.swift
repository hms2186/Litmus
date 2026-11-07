//
//  LitmusFocusLiveActivity.swift
//  The focus timer as a Live Activity, drawn like a pit-wall timing tower.
//
//  - The countdown and the three sector bars are driven by time itself (`Text(timerInterval:)`, `ProgressView(timerInterval:)`),
//    so they keep running with the app in the background and cost no updates.
//  - The bars are the circuit's sectors, red, blue and yellow, as in the app's track; each one ends on a coin checkpoint.
//  - The Lock Screen card is Liquid Glass: a light tint lets the system's glass through, and the chips and the tyre
//    badge are glass of their own, grouped in one container so they blend as they sit close.
//

import WidgetKit
import SwiftUI
import ActivityKit

private enum Paint {
    static let sectorRed = Color(red: 255/255, green: 38/255, blue: 48/255)
    static let sectorBlue = Color(red: 38/255, green: 178/255, blue: 244/255)
    static let sectorYellow = Color(red: 255/255, green: 204/255, blue: 20/255)
    static let coin = Color(red: 255/255, green: 197/255, blue: 59/255)
    static let ink = Color(red: 10/255, green: 10/255, blue: 12/255)

    static func tyre(_ compound: String) -> Color {
        switch compound.lowercased() {
        case "soft": return Color(red: 255/255, green: 38/255, blue: 48/255)
        case "medium": return Color(red: 255/255, green: 210/255, blue: 0/255)
        case "hard": return .white
        case "intermediate": return Color(red: 57/255, green: 181/255, blue: 74/255)
        case "wet": return Color(red: 0/255, green: 140/255, blue: 255/255)
        default: return .white
        }
    }
}

struct LitmusFocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: F1FocusLapActivityAttributes.self) { context in
            LockScreenTimer(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Paint.ink.opacity(0.62))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TyreBadge(compound: context.attributes.tyreCompound)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: context.state, size: 30)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.topicTitle)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SectorBars(state: context.state, height: 6)
                        .padding(.top, 4)
                }
            } compactLeading: {
                TyreBadge(compound: context.attributes.tyreCompound, compact: true)
            } compactTrailing: {
                CountdownText(state: context.state, size: 14)
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paint.sectorYellow)
            }
            .keylineTint(Paint.sectorRed)
        }
    }
}

// MARK: - Lock Screen

/// The Lock Screen card: the subject and topic and a stopwatch pill on the left, the engineer leaning in from the
/// right, and the three sector bars along the bottom with the car on its way to the next coin. Text is SF Pro
/// (the system font, which is SF Pro Display from 20 pt up).
private struct LockScreenTimer: View {
    let attributes: F1FocusLapActivityAttributes
    let state: F1FocusLapActivityAttributes.ContentState

    private var subjectLabel: String {
        let subject = attributes.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return "LITMUS · " + (subject.isEmpty ? "FOCUS" : subject.uppercased())
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Circle().fill(Paint.sectorRed).frame(width: 7, height: 7)
                        Text(subjectLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(2.6)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Text(state.topicTitle)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    TimerPill(state: state)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

                FocusEngineer()
                    .padding(.leading, 6)
            }

            SectorBars(state: state, height: 6, showsCar: true)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        // A red edge on the left, like the pit-wall display
        .overlay(alignment: .leading) {
            Capsule().fill(Paint.sectorRed).frame(width: 3.5).padding(.vertical, 12)
        }
    }
}

/// The stopwatch and the time left, in a dark pill with a red edge.
private struct TimerPill: View {
    let state: F1FocusLapActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "stopwatch")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Paint.sectorYellow)
            // The system draws the running timer, so it is given a width of its own (mm:ss in 36 pt italic) to keep the pill snug
            CountdownText(state: state, size: 36, italic: true)
                .frame(width: 104, alignment: .leading)
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient(colors: [Paint.sectorRed.opacity(0.9), Paint.sectorRed.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time left")
    }
}

/// The engineer resting on the sector bars, with his note.
private struct FocusEngineer: View {
    var body: some View {
        Image("focus_boy")
            .resizable()
            .scaledToFit()
            .frame(height: 96)
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Keep\nGoing!")
                        .font(.custom("BradleyHandITCTT-Bold", size: 15))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(-3)
                        .rotationEffect(.degrees(-8))
                    Capsule().fill(.white.opacity(0.9)).frame(width: 22, height: 1.5)
                        .rotationEffect(.degrees(-20))
                        .offset(x: 10, y: 2)
                }
                .fixedSize()
                .offset(x: 30, y: 14)
            }
            .padding(.trailing, 22)
            .accessibilityHidden(true)
    }
}

// MARK: - Pieces

/// The remaining time. While running it counts down by itself; paused, it shows the time that was left.
private struct CountdownText: View {
    let state: F1FocusLapActivityAttributes.ContentState
    let size: CGFloat
    var italic = false

    var body: some View {
        Group {
            if state.isPaused {
                Text(String(format: "%d:%02d", state.secondsRemaining / 60, state.secondsRemaining % 60))
            } else {
                Text(timerInterval: Date.now...max(state.endTime, Date.now.addingTimeInterval(1)), pauseTime: nil, countsDown: true, showsHours: false)
            }
        }
        .font(italic ? .system(size: size, weight: .heavy).italic().monospacedDigit() : .system(size: size, weight: .heavy).monospacedDigit())
        .foregroundStyle(Paint.sectorYellow)
        .shadow(color: Paint.sectorYellow.opacity(italic ? 0.45 : 0), radius: 8)
        .multilineTextAlignment(.leading)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
}

/// Three bars, one per sector of the circuit; each fills during its third of the timer and ends on a coin. The car
/// drives along the top edge of the bars, to the point the timer has reached.
private struct SectorBars: View {
    let state: F1FocusLapActivityAttributes.ContentState
    let height: CGFloat
    /// The car is only drawn on the Lock Screen card, not in the Dynamic Island
    var showsCar = false

    private let colors = [Paint.sectorRed, Paint.sectorBlue, Paint.sectorYellow]
    private let carWidth: CGFloat = 92

    /// How far through the timer it is as this view is drawn: from the clock while it runs, as it stood while paused.
    private var progress: Double {
        if state.isPaused { return min(1, max(0, state.lapProgress)) }
        let total = max(1, state.endTime.timeIntervalSince(state.startTime))
        return min(1, max(0, Date.now.timeIntervalSince(state.startTime) / total))
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("S\(index + 1)")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(colors[index])
                        .shadow(color: colors[index].opacity(0.55), radius: 5)
                    bar(index)
                    if index == 2 { FinishFlag(size: 26) } else { CoinMark(size: 26) }
                }
            }
        }
        // The car drives along the top edge of the bars, to the point the timer has reached
        .overlay(alignment: .topLeading) {
            if showsCar {
                GeometryReader { geo in
                    // Each update glides the car to its new place (a linear move of up to 2 s, the longest a widget animates)
                    CarMark(width: carWidth)
                        .offset(x: progress * max(0, geo.size.width - carWidth), y: -19)
                        .animation(.linear(duration: 2), value: progress)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Three checkpoints, one coin each")
    }

    @ViewBuilder
    private func bar(_ sector: Int) -> some View {
        let total = state.endTime.timeIntervalSince(state.startTime)
        let from = state.startTime.addingTimeInterval(total * Double(sector) / 3)
        let to = state.startTime.addingTimeInterval(total * Double(sector + 1) / 3)
        Group {
            if state.isPaused {
                // A paused timer cannot run a bar on its own: show how far it got
                ProgressView(value: min(1, max(0, state.lapProgress * 3 - Double(sector))))
                    .progressViewStyle(.linear)
            } else {
                ProgressView(timerInterval: from...max(to, from.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
            }
        }
        .tint(colors[sector])
        .frame(height: height)
        .shadow(color: colors[sector].opacity(0.5), radius: 4)
    }
}

/// The car with a red motion trail behind it.
private struct CarMark: View {
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(colors: [.clear, Paint.sectorRed.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.55, height: 4)
                .clipShape(Capsule())
                .blur(radius: 1.2)
                .offset(x: -width * 0.42)
            Image("focus_car")
                .resizable()
                .scaledToFit()
                .frame(width: width)
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }
}

/// The app's coin (as in its coin badge): a gold disc with a darker face and a "$", the checkpoint at the end of each sector.
private struct CoinMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 255/255, green: 197/255, blue: 89/255))
            Circle().fill(Color(red: 176/255, green: 119/255, blue: 13/255)).padding(size * 0.09)
            Text("$")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(Color(red: 255/255, green: 214/255, blue: 130/255))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The chequered flag that ends the last sector.
private struct FinishFlag: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "flag.checkered")
            .font(.system(size: size * 0.8, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The tyre compound as a ring in its colour with the compound's letter.
private struct TyreBadge: View {
    let compound: String
    var compact = false

    var body: some View {
        let size: CGFloat = compact ? 20 : 34
        ZStack {
            Circle().fill(.black.opacity(0.35))
            Circle().stroke(Paint.tyre(compound), lineWidth: compact ? 3 : 4.5)
            Text(String(compound.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .glassEffect(.regular, in: Circle())
        .accessibilityLabel("\(compound) tyres")
    }
}
