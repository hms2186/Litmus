//
//  MainTabView.swift
//  App shell, matching the Figma flow: Super License onboarding, then a four-tab shell
//  (Home, Timer, Explain, Flashcards) with the start lights, live cockpit HUD and congratulations
//  screens layered over it.
//
//  Owns the single FeedbackViewModel, so the v4.0 engine state drives the Explain tab.
//

import SwiftUI
import UserNotifications
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var feedback = FeedbackViewModel(transport: LitmusApp.transport)
    @AppStorage("hasCompletedSuperLicenseOnboarding") private var hasCompletedOnboarding = false

    // Navigation
    @State private var selectedTab: AppNavigationTab = .home
    /// First launch: onboarding is the first screen, already in place under the launch animation, so the dashboard never shows and nothing slides up
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedSuperLicenseOnboarding")

    // Learner: saved on the device, so the name given in onboarding is used everywhere, every launch
    @AppStorage("learner_name") private var learnerName = ""
    @AppStorage("learner_grade") private var learnerGrade = "Grade 10"
    @AppStorage("learner_nationality") private var learnerNationality = "India"
    @AppStorage("learner_curriculum") private var learnerCurriculum = "NCERT"
    @ObservedObject private var progress = StudyProgressManager.shared
    @State private var studentCountry: StudentCountry = .india

    // Study session (the lap): one source of truth for the Timer tab, the cockpit HUD and the clock
    @State private var customTopicText = ""
    @State private var chosenTopic: NCERTTopic?
    @State private var sessionTopic = NCERTTopic.sampleChapter[0]
    @State private var timerRecommendation: TimerRecommendation?
    @State private var focusMinutes = 15.0
    // Held, not observed: only the cockpit redraws on each tick
    @State private var lapClock = LapClock()
    @State private var isFocusTimerRunning = false
    @State private var isLapActive = false
    @State private var showCongratulations = false
    /// Timer "Change": Home opens the chosen chapter's topic list
    @State private var openTopicsOnHome = false
    @State private var showStartLights = false
    @State private var deckRequest: DeckRequest?
    @Environment(\.scenePhase) private var scenePhase
    @State private var finishScheduled = false
    @State private var lapEndDate: Date?
    @State private var selectedCircuit: Circuit = .autodromoHermanosRodriguez
    @State private var selectedTyre: TyreCompound = .soft

    // Explain tab
    @State private var transcription = ""
    @State private var isRecording = false
    @State private var isActivelyExplaining = false
    @State private var showTestButtons = false
    @State private var lapSecondsStudied = 0
    @State private var lapCoinsEarned = 0

    // Alerts
    @State private var showTopicRequired = false
    @State private var showResetLap = false
    @State private var showEndLap = false
    @State private var showSettings = false
    @State private var settingsTabBarHidden = false
    @State private var pushedHidesTabBar = false
    /// The tab bar leaves a moment before Settings is pushed, so its large title is in place when the screen arrives
    @State private var showRevise = false

    private var profile: LearnerUserProfile {
        LearnerUserProfile(
            name: learnerName.isEmpty ? "Driver" : learnerName,
            academicYear: learnerGrade,
            curriculum: learnerCurriculum,
            nationality: learnerNationality
        )
    }

    var body: some View {
        ZStack {
            AppBackground()

            TabView(selection: $selectedTab) {
                Tab(AppNavigationTab.home.shortTitle, systemImage: "house.fill", value: AppNavigationTab.home) {
                    tabScreen(.home)
                        .tint(.white)
                }
                .badge(isFocusTimerRunning ? Text("Live") : nil)

                Tab(AppNavigationTab.timer.shortTitle, systemImage: "timer", value: AppNavigationTab.timer) {
                    tabScreen(.timer)
                        .tint(.white)
                }
                Tab(AppNavigationTab.explain.shortTitle, systemImage: AppNavigationTab.explain.iconName, value: AppNavigationTab.explain) {
                    tabScreen(.explain)
                        .tint(.white)
                }
                .badge(isRecording ? Text("Live") : nil)

                Tab(AppNavigationTab.flashcards.shortTitle, systemImage: AppNavigationTab.flashcards.iconName, value: AppNavigationTab.flashcards) {
                    tabScreen(.flashcards)
                        .tint(.white)
                }
            }
            // The tab bar on top, with no sidebar button
            .tabViewStyle(.tabBarOnly)
            // Red applies to the tab bar only; each tab's content puts buttons back to their own colour
            .tint(AppTheme.tabAccent)

            // In-race cockpit: full screen, above the tab bar (Figma "Stay on track")
            if isLapActive {
                FocusTimerView(
                    clock: lapClock,
                    focusMinutes: focusMinutes,
                    topicTitle: customTopicText,
                    circuit: selectedCircuit,
                    tyreCompound: selectedTyre,
                    isFocusTimerRunning: $isFocusTimerRunning,
                    onBoxBox: { showEndLap = true },
                    onAddTime: { lapClock.remaining += 300 },
                    onRedFlag: { showResetLap = true },
                    onFinishLap: finishLapSoon,
                    onFinishedLearning: {
                        // Finish was confirmed: save the session and go to Explain, with no congratulations screen
                        finishLap(celebrate: false)
                        withAnimation(AppMotionSystem.fluidPageSpring) {
                            resetAttempt()
                            selectedTab = .explain
                        }
                    }
                )
                .screenChangeTransition()
                .zIndex(200)
                .ignoresSafeArea()
            }

            // The start lights run between choosing the timer and the lap; the clock starts when the fifth one is on
            if showStartLights {
                StartLightsView(topic: customTopicText) { startLap() }
                    .transition(.opacity)
                    .zIndex(190)
            }

            if showCongratulations {
                CongratulationsView(
                    driverName: profile.name,
                    topicTitle: sessionTopic.title,
                    onMoreTime: {
                        // Back to choosing a timer, not back onto the track
                        withAnimation(AppMotionSystem.fluidPageSpring) {
                            showCongratulations = false
                            lapClock.remaining = Int(focusMinutes * 60)
                            selectedTab = .timer
                        }
                    },
                    onStartRadio: {
                        // On to the Explain stage
                        withAnimation(AppMotionSystem.fluidPageSpring) {
                            showCongratulations = false
                            resetAttempt()
                            selectedTab = .explain
                        }
                    }
                )
                .screenChangeTransition()
                .zIndex(250)
                .ignoresSafeArea()
            }
        }
        .background(AppTheme.trackAsphalt.ignoresSafeArea())
        .tint(.white)
        .preferredColorScheme(.dark)
        // Actionable: the button takes them to where a topic is chosen
        .alert("Choose a Study Topic", isPresented: $showTopicRequired) {
            Button("Cancel", role: .cancel) {}
            Button("Choose Topic") { withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .home } }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Pick a chapter and topic before you start a session.")
        }
        // The learner chose Reset and End themselves, so these buttons are not styled destructive (HIG)
        .alert("Reset this session?", isPresented: $showResetLap) {
            Button("Cancel", role: .cancel) {}
            Button("Reset") { abortLap() }
        } message: {
            Text("Its progress will be reset.")
        }
        .alert("End this session early?", isPresented: $showEndLap) {
            Button("Cancel", role: .cancel) {}
            Button("End Session") { abortLap() }
        } message: {
            Text("It will be logged as incomplete.")
        }
        .fullScreenCover(isPresented: $showRevise) {
            ReviseView(cards: FlashcardLibrary.cards(for: sessionTopic), coins: progress.coins) {
                showRevise = false
                resetAttempt()
                selectedTab = .flashcards
            }
        }
        .overlay {
            if showOnboarding {
                ZStack {
                    Color.black.ignoresSafeArea()
                    OnboardingView(
                        initialName: learnerName,
                        initialAcademicYear: learnerGrade,
                        initialNationality: learnerNationality,
                        onSave: { name, year, nationality, curriculum in
                            withAnimation(AppMotionSystem.interactiveSpring) {
                                learnerName = name
                                learnerGrade = year
                                learnerNationality = nationality
                                learnerCurriculum = curriculum
                                studentCountry = StudentCountry.from(nationality: nationality)
                                hasCompletedOnboarding = true
                                showOnboarding = false
                            }
                        },
                        onDismiss: {
                            withAnimation(AppMotionSystem.interactiveSpring) {
                                hasCompletedOnboarding = true
                                showOnboarding = false
                            }
                        },
                        onAvatarChosen: { UserDefaults.standard.set($0, forKey: "learner_avatar") },
                        onMonogramSeedChosen: { UserDefaults.standard.set($0, forKey: "learner_monogram_color") }
                    )
                }
                .transition(.opacity)
                .accessibilityAddTraits(.isModal)
            }
        }
        .task {
            feedback.modelContext = modelContext
            WidgetSync.refresh(fallback: sessionTopic)
        }
        .task(id: customTopicText) { updateSessionTopic() }
        // Reset App returns here: first-time setup begins again
        .onChange(of: hasCompletedOnboarding) { _, done in
            if !done { withAnimation(.smooth(duration: 0.4)) { showOnboarding = true } }
        }
        // The widgets follow the app: refreshed when it opens or leaves, and when a session or explanation ends
        .onChange(of: scenePhase) { _, phase in
            guard phase != .inactive else { return }
            StudyProgressManager.shared.refreshWeek()
            WidgetSync.refresh(fallback: sessionTopic)
            if phase == .background {
                // Leaving the app: a few revise nudges for what was studied lately
                let topics = LitmusWidgetStore.load().topics
                Task {
                    await NotificationManager.shared.scheduleReviseReminders(topics: topics)
                    await NotificationManager.shared.refreshPersonalReminders(name: ProfileStore.shared.active.name, topic: topics.first?.topic)
                }
            } else {
                NotificationManager.shared.cancelReviseReminders()
                NotificationManager.shared.clearStreakRisk()
            }
        }
        .onOpenURL { url in
            // The Revise widget and the revise reminders open the deck of a chapter
            if let request = LitmusShared.deckRequest(from: url) {
                deckRequest = DeckRequest(chapter: request.chapter, subject: request.subject)
                selectedTab = .flashcards
            } else if url.scheme == "litmus", url.host == "revise" {
                selectedTab = .flashcards
            }
        }
        .onChange(of: sessionTopic.id) { _, _ in if !isLapActive { refreshRecommendation() } }
        .task(id: isFocusTimerRunning) { await runClock() }
        .onChange(of: isFocusTimerRunning) { _, running in
            // The widget shows Paused, or runs again from the time that is left
            guard isLapActive else { return }
            LiveActivityManager.shared.updateLapProgress(remainingSeconds: lapClock.remaining, totalMinutes: focusMinutes, isPaused: !running, topicTitle: customTopicText)
        }
    }

    /// "Grade 10" in the profile is "Class 10" in the curriculum.
    private var studyGrade: String {
        let digits = profile.academicYear.filter(\.isNumber)
        return CurriculumCatalog.shared.grades.contains("Class \(digits)") ? "Class \(digits)" : "Class 10"
    }

    // MARK: - Tabs

    @ViewBuilder
    private func tabScreen(_ tab: AppNavigationTab) -> some View {
        NavigationStack {
            Group {
                switch tab {
                case .explain:
                    if customTopicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Nothing chosen: without this the first topic of the curriculum was used silently, and the
                        // student's answer was graded against a topic they never picked
                        ZStack {
                            AppBackground()
                            ContentUnavailableView {
                                Label("Choose a topic first", systemImage: "book.closed")
                            } description: {
                                Text("Pick a chapter and a topic on Home, then explain it here.")
                            } actions: {
                                Button("Choose Topic") {
                                    openTopicsOnHome = true
                                    withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .home }
                                }
                                .litmusProminentGlassButton()
                                .buttonBorderShape(.capsule)
                                .controlSize(.large)
                            }
                        }
                    } else {
                    ExplainView(
                        customTopicText: sessionTopic.title,
                        feedback: feedback,
                        topic: sessionTopic,
                        driverName: $learnerName,
                        studentCountry: $studentCountry,
                        transcriptionText: $transcription,
                        isRecording: $isRecording,
                        isActivelyExplaining: $isActivelyExplaining,
                        showTestButtons: $showTestButtons,
                        coins: progress.coins,
                        spendCoins: { progress.spend($0) },
                        coinsEarned: lapCoinsEarned,
                        studySeconds: lapSecondsStudied,
                        isTabActive: selectedTab == .explain,
                        onExplanationResult: { passed, note in
                            progress.noteExplanationResult(topic: sessionTopic.title, reviewNote: passed ? nil : (note ?? "revisit this topic"))
                            // A gap in the explanation earns one gentle reminder; explaining it well withdraws it
                            let topic = sessionTopic.title
                            if passed { NotificationManager.shared.cancelRevisit(topic: topic) }
                            else { Task { await NotificationManager.shared.scheduleRevisit(topic: topic) } }
                        },
                        onSessionSummary: { seconds in
                            progress.recordExplanation(seconds: seconds, topic: sessionTopic.title, chapter: sessionTopic.chapter, subject: sessionTopic.subject)
                        },
                        onDone: {
                            withAnimation(AppMotionSystem.interactiveSpring) {
                                resetAttempt()
                                selectedTab = .home
                            }
                        },
                        onReset: {
                            withAnimation(AppMotionSystem.interactiveSpring) {
                                resetAttempt()
                                selectedTab = .home
                            }
                        },
                        onNavigateToRevise: { showRevise = true }
                    )
                    }
                case .flashcards:
                    FlashcardsView(grade: studyGrade, request: $deckRequest, coins: progress.coins, topic: sessionTopic)
                default:
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 20) {
                            if tab == .home {
                                HomeView(
                                    customTopicText: $customTopicText,
                                    chosenTopic: $chosenTopic,
                                    studentCountry: $studentCountry,
                                    activeProfile: profile,
                                    onStartLap: {
                                        if customTopicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            showTopicRequired = true
                                        } else {
                                            applyRecommendedTimer()
                                            withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .timer }
                                        }
                                    },
                                    onNavigateToRevise: { chapter, subject in
                                        deckRequest = DeckRequest(chapter: chapter, subject: subject)
                                        withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .flashcards }
                                    },
                                    openTopicsRequest: $openTopicsOnHome
                                )
                            } else {
                                TimerSetupView(
                                    selectedCircuit: $selectedCircuit,
                                    focusMinutes: $focusMinutes,
                                    selectedTyre: $selectedTyre,
                                    onLightsOut: {
                                        if customTopicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            showTopicRequired = true
                                        } else {
                                            beginLap()
                                        }
                                    },
                                    onSkipTimer: { withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .explain } },
                                    recommendation: timerRecommendation,
                                    // Only a topic the learner has actually chosen; none chosen shows no "Studying" pill
                                    topicTitle: customTopicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : sessionTopic.title,
                                    onChooseTopic: { withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .home } },
                                    onChangeTopic: {
                                        // Home opens the topics of the chapter that is chosen now
                                        openTopicsOnHome = true
                                        withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .home }
                                    }
                                )
                                .containerRelativeFrame(.vertical, alignment: .center) { length, _ in max(0, length - 120) }
                            }
                        }
                        .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
                        .padding(.vertical, 16)
                    }
                    // The tab bar and the corner buttons float over the page, so the top edge fades into them
                    .litmusSoftScrollEdge(for: .top)
                }
            }
            .background { AppBackground() }
            // The keyboard (a text field in Settings, or the Home search) must not squeeze the page behind it. Only Explain,
            // where the student types an answer, lets the keyboard move its layout.
            .ignoresSafeArea(tab == .explain ? [] : .keyboard, edges: .bottom)
            // The tab bar steps away while the student is explaining (the back button on that screen leaves it) and while
            // Settings is open. It is hidden here, at the root, so it goes in the same moment the push starts.
            .toolbarVisibility(showSettings || settingsTabBarHidden || pushedHidesTabBar || (tab == .explain && isActivelyExplaining) ? .hidden : .visible, for: .tabBar)
            // No tab has a bar title: Study Deck carries its large heading inside the page, so it scrolls away instead of
            // collapsing into a small title under the tab bar
            .navigationTitle("")
            .navigationBarTitleDisplayMode(showSettings ? .large : .inline)
            // Hidden under Settings too, so its large title arrives with its own bar instead of growing out of this one
            .toolbarVisibility(showSettings ? .hidden : .visible, for: .navigationBar)
            // The profile picture and Settings, a little way down from the top edge. They are drawn over the tab's content (not
            // in the navigation bar, whose items are rebuilt each time a screen is pushed and popped, which made them flicker).
            // Liquid Glass is around Settings alone.
            .overlay(alignment: .topTrailing) {
                do {
                    HStack(spacing: 12) {
                        // Switching profile is a Home screen thing; Settings is on every screen
                        if selectedTab == .home { ProfileSwitcherButton() }
                        if selectedTab == .explain { CoinCounter(count: progress.coins) }
                        settingsButton
                    }
                    .padding(.top, 24)
                    .padding(.trailing, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea(edges: .top)
                }
            }
            // Settings is pushed on the tab's NavigationStack: the system back button, and the "Settings" navigation title
            .onChange(of: showSettings) { _, open in if !open { settingsTabBarHidden = false } }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView(embedded: true)
                    // System back chevron only, no text beside it
                    .minimalBackButton()
            }
        }
        // A pushed screen can ask for the tab bar to step away (the flashcard deck does)
        .onPreferenceChange(HidesTabBarKey.self) { pushedHidesTabBar = $0 }
    }

    /// Settings: the standard gear symbol on a round glass button, 44 pt, the minimum touch target
    private var settingsButton: some View {
        Button {
            // The tab bar goes first, then Settings is pushed, so the page is laid out once and nothing shifts
            withAnimation(.smooth(duration: 0.25)) { settingsTabBarHidden = true }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                showSettings = true
            }
        } label: {
            Label("Settings", systemImage: "gear")
        }
        .litmusGlassButton()
        .buttonBorderShape(.circle)
        .labelStyle(.iconOnly)
        .foregroundStyle(.white)
        .tint(.white)
        .font(.system(size: 20, weight: .medium))   // the glyph's scale
        .frame(width: 44, height: 44)               // the 44 pt touch target
    }

    // MARK: - Session state

    /// Matches the chosen topic to a curriculum topic, preferring ones the engine can grade.
    private func updateSessionTopic() {
        if let chosenTopic, chosenTopic.title == customTopicText {
            guard chosenTopic.id != sessionTopic.id else { return }
            sessionTopic = chosenTopic
            resetAttempt()
            feedback.prepare(topic: chosenTopic)
            return
        }
        let wanted = customTopicText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let catalog = CurriculumCatalog.shared
        let all = catalog.allChapters.flatMap { catalog.topics(forChapter: $0) }
        var match: NCERTTopic?
        if !wanted.isEmpty {
            let hits = all.filter { $0.title.lowercased() == wanted }
                + all.filter { $0.title.lowercased().contains(wanted) || wanted.contains($0.title.lowercased()) }
            match = hits.first(where: { feedback.isEngineTopic($0) }) ?? hits.first
                ?? NCERTTopic.sampleChapter.first(where: { $0.title.lowercased().contains(wanted) })
        }
        let next = match ?? all.first(where: { feedback.isEngineTopic($0) }) ?? NCERTTopic.sampleChapter[0]
        guard next.id != sessionTopic.id else { return }
        sessionTopic = next
        resetAttempt()
        feedback.prepare(topic: next)
    }

    /// Suggests a timer for the chosen topic and selects it; the student can still pick another.
    private func applyRecommendedTimer() {
        updateSessionTopic()
        refreshRecommendation()
    }

    /// Works out the recommendation for the current topic and selects that timer, unless a lap is running.
    private func refreshRecommendation() {
        let recommendation = TimerAdvisor.recommend(for: sessionTopic)
        timerRecommendation = recommendation
        focusMinutes = Double(recommendation.minutes)
        lapClock.remaining = recommendation.minutes * 60
        switch recommendation.minutes {
        case ..<20: selectedTyre = .soft
        case ..<35: selectedTyre = .medium
        case ..<55: selectedTyre = .hard
        case ..<70: selectedTyre = .intermediate
        default: selectedTyre = .wet
        }
    }

    private func resetAttempt() {
        feedback.reset()
        transcription = ""
        isRecording = false
        isActivelyExplaining = false
    }

    /// One second of the lap. The clock runs only while the timer is running.
    private func runClock() async {
        // The time left is worked out from when the timer ends, not counted down tick by tick: if the app goes to the
        // background and comes back, the clock is right at once.
        lapEndDate = nil
        while isFocusTimerRunning, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard isFocusTimerRunning, !Task.isCancelled, isLapActive || lapClock.remaining > 0 else { continue }
            if lapEndDate == nil { lapEndDate = Date().addingTimeInterval(Double(lapClock.remaining)) }
            let left = max(0, Int((lapEndDate!.timeIntervalSinceNow).rounded(.up)))
            guard left != lapClock.remaining else { continue }
            lapClock.remaining = left
            awardCheckpointCoinsIfDue()
            // The widget's car is drawn from the clock whenever the widget redraws: a fresh state every few seconds keeps it close
            if isLapActive && left % 5 == 0 {
                LiveActivityManager.shared.updateLapProgress(remainingSeconds: left, totalMinutes: focusMinutes, isPaused: false, topicTitle: customTopicText)
            }
            if left == 0 && isLapActive { finishLapSoon() }
        }
        lapEndDate = nil
    }

    private var lapTotalSeconds: Int { max(1, Int(focusMinutes * 60)) }
    private var lapElapsedSeconds: Int { max(0, lapTotalSeconds - lapClock.remaining) }
    private var lapReachedHalfway: Bool { lapElapsedSeconds * 2 >= lapTotalSeconds }

    /// Three checkpoints, one coin each: a third of the way, two thirds, and the end of the timer.
    private func awardCheckpointCoinsIfDue() {
        guard isLapActive else { return }
        for checkpoint in 1...3 where lapElapsedSeconds * 3 >= lapTotalSeconds * checkpoint {
            if progress.awardLapCoin("CP\(checkpoint)") { lapCoinsEarned += 1 }
        }
    }

    /// When the timer runs out, the last coin has a moment to reach the badge before the lap closes.
    private func finishLapSoon() {
        guard isLapActive, !finishScheduled else { return }
        if lapClock.remaining > 0 { finishLap(); return }
        finishScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            finishLap()
            finishScheduled = false
        }
    }

    /// Timer "Begin": the start lights run first.
    private func beginLap() {
        progress.startNewLap()
        lapCoinsEarned = 0
        lapSecondsStudied = 0
        lapClock.remaining = lapTotalSeconds
        withAnimation(.smooth(duration: 0.4)) { showStartLights = true }
    }

    /// The fifth light is on: the cockpit opens and the timer starts ticking.
    private func startLap() {
        withAnimation(.smooth(duration: 0.4)) {
            lapClock.remaining = lapTotalSeconds
            isFocusTimerRunning = true
            isLapActive = true
            showStartLights = false
        }
        // App Blocking: the apps chosen in Settings are shielded while the timer runs
        AppBlocker.shared.startBlocking(for: Double(lapTotalSeconds))
        let topic = customTopicText
        let seconds = Double(lapTotalSeconds)
        Task { await NotificationManager.shared.scheduleTimerFinished(topic: topic, after: seconds) }
        // With Widget Timer on, the timer also runs as a Live Activity on the Lock Screen, with the app in the background
        if UserDefaults.standard.object(forKey: "settings_widget_timer") as? Bool ?? true {
            LiveActivityManager.shared.startLapActivity(topicTitle: customTopicText, subject: sessionTopic.subject, durationMinutes: focusMinutes, tyreCompound: selectedTyre.name)
        }
    }

    /// The session is done (time ran out, or Finish was tapped). Past the half-way point it earns the
    /// second coin and is written to the week's streak and study minutes; ending earlier earns nothing.
    private func finishLap(celebrate: Bool = true) {
        guard isLapActive else { return }
        lapSecondsStudied = lapElapsedSeconds
        awardCheckpointCoinsIfDue()
        if lapReachedHalfway {
            progress.recordSession(studiedSeconds: lapSecondsStudied, topic: sessionTopic.title, chapter: sessionTopic.chapter, subject: sessionTopic.subject)
        }
        withAnimation(AppMotionSystem.interactiveSpring) {
            isLapActive = false
            isFocusTimerRunning = false
            showCongratulations = celebrate
        }
        LiveActivityManager.shared.endLapActivity()
        AppBlocker.shared.stopBlocking()
        NotificationManager.shared.cancelTimerFinished()
        WidgetSync.refresh(fallback: sessionTopic)
    }

    private func abortLap() {
        withAnimation(AppMotionSystem.interactiveSpring) {
            isFocusTimerRunning = false
            isLapActive = false
            lapClock.remaining = lapTotalSeconds
        }
        LiveActivityManager.shared.endLapActivity()
        AppBlocker.shared.stopBlocking()
        NotificationManager.shared.cancelTimerFinished()
    }
}
