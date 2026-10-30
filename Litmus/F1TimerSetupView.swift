//
//  F1TimerSetupView.swift
//  Prototype
//
//  Exact 1:1 Implementation of Figma Node 589:4885 (Choose Your Timer).
//  Adheres to Apple HIG and user skills:
//  - Strictly NO track selection (as specified by user & Figma 589:4885).
//  - Title: "Choose Your Timer" ("Timer" in bright racing red).
//  - Custom timer dropdown selector: "Choose Custom Timer" + "15 mins".
//  - 5 Pirelli Tyre Presets:
//    1. SOFT (15 min - SOFT · QUICK STINT)
//    2. MEDIUM (25 min - MEDIUM · STANDARD FOCUS)
//    3. HARD (45 min - HARD · DEEP STUDY SESSION)
//    4. INTERMEDIATE (60 min - INTERMEDIATE · FULL CHAPTER)
//    5. WET (80 min - WET · EXTENDED MARATHON)
//  - Selected state: 3pt solid red rounded border.
//  - Action buttons: "Skip timer" (gray) & "Begin" (blue).
//

import SwiftUI

public struct F1TimerSetupView: View {
    @Binding public var selectedCircuit: F1Circuit
    @Binding public var focusMinutes: Double
    @Binding public var selectedTyre: TyreCompound
    public var onLightsOut: () -> Void
    public var onSkipTimer: (() -> Void)? = nil
    /// A timer suggested for the chosen topic, with the reason shown beside it.
    public var recommendation: F1TimerRecommendation? = nil
    public var topicTitle: String = ""

    // 5 Pirelli Tyre Compounds from Figma Node 589:4885
    public struct PresetStrategy: Identifiable {
        public let id: String
        public let compound: TyreCompound
        public let letter: String
        public let color: Color
        public let minutes: Int
        public let title: String
        public let subtitle: String
        public let assetName: String
    }

    private let presets: [PresetStrategy] = [
        PresetStrategy(
            id: "soft",
            compound: .soft,
            letter: "S",
            color: Color(red: 255/255, green: 24/255, blue: 36/255),
            minutes: 15,
            title: "15 min",
            subtitle: "SOFT · QUICK STINT",
            assetName: "tyre_soft"
        ),
        PresetStrategy(
            id: "medium",
            compound: .medium,
            letter: "M",
            color: Color(red: 255/255, green: 210/255, blue: 0/255),
            minutes: 25,
            title: "25 min",
            subtitle: "MEDIUM · STANDARD FOCUS",
            assetName: "tyre_medium"
        ),
        PresetStrategy(
            id: "hard",
            compound: .hard,
            letter: "H",
            color: Color.white,
            minutes: 45,
            title: "45 min",
            subtitle: "HARD · DEEP STUDY SESSION",
            assetName: "tyre_hard"
        ),
        PresetStrategy(
            id: "inter",
            compound: .intermediate,
            letter: "I",
            color: Color(red: 57/255, green: 181/255, blue: 74/255),
            minutes: 60,
            title: "60 min",
            subtitle: "INTERMEDIATE · FULL CHAPTER",
            assetName: "tyre_inter"
        ),
        PresetStrategy(
            id: "wet",
            compound: .wet,
            letter: "W",
            color: Color(red: 0/255, green: 140/255, blue: 255/255),
            minutes: 80,
            title: "80 min",
            subtitle: "WET · EXTENDED MARATHON",
            assetName: "tyre_wet"
        )
    ]


    public init(
        selectedCircuit: Binding<F1Circuit> = .constant(.silverstone),
        focusMinutes: Binding<Double>,
        selectedTyre: Binding<TyreCompound>,
        onLightsOut: @escaping () -> Void,
        onSkipTimer: (() -> Void)? = nil,
        recommendation: F1TimerRecommendation? = nil,
        topicTitle: String = ""
    ) {
        self._selectedCircuit = selectedCircuit
        self._focusMinutes = focusMinutes
        self._selectedTyre = selectedTyre
        self.onLightsOut = onLightsOut
        self.onSkipTimer = onSkipTimer
        self.recommendation = recommendation
        self.topicTitle = topicTitle
    }

    private func updateCompoundForMinutes(_ mins: Int) {
        if mins <= 15 { selectedTyre = .soft }
        else if mins <= 25 { selectedTyre = .medium }
        else if mins <= 45 { selectedTyre = .hard }
        else if mins <= 60 { selectedTyre = .intermediate }
        else { selectedTyre = .wet }
    }

    private func setWheel(hours: Int, minutes: Int) {
        let total = min(max(hours * 60 + minutes, 1), 180)
        focusMinutes = Double(total)
        updateCompoundForMinutes(total)
    }

    private var wheelHours: Binding<Int> {
        Binding(get: { Int(focusMinutes) / 60 },
                set: { setWheel(hours: $0, minutes: Int(focusMinutes) % 60) })
    }

    private var wheelMinutes: Binding<Int> {
        Binding(get: { Int(focusMinutes) % 60 },
                set: { setWheel(hours: Int(focusMinutes) / 60, minutes: $0) })
    }

    private func selectStrategy(_ preset: PresetStrategy) {
        selectedTyre = preset.compound
        focusMinutes = Double(preset.minutes)
    }

    public var body: some View {
        timerBody
    }

    private var timerBody: some View {
        VStack {
            Spacer()

            // Main Figma 589:4885 Card
            VStack(alignment: .leading, spacing: 32) {
                // Header: Choose Your Timer
                HStack(spacing: 0) {
                    Text("Choose Your ")
                        .f1Font(size: 48, weight: .bold)
                        .foregroundStyle(Color.white)
                    
                    Text("Timer")
                        .f1Font(size: 48, weight: .bold)
                        .foregroundStyle(Color(red: 255/255, green: 186/255, blue: 73/255))
                    
                    Spacer()
                }

                // Clock-style wheel picker (hours + minutes)
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Text("Custom Timer")
                            .f1Font(size: 17, weight: .regular)
                            .foregroundStyle(Color(white: 0.75))
                            .padding(.trailing, 12)
                        Picker("Hours", selection: wheelHours) {
                            ForEach(0...3, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 70, height: 120)
                        .clipped()
                        Text("hr").f1Font(size: 15, weight: .medium).foregroundStyle(Color(white: 0.6))
                        Picker("Minutes", selection: wheelMinutes) {
                            ForEach(0...59, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 70, height: 120)
                        .clipped()
                        Text("min").f1Font(size: 15, weight: .medium).foregroundStyle(Color(white: 0.6))
                    }
                    .environment(\.colorScheme, .dark)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                    )
                    Spacer()
                }

                // 5 Pirelli Presets Row
                HStack(spacing: 20) {
                    ForEach(presets) { preset in
                        let isSelected = selectedTyre == preset.compound && Int(focusMinutes) == preset.minutes

                        Button {
                            withAnimation(AppMotionSystem.snappy) {
                                selectStrategy(preset)
                            }
                        } label: {
                            VStack(spacing: 14) {
                                // Pirelli Tyre Icon Badge (matching Figma 589:4885)
                                ZStack {
                                    Circle()
                                        .fill(Color(white: 0.10))
                                        .frame(width: 80, height: 80)
                                    
                                    // Outer tyre sidewall
                                    Circle()
                                        .stroke(Color(white: 0.22), lineWidth: 8)
                                        .frame(width: 72, height: 72)
                                    
                                    // Compound Color Ring
                                    Circle()
                                        .stroke(preset.color, lineWidth: 5)
                                        .frame(width: 58, height: 58)
                                    
                                    // Compound Letter (SF Pro Display)
                                    Text(preset.letter)
                                        .f1Font(size: 26, weight: .bold)
                                        .foregroundStyle(preset.color)
                                }
                                .scaleEffect(isSelected ? 1.06 : 1.0)
                                .animation(AppMotionSystem.snappy, value: isSelected)
                                .padding(.top, 8)

                                // Duration & Subtitle
                                VStack(spacing: 4) {
                                    Text(preset.title)
                                        .f1Font(size: 19, weight: .semibold)
                                        .foregroundStyle(Color.white)
                                    
                                    Text(preset.subtitle)
                                        .f1Font(size: 10, weight: .medium)
                                        .foregroundStyle(Color(white: 0.65))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .padding(.bottom, 6)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 10)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(
                                        isSelected ?
                                        Color(red: 10/255, green: 132/255, blue: 255/255) :
                                        Color.white.opacity(0.18),
                                        lineWidth: isSelected ? 3 : 0.75
                                    )
                            )
                            .shadow(
                                color: isSelected ? Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.35) : Color.clear,
                                radius: 10,
                                y: 3
                            )
                        }
                        .buttonStyle(.f1CardSpring)
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .hoverEffect(.lift)
                        .overlay(alignment: .top) {
                            if recommendation?.minutes == preset.minutes {
                                Text("Recommended")
                                    .f1Font(size: 12, weight: .semibold)
                                    .foregroundStyle(.black.opacity(0.85))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(red: 255/255, green: 186/255, blue: 73/255), in: Capsule())
                                    .offset(y: -10)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .accessibilityLabel("Select \(preset.title) tyre strategy\(recommendation?.minutes == preset.minutes ? ", recommended for your topic" : "")")
                    }
                }

                // Action Buttons Row: "Skip timer" & "Begin"
                HStack(spacing: 18) {
                    Spacer()

                    // Skip Timer Button (Official Apple Bordered)
                    Button {
                        onSkipTimer?()
                    } label: {
                        Text("Skip timer")
                            .f1Font(size: 17, weight: .semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(Color.white.opacity(0.85))
                    .contentShape(Capsule())
                    .hoverEffect(.lift)
                    .accessibilityLabel("Skip Timer and enter Team Radio")

                    // Begin Button (Official Apple Bordered Prominent)
                    Button {
                        onLightsOut()
                    } label: {
                        Text("Begin")
                            .f1Font(size: 17, weight: .semibold)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(Color(red: 0/255, green: 136/255, blue: 255/255))
                    .contentShape(Capsule())
                    .hoverEffect(.lift)
                    .accessibilityLabel("Begin Focus Stint")

                    Spacer()
                }
                .padding(.top, 8)
            }
            .f1Feedback(.selection, trigger: selectedTyre)
            .padding(36)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, y: 12)
            .frame(maxWidth: 1040)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .onAppear {
            if focusMinutes <= 0 {
                focusMinutes = 45
            }
            if let matching = presets.first(where: { $0.minutes == Int(focusMinutes) }) {
                selectedTyre = matching.compound
            }
        }
    }
}
