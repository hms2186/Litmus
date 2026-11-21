//
//  Accessibility.swift
//  The app's own accessibility options, set under Settings > Accessibility, and how the whole app follows them.
//
//  They sit beside the system's: Bold Text and Larger Text in iPadOS Settings already apply to the system fonts, and the
//  options here apply to every font the app draws at a fixed size too. Reduce Motion is on when either the system's switch
//  or the app's is on.
//

import SwiftUI

/// The keys the options are stored under.
enum A11yKey {
    static let textStep = "a11y_text_step"
    static let boldText = "a11y_bold_text"
    static let reduceMotion = "a11y_reduce_motion"
    static let haptics = "a11y_haptics"
}

/// Text sizes, as in Settings > Display & Brightness > Text Size: seven steps from small to the largest.
enum TextSize {
    static let steps: [(scale: CGFloat, dynamic: DynamicTypeSize)] = [
        (0.88, .small), (1.0, .large), (1.1, .xLarge), (1.2, .xxLarge), (1.32, .xxxLarge), (1.5, .accessibility1), (1.7, .accessibility2)
    ]
    static let defaultStep = 1
    /// Stored when the person has not chosen a size in the app: the app then follows Larger Text in iPadOS Settings
    static let followDevice = -1

    /// The app's step closest to the size set in iPadOS Settings > Display & Brightness > Text Size (and Accessibility > Larger Text)
    static func step(forSystem size: DynamicTypeSize) -> Int {
        switch size {
        case .xSmall, .small: return 0
        case .medium, .large: return 1
        case .xLarge: return 2
        case .xxLarge: return 3
        case .xxxLarge: return 4
        case .accessibility1: return 5
        default: return steps.count - 1   // the largest accessibility sizes use the app's largest step so layouts still fit
        }
    }

    static func scale(forStep step: Int) -> CGFloat { steps[min(max(step, 0), steps.count - 1)].scale }
    static func dynamicType(forStep step: Int) -> DynamicTypeSize { steps[min(max(step, 0), steps.count - 1)].dynamic }
}

private struct TextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
private struct BoldTextKey: EnvironmentKey { static let defaultValue = false }
private struct ReduceMotionKey: EnvironmentKey { static let defaultValue = false }
private struct HapticsKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var appTextScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
    var appBoldText: Bool {
        get { self[BoldTextKey.self] }
        set { self[BoldTextKey.self] = newValue }
    }
    /// On when the system's Reduce Motion or the app's own is on.
    var appReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
    var appHaptics: Bool {
        get { self[HapticsKey.self] }
        set { self[HapticsKey.self] = newValue }
    }
}

/// A font at a design size that follows the text size and Bold Text chosen in Settings.
private struct ScaledFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    @Environment(\.appTextScale) private var scale
    @Environment(\.appBoldText) private var bold

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
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }

    /// A haptic that the Haptic Feedback option can turn off.
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(HapticModifier(feedback: feedback, trigger: trigger))
    }
}

private struct HapticModifier<T: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: T
    @Environment(\.appHaptics) private var haptics

    func body(content: Content) -> some View {
        // Read here, while the view is updating: the closure below runs later, where the environment cannot be read
        let enabled = haptics
        return content.sensoryFeedback(feedback, trigger: trigger) { _, _ in enabled }
    }
}

/// Reads the options from the device's settings and hands them to everything below it.
struct AccessibilityHost<Content: View>: View {
    @AppStorage(A11yKey.textStep) private var textStep = TextSize.followDevice
    @AppStorage(A11yKey.boldText) private var boldText = false
    @AppStorage(A11yKey.reduceMotion) private var reduceMotion = false
    @AppStorage(A11yKey.haptics) private var haptics = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.legibilityWeight) private var systemWeight
    @Environment(\.dynamicTypeSize) private var systemTextSize
    @ViewBuilder var content: Content

    var body: some View {
        // Until a size is chosen in the app, the iPad's own text size decides
        let step = textStep == TextSize.followDevice ? TextSize.step(forSystem: systemTextSize) : textStep
        let bold = boldText || systemWeight == .bold
        // Read here, while the view updates: the transaction closure below runs later, where the environment cannot be read
        let reduceAnimations = reduceMotion || systemReduceMotion
        return content
            .environment(\.appTextScale, TextSize.scale(forStep: step))
            .environment(\.appBoldText, bold)
            .environment(\.appReduceMotion, reduceMotion || systemReduceMotion)
            .environment(\.appHaptics, haptics)
            // With Reduce Motion on, every animation in the app becomes a short fade-paced ease instead of a spring or slide
            .transaction { transaction in
                if reduceAnimations, transaction.animation != nil {
                    transaction.animation = .easeInOut(duration: 0.2)
                }
            }
            // System text styles follow the same step, and Bold Text bolds the system fonts as well
            .dynamicTypeSize(textStep == TextSize.followDevice ? systemTextSize : TextSize.dynamicType(forStep: step))
            .environment(\.legibilityWeight, bold ? .bold : systemWeight)
    }
}
