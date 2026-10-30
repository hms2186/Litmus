//
//  F1Accessibility.swift
//  The app's own accessibility options, set under Settings > Accessibility, and how the whole app follows them.
//
//  They sit beside the system's: Bold Text and Larger Text in iPadOS Settings already apply to the system fonts, and the
//  options here apply to every font the app draws at a fixed size too. Reduce Motion is on when either the system's switch
//  or the app's is on.
//

import SwiftUI

/// The keys the options are stored under.
enum F1A11yKey {
    static let textStep = "a11y_text_step"
    static let boldText = "a11y_bold_text"
    static let reduceMotion = "a11y_reduce_motion"
    static let haptics = "a11y_haptics"
}

/// Text sizes, as in Settings > Display & Brightness > Text Size: seven steps from small to the largest.
enum F1TextSize {
    static let steps: [(scale: CGFloat, dynamic: DynamicTypeSize)] = [
        (0.88, .small), (1.0, .large), (1.1, .xLarge), (1.2, .xxLarge), (1.32, .xxxLarge), (1.5, .accessibility1), (1.7, .accessibility2)
    ]
    static let defaultStep = 1

    static func scale(forStep step: Int) -> CGFloat { steps[min(max(step, 0), steps.count - 1)].scale }
    static func dynamicType(forStep step: Int) -> DynamicTypeSize { steps[min(max(step, 0), steps.count - 1)].dynamic }
}

private struct TextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
private struct BoldTextKey: EnvironmentKey { static let defaultValue = false }
private struct ReduceMotionKey: EnvironmentKey { static let defaultValue = false }
private struct HapticsKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var f1TextScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
    var f1BoldText: Bool {
        get { self[BoldTextKey.self] }
        set { self[BoldTextKey.self] = newValue }
    }
    /// On when the system's Reduce Motion or the app's own is on.
    var f1ReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
    var f1Haptics: Bool {
        get { self[HapticsKey.self] }
        set { self[HapticsKey.self] = newValue }
    }
}

/// A font at a design size that follows the text size and Bold Text chosen in Settings.
private struct F1FontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    @Environment(\.f1TextScale) private var scale
    @Environment(\.f1BoldText) private var bold

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: bold ? weight.bolder : weight, design: design))
    }
}

private extension Font.Weight {
    /// One step heavier, as Bold Text does
    var bolder: Font.Weight {
        switch self {
        case .ultraLight: return .light
        case .thin: return .regular
        case .light: return .regular
        case .regular: return .semibold
        case .medium: return .semibold
        case .semibold: return .bold
        case .bold: return .heavy
        default: return self
        }
    }
}

extension View {
    /// Replaces `.font(.system(size:weight:design:))`: the same font, scaled by the chosen text size and made bolder by Bold Text.
    func f1Font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(F1FontModifier(size: size, weight: weight, design: design))
    }

    /// A haptic that the Haptic Feedback option can turn off.
    func f1Feedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(F1FeedbackModifier(feedback: feedback, trigger: trigger))
    }
}

private struct F1FeedbackModifier<T: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: T
    @Environment(\.f1Haptics) private var haptics

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { _, _ in haptics }
    }
}

/// Reads the options from the device's settings and hands them to everything below it.
struct F1AccessibilityHost<Content: View>: View {
    @AppStorage(F1A11yKey.textStep) private var textStep = F1TextSize.defaultStep
    @AppStorage(F1A11yKey.boldText) private var boldText = false
    @AppStorage(F1A11yKey.reduceMotion) private var reduceMotion = false
    @AppStorage(F1A11yKey.haptics) private var haptics = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.legibilityWeight) private var systemWeight
    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(\.f1TextScale, F1TextSize.scale(forStep: textStep))
            .environment(\.f1BoldText, boldText)
            .environment(\.f1ReduceMotion, reduceMotion || systemReduceMotion)
            .environment(\.f1Haptics, haptics)
            // System text styles follow the same step, and Bold Text bolds the system fonts as well
            .dynamicTypeSize(F1TextSize.dynamicType(forStep: textStep))
            .environment(\.legibilityWeight, boldText ? .bold : systemWeight)
    }
}
