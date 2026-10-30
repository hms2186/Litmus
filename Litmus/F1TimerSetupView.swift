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

    private let customMinuteOptions: [Int] = [10, 15, 20, 25, 30, 45, 60, 80]
    @State private var customMinutesInput: String = "45"

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

    private func selectStrategy(_ preset: PresetStrategy) {
        selectedTyre = preset.compound
        focusMinutes = Double(preset.minutes)
        customMinutesInput = "\(preset.minutes)"
    }

    public var body: some View {
        timerBody
            .onAppear { customMinutesInput = "\(Int(focusMinutes))" }
            .onChange(of: focusMinutes) { _, minutes in
                if customMinutesInput != "\(Int(minutes))" { customMinutesInput = "\(Int(minutes))" }
            }
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

                // Choose Custom Timer Capsule with Direct Numeric Input + Menu Picker
                HStack {
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Text("Choose Custom Timer")
                            .f1Font(size: 17, weight: .regular)
                            .foregroundStyle(Color(white: 0.75))
                        
                        // Direct Numeric Input TextField
                        HStack(spacing: 6) {
                            TextField("45", text: $customMinutesInput)
                                .keyboardType(.numberPad)
                                .f1Font(size: 18, weight: .bold)
                                .foregroundStyle(F1Theme.typographyYellow)
                                .multilineTextAlignment(.center)
                                .frame(width: 48)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.10))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                                .onChange(of: customMinutesInput) { _, newValue in
                                    let filtered = newValue.filter { "0123456789".contains($0) }
                                    if filtered != newValue {
                                        customMinutesInput = filtered
                                    }
                                    if let val = Double(filtered), val > 0 && val <= 180 {
                                        focusMinutes = val
                                        updateCompoundForMinutes(Int(val))
                                    }
                                }

                            Text("mins")
                                .f1Font(size: 15, weight: .medium)
                                .foregroundStyle(Color(white: 0.60))
                        }

                        Divider()
                            .frame(height: 24)
                            .background(Color.white.opacity(0.2))

                        // Quick Presets Dropdown Menu
                        Menu {
                            ForEach(customMinuteOptions, id: \.self) { mins in
                                Button {
                                    focusMinutes = Double(mins)
                                    customMinutesInput = "\(mins)"
                                    updateCompoundForMinutes(mins)
                                } label: {
                                    if Int(focusMinutes) == mins {
                                        Label("\(mins) mins", systemImage: "checkmark")
                                    } else {
                                        Text("\(mins) mins")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(F1Theme.typographyYellow)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .buttonStyle(.f1Spring)
                        .contentShape(Capsule())
                        .hoverEffect(.highlight)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
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
            customMinutesInput = "\(Int(focusMinutes))"
            if let matching = presets.first(where: { $0.minutes == Int(focusMinutes) }) {
                selectedTyre = matching.compound
            }
        }
    }
}
