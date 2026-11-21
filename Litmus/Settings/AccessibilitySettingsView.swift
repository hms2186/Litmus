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
    @Environment(\.inSettingsPane) private var inPane

    /// The step shown: the one chosen here, or the iPad's own until one is chosen
    private var shownStep: Int { textStep == TextSize.followDevice ? TextSize.step(forSystem: systemTextSize) : textStep }
    @AppStorage(A11yKey.boldText) private var boldText = false
    @AppStorage(A11yKey.reduceMotion) private var reduceMotion = false
    @AppStorage(A11yKey.haptics) private var haptics = true

    private let red = Color(red: 255/255, green: 24/255, blue: 36/255)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                section(title: "Vision") {
                    textSizeControl
                    Divider().overlay(Color.white.opacity(0.12))
                    toggleRow(icon: "bold", title: "Bold Text", detail: "Makes the text in the app heavier and easier to read. It is also on when it is on in iPadOS Settings.", isOn: boldBinding)
                }
                section(title: "Motion & Feedback") {
                    toggleRow(icon: "figure.walk.motion", title: "Reduce Motion", detail: "Replaces sliding, zooming and spinning with simple fades. It is also on when it is on in iPadOS Settings.", isOn: $reduceMotion)
                    Divider().overlay(Color.white.opacity(0.12))
                    toggleRow(icon: "iphone.radiowaves.left.and.right", title: "Haptic Feedback", detail: "Taps you can feel when you choose, finish a step or earn a coin.", isOn: $haptics)
                }
                Text("These follow the settings in iPadOS until you change them here. Text Size, Bold Text and Reduce Motion in iPadOS apply to Litmus too.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background { if !inPane { AppBackground().ignoresSafeArea() } }
        .centeredTitle("Accessibility")
        .animation(.smooth(duration: 0.25), value: shownStep)
    }

    /// Shows on when iPadOS Bold Text is on; turning it off here only turns off the app's own switch
    private var boldBinding: Binding<Bool> {
        Binding(get: { boldText || systemWeight == .bold }, set: { boldText = $0 })
    }

    // MARK: Text size

    private var textSizeControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Text Size", systemImage: "textformat.size")
                .font(.headline)
                .foregroundStyle(.white)
            HStack(spacing: 14) {
                Text("A").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                Slider(value: Binding(get: { Double(shownStep) }, set: { textStep = Int($0.rounded()) }),
                       in: 0...Double(TextSize.steps.count - 1), step: 1)
                    .tint(red)
                    .accessibilityLabel("Text size")
                    .accessibilityValue("Step \(shownStep + 1) of \(TextSize.steps.count)")
                Text("A").font(.system(size: 26, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            }
            if textStep != TextSize.followDevice {
                Button("Match iPadOS Text Size") { textStep = TextSize.followDevice }
                    .font(.subheadline)
                    .tint(red)
            }
            // The size chosen, shown on a sample of the app's own text
            VStack(alignment: .leading, spacing: 6) {
                Text("Explain it in your own words")
                    .scaledFont(size: 22, weight: .semibold)
                Text("A flashcard, a radio line and a button all read at this size.")
                    .scaledFont(size: 17)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.vertical, 6)
    }

    // MARK: Pieces

    private func toggleRow(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(red.opacity(0.3), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(red)
        .padding(.vertical, 6)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .litmusGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}
