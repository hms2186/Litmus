//
//  F1AppRouter.swift
//  App shell, matching the Figma flow: Super License onboarding, then a four-tab shell
//  (Home, Timer, Explain, Flashcards) with the start lights, live cockpit HUD and congratulations
//  screens layered over it.
//
//  Owns the single FeedbackViewModel, so the v4.0 engine state drives the Explain tab.
//

import SwiftUI
import UserNotifications
import SwiftData

struct F1AppRouter: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var feedback = FeedbackViewModel(transport: LitmusApp.transport)
    @AppStorage("hasCompletedSuperLicenseOnboarding") private var hasCompletedOnboarding = false

    // Navigation
    @State private var selectedTab: AppNavigationTab = .pitWall
    @State private var showOnboarding = false

    // Learner: saved on the device, so the name given in onboarding is used everywhere, every launch
    @AppStorage("learner_name") private var learnerName = ""
    @AppStorage("learner_grade") private var learnerGrade = "Grade 10"
    @AppStorage("learner_nationality") private var learnerNationality = "India"
    @AppStorage("learner_driver_number") private var learnerNumber = 44
    @AppStorage("learner_curriculum") private var learnerCurriculum = "NCERT"
    @ObservedObject private var progress = F1SessionProgressManager.shared
    @State private var studentCountry: StudentCountry = .india

    // Study session (the lap): one source of truth for the Timer tab, the cockpit HUD and the clock
    @State private var customTopicText = ""
    @State private var chosenTopic: NCERTTopic?
    @State private var sessionTopic = NCERTTopic.sampleChapter[0]
    @State private var timerRecommendation: F1TimerRecommendation?
    @State private var focusMinutes = 15.0
    // Held, not observed: only the cockpit redraws on each tick
    @State private var lapClock = LapClock()
    @State private var isFocusTimerRunning = false
    @State private var isLapActive = false
    @State private var showCongratulations = false
    @State private var showStartLights = false
    @State private var deckRequest: F1DeckRequest?
    @Environment(\.scenePhase) private var scenePhase
    @State private var finishScheduled = false
    @State private var lapEndDate: Date?
    @State private var selectedCircuit: F1Circuit = .autodromoHermanosRodriguez
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
    @State private var showRevise = false

    private var profile: LearnerUserProfile {
        LearnerUserProfile(
            name: learnerName.isEmpty ? "Driver" : learnerName,
            academicYear: learnerGrade,
            curriculum: learnerCurriculum,
            nationality: learnerNationality,
            driverNumber: learnerNumber
        )
    }

    var body: some View {
        ZStack {
            AppleMusicDarkGradientBackground()

            TabView(selection: $selectedTab) {
                Tab(AppNavigationTab.pitWall.shortTitle, systemImage: "house.fill", value: AppNavigationTab.pitWall) {
                    tabScreen(.pitWall)
                }
                .badge(isFocusTimerRunning ? Text("Live") : nil)

                Tab(AppNavigationTab.carSetup.shortTitle, systemImage: "timer", value: AppNavigationTab.carSetup) {
                    tabScreen(.carSetup)
                }

                Tab(AppNavigationTab.teamRadio.shortTitle, systemImage: AppNavigationTab.teamRadio.iconName, value: AppNavigationTab.teamRadio) {
                    tabScreen(.teamRadio)
                        // The tab bar steps away while the student is explaining (the canvas, or the mic page)
                        .toolbarVisibility(isActivelyExplaining ? .hidden : .visible, for: .tabBar)
                }
                .badge(isRecording ? Text("Live") : nil)

                Tab(AppNavigationTab.flashcards.shortTitle, systemImage: AppNavigationTab.flashcards.iconName, value: AppNavigationTab.flashcards) {
                    tabScreen(.flashcards)
                }
            }
            // The tab bar on top, with no sidebar button
            .tabViewStyle(.tabBarOnly)

            // In-race cockpit: full screen, above the tab bar (Figma "Stay on track")
            if isLapActive {
                F1LiveCockpitHUDView(
                    clock: lapClock,
                    focusMinutes: focusMinutes,
                    circuit: selectedCircuit,
                    tyreCompound: selectedTyre,
                    isFocusTimerRunning: $isFocusTimerRunning,
                    onBoxBox: { showEndLap = true },
                    onAddTime: { lapClock.remaining += 300 },
                    onRedFlag: { showResetLap = true },
                    onFinishLap: finishLapSoon
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)
                .ignoresSafeArea()
            }

            // The start lights run between choosing the timer and the lap; the clock starts when the fifth one is on
            if showStartLights {
                F1StartSequenceView(topic: customTopicText) { startLap() }
                    .transition(.opacity)
                    .zIndex(190)
            }

            if showCongratulations {
                F1CongratulationsView(
                    driverName: profile.name,
                    topicTitle: sessionTopic.title,
                    onMoreTime: {
                        // Back to choosing a timer, not back onto the track
                        withAnimation(AppMotionSystem.fluidPageSpring) {
                            showCongratulations = false
                            lapClock.remaining = Int(focusMinutes * 60)
                            selectedTab = .carSetup
                        }
                    },
                    onStartRadio: {
                        // On to the Explain stage
                        withAnimation(AppMotionSystem.fluidPageSpring) {
                            showCongratulations = false
                            resetAttempt()
                            selectedTab = .teamRadio
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .zIndex(250)
                .ignoresSafeArea()
            }
        }
        .background(F1Theme.trackAsphalt.ignoresSafeArea())
        .tint(Color(red: 10/255, green: 132/255, blue: 255/255))
        .preferredColorScheme(.dark)
        .alert("Study Topic Required", isPresented: $showTopicRequired) {
            Button("OK") {}
        } message: {
            Text("Please enter a study topic or concept to master before starting your Grand Prix lap.")
        }
        .alert("Reset Grand Prix Lap?", isPresented: $showResetLap) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Lap", role: .destructive) { abortLap() }
        } message: {
            Text("Are you sure you want to abort the current lap? All in-progress lap metrics will be reset.")
        }
        .alert("Box & End Lap Early?", isPresented: $showEndLap) {
            Button("Cancel", role: .cancel) {}
            Button("Box & End", role: .destructive) { abortLap() }
        } message: {
            Text("Your stint is still in progress. Boxing now will log an incomplete Grand Prix lap.")
        }
        .fullScreenCover(isPresented: $showRevise) {
            F1ReviseView(cards: F1FlashcardLibrary.cards(for: sessionTopic), coins: progress.coins) {
                showRevise = false
                resetAttempt()
                selectedTab = .flashcards
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            F1SuperLicenseOnboardingView(
                initialName: learnerName,
                initialAcademicYear: learnerGrade,
                initialNationality: learnerNationality,
                initialDriverNumber: learnerNumber,
                onSave: { name, year, nationality, number, curriculum in
                    withAnimation(AppMotionSystem.interactiveSpring) {
                        learnerName = name
                        learnerGrade = year
                        learnerNationality = nationality
                        learnerNumber = number
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
                }
            )
        }
        .task {
            feedback.modelContext = modelContext
            F1WidgetSync.refresh(fallback: sessionTopic)
            if !hasCompletedOnboarding { showOnboarding = true }
        }
        .task(id: customTopicText) { updateSessionTopic() }
        // The widgets follow the app: refreshed when it opens or leaves, and when a session or explanation ends
        .onChange(of: scenePhase) { _, phase in
            guard phase != .inactive else { return }
            F1WidgetSync.refresh(fallback: sessionTopic)
            if phase == .background {
                // Leaving the app: a few revise nudges for what was studied lately
                let topics = LitmusWidgetStore.load().topics
                Task { await F1NotificationManager.shared.scheduleReviseReminders(topics: topics) }
            } else {
                F1NotificationManager.shared.cancelReviseReminders()
            }
        }
        .onOpenURL { url in
            // The Revise widget and the revise reminders open the deck of a chapter
            if let request = LitmusShared.deckRequest(from: url) {
                deckRequest = F1DeckRequest(chapter: request.chapter, subject: request.subject)
                selectedTab = .flashcards
            }
        }
        .onChange(of: sessionTopic.id) { _, _ in if !isLapActive { refreshRecommendation() } }
        .task(id: isFocusTimerRunning) { await runClock() }
        .onChange(of: isFocusTimerRunning) { _, running in
            // The widget shows Paused, or runs again from the time that is left
            guard isLapActive else { return }
            F1LiveActivityManager.shared.updateLapProgress(remainingSeconds: lapClock.remaining, totalMinutes: focusMinutes, isPaused: !running, topicTitle: customTopicText)
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
                case .teamRadio:
                    F1TeamRadioStudioView(
                        customTopicText: sessionTopic.title,
                        feedback: feedback,
                        topic: sessionTopic,
                        driverName: $learnerName,
                        studentCountry: $studentCountry,
                        driverNumber: profile.driverNumber,
                        transcriptionText: $transcription,
                        isRecording: $isRecording,
                        isActivelyExplaining: $isActivelyExplaining,
                        showTestButtons: $showTestButtons,
                        coins: progress.coins,
                        spendCoins: { progress.spend($0) },
                        coinsEarned: lapCoinsEarned,
                        studySeconds: lapSecondsStudied,
                        isTabActive: selectedTab == .teamRadio,
                        onExplanationResult: { passed, note in
                            progress.noteExplanationResult(topic: sessionTopic.title, reviewNote: passed ? nil : (note ?? "revisit this topic"))
                            // A gap in the explanation earns one gentle reminder; explaining it well withdraws it
                            let topic = sessionTopic.title
                            if passed { F1NotificationManager.shared.cancelRevisit(topic: topic) }
                            else { Task { await F1NotificationManager.shared.scheduleRevisit(topic: topic) } }
                        },
                        onSessionSummary: { seconds in
                            progress.recordExplanation(seconds: seconds, topic: sessionTopic.title, chapter: sessionTopic.chapter, subject: sessionTopic.subject)
                        },
                        onDone: {
                            withAnimation(AppMotionSystem.interactiveSpring) {
                                resetAttempt()
                                selectedTab = .pitWall
                            }
                        },
                        onReset: {
                            withAnimation(AppMotionSystem.interactiveSpring) {
                                resetAttempt()
                                selectedTab = .pitWall
                            }
                        },
                        onNavigateToRevise: { showRevise = true }
                    )
                case .flashcards:
                    F1StudyDeckView(grade: studyGrade, request: $deckRequest, coins: progress.coins, topic: sessionTopic)
                default:
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 20) {
                            if tab == .pitWall {
                                F1HomeDashboardView(
                                    customTopicText: $customTopicText,
                                    chosenTopic: $chosenTopic,
                                    studentCountry: $studentCountry,
                                    activeProfile: profile,
                                    onStartLap: {
                                        if customTopicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            showTopicRequired = true
                                        } else {
                                            applyRecommendedTimer()
                                            withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .carSetup }
                                        }
                                    },
                                    onNavigateToRevise: { chapter, subject in
                                        deckRequest = F1DeckRequest(chapter: chapter, subject: subject)
                                        withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .flashcards }
                                    }
                                )
                            } else {
                                F1TimerSetupView(
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
                                    onSkipTimer: { withAnimation(AppMotionSystem.fluidPageSpring) { selectedTab = .teamRadio } },
                                    recommendation: timerRecommendation,
                                    topicTitle: sessionTopic.title
                                )
                                .containerRelativeFrame(.vertical, alignment: .center) { length, _ in max(0, length - 120) }
                            }
                        }
                        .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
                        .padding(.vertical, 16)
                    }
                    // The tab bar and the corner buttons float over the page, so the top edge fades into them
                    .scrollEdgeEffectStyle(.automatic, for: .top)
                }
            }
            .background { AppleMusicDarkGradientBackground() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(isActivelyExplaining ? .hidden : .visible, for: .navigationBar)
            // The profile picture and Settings, a little way down from the top edge. They are drawn over the tab's content (not
            // in the navigation bar, whose items are rebuilt each time a screen is pushed and popped, which made them flicker).
            // Liquid Glass is around Settings alone.
            .overlay(alignment: .topTrailing) {
                if !isActivelyExplaining {
                    HStack(spacing: 12) {
                        // Switching profile is a Home screen thing; Settings is on every screen
                        if selectedTab == .pitWall { F1ProfileSwitcherButton() }
                        if selectedTab == .teamRadio { F1CoinCounter(count: progress.coins) }
                        settingsButton
                    }
                    .padding(.top, 24)
                    .padding(.trailing, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea(edges: .top)
                }
            }
            // Settings opens on the tab's own stack, so it has the system back button
            .navigationDestination(isPresented: $showSettings) {
                F1SettingsView(embedded: true)
            }
        }
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gear")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.f1Spring)
        .contentShape(Circle())
        .hoverEffect(.lift)
        .accessibilityLabel("Settings")
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
        let recommendation = F1TimerAdvisor.recommend(for: sessionTopic)
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
            if isLapActive && left % 2 == 0 {
                F1LiveActivityManager.shared.updateLapProgress(remainingSeconds: left, totalMinutes: focusMinutes, isPaused: false, topicTitle: customTopicText)
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
        F1AppBlocker.shared.startBlocking()
        let topic = customTopicText
        let seconds = Double(lapTotalSeconds)
        Task { await F1NotificationManager.shared.scheduleTimerFinished(topic: topic, after: seconds) }
        // With Widget Timer on, the timer also runs as a Live Activity on the Lock Screen, with the app in the background
        if UserDefaults.standard.object(forKey: "settings_widget_timer") as? Bool ?? true {
            F1LiveActivityManager.shared.startLapActivity(topicTitle: customTopicText, subject: sessionTopic.subject, durationMinutes: focusMinutes, tyreCompound: selectedTyre.name)
        }
    }

    /// The session is done (time ran out, or Finish was tapped). Past the half-way point it earns the
    /// second coin and is written to the week's streak and study minutes; ending earlier earns nothing.
    private func finishLap() {
        guard isLapActive else { return }
        lapSecondsStudied = lapElapsedSeconds
        awardCheckpointCoinsIfDue()
        if lapReachedHalfway {
            progress.recordSession(studiedSeconds: lapSecondsStudied, topic: sessionTopic.title, chapter: sessionTopic.chapter, subject: sessionTopic.subject)
        }
        withAnimation(AppMotionSystem.interactiveSpring) {
            isLapActive = false
            isFocusTimerRunning = false
            showCongratulations = true
        }
        F1LiveActivityManager.shared.endLapActivity()
        F1AppBlocker.shared.stopBlocking()
        F1NotificationManager.shared.cancelTimerFinished()
        F1WidgetSync.refresh(fallback: sessionTopic)
    }

    private func abortLap() {
        withAnimation(AppMotionSystem.interactiveSpring) {
            isFocusTimerRunning = false
            isLapActive = false
            lapClock.remaining = lapTotalSeconds
        }
        F1LiveActivityManager.shared.endLapActivity()
        F1AppBlocker.shared.stopBlocking()
        F1NotificationManager.shared.cancelTimerFinished()
    }
}
