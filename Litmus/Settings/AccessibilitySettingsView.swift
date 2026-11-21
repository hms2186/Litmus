//
//  AccessibilitySettingsView.swift
//  Settings > Accessibility. Text Size (a slider of seven steps with a live preview, as in the system's Display &
//  Brightness), Bold Text, Reduce Motion and Haptic Feedback. Each applies to the whole app straight away.
//

import SwiftUI

struct AccessibilitySettingsView: View {
    @AppStorage(A11yKey.textStep) private var textStep = TextSize.followDevice
    @Environment(\.dynamicTypeSize) private var systemTextSize
    @Environment(\.legibilityWeight) private var systemWeight

    /// The step shown: the one chosen here, or the iPad's own until one is chosen
    private var shownStep: Int { textStep == TextSize.followDevice ? TextSize.step(forSystem: systemTextSize) : textStep }
    @AppStorage(A11yKey.boldText) private var boldText = false
    @AppStorage(A11yKey.reduceMotion) private var reduceMotion = false
    @AppStorage(A11yKey.haptics) private var haptics = true

    var body: some View {
        SettingsScroll {
            SettingsGroup(header: "Text Size") { textSizeControl }
            SettingsGroup(footer: "Makes the text in the app heavier and easier to read. It is also on when it is on in iPadOS Settings.") {
                Toggle(isOn: boldBinding) { SettingsLabel(title: "Bold Text", symbol: "bold", color: .blue) }.tint(.green).settingsRow()
            }
            SettingsGroup(footer: "Replaces sliding, zooming and spinning with simple fades. It is also on when it is on in iPadOS Settings.") {
                Toggle(isOn: $reduceMotion) { SettingsLabel(title: "Reduce Motion", symbol: "figure.walk.motion", color: .blue) }.tint(.green).settingsRow()
            }
            SettingsGroup(footer: "Taps you can feel when you choose, finish a step or earn a coin. These settings follow iPadOS until you change them here.") {
                Toggle(isOn: $haptics) { SettingsLabel(title: "Haptic Feedback", symbol: "iphone.radiowaves.left.and.right", color: .pink) }.tint(.green).settingsRow()
            }
        }
        .settingsScreen("Accessibility")
        .animation(.smooth(duration: 0.25), value: shownStep)
    }

    /// Shows on when iPadOS Bold Text is on; turning it off here only turns off the app's own switch
    private var boldBinding: Binding<Bool> {
        Binding(get: { boldText || systemWeight == .bold }, set: { boldText = $0 })
    }

    // MARK: Text size

    @ViewBuilder private var textSizeControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("A").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(shownStep) }, set: { textStep = Int($0.rounded()) }),
                       in: 0...Double(TextSize.steps.count - 1), step: 1)
                    .tint(.red)
                    .accessibilityLabel("Text size")
                    .accessibilityValue("Step \(shownStep + 1) of \(TextSize.steps.count)")
                Text("A").font(.system(size: 26, weight: .medium)).foregroundStyle(.secondary)
            }
            if textStep != TextSize.followDevice {
                Button("Match iPadOS Text Size") { textStep = TextSize.followDevice }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
        .settingsRow()
        // The size chosen, shown on a sample of the app's own text
        VStack(alignment: .leading, spacing: 6) {
            Text("Explain it in your own words")
                .scaledFont(size: 22, weight: .semibold)
            Text("A flashcard, a radio line and a button all read at this size.")
                .scaledFont(size: 17)
                .foregroundStyle(.secondary)
        }
        .settingsRow()
        .accessibilityElement(children: .combine)
    }
}
