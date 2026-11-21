//
//  OnboardingView.swift
//  Prototype
//
//  Official Apple HIG Sheet Implementation of Figma Nodes:
//  - 995:1118: "Welcome" Screen (Welcome + Litmus : Focus ,Explain, Revise + Get Started!)
//  - 626:3250: "Super License" Screen 1 (Tell me about yourself - What Should I Call You? & Academic Year Grade)
//  - 987:1477: "Super License" Screen 2 (A bit more about your Education - curriculum)
//  Strictly adheres to Apple HIG Sheets, SF Pro Typography, and interactive navigation.
//

import SwiftUI

public struct OnboardingView: View {
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
    public var onSave: (String, String, String, String) -> Void
    public var onDismiss: (() -> Void)?
    /// The picture chosen on the name step, reported just before `onSave`.
    public var onAvatarChosen: (Int) -> Void
    /// The monogram colour chosen on the name step, reported just before `onSave`, so it belongs to this learner.
    public var onMonogramSeedChosen: (Int) -> Void
    /// Adding another profile (the + in the profile picker): a back chevron steps back, and leaves from the first step.
    /// The first-time onboarding has no chevron.
    public var showsBackChevron: Bool
    
    // State properties for interactive flow
    @State private var currentStep: OnboardingStep = .welcome
    /// Compact width (iPhone, or a narrow iPad window): each step stacks its picture above its content.
    /// Regular width keeps the iPad layout exactly as designed.
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    @State private var name: String
    @State private var academicYear: String
    @State private var curriculum: String
    @State private var avatar: Int
    @State private var showAllAvatars = false
    /// Minutes the learner wants to study each day, chosen on the wheel
    @State private var dailyGoalMinutes = 120
    /// A new monogram colour each time this screen appears.
    @State private var monogramSeed = Int.random(in: 0..<1000)
    
    // Available choices matching Figma & adolescent learning curriculum (Grade 9 and 10)
    private let availableGrades: [String] = [
        "Grade 9", "Grade 10"
    ]
    
    private let availableCurriculums: [String] = ["NCERT", "ICSE", "NGSS", "International Baccalaureate"]
    
    public init(
        initialName: String = "Aarushi",
        initialAcademicYear: String = "Grade 10",
        initialNationality: String = "India",
        onSave: @escaping (String, String, String, String) -> Void,
        onDismiss: (() -> Void)? = nil,
        onAvatarChosen: @escaping (Int) -> Void = { _ in },
        onMonogramSeedChosen: @escaping (Int) -> Void = { _ in },
        showsBackChevron: Bool = false
    ) {
        self.onAvatarChosen = onAvatarChosen
        self.onMonogramSeedChosen = onMonogramSeedChosen
        // A new profile starts on one of the characters; the first-time setup starts on the saved picture
        self.initialName = initialName
        self.initialAcademicYear = initialAcademicYear
        self.initialNationality = initialNationality
        self.onSave = onSave
        self.onDismiss = onDismiss
        self.showsBackChevron = showsBackChevron
        
        self._name = State(initialValue: initialName)
        // Nothing is chosen until the learner chooses it
        self._academicYear = State(initialValue: "")
        self._curriculum = State(initialValue: "")
        self._avatar = State(initialValue: ProfileAvatar.monogram)
        
        self._currentStep = State(initialValue: .welcome)
    }
    
    public var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let cardWidth: CGFloat = max(0, min(960, geo.size.width - 48))
                // iPad keeps the 620-point design height; a phone's narrow card may use more of its tall screen
                let cardHeight: CGFloat = max(0, min(isCompact ? 780 : 620, geo.size.height - 48))
                
                ZStack {
                    // Liquid Glass card over the launch backdrop
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
                        // Next sits at the centre of the sheet, at the same height on both steps
                        .overlay(alignment: .bottom) {
                            if currentStep == .name {
                                onboardingButton("Next", enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) { currentStep = .education }
                                }
                                .padding(.bottom, 44)
                                .transition(.opacity)
                            } else if currentStep == .education {
                                onboardingButton("Next", enabled: !curriculum.isEmpty && !academicYear.isEmpty) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) { currentStep = .widgets }
                                }
                                .padding(.bottom, 44)
                                .transition(.opacity)
                            } else if currentStep == .widgets {
                                // The system's own notification prompt appears here, as setup ends
                                onboardingButton("Let’s Begin!", enabled: !askingForReminders) { turnOnReminders() }
                                .padding(.bottom, 44)
                                .transition(.opacity)
                            }
                        }

                        // Back sits on the sheet itself, top leading
                        if showsBackChevron || currentStep != .welcome {
                            Button(action: goBack) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 28, height: 28)
                            }
                            .litmusGlassButton()
                            .buttonBorderShape(.circle)
                            .tint(.white)
                            .padding(.leading, 24)
                            .padding(.top, 24)
                            .accessibilityLabel("Back")
                            .transition(.opacity)
                        }

                        // How much of setup is left, quietly at the top: an unfinished task pulls people to finish it
                        if currentStep != .welcome {
                            progressIndicator
                                .frame(width: cardWidth)
                                .padding(.top, 30)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: cardWidth, height: cardHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background {
                // Full-bleed, including the bottom safe area, so no grey strip shows under the sheet
                ZStack {
                    Color(red: 14/255, green: 14/255, blue: 16/255)
                    SplashBackdrop()
                }
                .ignoresSafeArea()
            }
            .haptic(.impact(weight: .medium), trigger: currentStep)
            // The system's back button: on every step after the first, and on the first when it was opened from Settings
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .presentationBackground(Color(red: 14/255, green: 14/255, blue: 16/255))
        // Presented from the screen itself, not from a picture in the grid inside the sliding card, so it opens at once
        .sheet(isPresented: $showAllAvatars) {
            AvatarPicker(selection: $avatar, name: name, monogramSeed: monogramSeed)
        }
    }
    
    private func goBack() {
        if currentStep == .welcome {
            onDismiss?()
            dismiss()
        } else {
            withAnimation(.smooth(duration: 0.35)) {
                switch currentStep {
                case .widgets: currentStep = .education
                case .education: currentStep = .name
                default: currentStep = .welcome
                }
            }
        }
    }

    // MARK: - Step 1: Welcome Screen (Figma Node 995:1118)
    @ViewBuilder
    private func welcomeStepView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        if isCompact { compactWelcome(cardHeight: cardHeight) } else { regularWelcome(cardWidth: cardWidth, cardHeight: cardHeight) }
    }

    private func regularWelcome(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let formWidth = min(460, cardWidth * 0.50)
        return HStack(spacing: 0) {
            // Left Content Centered (matching Figma Node 995:1118)
            VStack(alignment: .center, spacing: 14) {
                Spacer()
                
                VStack(alignment: .center, spacing: 14) {
                    Text("Welcome")
                        .scaledFont(size: 58, weight: .bold, design: .default)
                        .foregroundStyle(AppTheme.typographyYellow)
                        .lineLimit(1)
                    
                    Text("Litmus : Focus ,Explain, Revise")
                        .scaledFont(size: 22, weight: .semibold, design: .default)
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
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 4)
                }
                .litmusProminentGlassButton()
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(AppTheme.accent)
                
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
    
    // MARK: - Step 2: Name and picture (Figma "Tell me about yourself")
    @ViewBuilder
    private func nameStepView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        if isCompact { compactName(cardWidth: cardWidth) } else { regularName(cardWidth: cardWidth, cardHeight: cardHeight) }
    }

    private func regularName(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let formWidth = min(520, cardWidth * 0.55)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                (Text("What should I call ").foregroundStyle(.white) + Text("you").foregroundStyle(onboardingYellow))
                    .scaledFont(size: 38, weight: .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.bottom, 18)

                HStack {
                    TextField("Your Name", text: $name)
                        .scaledFont(size: 19)
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
                .frame(width: max(0, formWidth - 40))
                .litmusGlass(interactive: true, in: Capsule())

                (Text("Choose your ").foregroundStyle(.white) + Text("profile picture").foregroundStyle(onboardingYellow))
                    .scaledFont(size: 38, weight: .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 34)
                    .padding(.bottom, 14)

                avatarOptions
                    .frame(width: max(0, formWidth - 40))
                Spacer(minLength: 24)
                Color.clear.frame(height: 70)
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

    /// Two rows of pictures; "More" opens the full picker used in Settings.
    private var avatarOptions: some View { avatarGrid(columnCount: 5, size: 78) }

    /// The pictures to choose from, in `columnCount` columns of `size`-point pictures (7 × 52 on iPad, 6 × 44 on iPhone).
    private func avatarGrid(columnCount: Int, size: CGFloat) -> some View {
        // Row 1: initials, then three boy and three girl characters. Row 2: six classic pictures and the More button.
        // A pick from the full picker takes the last slot.
        // Five to a row, in large circles: initials, two boy and two girl characters, one more of each, two classic ones, and More
        var shown = [ProfileAvatar.monogram, 0, 4, 7, 11, 2, 9] + Array(ProfileAvatar.classicChoices.prefix(2))
        if !shown.contains(avatar) { shown[shown.count - 1] = avatar }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(shown, id: \.self) { choice in
                Button {
                    withAnimation(.smooth(duration: 0.25)) { avatar = choice }
                } label: {
                    ProfileAvatar(index: choice, size: size, ring: avatar == choice ? AppTheme.accent : Color.white.opacity(0.18), name: name, monogramSeed: monogramSeed)
                        .overlay(alignment: .bottomTrailing) {
                            if avatar == choice {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, AppTheme.accent)
                            }
                        }
                }
                .buttonStyle(.pressSpring)
                .accessibilityLabel(choice == ProfileAvatar.monogram ? "Initials" : "Picture")
                .accessibilityAddTraits(avatar == choice ? .isSelected : [])
            }
            Button { showAllAvatars = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: size - 18, height: size - 18)
            }
            // The system glass button style handles touch itself; interactive glass inside a custom style
            // swallowed taps on iPadOS 26.6.2
            .litmusGlassButton()
            .buttonBorderShape(.circle)
            .frame(width: size, height: size)
            .accessibilityLabel("More pictures")
        }
        .padding(4)
    }

    // MARK: - Step 3: Curriculum and grade (Figma "A bit more about your Education")
    @ViewBuilder
    private func educationStepView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        if isCompact { compactEducation(cardWidth: cardWidth) } else { regularEducation(cardWidth: cardWidth, cardHeight: cardHeight) }
    }

    private func regularEducation(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("A bit more about your ").foregroundStyle(.white) + Text("Education").foregroundStyle(onboardingYellow))
                    .scaledFont(size: 36, weight: .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 88)
                    .padding(.bottom, 24)

                Text("Which curriculum do you follow?")
                    .scaledFont(size: 19).foregroundStyle(.white)
                    .padding(.bottom, 14)
                HStack(spacing: 12) {
                    ForEach(availableCurriculums, id: \.self) { item in
                        // Only NCERT has content: the others show, see-through and labelled, but cannot be chosen
                        let offered = item == "NCERT"
                        chip(item == "International Baccalaureate" ? "International\nBaccalaureate" : item, selected: curriculum == item, width: item == "International Baccalaureate" ? 170 : (item == "NCERT" ? 122 : 100)) {
                            if offered { curriculum = item }
                        }
                        .opacity(offered ? 1 : 0.45)
                        .disabled(!offered)
                        .overlay(alignment: .top) {
                            if !offered { unavailableTag.offset(y: -10) }
                        }
                        .accessibilityLabel(offered ? item : "\(item), unavailable")
                    }
                }
                .padding(.top, 10)          // room for the tags that sit on the chips' top edge
                .padding(.bottom, 16)

                Text("Which grade are you in?")
                    .scaledFont(size: 19).foregroundStyle(.white)
                    .padding(.bottom, 14)
                HStack(spacing: 12) {
                    ForEach(9...10, id: \.self) { grade in
                        chip(ordinal(grade), selected: academicYear == "Grade \(grade)", width: 86) {
                            academicYear = "Grade \(grade)"
                        }
                    }
                }
                .padding(.bottom, 12)

                // The question, with its wheel at the right on the same line
                HStack(alignment: .center, spacing: 16) {
                    Text("How much time do you want to study every day?")
                        .scaledFont(size: 19).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    goalWheel(height: 92).frame(width: 150)
                }

                Spacer(minLength: 24)
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

    // MARK: - Progress (Zeigarnik effect) and Step: daily study time

    /// Steps reached out of three (name, education, widgets); the first already counts, so the bar never starts empty.
    private var stepsDone: Int {
        switch currentStep {
        case .welcome: return 0
        case .name: return 1
        case .education: return 2
        case .widgets: return 3
        }
    }

    private var progressIndicator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < stepsDone ? Color.white.opacity(0.6) : Color.white.opacity(0.14))
                        .frame(width: 38, height: 3)
                }
            }
            Text("\(stepsDone)/3 done")
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .animation(.smooth(duration: 0.4), value: stepsDone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup, \(stepsDone) of 3 steps done")
    }

    private func goalText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private func goalWheel(height: CGFloat) -> some View {
        Picker("Study time every day", selection: $dailyGoalMinutes) {
            ForEach(Array(stride(from: 15, through: 480, by: 15)), id: \.self) { minutes in
                Text(goalText(minutes)).tag(minutes)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(height: height)
        .colorScheme(.dark)
        .haptic(.selection, trigger: dailyGoalMinutes)
    }

    // MARK: - Step 4: Keep updated outside the app

    /// A widget cannot be added from inside an app, so this shows how, with a picture of the widget to look for.
    @ViewBuilder
    private func widgetsStepView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        if isCompact { compactWidgets } else { regularWidgets(cardWidth: cardWidth, cardHeight: cardHeight) }
    }

    private func regularWidgets(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("Keep Updated ").foregroundStyle(.white) + Text("outside the app").foregroundStyle(onboardingYellow))
                    .scaledFont(size: 36, weight: .regular)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 80)
                    .padding(.bottom, 14)
                Text("Add the Litmus widget to your Home Screen to see your streak and jump straight back to revising.")
                    .scaledFont(size: 18).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 16) {
                    widgetInstruction(1, symbol: "hand.tap", text: "Touch and hold an empty spot on your Home Screen")
                    widgetInstruction(2, symbol: "plus", text: "Tap the + button at the top")
                    widgetInstruction(3, symbol: "magnifyingglass", text: "Search for “Litmus”, then tap Add Widget")
                }

                Spacer(minLength: 20)
            }
            .padding(.bottom, 108)   // clear of the buttons centred along the bottom of the sheet
            .padding(.leading, 56)
            .frame(maxWidth: 560, alignment: .leading)

            Spacer(minLength: 0)

            widgetPreview
                .padding(.trailing, 48)
                .accessibilityHidden(true)
        }
    }

    @State private var askingForReminders = false

    /// Shows the system's notification prompt as setup ends. Allowed: the Notifications switch in Settings turns on
    /// and the reminders are scheduled. Not allowed: the switch stays off and setup goes on.
    private func turnOnReminders() {
        askingForReminders = true
        Task {
            UserDefaults.standard.set(true, forKey: "settings_study_reminders")
            let allowed = await StudyReminder.setEnabled(true)
            if !allowed { UserDefaults.standard.set(false, forKey: "settings_study_reminders") }
            askingForReminders = false
            finish()
        }
    }

    private func finish() {
        let nationality = curriculum == "NGSS" ? "USA" : (curriculum == "International Baccalaureate" ? "International" : "India")
        onMonogramSeedChosen(monogramSeed)
        onAvatarChosen(avatar)
        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), academicYear, nationality, curriculum)
        // The daily goal belongs to the profile that was just made
        UserDefaults.standard.set(dailyGoalMinutes, forKey: "learner_daily_goal_minutes")
        ProfileStore.shared.captureActive()
        onDismiss?()
        dismiss()
    }

    private func widgetInstruction(_ number: Int, symbol: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .litmusGlass(in: Circle())
            Text(text)
                .scaledFont(size: 17)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }

    /// The widgets as they look on an iPad Home Screen: Active Days and Weekly Streaks.
    private var widgetPreview: some View {
        Image("onboarding_widgets")
            .resizable()
            .scaledToFit()
            .frame(width: 440)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }

    // MARK: - Compact width (iPhone)
    // The same steps, stacked: picture above, content at full width, scrolling when the text is large.
    // Each leaves room at the top for Back and at the bottom for the Next button laid over the sheet.

    /// The waving driver, then Welcome, the line under it and Get Started.
    private func compactWelcome(cardHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 12)
            Image("racer_welcome_waving")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: min(260, cardHeight * 0.42))
                .accessibilityHidden(true)
            Text("Welcome")
                .scaledFont(size: 46, weight: .bold)
                .foregroundStyle(AppTheme.typographyYellow)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Litmus : Focus ,Explain, Revise")
                .scaledFont(size: 19, weight: .semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 18)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) { currentStep = .name }
            } label: {
                Text("Get Started")
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 4)
            }
            .litmusProminentGlassButton()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(AppTheme.accent)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The name field and the pictures, six to a row.
    private func compactName(cardWidth: CGFloat) -> some View {
        // Six pictures and their gaps fit the card's width inside its 24-point margins
        let pictureSize = min(64, max(44, (cardWidth - 48 - 60) / 5))
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("What should I call ").foregroundStyle(.white) + Text("you").foregroundStyle(onboardingYellow))
                    .scaledFont(size: 28, weight: .regular)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
                HStack {
                    TextField("Your Name", text: $name)
                        .scaledFont(size: 18)
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
                .padding(.horizontal, 20)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .litmusGlass(interactive: true, in: Capsule())
                (Text("Choose your ").foregroundStyle(.white) + Text("profile picture").foregroundStyle(onboardingYellow))
                    .scaledFont(size: 28, weight: .regular)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)
                    .padding(.bottom, 12)
                avatarGrid(columnCount: 5, size: pictureSize)
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, 120)
        }
    }

    /// The tablet picture, then the curriculum chips two to a row and the grade chips.
    private func compactEducation(cardWidth: CGFloat) -> some View {
        // Half the row each, less the padding the glass button style adds around the label (about 28 points)
        let chipWidth = max(96, (cardWidth - 48 - 12) / 2 - 28)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Image("racer_license_tablet")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 110)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
                (Text("A bit more about your ").foregroundStyle(.white) + Text("Education").foregroundStyle(onboardingYellow))
                    .scaledFont(size: 28, weight: .regular)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)
                Text("Which curriculum do you follow?")
                    .scaledFont(size: 17).foregroundStyle(.white)
                    .padding(.bottom, 12)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 18) {
                    ForEach(availableCurriculums, id: \.self) { item in
                        let offered = item == "NCERT"
                        chip(item == "International Baccalaureate" ? "International\nBaccalaureate" : item, selected: curriculum == item, width: chipWidth) {
                            if offered { curriculum = item }
                        }
                        .opacity(offered ? 1 : 0.45)
                        .disabled(!offered)
                        .overlay(alignment: .top) {
                            if !offered { unavailableTag.offset(y: -10) }
                        }
                        .accessibilityLabel(offered ? item : "\(item), unavailable")
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 26)
                Text("Which grade are you in?")
                    .scaledFont(size: 17).foregroundStyle(.white)
                    .padding(.bottom, 12)
                HStack(spacing: 12) {
                    ForEach(9...10, id: \.self) { grade in
                        chip(ordinal(grade), selected: academicYear == "Grade \(grade)", width: 86) {
                            academicYear = "Grade \(grade)"
                        }
                    }
                }
                .padding(.bottom, 26)
                HStack(alignment: .center, spacing: 12) {
                    Text("How much time do you want to study every day?")
                        .scaledFont(size: 17).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    goalWheel(height: 120).frame(width: 140)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 120)
        }
    }

    /// The widget steps, then the picture of the widgets at the card's width.
    private var compactWidgets: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("Keep Updated ").foregroundStyle(.white) + Text("outside the app").foregroundStyle(onboardingYellow))
                    .scaledFont(size: 28, weight: .regular)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                Text("Add the Litmus widget to your Home Screen to see your streak and jump straight back to revising.")
                    .scaledFont(size: 16).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)
                VStack(alignment: .leading, spacing: 14) {
                    widgetInstruction(1, symbol: "hand.tap", text: "Touch and hold an empty spot on your Home Screen")
                    widgetInstruction(2, symbol: "plus", text: "Tap the + button at the top")
                    widgetInstruction(3, symbol: "magnifyingglass", text: "Search for “Litmus”, then tap Add Widget")
                }
                Image("onboarding_widgets")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
                    .padding(.top, 24)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, 120)
        }
    }

    private var onboardingYellow: Color { Color(red: 255/255, green: 193/255, blue: 7/255) }

    private func ordinal(_ n: Int) -> String { "\(n)th" }

    /// The small "Unavailable" tag laid across the top edge of a curriculum chip that has no content yet.
    private var unavailableTag: some View {
        Text("Unavailable")
            .scaledFont(size: 11, weight: .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(white: 0.22), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
            .fixedSize()
            .accessibilityHidden(true)
    }

    private func chip(_ title: String, selected: Bool, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .scaledFont(size: 16)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.8))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .frame(width: width, height: 54)
        }
        .litmusGlassStyle(prominent: selected)
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func onboardingButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .scaledFont(size: 18, weight: .medium)
                .foregroundStyle(.white)
                .frame(width: 170, height: 54)
        }
        .litmusProminentGlassButton()
        .buttonBorderShape(.capsule)
        .tint(AppTheme.accent)
        .disabled(!enabled)
    }
}
