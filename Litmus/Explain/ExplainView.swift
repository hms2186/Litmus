//
//  ExplainView.swift
//  Prototype
//
//  Exact 1:1 Implementation of Figma Nodes:
//  - 1057:1533: New Explain Screen Revamp (Centered Hero, Left Floating Input Capsule, Top-Right Radio Tile, Bottom Floating Mic Dock)
//  - 1057:6056: Active Listening State (Radio says "I'm listening...", Listening status indicator, live transcription readout)
//  - 1057:4639: Waveform Equalizer & Left Transcription Card Layout
//  - 1057:1560: Native Transcription Card Toolbar (Mic, Pencil, Keyboard, Reset, Play, Done)
//  - 772:3540: "Good Try, Here's what you missed" Analysis & Action Buttons
//  - 802:3825: "USE REWARDS" Spend 3 Coins Modal
//  - 589:5305: "WHAT YOU MISSED" Reference View
//  - 626:3259: "Well Done!! You are clear now" Session Summary
//

import SwiftUI
import SwiftData
import PencilKit
import AVFoundation

public enum ExplainInputMode: String, Identifiable, Hashable {
    case speak = "Speak"
    case write = "Write"
    case type = "Type"
    
    public var id: String { rawValue }
}

struct ExplainView: View {
    var customTopicText: String
    @ObservedObject var feedback: FeedbackViewModel
    var topic: NCERTTopic
    @Binding var driverName: String
    @Binding var studentCountry: StudentCountry
    @Binding var transcriptionText: String
    @Binding var isRecording: Bool
    @Binding var isActivelyExplaining: Bool
    @Binding var showTestButtons: Bool
    var coins: Int
    var spendCoins: (Int) -> Bool
    var coinsEarned: Int
    var studySeconds: Int = 0
    /// The engineer speaks only while the Explain tab is the one on screen.
    var isTabActive = true
    var onEvaluationComplete: ((Int, String) -> Void)?
    /// Called when an attempt is finished: whether it cleared the topic, and what to work on if not.
    var onExplanationResult: ((Bool, String?) -> Void)? = nil
    /// The summary is on screen: how long the explanation took, in seconds.
    var onSessionSummary: ((Int) -> Void)? = nil
    var onDone: () -> Void
    var onReset: () -> Void
    var onNavigateToRevise: (() -> Void)? = nil
    
    // Environment & Navigation
    @Environment(\.dismiss) private var dismiss
    /// Compact width (iPhone): the stage stacks the radio card over a row of modes. Regular width keeps the iPad layout.
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    
    // State
    @StateObject private var speechRecorder = LiveSpeechRecorder()
    @State private var clarityScore: Int = 50 // 50: Initial/Recording, <80: Good Try, >=80: Well Done
    @State private var hasEvaluated: Bool = false
    @State private var isEvaluating: Bool = false
    @State private var inputMode: StudioInputMode = .voice
    @State private var activeInputMode: ExplainInputMode? = nil
    @State private var showRewardActionSheet: Bool = false
    @State private var showWhatYouMissedView: Bool = false
    /// Short revision cards for the topic, made from its textbook passage before the sheet opens
    @State private var missedCards: [FlashcardItem] = []
    @State private var preparingCards = false
    @State private var showAnswerSheet = false
    @State private var showHintsCarousel: Bool = false
    @State private var hintsDismissed: Bool = false
    @State private var showSummary: Bool = false
    @State private var hintsPaid: Bool = false
    @State private var typedText: String = ""
    @State private var isListeningStage = false
    @State private var showLeaveWarning = false
    @State private var debriefShown = false
    @StateObject private var voice = EngineerVoice()
    @State private var sketchText: String = ""
    @State private var sketchRecognition: Task<Void, Never>?
    @State private var showNotEnoughCoins: Bool = false
    /// The radio box's reply on the Write and Type screens when the answer is not enough to check yet.
    @State private var inputNotice: String?
    /// The stage's width, so the dock fits a narrow window.
    @State private var explainSeconds: Int = 0
    @State private var explainStartedAt = Date()
    @Environment(\.modelContext) private var modelContext
    @State private var latestEvaluationResult: StudioDebrief? = nil
    @FocusState private var isFieldFocused: Bool
    
    // Apple Pencil & Speech Audio Replay
    @State private var pencilCanvasView = PKCanvasView()
    @State private var isPencilCanvasEmpty: Bool = true
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var speechTask: Task<Void, Never>?
    @State private var lastSpokenLine = ""
    
    private enum StudioInputMode {
        case voice
        case pencil
        case keyboard
    }
    
    init(
        customTopicText: String = "",
        feedback: FeedbackViewModel,
        topic: NCERTTopic,
        driverName: Binding<String> = .constant("Aarushi"),
        studentCountry: Binding<StudentCountry> = .constant(.india),
        transcriptionText: Binding<String>,
        isRecording: Binding<Bool>,
        isActivelyExplaining: Binding<Bool> = .constant(false),
        showTestButtons: Binding<Bool> = .constant(false),
        coins: Int = 10,
        spendCoins: @escaping (Int) -> Bool = { _ in false },
        coinsEarned: Int = 0,
        studySeconds: Int = 0,
        isTabActive: Bool = true,
        onEvaluationComplete: ((Int, String) -> Void)? = nil,
        onExplanationResult: ((Bool, String?) -> Void)? = nil,
        onSessionSummary: ((Int) -> Void)? = nil,
        onDone: @escaping () -> Void,
        onReset: @escaping () -> Void = {},
        onNavigateToRevise: (() -> Void)? = nil
    ) {
        self.customTopicText = customTopicText
        self.feedback = feedback
        self.topic = topic
        self._driverName = driverName
        self._studentCountry = studentCountry
        self._transcriptionText = transcriptionText
        self._isRecording = isRecording
        self._isActivelyExplaining = isActivelyExplaining
        self._showTestButtons = showTestButtons
        self.coins = coins
        self.spendCoins = spendCoins
        self.coinsEarned = coinsEarned
        self.studySeconds = studySeconds
        self.isTabActive = isTabActive
        self.onEvaluationComplete = onEvaluationComplete
        self.onExplanationResult = onExplanationResult
        self.onSessionSummary = onSessionSummary
        self.onDone = onDone
        self.onReset = onReset
        self.onNavigateToRevise = onNavigateToRevise
    }
    
    private var activeTopicTitle: String {
        let t = customTopicText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Laws of Motion" : t
    }
    
    /// The engineer's pose for the current attempt. Engine topics follow the attempt machine and its Rule
    /// Engine outcome; other topics keep the score-based poses.
    private var activePose: EngineerPose {
        if feedback.engineTopicActive {
            switch feedback.machine.state {
            case .grading, .awaitingFollowUp, .reprompt:
                return .listening                // needs clarification / waiting for the student
            case .correcting:
                return .needsCorrection
            case .finished(let outcome):
                return outcome == .mastered || outcome == .likelyMastered ? .mastered : .needsCorrection
            case .ready, .offTopic, .blocked:
                break
            }
        } else if hasEvaluated {
            return clarityScore >= 80 ? .mastered : .needsCorrection
        }
        return isRecording || isActivelyExplaining ? .listening : .idle
    }

    // MARK: - Engine state (bound to FeedbackViewModel)

    /// The attempt state for topics the engine grades; nil for legacy topics.
    private var engineState: AttemptState? {
        feedback.engineTopicActive ? feedback.machine.state : nil
    }

    /// The debrief is showing: the engine finished the attempt, or it asked a follow-up or a correction
    /// (shown as the "Good try" debrief, as in the design) until the student answers again.
    private var evaluated: Bool {
        if let engineState {
            switch engineState {
            case .finished: return true
            case .awaitingFollowUp, .correcting: return !hintsDismissed
            default: return false
            }
        }
        return hasEvaluated
    }

    /// The hint carousel is showing: only when the student asked for hints.
    private var hintsVisible: Bool { showHintsCarousel }

    /// What the radio says on the stage: the engine's own line once an attempt is under way.
    private var stageRadioMessage: String {
        if let engineState, engineState != .ready { return feedback.radioPrompt }
        if let line = feedback.reviewPrompt(for: topic), engineState == nil { return line }
        return "“Radio check, please explain \(activeTopicTitle)”"
    }

    /// Starts a fresh answer. A pending follow-up or correction is kept; everything else is reset.
    /// The attempt cleared the topic (the debrief then offers the summary instead of hints).
    private var attemptPassed: Bool {
        if let engineState, case .finished(let outcome) = engineState {
            return outcome == .mastered || outcome == .likelyMastered
        }
        return engineState == nil && hasEvaluated && clarityScore >= 80
    }

    /// The feedback, hints or summary of a finished attempt is on screen
    private var reviewingResult: Bool { evaluated || showSummary || showHintsCarousel }

    /// Which full page the screen shows. One value, so the page is chosen in one place and animates as one change.
    private enum Page { case hints, summary, debrief, stage }

    private var page: Page {
        if hintsVisible { return .hints }
        if evaluated && showSummary { return .summary }
        if evaluated { return .debrief }
        return .stage
    }

    /// Leaves the explanation and returns to the Explain start page.
    private func leaveExplanation() {
        stopRecordingIfNeeded()
        voice.stop()
        withAnimation(AppMotionSystem.fluidSpring) {
            showHintsCarousel = false
            showSummary = false
            hintsPaid = false
            typedText = ""
            sketchText = ""
            pencilCanvasView.drawing = PKDrawing()
            hasEvaluated = false
            clarityScore = 50
            transcriptionText = ""
            isListeningStage = false
            activeInputMode = nil
            isActivelyExplaining = false
        }
        feedback.reset()
    }

    private func restartAttempt() {
        withAnimation(AppMotionSystem.fluidSpring) {
            showHintsCarousel = false
            showSummary = false
            hintsPaid = false
            typedText = ""
            sketchText = ""
            pencilCanvasView.drawing = PKDrawing()
            hasEvaluated = false
            clarityScore = 50
            transcriptionText = ""
            isActivelyExplaining = true
            switch engineState {
            case .awaitingFollowUp, .correcting: hintsDismissed = true
            case .some: feedback.reset()
            case .none: break
            }
        }
        // Come back to the same way of answering: the Sketch or Type screen reopens, not the Speak stage
        switch inputMode {
        case .pencil: reopen(.write)
        case .keyboard: reopen(.type)
        case .voice: break
        }
    }

    private func reopen(_ mode: ExplainInputMode) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(AppMotionSystem.snappy) {
                activeInputMode = mode
                isActivelyExplaining = true
            }
        }
    }

    /// Hint cards for topics the engine does not grade: the topic's own flashcards.
    private var topicHintCards: [HintCard] {
        let cards = FlashcardLibrary.cards(for: topic).prefix(3)
        return cards.enumerated().map { index, card in
            HintCard(id: index, title: card.title, bodyText: card.body, indexLabel: "\(index + 1)/\(cards.count)", keywords: card.keywords)
        }
    }

    private var engineConcept: CompiledConcept? {
        CompiledCurriculumStore.shared.entry(forLabel: topic.title)?.concept
    }

    private var engineReport: EvaluationReport? {
        feedback.engineTopicActive ? feedback.decision?.report : nil
    }

    /// Display-only mapping from the Rule Engine outcome to this screen's 0-100 clarity ring.
    private func displayScore(for outcome: EvaluationOutcome) -> Int {
        switch outcome {
        case .mastered: return 100
        case .likelyMastered: return 90
        case .partial(let almostThere): return almostThere ? 70 : 40
        case .notYet, .needsCorrection, .needsClarification: return 30
        case .notGradable, .offTopic: return 0
        }
    }

    private func applyEngineState(_ state: AttemptState) {
        guard feedback.engineTopicActive else { return }
        switch state {
        case .ready:
            break
        case .grading:
            isEvaluating = true
            hintsDismissed = false
            showHintsCarousel = false
            showSummary = false
        case .reprompt, .offTopic, .blocked:
            isEvaluating = false
            if let mode = activeInputMode, mode != .speak { inputNotice = notice(for: state) }
            // A spoken answer that was empty, too short or off topic goes straight back to the Explain start page, with the
            // tab bar and the engineer's line there, instead of leaving a half-hidden screen behind
            if activeInputMode == nil, !isRecording, !isListeningStage {
                withAnimation(AppMotionSystem.fluidSpring) { isActivelyExplaining = false }
            }
        case .awaitingFollowUp, .correcting:
            isEvaluating = false
            hintsDismissed = false
            showSummary = false
            let report = feedback.decision?.report ?? EvaluationReport()
            latestEvaluationResult = StudioDebrief(
                score: 30,
                passedIB: !report.right.isEmpty,
                passedParakh: false,
                feynmanGap: report.missing.first ?? report.corrections.first ?? "",
                nextGuidingQuestion: report.followUp ?? report.vague.first ?? ""
            )
            isActivelyExplaining = true
            withAnimation(AppMotionSystem.fluidSpring) { clarityScore = 30 }
            onExplanationResult?(false, (report.corrections.first ?? report.missing.first).map(FeedbackPhrasing.shortNote))
        case .finished(let outcome):
            isEvaluating = false
            let report = feedback.decision?.report ?? EvaluationReport()
            let score = displayScore(for: outcome)
            latestEvaluationResult = StudioDebrief(
                score: score,
                passedIB: !report.right.isEmpty,
                passedParakh: outcome == .mastered || outcome == .likelyMastered,
                feynmanGap: report.missing.first ?? report.corrections.first ?? "",
                nextGuidingQuestion: report.vague.first ?? ""
            )
            hasEvaluated = true
            isActivelyExplaining = true
            showHintsCarousel = false
            withAnimation(AppMotionSystem.fluidSpring) { clarityScore = score }
            onEvaluationComplete?(score, activeTopicTitle)
            let passed = outcome == .mastered || outcome == .likelyMastered
            // A correct explanation goes straight to the well-done summary. The "Good try" review (missing, vague, right,
            // Try again, Get Hints) is for an answer that still has something to fix.
            if passed { withAnimation(.smooth(duration: 0.45)) { showSummary = true } }
            onExplanationResult?(passed, passed ? nil : (report.corrections.first ?? report.missing.first).map(FeedbackPhrasing.shortNote))
        }
    }

    /// "Time Taken to Explain" tile from the listening screen design.
    private var explainTimerTile: some View {
        TimelineView(.periodic(from: explainStartedAt, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(explainStartedAt)))
            VStack(spacing: 4) {
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(.system(size: 40, weight: .regular).monospacedDigit())
                    .foregroundStyle(.white)
                Text("Time Taken to Explain")
                    .scaledFont(size: 15)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .litmusGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private var gradingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Checking your explanation…")
                .scaledFont(size: 20, weight: .semibold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }


    public var body: some View {
        ZStack {
            // Background: Official F1 Command Workspace
            Color.black
                .ignoresSafeArea()
            
            GeometryReader { geo in
                Image("race_engineer_workspace_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            
            switch page {
            case .hints:
                HintsView(
                    hintCards: HintCardBuilder.cards(state: feedback.machine.state, concept: engineConcept, decision: feedback.decision, fallback: topicHintCards, keywords: FlashcardLibrary.keywords(for: topic)),
                    coinBalance: coins,
                    onTryAgain: restartAttempt,
                    onSessionSummary: {
                        withAnimation(AppMotionSystem.fluidSpring) {
                            showHintsCarousel = false
                            showSummary = true
                            if clarityScore == 50 { clarityScore = 30 }
                        }
                    }
                )
            case .summary:
                // Mastered Session Summary (Figma 1264:3088) & Partial Mastery (Figma 1264:2793)
                wellDoneSummaryView
                    .screenChangeTransition()
            case .debrief:
                // Good Try Debrief (Figma 1264:2970)
                goodTryAnalysisView
                    .screenChangeTransition()
            case .stage:
                // Main Active Stage (Figma 1057:1533 / 1057:6056)
                explainRevampMainStage
                    .screenChangeTransition()
            }
            
            // Grading in progress: the on-device check can take a few seconds
            if isEvaluating {
                gradingOverlay
                    .transition(.opacity)
            }

            // An earlier answer was re-graded in the background and needs a look before a new one
            if let card = feedback.reviewCard, case .ready = feedback.machine.state, !evaluated, activeInputMode == nil {
                Color.black.opacity(0.55).ignoresSafeArea()
                ReviewCardView(card: card) { feedback.dismissReviewCard(topic: topic) }
                    .padding(28)
                    .frame(maxWidth: 560)
                    .litmusGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            // Modal: USE REWARDS (Figma 802:3825)
            if showRewardActionSheet {
                Color.black.opacity(0.70)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                useRewardsModal
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.45), value: page)
        .animation(.smooth(duration: 0.35), value: isEvaluating)
        .overlay {
            if preparingCards {
                ProgressView("Preparing your cards…")
                    .padding(24)
                    .litmusGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showAnswerSheet) { answerSheet }
        .sheet(isPresented: $showWhatYouMissedView) {
            NavigationStack {
                ZStack {
                    Color(red: 14/255, green: 14/255, blue: 16/255)
                        .ignoresSafeArea()
                    
                    ReviseFlashcardsView(
                        cognitiveTokens: .constant(7),
                        initialMode: .whatYouMissed(
                            missedCards
                        ),
                        onTryAgainInRadio: {
                            showWhatYouMissedView = false
                            withAnimation {
                                clarityScore = 50
                                transcriptionText = ""
                                isActivelyExplaining = true
                            }
                        },
                        onOpenDebrief: {
                            showWhatYouMissedView = false
                            withAnimation {
                                clarityScore = 90
                            }
                        }
                    )
                }
                // A sheet always has a visible way out besides swiping it down
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { showWhatYouMissedView = false } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
            }
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .task {
            // The radio clicks in as the screen opens, then the engineer speaks
            if isTabActive { StartLightsSound.shared.radioNotification() }
            speakRadioLine()
        }
        // The speech model is found and installed ahead of the first recording, so Speak starts at once
        .task { await speechRecorder.prepare() }
        .task(id: topic.id) {
            // Load an earlier review card or revisit flag before the first answer.
            if feedback.modelContext == nil { feedback.modelContext = modelContext }
            if case .ready = feedback.machine.state { feedback.prepare(topic: topic) }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // While explaining, the navigation bar stays and carries the system's own back chevron (like Sketch and Type),
        // which asks before it throws an unfinished explanation away
        .toolbar {
            if (isActivelyExplaining || reviewingResult) && activeInputMode == nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // Leaving always asks first: it throws away what the learner has just said or been told
                        showLeaveWarning = true
                    } label: {
                        // A Label, as the system's own bar buttons use, so the bar sizes the button and its hover to a circle
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
            }
        }
        .alert(reviewingResult ? "Leave this review?" : "Leave this explanation?", isPresented: $showLeaveWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) { leaveExplanation() }
        } message: {
            Text(reviewingResult
                 ? "This feedback and these hints will not be kept."
                 : "What you have said so far will not be saved.")
        }
        .haptic(.impact(weight: .heavy), trigger: isRecording)
        .haptic(.impact(weight: .medium), trigger: activeInputMode)
        .navigationDestination(item: $activeInputMode) { mode in
            explainWorkstationScreen(for: mode)
                .minimalBackButton()
        }
        .onChange(of: feedback.machine.state) { _, state in applyEngineState(state) }
        .onChange(of: currentRadioMessage) { _, _ in speakRadioLine() }
        .onChange(of: activeInputMode) { _, mode in
            // Changing the way of answering silences the engineer at once and drops any line still waiting to start; the
            // new screen's line is spoken once, after the changes have settled, so quick switches never overlap
            speechTask?.cancel()
            voice.stop()
            speechSynthesizer.stopSpeaking(at: .immediate)
            lastSpokenLine = ""
            if mode != nil { explainStartedAt = Date() }
            speakRadioLine()
        }
        .onChange(of: showSummary) { _, showing in if showing { onSessionSummary?(explainSeconds) } }
        #if DEBUG
        // Layout checking only: opens the session summary straight away, with no graded answer behind it
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-debugSummary") {
                hasEvaluated = true; clarityScore = 90; showSummary = true; isActivelyExplaining = true
            }
        }
        #endif
        // The stage changes are visual (the dock grows, the screen fades), so VoiceOver is told in words
        .onChange(of: isListeningStage) { _, listening in
            if listening { AccessibilityNotification.Announcement("Listening. Explain the topic in your own words.").post() }
        }
        .onChange(of: isEvaluating) { _, checking in
            if checking { AccessibilityNotification.Announcement("Checking your explanation").post() }
        }
        .onChange(of: evaluated) { _, done in
            if done { AccessibilityNotification.Announcement("Feedback is ready").post() }
        }
        .onChange(of: showHintsCarousel) { _, showing in
            if showing { AccessibilityNotification.Announcement("Hints").post() }
        }
        .onChange(of: showSummary) { _, showing in
            if showing { AccessibilityNotification.Announcement("Session summary").post() }
        }
        .onChange(of: isTabActive) { _, active in
            if active { StartLightsSound.shared.radioNotification(); lastSpokenLine = ""; speakRadioLine() }
            else {
                speechTask?.cancel(); lastSpokenLine = ""; voice.stop(); speechSynthesizer.stopSpeaking(at: .immediate)
                // Leaving Explain from the debrief, hints or summary starts fresh next time, instead of coming back to a stuck screen
                if reviewingResult { leaveExplanation() }
            }
        }
        .onChange(of: isRecording) { _, recording in if recording { voice.stop() } }
        .onChange(of: speechRecorder.isRecording) { _, recording in
            isRecording = recording
            if recording { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isActivelyExplaining = true } }
        }
        .onChange(of: activeInputMode) { _, mode in
            if mode != nil {
                isActivelyExplaining = true
            } else if !isRecording && !evaluated && !isEvaluating {
                isActivelyExplaining = false
            }
        }
    }
    
    // MARK: - Explain stage and listening screen: one screen, so the character never moves
    // The engineer is drawn at the same size and place in both poses; tapping the mic only fades the
    // pose, swaps the left column and widens the dock.
    private var explainRevampMainStage: some View {
        ZStack {
            engineerFigure

            VStack(spacing: 0) {
                if isCompact {
                    // A phone is too narrow for the modes beside the radio card: the card spans the top, the modes sit under it
                    VStack(alignment: .leading, spacing: 14) {
                        radioCard(message: currentRadioMessage ?? "")
                            .frame(maxWidth: .infinity)
                        ZStack(alignment: .topLeading) {
                            compactModeRow
                                .opacity(isListeningStage ? 0 : 1)
                                .allowsHitTesting(!isListeningStage)
                            VStack(alignment: .leading, spacing: 12) {
                                topicHeading()
                                explainTimerTile
                            }
                            .opacity(isListeningStage ? 1 : 0)
                            .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 64)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        ZStack(alignment: .topLeading) {
                            modeSelectionButtons
                                .opacity(isListeningStage ? 0 : 1)
                                .offset(x: isListeningStage ? -24 : 0)
                                .allowsHitTesting(!isListeningStage)
                            VStack(alignment: .leading, spacing: 24) {
                                topicHeading()
                                explainTimerTile
                            }
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(.top, -28)
                            .opacity(isListeningStage ? 1 : 0)
                            .offset(x: isListeningStage ? 0 : 24)
                            .allowsHitTesting(false)
                        }
                        // Takes the room the radio card leaves, so on a narrow (portrait) screen the topic wraps instead of
                        // pushing the card off the edge
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .trailing, spacing: 14) {
                            radioCard(message: currentRadioMessage ?? "")
                                .frame(width: 330)
                        }
                    }
                    .padding(.horizontal, 28)
                    // Clear of the back button, coin counter and settings button the app keeps in the top corners; a little higher
                    // while listening, where the topic and the timer sit nearer the top edge
                    .padding(.top, isListeningStage ? 70 : 100)
                }

                Spacer()

                micDock
                    .padding(.bottom, isListeningStage ? 56 : 40)
            }

            VStack {
                Spacer()
                HStack { Spacer(); disclaimerText }
            }
            .padding(.trailing, 28)
            .padding(.bottom, 18)
        }
        .animation(.smooth(duration: 0.55), value: isListeningStage)
    }

    private var engineerFigure: some View {
        // Behind the dock, filling the screen; the same live character in both stages, so waiting -> listening is a pose
        // change, not a cut to another clip
        // Laid over a clear screen-sized frame, so the filled picture never widens the layout around it
        // (on a tall, narrow phone it would otherwise push the panels off both edges)
        Color.clear
            .overlay { EngineerAvatarView(pose: isListeningStage ? .listening : .idle, isSpeaking: voice.isSpeaking, layout: .fill) }
            .clipped()
            .ignoresSafeArea()
    }

    private var disclaimerText: some View {
        Text("Disclaimer: Your voice stays on this iPad.")
            .scaledFont(size: 14)
            .foregroundStyle(.white.opacity(0.6))
    }

    /// The glass dock. Before speaking it is a small panel around a white mic; on Click to start the glass grows out from the
    /// mic into the transcript box while the mic slides to the right and turns red ("Click to End"). Plain Liquid Glass, no tint.
    private var micDock: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        // Widths are limits, not fixed sizes, so the dock never asks for more room than the screen has (portrait included)
        let dockMax: CGFloat = isListeningStage ? 1080 : 590
        return ZStack {
            // The words so far, in the part of the glass the mic has left
            HStack(spacing: 0) {
                Group {
                    let text = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        Text("Your Transcription appears here")
                            .scaledFont(size: 19, weight: .medium)
                            .foregroundStyle(Color.white.opacity(0.55))
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(text)
                                .scaledFont(size: 19, weight: .medium)
                                .foregroundStyle(.white)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .defaultScrollAnchor(.bottom)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 36)
                .padding(.vertical, 18)
                Color.clear.frame(width: 220)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 206)
            .opacity(isListeningStage ? 1 : 0)
            .allowsHitTesting(isListeningStage)

            micButton
                .frame(maxWidth: .infinity, alignment: isListeningStage ? .trailing : .center)
                .offset(x: isListeningStage ? -40 : 0)
        }
        .frame(maxWidth: dockMax)
        .frame(height: isListeningStage ? 206 : 190)
        // Liquid Glass (HIG): the standard regular material, applied straight to the panel that holds the controls, no tint or extra stroke
        .litmusGlass(in: shape)
        .padding(.horizontal, 36)
    }

    private var micButton: some View {
        Button {
            if speechRecorder.isRecording || isListeningStage && isRecording {
                endListening()
            } else if isListeningStage {
                toggleRecording()
            } else {
                beginListening()
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    PulsingMicRing(isRecording: isRecording)
                        .frame(width: 140, height: 140)
                        .opacity(isListeningStage ? 1 : 0)
                    Circle()
                        .fill(isListeningStage ? Color(red: 238/255, green: 0, blue: 0) : Color.white)
                        .frame(width: isListeningStage ? 132 : 124, height: isListeningStage ? 132 : 124)
                    Image(systemName: "mic.fill")
                        .font(.system(size: isListeningStage ? 56 : 54, weight: .semibold))
                        .foregroundStyle(isListeningStage ? Color.white : Color(red: 238/255, green: 0, blue: 0))
                }
                Text(isListeningStage ? (isRecording ? "Click to End" : "Click to start") : "Click to start")
                    .scaledFont(size: isListeningStage ? 20 : 14)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.pressSpring)
        .contentShape(Circle())
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.lift)
        .accessibilityLabel(isListeningStage ? (isRecording ? "End recording and check my explanation" : "Start recording") : "Start voice explanation")
    }

    private func beginListening() {
        voice.stop()
        inputMode = .voice
        transcriptionText = ""
        explainStartedAt = Date()
        withAnimation(.smooth(duration: 0.55)) {
            isListeningStage = true
            isActivelyExplaining = true
        }
        toggleRecording()
    }

    private func endListening() {
        stopRecordingIfNeeded()
        evaluateTranscription()
        withAnimation(.smooth(duration: 0.55)) { isListeningStage = false }
    }

    // MARK: - What the engineer says

    private var debriefRadioMessage: String {
        if attemptPassed { return "“Well explained! Here’s how it went.”" }
        return engineState == nil ? "“Good try! Here’s what you missed. Try again.”" : "“\(feedback.radioPrompt)”"
    }

    /// The line in the radio box for the screen being shown. It is read aloud and revealed as it is spoken.
    private var currentRadioMessage: String? {
        if hintsVisible { return nil }
        // On the Type and Sketch screens the engineer asks for that way of answering
        if let mode = activeInputMode, mode != .speak {
            if let inputNotice { return "“\(inputNotice)”" }
            return "“\(modeLine(mode))”"
        }
        if evaluated { return showSummary ? "“\(summaryRadioLine)”" : debriefRadioMessage }
        if isListeningStage { return "“I’m listening...”" }
        let line = stageRadioMessage
        return line.hasPrefix("“") ? line : "“\(line)”"
    }

    /// What the engineer says on each answering screen: the same question, asked for the way the student is answering.
    private func modeLine(_ mode: ExplainInputMode) -> String {
        let base = stageRadioMessage.trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
        // A re-prompt from an earlier spoken answer ("I didn't catch that") is not the question for a written one
        var isReprompt = false
        switch engineState {
        case .some(.reprompt), .some(.grading): isReprompt = true
        default: break
        }
        let question = base.hasPrefix("Radio check") || isReprompt ? "Explain \(activeTopicTitle) in your own words." : base
        switch mode {
        case .type: return "Type it out, take your time. \(question)"
        case .write: return "Sketch or write it with your Pencil. \(question)"
        case .speak: return base
        }
    }

    /// Every trigger (the screen opening, the line changing, the tab coming back) lands here. They are coalesced
    /// into one start a moment later, and a line already spoken is not spoken again, so the engineer never doubles up.
    private func speakRadioLine() {
        speechTask?.cancel()
        if isTabActive, let line = currentRadioMessage, line != lastSpokenLine, !isListeningStage, !isRecording, !isEvaluating {
            voice.expect(line)
        }
        speechTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            guard isTabActive, let line = currentRadioMessage, !isListeningStage, !isRecording, !isEvaluating else {
                voice.stop()
                return
            }
            guard line != lastSpokenLine else { voice.clearPending(); return }
            lastSpokenLine = line
            voice.speak(line)
        }
    }

    // MARK: - Active Engineer Character Container (For Write & Type Screens)
    private func activeEngineerBox(width: CGFloat = 420, height: CGFloat = 530) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
            
            Image("race_engineer")
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height, alignment: .bottom)
                .clipped()
        }
        .frame(width: width, height: height)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.40), radius: 24, y: 10)
    }
    
    // MARK: - Topic heading: one style on every Explain screen
    /// "Topic : <title>", the same size and weight wherever it appears. `lines` caps how many lines a long title may take.
    private func topicHeading(lines: Int = 2) -> some View {
        (Text("Topic").foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
            + Text(" : \(activeTopicTitle)").foregroundStyle(.white))
            .scaledFont(size: 34, weight: .regular)
            .lineLimit(lines)
            .minimumScaleFactor(lines == 1 ? 0.6 : 1)
            .multilineTextAlignment(.leading)
    }

    // MARK: - Mode menu (Figma "Explain": Speak, Sketch, Type in a vertical glass pill)
    private var modeSelectionButtons: some View {
        VStack(spacing: 10) {
            modeButton(.speak, icon: "mic.fill", label: "Speak", mode: .voice)
            modeButton(.write, icon: "pencil.and.ruler.fill", label: "Sketch", mode: .pencil)
            modeButton(.type, icon: "keyboard", label: "Type", mode: .keyboard)
        }
        .padding(10)
        // The pill is a layer behind the three glass buttons, not a glass that wraps them, so each button's pointer
        // hover is drawn on the button itself
        .litmusGlassBackdrop(in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.75))
    }

    /// The three ways to explain as one row of round buttons with their names under them (iPhone).
    private var compactModeRow: some View {
        HStack(spacing: 0) {
            compactModeButton(.speak, icon: "mic.fill", label: "Speak", mode: .voice)
            compactModeButton(.write, icon: "pencil.and.ruler.fill", label: "Sketch", mode: .pencil)
            compactModeButton(.type, icon: "keyboard", label: "Type", mode: .keyboard)
        }
        .padding(.vertical, 10)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.75))
    }

    /// One mode for the phone row: does exactly what the iPad mode button does.
    private func compactModeButton(_ target: ExplainInputMode, icon: String, label: String, mode: StudioInputMode) -> some View {
        let chosen = target == (activeInputMode ?? .speak)
        return Button {
            if target == .speak {
                beginListening()
            } else {
                withAnimation(AppMotionSystem.snappy) {
                    activeInputMode = target
                    inputMode = mode
                    isActivelyExplaining = true
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(chosen ? AppTheme.accent : Color.white.opacity(0.12), in: Circle())
                Text(label)
                    .font(.system(size: 14, weight: chosen ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(chosen ? 1 : 0.85))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) mode")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func modeButton(_ target: ExplainInputMode, icon: String, label: String, mode: StudioInputMode) -> some View {
        let chosen = target == (activeInputMode ?? .speak)
        let choose = {
            if target == .speak {
                beginListening()
            } else {
                withAnimation(AppMotionSystem.snappy) {
                    activeInputMode = target
                    inputMode = mode
                    isActivelyExplaining = true
                }
            }
        }
        // A round glass button with its name beside it; the chosen one is the prominent button, the other two plain glass
        return HStack(spacing: 12) {
            Button(action: choose) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .litmusGlassStyle(prominent: chosen)
            .buttonBorderShape(.circle)
            .accessibilityLabel("\(label) mode")

            Text(label)
                .font(.system(size: 17, weight: chosen ? .semibold : .regular))
                .foregroundStyle(.white.opacity(chosen ? 1 : 0.85))
                .frame(width: 60, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: choose)
                .accessibilityHidden(true)
        }
        .padding(.trailing, 8)
    }

    // MARK: - Explain Workstation Screen (Pushed via NavigationStack with Native Apple Back Button)
    @ViewBuilder
    private func explainWorkstationScreen(for mode: ExplainInputMode) -> some View {
        Group {
            switch mode {
            case .speak:
                EmptyView()
            case .write, .type:
                explainCanvasScreen(for: mode)
            }
        }
        // The title is drawn with the page (see explainCanvasScreen) rather than by the bar, which slid it in late and made it jump
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbarVisibility(.visible, for: .navigationBar)
    }

    // MARK: - Dedicated Canvas Screen for Write & Type (Pushed via NavigationStack with Native Back Button)
    private func explainCanvasScreen(for mode: ExplainInputMode) -> some View {
        ZStack {
            // Authentic Ferrari Pit Wall Garage Atmosphere
            Color.black
                .ignoresSafeArea()
            
            GeometryReader { geo in
                Image("race_engineer_workspace_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            
            // Cinematic dark gradient overlay for optimal focus & contrast
            LinearGradient(
                colors: [
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // A Freeform-style canvas: the topic and the engineer's radio box are notes on it, Done and full screen sit in the corner
            freeformCanvas
        }
        // The title sits where the bar's own would, but is part of the page, so it arrives with it and never moves
        .overlay(alignment: .top) {
            Text(mode == .write ? "Sketch" : "Type")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 50)
                .padding(.top, Self.canvasTopInset - 45)
                .accessibilityAddTraits(.isHeader)
                .ignoresSafeArea(.container)
                .allowsHitTesting(false)
        }
        // The bar floats over the page with no band of its own; Done sits in it at the top right
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .hideTopScrollEdgeEffect()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { submitWrittenAnswer() }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
            }
        }
        // Checking happens here, and the screen leaves only for the analysis, never back to the mic page
        .overlay {
            if isEvaluating {
                gradingOverlay.transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: isEvaluating)
        .onChange(of: evaluated) { _, done in
            if done {
                activeInputMode = nil
                // The answer has been handed in: the next time the Write or Type screen opens it is empty
                typedText = ""
                sketchText = ""
                pencilCanvasView.drawing = PKDrawing()
            }
        }
        .onChange(of: typedText) { _, _ in inputNotice = nil }
        // The keyboard is asked for once the screen has finished sliding in: asking while it moves made the keyboard
        // flash up and drop away more than once
        .task {
            guard inputMode == .keyboard else { return }
            try? await Task.sleep(for: .milliseconds(450))
            if !Task.isCancelled, activeInputMode != nil { isFieldFocused = true }
        }
        .onDisappear {
            activeInputMode = nil
            if !evaluated && !isEvaluating {
                isActivelyExplaining = false
            }
        }
    }
    
    // MARK: - Freeform-style canvas (Sketch and Type)

    private var freeformCanvas: some View {
        return ZStack(alignment: .topLeading) {
            // The page itself runs edge to edge, under the navigation bar, the home indicator and the keyboard, so the
            // keyboard's bar floats over the page instead of leaving a band of another colour beneath it
            ZStack(alignment: .topLeading) {
                Color(white: 0.08).opacity(0.94)
                // In Sketch the dots belong to the scrolling, zooming page (drawn inside the canvas); in Type they are fixed
                if inputMode != .pencil { canvasDotGrid }
            }
            .ignoresSafeArea()

            // What is typed or drawn stays above the keyboard, so the last lines are never hidden behind it
            canvasInteractiveContent
                // Type starts right under the bar, and its lines stop short of the radio card on the right
                .padding(.top, inputMode == .keyboard ? Self.canvasTopInset : 0)
                .padding(.trailing, inputMode == .keyboard ? 400 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container)

            // The notes sit clear of the navigation bar by a fixed amount, so nothing moves when the bar settles in during the push
            ZStack(alignment: .topLeading) {
            if inputMode == .pencil {
                // What the handwriting reads as, kept short; it scrolls when it is longer
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recognised handwriting")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(.white.opacity(0.6))
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(sketchText.isEmpty ? "Your handwriting appears here as you write" : sketchText)
                                .scaledFont(size: 17)
                                .foregroundStyle(sketchText.isEmpty ? .white.opacity(0.45) : .white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 72)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 560, alignment: .leading)
                    .litmusGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.leading, 20)
                    // Clear of the floating pencil tool picker along the bottom
                    .padding(.bottom, 120)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // The engineer's radio box is a note on the canvas, which can be dragged anywhere on it; it names the topic and is read aloud
            FreeformNote(alignment: .topTrailing) {
                radioCard(message: currentRadioMessage ?? "“\(stageRadioMessage)”", compact: true)
                    .frame(width: 340)
            }
            }
            .padding(.horizontal, 40)
            .padding(.top, Self.canvasTopInset + 8)
            .padding(.bottom, 44)
            .ignoresSafeArea(.container)
        }
    }

    /// The status bar plus the navigation bar, measured once, so the notes never shift while the push settles.
    private static var canvasTopInset: CGFloat {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        return (window?.safeAreaInsets.top ?? 24) + 50
    }

    /// The faint dot grid of a Freeform board
    private var canvasDotGrid: some View {
        Canvas { context, size in
            let spacing: CGFloat = 28
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(.white.opacity(0.14)))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Canvas Interactive Content (Accepts Pencil Drawing & Keyboard Text)
    private var canvasInteractiveContent: some View {
        ZStack(alignment: .topLeading) {
            // Text Area Layer (Keyboard Mode Only - Write Mode has NO text inside the box)
            if inputMode == .keyboard {
                ZStack(alignment: .topLeading) {
                    if typedText.isEmpty {
                        Text("Type your explanation here...")
                            .scaledFont(size: 20, weight: .regular)
                            .foregroundStyle(Color.white.opacity(0.40))
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $typedText)
                        .focused($isFieldFocused)
                        .scaledFont(size: 20, weight: .regular)
                        .lineSpacing(6)
                        .foregroundStyle(Color.white)
                        .scrollContentBackground(.hidden)
                        .padding(16)
                        .writingToolsBehavior(.disabled)
                }
            }
            
            // Drawing Canvas Layer (Apple Pencil Kit - Pure Blank Canvas in Write Mode)
            if inputMode == .pencil {
                PencilDrawingCanvasView(canvasView: $pencilCanvasView, isPencilMode: true) {
                    isPencilCanvasEmpty = pencilCanvasView.drawing.bounds.isEmpty
                    inputNotice = nil
                    scheduleSketchRecognition()
                }
                .allowsHitTesting(true)
                .padding(10)
            }
        }
    }

    
    // MARK: - Left Card: Race Engineer (Used for Passed / Failed States)
    private var raceEngineerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Race Engineer")
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(Color.white)
                
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            
            // Character with Video
            ZStack(alignment: .bottom) {
                EngineerAvatarView(pose: activePose, isSpeaking: voice.isSpeaking, layout: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 380)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            Spacer(minLength: 4)
        }
        .frame(height: 480)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 20, y: 10)
    }
    
    // MARK: - Right Top Radio Card (Figma 1057:1533, 1057:6056)
    private func radioCard(message: String, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: name and "Radio"
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(driverName.isEmpty ? "Aarushi" : driverName)
                        .scaledFont(size: 23, weight: .bold)
                        .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
                    
                    Text("Radio")
                        .scaledFont(size: 18, weight: .bold)
                        .foregroundStyle(Color.white)
                }
                Spacer()
            }
            
            // Row 2: Live Animated Equalizer Waveform Bars across the card (Figma 1057:1533, 1057:6056); Sketch and Type show them too
            RadioEqualizerWaveformView(isRecording: isRecording || isActivelyExplaining, isActive: isRecording || voice.isSpeaking)
            
            // Row 3: Radio Message Quote
            // The whole line is laid out from the start and the words appear in place as they are spoken, so the card never resizes
            let parts = voice.displayParts(for: message)
            let line = (Text(parts.shown).foregroundStyle(Color.white) + Text(parts.hidden).foregroundStyle(Color.clear))
                .scaledFont(size: 16, weight: .medium)
            // Up to about four lines sit in the card as they are; a longer line keeps the card the same size and scrolls inside it
            ViewThatFits(in: .vertical) {
                line.fixedSize(horizontal: false, vertical: true)
                ScrollView(.vertical, showsIndicators: false) {
                    line.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 86, alignment: .top)
        }
        .padding(16)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 16, y: 8)
    }
    
    // MARK: - Helper Design Components (Figma 1264:2970 & 1264:3088)
    private var resolvedConcepts: [(title: String, isMastered: Bool)] {
        if let report = engineReport {
            return report.right.map { (FeedbackPhrasing.idea($0), true) }
                + (report.corrections + report.missing + report.vague + report.conflicts).map { (FeedbackPhrasing.idea($0), false) }
        }
        // No engine report: one row for the topic itself. (This used to name fixed concepts such as "Newton's First Law"
        // whatever the topic was.)
        guard !activeTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [(activeTopicTitle, clarityScore >= 80 || latestEvaluationResult?.passedParakh == true)]
    }
    
    private var debriefDiagnosticRows: (passed: String, vague: String, missing: String) {
        if let report = engineReport {
            // From the Rule Engine's report, the compiled concept and the student's own words (see DebriefComposer)
            let rows = DebriefComposer.rows(report: report, outcome: feedback.decision?.outcome,
                                            concept: feedback.activeConcept, answers: feedback.attemptAnswers)
            return (rows.right, rows.vague, rows.missing)
        }
        // The engine produced no report for this answer
        let debrief = latestEvaluationResult
        let gap = (debrief?.feynmanGap ?? "").replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
        let next = (debrief?.nextGuidingQuestion ?? "").replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
        return ("", next, gap)
    }
    
    private var hasMissedConcepts: Bool {
        resolvedConcepts.contains(where: { !$0.isMastered })
    }
    
    private var masteredCount: Int {
        resolvedConcepts.filter({ $0.isMastered }).count
    }
    
    // MARK: - Debrief (Figma "Good try": missing, vague and right, then Try again / Get Hints)
    // Proportions follow the design: the panel is 63% of the width and 72% of the height, the radio box
    // sits to its right and the engineer bottom-right.
    private var goodTryAnalysisView: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            // Portrait: the radio card keeps its top-right place and the review card goes below it, full width
            let portrait = height > width
            let panelTop = portrait ? 380.0 : max(height * 0.17, 150)
            ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        Image("engineer_confused")
                            .resizable()
                            .scaledToFit()
                            .frame(height: height * (portrait ? 0.2 : 0.52))
                            .padding(.trailing, width * 0.02)
                            .accessibilityHidden(true)
                    }
                }

                // Same place and size as the Topic heading on the Explain stage
                topicHeading(lines: 1)
                    .frame(maxWidth: width * 0.62, alignment: .leading)
                    .padding(.leading, 28)
                    // 70 like the listening screen, minus the 28 its heading block is lifted by, so the heading sits on the same line
                    .padding(.top, 42)

                // The card takes all the height there is; the buttons sit under it, outside the card
                VStack(spacing: 20) {
                    debriefPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    debriefButtons
                }
                .frame(width: portrait ? width - 56 : width * 0.63, height: height - panelTop - 36)
                .padding(.leading, 28)
                .padding(.top, panelTop)

                // The radio card is where the Explain stage has it: top right, 330 wide
                radioCard(message: debriefRadioMessage)
                    .frame(width: 330)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 28)
                    .padding(.top, 70)
            }
            .onAppear {
                debriefShown = false
                withAnimation(.smooth(duration: 0.5)) { debriefShown = true }
            }
            .onDisappear { debriefShown = false }
        }
    }

    /// Try again and Get Hints (or Session Summary), below the card like the session summary's buttons, so the card's
    /// whole height is for the text.
    private var debriefButtons: some View {
        HStack(spacing: 28) {
                Spacer()
                Button { restartAttempt() } label: {
                    Text("Try again")
                        .scaledFont(size: 18, weight: .medium)
                        .foregroundStyle(.white)
                        .frame(width: 180, height: 54)
                }
                // One prominent button: Try again is the main action only while the attempt has not passed
                .litmusGlassStyle(prominent: !attemptPassed)
                .buttonBorderShape(.capsule)
                if attemptPassed {
                    Button {
                        withAnimation(.smooth(duration: 0.45)) { showSummary = true }
                    } label: {
                        Text("Session Summary")
                            .scaledFont(size: 18, weight: .medium)
                            .foregroundStyle(.white)
                            .frame(width: 200, height: 54)
                    }
                    .litmusProminentGlassButton()
                    .buttonBorderShape(.capsule)
                    .tint(AppTheme.accent)
                } else {
                    Button { getHints() } label: {
                        HStack(spacing: 8) {
                            Text("Get Hints")
                                .scaledFont(size: 18, weight: .medium)
                            miniCoin
                            Text("3")
                                .scaledFont(size: 18, weight: .bold)
                                .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 190, height: 54)
                    }
                    .litmusGlassButton()
                    .buttonBorderShape(.capsule)
                }
                Spacer()
            }
    }

    private var debriefPanel: some View {
        let rows = debriefDiagnosticRows
        return VStack(alignment: .leading, spacing: 0) {
            // The rows scroll when an answer's own words make them taller than the panel
            ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                debriefRow(order: 0, icon: "xmark.square", color: Color(red: 233/255, green: 30/255, blue: 30/255), label: "What was missing: ",
                           text: rows.missing.isEmpty ? (attemptPassed ? "Nothing missing: you covered the main ideas." : "I could not check this answer against the topic. Try again in your own words.") : rows.missing)
                debriefRow(order: 1, icon: "exclamationmark.triangle.fill", color: Color(red: 255/255, green: 197/255, blue: 89/255), label: "What was vague: ",
                           text: rows.vague.isEmpty ? (attemptPassed ? "Nothing vague: your explanation was clear." : "Add a little more detail, step by step.") : rows.vague)
                debriefRow(order: 2, icon: "checkmark.square.fill", color: Color(red: 58/255, green: 221/255, blue: 1/255), label: "What was right: ",
                           text: rows.passed.isEmpty ? "None of the key ideas for \(activeTopicTitle) was clearly stated yet." : rows.passed)
            }
            .animation(.smooth(duration: 0.4), value: rows.missing + rows.vague + rows.passed)
            }
            .defaultScrollAnchor(.top)
            .scrollBounceBehavior(.basedOnSize)
            // HIG (Scroll views): the system's own cues. The scroll bar is shown and flashes when the review appears, and
            .scrollIndicators(.visible)
            .scrollIndicatorsFlash(onAppear: true)

        }
        .padding(.horizontal, 40)
        .padding(.top, 44)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.75))
        .alert("Not Enough Coins", isPresented: $showNotEnoughCoins) {
            Button("OK") {}
        } message: {
            Text("Hints cost \(StudyProgressManager.hintCost) coins. Finish a focus session to earn more.")
        }
    }

    private func debriefRow(order: Int, icon: String, color: Color, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32)
            Text(label + text)
                .scaledFont(size: 26, weight: .regular)
                .foregroundStyle(.white)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(debriefShown ? 1 : 0)
        .offset(y: debriefShown ? 0 : 14)
        .animation(.smooth(duration: 0.5).delay(0.15 + Double(order) * 0.14), value: debriefShown)
        .accessibilityElement(children: .combine)
    }

    private var miniCoin: some View {
        ZStack {
            Circle().fill(Color(red: 255/255, green: 197/255, blue: 89/255)).frame(width: 24, height: 24)
            Text("$").scaledFont(size: 14, weight: .bold).foregroundStyle(Color(red: 150/255, green: 100/255, blue: 10/255))
        }
    }

    /// Hints cost 3 coins, charged once per attempt.
    private func getHints() {
        if !hintsPaid {
            guard spendCoins(StudyProgressManager.hintCost) else { showNotEnoughCoins = true; return }
            hintsPaid = true
        }
        withAnimation(AppMotionSystem.fluidSpring) { showHintsCarousel = true }
    }

    // MARK: - Dynamic Debrief Feedback Rows for Well Done / Mastery
    private var wellDoneFeedbackRows: [(isPassed: Bool, label: String, detail: String)] {
        if let report = engineReport {
            return report.right.map { (true, "What you got right", $0) }
                + report.corrections.map { (false, "Fix this", $0) }
                + report.missing.map { (false, "What is missing", $0) }
                + report.vague.map { (false, "Be more specific", $0) }
                + report.conflicts.map { (false, "Check this", $0) }
        }
        // No engine report: only what is known, the topic itself and whether it was cleared (these rows used to carry
        // invented detail for a few fixed topics such as motion, money and light)
        return resolvedConcepts.map { concept in
            concept.isMastered ? (true, "What you got right", concept.title) : (false, "Needs review", concept.title)
        }
    }

    // MARK: - Session summary (Figma: times, radio line, coins, per-concept status, Revise / Done)
    private var wellDoneSummaryView: some View {
        GeometryReader { geo in
            summaryContent(portrait: geo.size.height > geo.size.width)
        }
    }

    private func summaryContent(portrait: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The heading, then the status card on the left (the same big card as the review screen) and, on the right,
            // the radio line, the coins and the two time tiles stacked beneath them
            topicHeading(lines: 1)
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in width * 0.62 }
                .padding(.horizontal, 28)
                .padding(.top, 42)

            if portrait {
                // Portrait: the radio line and the coins and times sit side by side above the status card, which takes the rest
                HStack(alignment: .top, spacing: 20) {
                    // The times and the coins on the left, the radio card on the right, tops level
                    VStack(alignment: .leading, spacing: 10) {
                        timeTile(seconds: explainSeconds, label: "EXPLAIN TIME")
                        timeTile(seconds: studySeconds, label: "FOCUS TIME")
                        (Text("Coins Gained: ").foregroundStyle(.white) + Text("+\(coinsEarned)").foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255)))
                            .scaledFont(size: 24, weight: .regular)
                            .frame(width: 257)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    radioCard(message: "“\(summaryRadioLine)”")
                        .frame(width: 330)
                        .fixedSize(horizontal: false, vertical: true)
                }

                .padding(.horizontal, 28)
                .padding(.top, 20)
                perConceptPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
            } else {
            HStack(alignment: .top, spacing: 20) {
                    perConceptPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .trailing, spacing: 14) {
                        radioCard(message: "“\(summaryRadioLine)”")
                            .frame(width: 330)
                            // Full height: this column is squeezed by the row, which used to cut the line off
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 2) {
                            (Text("Coins Gained: ").foregroundStyle(.white) + Text("+\(coinsEarned)").foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255)))
                                .scaledFont(size: 26, weight: .regular)
                            Text(coinsEarned >= 2 ? "Half-way +1, finished +1" : coinsEarned == 1 ? "Half-way +1" : "Finish a focus session to earn coins")
                                .scaledFont(size: 15)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(width: 330)
                        // The same size as before (257 x 110), centred under the coins
                        timeTile(seconds: explainSeconds, label: "EXPLAIN TIME").frame(width: 330)
                        timeTile(seconds: studySeconds, label: "FOCUS TIME").frame(width: 330)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
    
            }

            Spacer(minLength: 20)

            // One prominent button (Done, the usual way out); Revise is the quieter second choice
            HStack(spacing: 20) {
                Button { showAnswerSheet = true } label: {
                    Text("Your Answer")
                        .scaledFont(size: 18, weight: .medium)
                        .foregroundStyle(.white)
                        .frame(width: 170, height: 52)
                }
                .litmusGlassButton()
                .buttonBorderShape(.capsule)
                .accessibilityHint("Shows the text of your answer that was graded")
                Button {
                    if let onNavigateToRevise { onNavigateToRevise() } else { getHints() }
                } label: {
                    Text("Revise")
                        .scaledFont(size: 18, weight: .medium)
                        .foregroundStyle(.white)
                        .frame(width: 170, height: 52)
                }
                .litmusGlassButton()
                .buttonBorderShape(.capsule)
                Button { onDone() } label: {
                    Text("Done")
                        .scaledFont(size: 18, weight: .medium)
                        .foregroundStyle(.white)
                        .frame(width: 170, height: 52)
                }
                .litmusProminentGlassButton()
                .buttonBorderShape(.capsule)
                .tint(AppTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        // The running streak, in the bottom-right corner (above the buttons when the page is narrow, so they never touch)
        .overlay(alignment: .bottomTrailing) {
            summaryStreakBadge
                .padding(.trailing, 28)
                .padding(.bottom, portrait ? 112 : 40)
        }
    }

    /// "5-day streak" with a flame, from the days studied in a row up to today
    @ViewBuilder
    private var summaryStreakBadge: some View {
        let days = StudyProgressManager.shared.streakDays
        if days > 0 {
            HStack(spacing: 10) {
                StreakFlame(letter: "", size: 34)
                Text(days == 1 ? "1-day streak" : "\(days)-day streak")
                    .scaledFont(size: 22, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .litmusGlass(in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(days) day streak")
        }
    }

    private var summaryRadioLine: String {
        let rows = resolvedConcepts
        guard !rows.isEmpty else { return feedback.engineTopicActive ? feedback.radioPrompt : "Well done!" }
        let clear = rows.filter(\.isMastered).count
        if let review = rows.first(where: { !$0.isMastered }) {
            return "\(clear) of \(rows.count) concepts clear. Revisit \(review.title)."
        }
        return "All \(rows.count) concepts clear. Well done!"
    }

    private func timeTile(seconds: Int, label: String, width: CGFloat = 257, height: CGFloat = 110) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 32, weight: .regular).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .scaledFont(size: 22, weight: .regular)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: width, height: height)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The text the app graded, in a standard sheet: a navigation title, a Done button, a drag indicator, and a
    /// medium detent that opens to large for a long answer. The text can be selected and copied.
    private var answerSheet: some View {
        let answers = feedback.attemptAnswers.isEmpty
            ? [transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
            : feedback.attemptAnswers
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if answers.isEmpty {
                        Text("There is no answer text to show.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(answers.enumerated()), id: \.offset) { index, answer in
                        VStack(alignment: .leading, spacing: 8) {
                            if answers.count > 1 {
                                Text(index == 0 ? "Your answer" : "Follow-up \(index)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(answer)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Your Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showAnswerSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var perConceptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Per-Concept Status")
                .scaledFont(size: 20, weight: .semibold)
                .foregroundStyle(.white)
            // Every idea is listed: the list scrolls inside the panel instead of being cut at four rows
            ScrollView {
              VStack(alignment: .leading, spacing: 12) {
              ForEach(Array(resolvedConcepts.enumerated()), id: \.offset) { _, concept in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Image(systemName: concept.isMastered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(concept.isMastered ? Color(red: 58/255, green: 221/255, blue: 1/255) : Color(red: 255/255, green: 197/255, blue: 89/255))
                        .frame(width: 32)
                    // Whole text, never cut off with "…": the list scrolls instead
                    Text(concept.title)
                        .scaledFont(size: 22, weight: .regular)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // The green tick already says it was covered; only a missing idea gets a word
                    if !concept.isMastered {
                        Text("Needs review")
                            .scaledFont(size: 18, weight: .medium)
                            .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                            .fixedSize()
                    }
                }
                // One element for VoiceOver: the idea and whether it was covered, not a loose symbol and two texts
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(concept.title), \(concept.isMastered ? "covered" : "needs review")")
              }
              }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.visible)
            .scrollIndicatorsFlash(onAppear: true)
        }
        // Compact: the heading and the first row sit close together so more ideas fit before the list scrolls
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.75))
    }

    // MARK: - Modal: USE REWARDS (Figma 802:3825)
    private var useRewardsModal: some View {
        VStack(spacing: 20) {
            Text("USE REWARDS")
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(Color.white)
                .padding(.top, 24)
            
            HStack(spacing: 6) {
                Text("Spend 3")
                    .scaledFont(size: 16, weight: .regular)
                    .foregroundStyle(Color.white.opacity(0.85))
                
                Text("🪙")
                    .scaledFont(size: 16)
                
                Text("to reveal answers")
                    .scaledFont(size: 16, weight: .regular)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            
            VStack(spacing: 12) {
                // "Retry without Answers" (Official Apple Bordered)
                Button("Retry without Answers") {
                    withAnimation {
                        showRewardActionSheet = false
                        clarityScore = 50
                        transcriptionText = ""
                        isActivelyExplaining = true
                    }
                }
                .litmusGlassButton()
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity)
                
                // "Accept" (Official Apple Bordered Prominent)
                Button("Accept") {
                    showRewardActionSheet = false
                    preparingCards = true
                    Task {
                        // The chapter's own passage is the context, so the cards hold textbook facts, not guesses
                        let passage = engineConcept?.cardText ?? ""
                        // ...and the ideas the engine found missing or wrong, so the cards target the gaps
                        let report = feedback.decision?.report
                        let gaps = (report?.missing ?? []) + (report?.corrections ?? [])
                        missedCards = await OnDeviceFlashcardGenerator.shared.generateFlashcards(
                            topic: activeTopicTitle, contextText: passage, subject: topic.subject, focus: gaps)
                        preparingCards = false
                        withAnimation { showWhatYouMissedView = true }
                    }
                }
                .litmusProminentGlassButton()
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 320)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 24, y: 12)
    }
    
    // MARK: - Recording & Real NaturalLanguage Evaluation Pipeline
    /// Stops the recorder if it is running. Used by every exit path: it can never start a recording,
    /// which is what crashed when the listening screen closed after End.
    private func stopRecordingIfNeeded() {
        if speechRecorder.isRecording { speechRecorder.stopRecording() }
    }

    /// Starts or stops the recorder. `isRecording` follows the recorder (see `onChange` below), so the
    /// screen never disagrees with the microphone, e.g. when speech permission is refused.
    private func toggleRecording() {
        if speechRecorder.isRecording {
            speechRecorder.stopRecording()
        } else {
            speechRecorder.contextualStrings = feedback.speechHints(for: topic)
            transcriptionText = ""
            speechRecorder.toggleRecording { text in
                transcriptionText = text
            }
        }
    }
    
    /// Recognises the handwriting a moment after the last stroke, so the Sketch screen shows it.
    private func scheduleSketchRecognition() {
        sketchRecognition?.cancel()
        sketchRecognition = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            sketchText = await PencilTextExtractor.extractText(from: pencilCanvasView)
        }
    }

    /// Sends the spoken answer to the v4.0 engine through the view model; the UI reacts to its state.
    private func evaluateTranscription() {
        explainSeconds = max(0, Int(Date().timeIntervalSince(explainStartedAt)))
        isEvaluating = true
        isActivelyExplaining = true
        Task { @MainActor in
            stopRecordingIfNeeded()
            // The last words arrive a moment after the microphone stops
            await speechRecorder.waitUntilFinalized()
            let text = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            transcriptionText = text
            feedback.evaluate(text, topic: topic, confidence: speechRecorder.finalConfidence)
            // A re-prompt (empty or too-short answer) never reaches grading, so nothing else would clear this.
            isEvaluating = feedback.isEvaluating
            if let state = engineState, activeInputMode == nil {
                switch state {
                case .reprompt, .offTopic, .blocked:
                    withAnimation(AppMotionSystem.fluidSpring) { isActivelyExplaining = false }
                default: break
                }
            }
        }
    }

    /// Done on the Write and Type screens. An answer that is not enough is answered in the radio box, on the
    /// same screen; an answer that can be checked is graded here and the screen leaves only for the analysis.
    private func submitWrittenAnswer() {
        inputNotice = nil
        isActivelyExplaining = true
        sketchRecognition?.cancel()
        Task { @MainActor in
            let answer: String
            if inputMode == .pencil {
                let recognised = await PencilTextExtractor.extractText(from: pencilCanvasView)
                if !recognised.isEmpty { sketchText = recognised }
                answer = sketchText
                if pencilCanvasView.drawing.bounds.isEmpty {
                    inputNotice = "I can't see an answer yet. Write it with your Pencil, then tap Done."
                    return
                }
                if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputNotice = "I couldn't read your handwriting. Try writing a little larger and clearer, or use Type."
                    return
                }
            } else {
                answer = typedText
            }
            let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            // Topics the engine does not grade have no re-prompt of their own
            if !feedback.isEngineTopic(topic), text.split(whereSeparator: \.isWhitespace).count < 3 {
                inputNotice = text.isEmpty ? "I can't see an answer yet. Type a few sentences, then tap Done." : "Can you say a bit more? Add a few more sentences, then tap Done."
                return
            }
            explainSeconds = max(0, Int(Date().timeIntervalSince(explainStartedAt)))
            transcriptionText = text
            feedback.evaluate(text, topic: topic, confidence: nil)
            if feedback.engineTopicActive, let notice = notice(for: feedback.machine.state) {
                inputNotice = notice
                isEvaluating = false
                return
            }
            isEvaluating = feedback.isEvaluating
            if let state = engineState, activeInputMode == nil {
                switch state {
                case .reprompt, .offTopic, .blocked:
                    withAnimation(AppMotionSystem.fluidSpring) { isActivelyExplaining = false }
                default: break
                }
            }
        }
    }

    /// The radio box's line when the engine asks for a better answer; nil when the answer is being graded.
    private func notice(for state: AttemptState) -> String? {
        let writing = inputMode == .pencil
        switch state {
        case .reprompt(let reason, _):
            switch reason {
            case .empty:
                return writing ? "I can't see an answer yet. Write it with your Pencil, then tap Done." : "I can't see an answer yet. Type a few sentences, then tap Done."
            case .tooShort:
                return "Can you say a bit more? Add a few more sentences, then tap Done."
            case .unintelligible:
                return writing ? "I couldn't read that. Try writing a little larger and clearer." : "I couldn't make that out. Check it and try again."
            case .dontKnow:
                return feedback.radioPrompt.replacingOccurrences(of: " You can also type your answer.", with: "")
            }
        case .offTopic, .blocked:
            return feedback.radioPrompt
        default:
            return nil
        }
    }

    // MARK: - Audio Speech Replay (Figma 1057:1560 Play Button)
    private func playTranscriptionAudio() {
        let textToSpeak = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Radio check. Please explain \(activeTopicTitle)."
            : transcriptionText
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        } else {
            let utterance = AVSpeechUtterance(string: textToSpeak)
            VoiceEngineService.configure(utterance)
            speechSynthesizer.speak(utterance)
        }
    }
}

// MARK: - PencilKit Representable for Interactive Apple Pencil Drawing (Figma 1057:1560)
/// The faint dot grid of a Freeform board, drawn for the part of the page on screen. It lives inside the canvas's scroll view and
/// is redrawn with the scroll position and zoom, so the dots move and scale with the drawing exactly as they do in Freeform.
final class DotGridView: UIView {
    var offset: CGPoint = .zero
    var zoom: CGFloat = 1
    private let spacing: CGFloat = 28

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let step = spacing * zoom
        guard step > 6 else { return }                       // zoomed far out: the dots would be a haze
        let radius = max(0.8, 1.2 * zoom)
        context.setFillColor(UIColor(white: 1, alpha: 0.16).cgColor)
        // Page position of the left and top edges of what is on screen, then the first dot at or after it
        let startX = (floor(offset.x / zoom / spacing) * spacing) * zoom - offset.x
        let startY = (floor(offset.y / zoom / spacing) * spacing) * zoom - offset.y
        var y = startY
        while y < bounds.height + step {
            var x = startX
            while x < bounds.width + step {
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                x += step
            }
            y += step
        }
    }
}

// MARK: - PencilKit Representable for Interactive Apple Pencil Drawing (Figma 1057:1560)
struct PencilDrawingCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var isPencilMode: Bool = true
    var onDrawingChanged: (() -> Void)? = nil

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .white, width: 3)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        // The tool picker's "Draw with Finger" switch decides: off, only the Pencil draws and a finger scrolls (as in Freeform)
        canvasView.drawingPolicy = .default
        canvasView.delegate = context.coordinator
        // PKCanvasView is a scroll view: it scrolls across the page and pinch zooms, like a Freeform board
        canvasView.isScrollEnabled = true
        canvasView.alwaysBounceVertical = true
        canvasView.alwaysBounceHorizontal = true
        canvasView.showsVerticalScrollIndicator = false
        canvasView.showsHorizontalScrollIndicator = false
        // No soft blur under the navigation bar: the page runs right up to the top
        if #available(iOS 26.0, *) { canvasView.topEdgeEffect.isHidden = true; canvasView.bottomEdgeEffect.isHidden = true }
        canvasView.minimumZoomScale = 0.4
        canvasView.maximumZoomScale = 4
        canvasView.bouncesZoom = true
        canvasView.decelerationRate = .normal

        // The dots, behind the drawing, inside the scroll view
        let grid = DotGridView()
        canvasView.insertSubview(grid, at: 0)
        context.coordinator.grid = grid

        if isPencilMode {
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
            context.coordinator.toolPicker.addObserver(canvasView)
            context.coordinator.pickerShown = true
            canvasView.becomeFirstResponder()
        }
        
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Everything here changes UIKit geometry or the first responder. Done during SwiftUI's own update pass that
        // feeds back into SwiftUI (safe area, size) and makes an attribute-graph cycle that freezes the app on the
        // 13-inch iPad, so it runs right after the update instead, and only when something actually changed.
        let coordinator = context.coordinator
        let pencil = isPencilMode
        DispatchQueue.main.async { [weak uiView, weak coordinator] in
            guard let uiView, let coordinator else { return }
            let bounds = uiView.bounds.size
            if bounds.width > 0 {
                let page = CGSize(width: max(bounds.width * 6, 6000), height: max(bounds.height * 6, 6000))
                if uiView.contentSize.width < page.width || uiView.contentSize.height < page.height {
                    uiView.contentSize = page
                }
                if !coordinator.hasCentred {
                    coordinator.hasCentred = true
                    uiView.contentOffset = CGPoint(x: (uiView.contentSize.width - bounds.width) / 2, y: (uiView.contentSize.height - bounds.height) / 2)
                }
                coordinator.syncGrid(uiView)
            }
            if pencil {
                if !coordinator.pickerShown {
                    coordinator.pickerShown = true
                    coordinator.toolPicker.setVisible(true, forFirstResponder: uiView)
                    coordinator.toolPicker.addObserver(uiView)
                }
                if !uiView.isFirstResponder { uiView.becomeFirstResponder() }
            } else {
                if coordinator.pickerShown {
                    coordinator.pickerShown = false
                    coordinator.toolPicker.setVisible(false, forFirstResponder: uiView)
                }
                if uiView.isFirstResponder { uiView.resignFirstResponder() }
            }
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: uiView)
        coordinator.toolPicker.removeObserver(uiView)
        if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilDrawingCanvasView
        let toolPicker = PKToolPicker()
        var grid: DotGridView?
        var hasCentred = false
        var pickerShown = false

        init(_ parent: PencilDrawingCanvasView) {
            self.parent = parent
        }

        /// Keeps the grid over the visible part of the page and tells it where the page is and how far it is zoomed.
        func syncGrid(_ scrollView: UIScrollView) {
            guard let grid else { return }
            grid.frame = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
            grid.offset = scrollView.contentOffset
            grid.zoom = scrollView.zoomScale
            grid.setNeedsDisplay()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { syncGrid(scrollView) }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { syncGrid(scrollView) }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onDrawingChanged?()
        }
    }
}

// MARK: - Radio Equalizer Waveform View (Live 60fps Animation - Figma 1057:1533, 1057:6056)
struct RadioEqualizerWaveformView: View {
    var isRecording: Bool
    /// The bars move only while someone is speaking or recording; otherwise the timeline is paused and costs nothing.
    var isActive: Bool = true
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { i in
                    let speed = isRecording ? 6.5 : 2.2
                    let base = isRecording ? 16.0 : 8.0
                    let amp = isRecording ? 12.0 : 4.0
                    let w1 = sin(t * speed + Double(i) * 0.85)
                    let w2 = cos(t * (speed * 0.7) + Double(i) * 1.35)
                    let h = max(4.0, min(34.0, base + (w1 + w2) * 0.5 * amp))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 233/255, green: 30/255, blue: 30/255).opacity(isRecording ? 0.95 : 0.60))
                        .frame(maxWidth: .infinity)
                        .frame(height: CGFloat(h))
                }
            }
            .frame(height: 36, alignment: .center)
        }
    }
}

// MARK: - Pulsing Mic Ring (Figma 1057:6056)
struct PulsingMicRing: View {
    var isRecording: Bool
    @State private var isPulsing: Bool = false
    
    var body: some View {
        Circle()
            .stroke(Color(red: 233/255, green: 30/255, blue: 30/255).opacity(isRecording ? 0.50 : 0.0), lineWidth: 3)
            .scaleEffect(isPulsing ? 1.35 : 1.0)
            .opacity(isPulsing ? 0.0 : 0.8)
            // The repeating pulse runs only while recording
            .animation(isPulsing ? .easeOut(duration: 1.2).repeatForever(autoreverses: false) : .default, value: isPulsing)
            .onChange(of: isRecording, initial: true) { _, recording in isPulsing = recording }
    }
}


/// What the debrief screens read from an attempt, filled from the engine's report.
struct StudioDebrief {
    var score: Int
    var passedIB: Bool
    var passedParakh: Bool
    var feynmanGap: String
    var nextGuidingQuestion: String
}

/// The coin balance, next to Settings in the corner of the Explain tab.
/// The coin counter over the Explain screen: the shared badge, as tall as the settings button next to it (44 pt, the minimum touch target).
struct CoinCounter: View {
    let count: Int
    var body: some View {
        CoinBadge(count: count, inToolbar: false, height: 48)
    }
}


/// A note on the Freeform-style canvas: starts in its corner and can be dragged anywhere.
private struct FreeformNote<Content: View>: View {
    let alignment: Alignment
    @ViewBuilder let content: Content
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        content
            .padding(20)
            .offset(x: offset.width + drag.width, y: offset.height + drag.height)
            .gesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in offset.width += value.translation.width; offset.height += value.translation.height }
            )
            // Beside the corner controls rather than under them
            .padding(.top, alignment == .topTrailing ? 84 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}


private extension View {
    /// No soft blur under the navigation bar (iOS 26 and later).
    @ViewBuilder func hideTopScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) { self.scrollEdgeEffectHidden(true, for: .top) } else { self }
    }
}
