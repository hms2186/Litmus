//
//  F1SuperLicenseOnboardingView.swift
//  Prototype
//
//  Official Apple HIG Sheet Implementation of Figma Nodes:
//  - 995:1118: "Welcome" Screen (Welcome + Litmus : Focus ,Explain, Revise + Get Started!)
//  - 626:3250: "Super License" Screen 1 (Tell me about yourself - What Should I Call You? & Academic Year Grade)
//  - 987:1477: "Super License" Screen 2 (A bit more about your Education - curriculum & Driver Number)
//  Strictly adheres to Apple HIG Sheets, SF Pro Typography, and interactive navigation.
//

import SwiftUI

// MARK: - Native iOS 18 Presentation Sizing for Expansive Onboarding Sheet
public struct OnboardingSheetSizing: PresentationSizing {
    public init() {}
    public func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        ProposedViewSize(width: 900, height: 600)
    }
}

public struct F1SuperLicenseOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    
    public enum OnboardingStep: Int, CaseIterable {
        case welcome = 0    // Node 995:1118
        case name = 1       // Node 626:3250
        case education = 2  // Node 987:1477
        case widgets = 3    // Keep updated outside the app
    }
    
    // Initial bindings / callbacks
    public var initialName: String
    public var initialAcademicYear: String
    public var initialNationality: String
    public var initialDriverNumber: Int
    public var onSave: (String, String, String, Int, String) -> Void
    public var onDismiss: (() -> Void)?
    /// Adding another profile (the + in the profile picker): a back chevron steps back, and leaves from the first step.
    /// The first-time onboarding has no chevron.
    public var showsBackChevron: Bool
    
    // State properties for interactive flow
    @State private var currentStep: OnboardingStep = .welcome
    @State private var name: String
    @State private var academicYear: String
    @State private var curriculum: String
    @State private var driverNumber: Int
    
    // Available choices matching Figma & adolescent learning curriculum (Grade 9 and 10)
    private let availableGrades: [String] = [
        "Grade 9", "Grade 10"
    ]
    
    private let availableCurriculums: [String] = ["NCERT", "ICSE", "NGSS", "International Baccalaureate"]
    
    private let availableDriverNumbers: [Int] = [
        1, 4, 11, 13, 14, 16, 23, 24, 31, 44, 55, 63, 77, 81
    ]
    
    public init(
        initialName: String = "Aarushi",
        initialAcademicYear: String = "Grade 10",
        initialNationality: String = "India",
        initialDriverNumber: Int = 24,
        onSave: @escaping (String, String, String, Int, String) -> Void,
        onDismiss: (() -> Void)? = nil,
        showsBackChevron: Bool = false
    ) {
        self.initialName = initialName
        self.initialAcademicYear = initialAcademicYear
        self.initialNationality = initialNationality
        self.initialDriverNumber = initialDriverNumber
        self.onSave = onSave
        self.onDismiss = onDismiss
        self.showsBackChevron = showsBackChevron
        
        self._name = State(initialValue: initialName)
        self._academicYear = State(initialValue: ["Grade 9", "Grade 10"].contains(initialAcademicYear) ? initialAcademicYear : "Grade 10")
        self._curriculum = State(initialValue: "NCERT")
        self._driverNumber = State(initialValue: initialDriverNumber)
        
        self._currentStep = State(initialValue: .welcome)
    }
    
    public var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let cardWidth: CGFloat = min(960, geo.size.width - 48)
                let cardHeight: CGFloat = min(620, geo.size.height - 48)
                
                ZStack {
                    // Deep Solid Black Sheet Canvas with subtle F1 car wallpaper
                    Color(red: 14/255, green: 14/255, blue: 16/255)
                        .ignoresSafeArea()
                    
                    Image("f1_car_bg")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 12)
                        .opacity(0.32)
                        .ignoresSafeArea()
                    
                    // Centered Premium Glass Card
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Color(red: 22/255, green: 22/255, blue: 25/255).opacity(0.96))
                            .overlay(
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.60), radius: 30, y: 12)
                        
                        // Card Content
                        VStack(spacing: 0) {
                            switch currentStep {
                            case .welcome:
                                welcomeStepView(cardWidth: cardWidth, cardHeight: cardHeight)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                        removal: .opacity.combined(with: .offset(x: -40))
                                    ))
                            case .name:
                                nameStepView(cardWidth: cardWidth, cardHeight: cardHeight)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(x: 40)),
                                        removal: .opacity.combined(with: .offset(x: -40))
                                    ))
                            case .education:
                                educationStepView(cardWidth: cardWidth, cardHeight: cardHeight)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(x: 40)),
                                        removal: .opacity.combined(with: .offset(x: -40))
                                    ))
                            case .widgets:
                                widgetsStepView(cardWidth: cardWidth, cardHeight: cardHeight)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(x: 40)),
                                        removal: .opacity.combined(with: .scale(scale: 0.98))
                                    ))
                            }
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        
                        // Official Apple HIG Back Button Inside Sheet Top-Left
                        if showsBackChevron {
                            Button {
                                if currentStep == .welcome {
                                    onDismiss?()
                                    dismiss()
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                                        switch currentStep {
                                        case .widgets: currentStep = .education
                                        case .education: currentStep = .name
                                        default: currentStep = .welcome
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .glassEffect(.regular.interactive(), in: Circle())
                            }
                            .buttonStyle(.f1Spring)
                            .contentShape(Circle())
                            .hoverEffect(.lift)
                            .accessibilityLabel("Back")
                            .padding(.top, 24)
                            .padding(.leading, 24)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .frame(width: cardWidth, height: cardHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .f1Feedback(.impact(weight: .medium), trigger: currentStep)
        }
    }
    
    // MARK: - Step 1: Welcome Screen (Figma Node 995:1118)
    private func welcomeStepView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let formWidth = min(460, cardWidth * 0.50)
        return HStack(spacing: 0) {
            // Left Content Centered (matching Figma Node 995:1118)
            VStack(alignment: .center, spacing: 14) {
                Spacer()
                
                VStack(alignment: .center, spacing: 14) {
                    Text("Welcome")
                        .f1Font(size: 58, weight: .bold, design: .default)
                        .foregroundStyle(F1Theme.typographyYellow)
                        .lineLimit(1)
                    
                    Text("Litmus : Focus ,Explain, Revise")
                        .f1Font(size: 22, weight: .semibold, design: .default)
                        .foregroundStyle(Color.white)
                        .minimumScaleFactor(0.80)
                        .lineLimit(1)
                }
                
                Spacer().frame(height: 38)
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                        currentStep = .name
                    }
                } label: {
                    Text("Get Started")
                        .f1Font(size: 17, weight: .semibold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Color(red: 0/255, green: 136/255, blue: 255/255))
                .contentShape(Capsule())
                .hoverEffect(.lift)
                
                Spacer()
            }
            .frame(width: formWidth)
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.leading, 32)
            
            Spacer()
            
            // Right Illustration: Sitting Driver (Figma 995:1118)
            ZStack(alignment: .bottomTrailing) {
                Image("racer_welcome_waving")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: min(480, cardHeight * 0.90))
                    .padding(.trailing, 28)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
    
    // MARK: - Step 2: Name and driver number (Figma "Tell me about yourself")
    private func nameStepView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let formWidth = min(520, cardWidth * 0.55)
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                (Text("Tell me about ").foregroundStyle(.white) + Text("yourself").foregroundStyle(onboardingYellow))
                    .f1Font(size: 38, weight: .regular)
                    .padding(.bottom, 26)

                VStack(spacing: 10) {
                    HStack {
                        TextField("What Should I Call You?", text: $name)
                            .f1Font(size: 19)
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                        if !name.isEmpty {
                            Button { name = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                            }
                            .accessibilityLabel("Clear name")
                        }
                    }
                    .padding(.horizontal, 22)
                    .frame(height: 58)
                    .glassEffect(.regular.interactive(), in: Capsule())

                    Menu {
                        Picker("Driver number", selection: $driverNumber) {
                            ForEach(availableDriverNumbers, id: \.self) { Text("\($0)").tag($0) }
                        }
                    } label: {
                        HStack {
                            Text("Choose your driver number")
                                .f1Font(size: 19)
                                .foregroundStyle(.white.opacity(0.75))
                            Spacer()
                            Text("\(driverNumber)")
                                .f1Font(size: 19, weight: .semibold)
                                .foregroundStyle(Color(red: 255/255, green: 56/255, blue: 60/255))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 255/255, green: 56/255, blue: 60/255))
                        }
                        .padding(.horizontal, 22)
                        .frame(height: 58)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                }
                .frame(width: formWidth - 40)

                Spacer().frame(height: 70)
                HStack {
                    Spacer().frame(width: (formWidth - 40) / 2 - 85)
                    onboardingButton("Next", enabled: hasName) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) { currentStep = .education }
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 56)
            .frame(width: formWidth + 56, alignment: .leading)

            Spacer()

            Image("racer_license_thinking")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: min(500, cardHeight * 0.78))
                .padding(.trailing, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Step 3: Curriculum and grade (Figma "A bit more about your Education")
    private func educationStepView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("A bit more about your ").foregroundStyle(.white) + Text("Education").foregroundStyle(onboardingYellow))
                    .f1Font(size: 36, weight: .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 92)
                    .padding(.bottom, 56)

                Text("Which curriculum do you follow?")
                    .f1Font(size: 19).foregroundStyle(.white)
                    .padding(.bottom, 14)
                HStack(spacing: 12) {
                    ForEach(availableCurriculums, id: \.self) { item in
                        chip(item == "International Baccalaureate" ? "International\nBaccalaureate" : item, selected: curriculum == item, width: item == "International Baccalaureate" ? 170 : (item == "NCERT" ? 122 : 100)) {
                            curriculum = item
                        }
                    }
                }
                .padding(.bottom, 34)

                Text("Which grade are you in?")
                    .f1Font(size: 19).foregroundStyle(.white)
                    .padding(.bottom, 14)
                HStack(spacing: 12) {
                    ForEach(9...10, id: \.self) { grade in
                        chip(ordinal(grade), selected: academicYear == "Grade \(grade)", width: 86) {
                            academicYear = "Grade \(grade)"
                        }
                    }
                }

                Spacer().frame(height: 52)
                HStack {
                    Spacer().frame(width: 110)
                    onboardingButton("Next", enabled: true) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) { currentStep = .widgets }
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 56)
            .frame(maxWidth: 640, alignment: .leading)

            Spacer()

            Image("racer_license_tablet")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: min(380, cardHeight * 0.6))
                .padding(.trailing, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Step 4: Keep updated outside the app

    /// A widget cannot be added from inside an app, so this shows how, with a picture of the widget to look for.
    private func widgetsStepView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("Keep Updated ").foregroundStyle(.white) + Text("outside the app").foregroundStyle(onboardingYellow))
                    .f1Font(size: 36, weight: .regular)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 80)
                    .padding(.bottom, 14)
                Text("Add the Litmus widget to your Home Screen to see your streak and jump straight back to revising.")
                    .f1Font(size: 18).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 16) {
                    widgetInstruction(1, symbol: "hand.tap", text: "Touch and hold an empty spot on your Home Screen")
                    widgetInstruction(2, symbol: "plus", text: "Tap the + button at the top")
                    widgetInstruction(3, symbol: "magnifyingglass", text: "Search for “Litmus”, then tap Add Widget")
                }

                Spacer(minLength: 20)
                HStack(spacing: 22) {
                    onboardingButton("Let’s Begin!", enabled: true) { finish() }
                    Button("Maybe later") { finish() }
                        .f1Font(size: 17, weight: .medium)
                        .foregroundStyle(.white.opacity(0.7))
                        .buttonStyle(.f1Spring)
                }
                .padding(.bottom, 44)
            }
            .padding(.leading, 56)
            .frame(maxWidth: 560, alignment: .leading)

            Spacer(minLength: 0)

            widgetPreview
                .padding(.trailing, 48)
                .accessibilityHidden(true)
        }
    }

    private func finish() {
        let nationality = curriculum == "NGSS" ? "USA" : (curriculum == "International Baccalaureate" ? "International" : "India")
        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), academicYear, nationality, driverNumber, curriculum)
        onDismiss?()
        dismiss()
    }

    private func widgetInstruction(_ number: Int, symbol: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: Circle())
            Text(text)
                .f1Font(size: 17)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }

    /// What the widget looks like: the week's streak, with the Revise cover beside it.
    private var widgetPreview: some View {
        let days = ["S", "M", "T", "W", "Th", "F", "Sa"]
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundStyle(Color(red: 255/255, green: 120/255, blue: 24/255))
                Text("Litmus").f1Font(size: 16, weight: .semibold).foregroundStyle(.white)
                Spacer()
            }
            (Text("Weekly ").foregroundStyle(.white) + Text("Streaks").foregroundStyle(onboardingYellow))
                .f1Font(size: 24, weight: .semibold)
            HStack(spacing: 8) {
                ForEach(days.indices, id: \.self) { index in
                    Text(days[index])
                        .f1Font(size: 13, weight: .medium)
                        .foregroundStyle(index == 3 ? Color.black.opacity(0.75) : .white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(index == 3 ? onboardingYellow : (index < 3 ? Color(red: 26/255, green: 188/255, blue: 156/255) : Color.white.opacity(0.12))))
                }
            }
            Image("cover_motion")
                .resizable()
                .scaledToFill()
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .frame(width: 300)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var onboardingYellow: Color { Color(red: 255/255, green: 193/255, blue: 7/255) }

    private func ordinal(_ n: Int) -> String { "\(n)th" }

    private func chip(_ title: String, selected: Bool, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .f1Font(size: 16)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.8))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .frame(width: width, height: 54)
                .glassEffect(.regular.interactive(), in: Capsule())
                .overlay(Capsule().stroke(selected ? Color(red: 10/255, green: 132/255, blue: 255/255) : .clear, lineWidth: 3))
        }
        .buttonStyle(.f1Spring)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func onboardingButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .f1Font(size: 18, weight: .medium)
                .foregroundStyle(.white)
                .frame(width: 170, height: 54)
                .background(Color(red: 10/255, green: 110/255, blue: 255/255).opacity(enabled ? 1 : 0.4), in: Capsule())
        }
        .buttonStyle(.f1Spring)
        .disabled(!enabled)
    }
}
