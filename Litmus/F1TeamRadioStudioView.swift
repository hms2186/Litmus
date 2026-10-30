//
//  F1TeamRadioStudioView.swift
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

struct F1TeamRadioStudioView: View {
    var customTopicText: String
    @ObservedObject var feedback: FeedbackViewModel
    var topic: NCERTTopic
    @Binding var driverName: String
    @Binding var studentCountry: StudentCountry
    var driverNumber: Int
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
    
    // State
    @StateObject private var speechRecorder = LiveSpeechRecorder()
    @State private var clarityScore: Int = 50 // 50: Initial/Recording, <80: Good Try, >=80: Well Done
    @State private var hasEvaluated: Bool = false
    @State private var isEvaluating: Bool = false
    @State private var inputMode: StudioInputMode = .voice
    @State private var activeInputMode: ExplainInputMode? = nil
    @State private var showRewardActionSheet: Bool = false
    @State private var showWhatYouMissedView: Bool = false
    @State private var showHintsCarousel: Bool = false
    @State private var hintsDismissed: Bool = false
    @State private var showSummary: Bool = false
    @State private var hintsPaid: Bool = false
    @State private var typedText: String = ""
    @State private var isListeningStage = false
    @State private var debriefShown = false
    @StateObject private var voice = F1EngineerVoice()
    @State private var sketchText: String = ""
    @State private var sketchRecognition: Task<Void, Never>?
    @State private var showNotEnoughCoins: Bool = false
    /// The radio box's reply on the Write and Type screens when the answer is not enough to check yet.
    @State private var inputNotice: String?
    @State private var canvasFullscreen = false
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
        driverNumber: Int = 44,
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
        self.driverNumber = driverNumber
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
    
    /// Avatar loop for the current attempt. Engine topics follow the attempt machine and its Rule
    /// Engine outcome; other topics keep the score-based loops.
    private var activeVideoName: String {
        if feedback.engineTopicActive {
            switch feedback.machine.state {
            case .grading, .awaitingFollowUp, .reprompt:
                return "listening1.1"            // needs clarification / waiting for the student
            case .correcting:
                return "wrong-1"                 // needs correction
            case .finished(let outcome):
                return outcome == .mastered || outcome == .likelyMastered ? "proceedtonxt-1" : "wrong-1"
            case .ready, .offTopic, .blocked:
                break
            }
        } else if hasEvaluated {
            return clarityScore >= 80 ? "proceedtonxt-1" : "wrong-1"
        }
        return isRecording || isActivelyExplaining ? "listening1.1" : "idle-1"
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
    private var topicHintCards: [F1HintCardItem] {
        let cards = F1FlashcardLibrary.cards(for: topic).prefix(3)
        return cards.enumerated().map { index, card in
            F1HintCardItem(id: index, title: card.title, bodyText: card.body, indexLabel: "\(index + 1)/\(cards.count)", keywords: card.keywords)
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
            onExplanationResult?(false, (report.corrections.first ?? report.missing.first).map(F1FeedbackPhrasing.shortNote))
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
            onExplanationResult?(passed, passed ? nil : (report.corrections.first ?? report.missing.first).map(F1FeedbackPhrasing.shortNote))
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
                    .f1Font(size: 15)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private var gradingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Checking your explanation…")
                .f1Font(size: 20, weight: .semibold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func applyLegacyResult() {
        guard !feedback.engineTopicActive, let result = feedback.result else { return }
        let score = result.tier == .right ? 90 : 30
        latestEvaluationResult = StudioDebrief(score: score, passedIB: result.tier == .right, passedParakh: result.tier == .right,
                                               feynmanGap: feedback.report.missing, nextGuidingQuestion: feedback.report.vague)
        isEvaluating = false
        hasEvaluated = true
        isActivelyExplaining = true
        withAnimation(AppMotionSystem.fluidSpring) { clarityScore = score }
        onEvaluationComplete?(score, activeTopicTitle)
        onExplanationResult?(score >= 80, score >= 80 ? nil : (feedback.report.missing.isEmpty ? nil : feedback.report.missing))
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
            
            if hintsVisible {
                F1HintsCarouselView(
                    hintCards: F1HintCardBuilder.cards(state: feedback.machine.state, concept: engineConcept, decision: feedback.decision, fallback: topicHintCards, keywords: F1FlashcardLibrary.keywords(for: topic)),
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
            } else if evaluated && showSummary {
                // Mastered Session Summary (Figma 1264:3088) & Partial Mastery (Figma 1264:2793)
                wellDoneSummaryView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 1.02))
                    ))
            } else if evaluated {
                // Good Try Debrief (Figma 1264:2970)
                goodTryAnalysisView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 1.02))
                    ))
            } else {
                // Main Active Stage (Figma 1057:1533 / 1057:6056)
                explainRevampMainStage
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 1.02))
                    ))
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
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
        .animation(.smooth(duration: 0.45), value: evaluated)
        .animation(.smooth(duration: 0.45), value: showSummary)
        .animation(.smooth(duration: 0.45), value: hintsVisible)
        .animation(.smooth(duration: 0.35), value: isEvaluating)
        .sheet(isPresented: $showWhatYouMissedView) {
            NavigationStack {
                ZStack {
                    Color(red: 14/255, green: 14/255, blue: 16/255)
                        .ignoresSafeArea()
                    
                    F1FlashcardsReviseView(
                        cognitiveTokens: .constant(7),
                        initialMode: .whatYouMissed(
                            OnDeviceFlashcardGenerator.shared.generateFlashcards(topic: activeTopicTitle, contextText: transcriptionText)
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
            }
            .preferredColorScheme(.dark)
        }
        .task {
            // The radio clicks in as the screen opens, then the engineer speaks
            if isTabActive { F1StartLightsSound.shared.radioNotification() }
            try? await Task.sleep(for: .seconds(0.7))
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
        .toolbarVisibility(evaluated || isListeningStage ? .hidden : .visible, for: .tabBar)
        .f1Feedback(.impact(weight: .heavy), trigger: isRecording)
        .f1Feedback(.impact(weight: .medium), trigger: activeInputMode)
        .navigationDestination(item: $activeInputMode) { mode in
            explainWorkstationScreen(for: mode)
        }
        .onChange(of: feedback.machine.state) { _, state in applyEngineState(state) }
        .onChange(of: currentRadioMessage) { _, _ in speakRadioLine() }
        .onChange(of: activeInputMode) { _, mode in if mode != nil { explainStartedAt = Date() } }
        .onChange(of: showSummary) { _, showing in if showing { onSessionSummary?(explainSeconds) } }
        .onChange(of: isTabActive) { _, active in if active { F1StartLightsSound.shared.radioNotification(); speakRadioLine() } else { voice.stop(); speechSynthesizer.stopSpeaking(at: .immediate) } }
        .onChange(of: isRecording) { _, recording in if recording { voice.stop() } }
        .onDisappear { voice.stop() }
        .onChange(of: speechRecorder.isRecording) { _, recording in
            isRecording = recording
            if recording { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isActivelyExplaining = true } }
        }
        .onChange(of: feedback.isEvaluating) { _, evaluating in
            if !evaluating { applyLegacyResult() }
        }
        .onChange(of: activeInputMode) { mode in
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
                HStack(alignment: .top, spacing: 20) {
                    ZStack(alignment: .topLeading) {
                        modeSelectionButtons
                            .opacity(isListeningStage ? 0 : 1)
                            .offset(x: isListeningStage ? -24 : 0)
                            .allowsHitTesting(!isListeningStage)
                        VStack(alignment: .leading, spacing: 24) {
                            (Text("Topic").foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
                                + Text(" : \(activeTopicTitle)").foregroundStyle(.white))
                                .f1Font(size: 34, weight: .regular)
                                .lineLimit(2)
                            explainTimerTile
                        }
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.top, 16)
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
                // Clear of the settings button the app keeps in the top-right corner
                .padding(.top, 8)

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

    /// Same size and position in both poses: the waiting pose is drawn this much larger than its clip's own frame, so his
    /// face is as big as in the listening cut-out and sits in the same place.
    private static let idleScale: CGFloat = 2.03

    private var engineerFigure: some View {
        // An overlay, so the picture never changes the size of the screen's layout. He sits on top of the mic dock, not
        // behind it, and his face is on the middle of the screen, in line with the mic.
        Color.clear
            .overlay {
                GeometryReader { geo in
                    // Room above the dock (about 250 points tall, from the bottom), under the tab bar
                    let height = min(max(geo.size.height - 250 - 90, 380), 640) * 0.88
                    ZStack(alignment: .bottom) {
                        if !isListeningStage {
                            // Scaled to the size of the listening cut-out and moved so the face is in the same place; the
                            // whole figure shows down to the top of the dock
                            idleVideo(height: height)
                                .scaleEffect(Self.idleScale, anchor: UnitPoint(x: 0.5, y: 0.343))
                                .offset(y: height * 0.241)
                                .frame(width: height * 16 / 9, height: height)
                                .mask(alignment: .bottom) { Rectangle().frame(width: height * 16 / 9 * 1.4, height: height * 3) }
                                .transition(.opacity)
                        }
                        if isListeningStage {
                            listeningVideo(height: height)
                                .transition(.opacity)
                        }
                    }
                    .padding(.bottom, 250)
                    // Exactly the screen's size (the clip is wider than a portrait screen), so he stays centred on it
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                }
            }
            .accessibilityHidden(true)
    }

    /// The engineer waiting for the student: a looping clip, cut out with its silhouette, at the size where his face
    /// matches the listening clip's.
    private func idleVideo(height: CGFloat) -> some View {
        // Only the first 3.4 s: a watermark from the clip's generator shows by his hands from about 4 s on
        ZStack {
            // The clip's first frame, so he is there at once and the video takes over from it without a flash
            Image("idle_still").resizable().scaledToFill()
            LoopingPlayerView(videoName: "Idle123", videoExtension: "mov", playRange: 0...3.4)
        }
            .frame(width: height * 16 / 9, height: height)
            .mask {
                Image("idle_mask")
                    .resizable()
                    .scaledToFit()
                    .frame(width: height * 16 / 9, height: height)
            }
            // His face sits a hair left of the middle of the clip: this puts it on the middle of the screen
            .offset(x: height * 16 / 9 * 0.0083)
    }

    private func listeningVideo(height: CGFloat) -> some View {
        // A cut-out clip with its own transparency (HEVC with alpha): no still, no mask, he is drawn as he is
        // Only the first 3.6 s: a generator watermark ("Luma") shows on his shoulder in the last second of the clip
        LoopingPlayerView(videoName: "ListeningCutout", videoExtension: "mov", playRange: 0...3.6, transparent: true)
            .frame(width: height * 16 / 9, height: height)
    }

    private var disclaimerText: some View {
        Text("Disclaimer: Your voice stays on this iPad.")
            .f1Font(size: 14)
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
                            .f1Font(size: 19, weight: .medium)
                            .foregroundStyle(Color.white.opacity(0.55))
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(text)
                                .f1Font(size: 19, weight: .medium)
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
        .glassEffect(.regular, in: shape)
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
                        .shadow(color: (isListeningStage ? Color.red : Color.black).opacity(0.35), radius: 12, y: 5)
                    Image(systemName: "mic.fill")
                        .font(.system(size: isListeningStage ? 56 : 54, weight: .semibold))
                        .foregroundStyle(isListeningStage ? Color.white : Color(red: 238/255, green: 0, blue: 0))
                }
                Text(isListeningStage ? (isRecording ? "Click to End" : "Click to start") : "Click to start")
                    .f1Font(size: isListeningStage ? 20 : 14)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.f1Spring)
        .contentShape(Circle())
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

    private func speakRadioLine() {
        guard isTabActive, let line = currentRadioMessage, !isListeningStage, !isRecording, !isEvaluating else {
            voice.stop()
            return
        }
        voice.speak(line)
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.40), radius: 24, y: 10)
    }
    
    // MARK: - Topic Header (Figma 1057:6056)
    private var currentTopicHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Topic :")
                .f1Font(size: 24, weight: .bold)
                .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
            
            Text(activeTopicTitle)
                .f1Font(size: 24, weight: .bold)
                .foregroundStyle(Color.white)
        }
    }
    
    // MARK: - Mode menu (Figma "Explain": Speak, Sketch, Type in a vertical glass pill)
    private var modeSelectionButtons: some View {
        VStack(spacing: 10) {
            modeButton(.speak, icon: "mic.fill", label: "Speak", mode: .voice)
            modeButton(.write, icon: "pencil.and.ruler.fill", label: "Sketch", mode: .pencil)
            modeButton(.type, icon: "keyboard", label: "Type", mode: .keyboard)
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.75))
    }

    private func modeButton(_ target: ExplainInputMode, icon: String, label: String, mode: StudioInputMode) -> some View {
        Button {
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(target == .speak ? Color(red: 10/255, green: 110/255, blue: 255/255) : Color.clear, in: Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
                Text(label)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 56, alignment: .leading)
            }
        }
        .buttonStyle(.f1Spring)
        .contentShape(Rectangle())
        .accessibilityLabel("\(label) mode")
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
        .navigationTitle(mode == .speak ? activeTopicTitle : "")
        .toolbarRole(.editor)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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
                .padding(.horizontal, canvasFullscreen ? 0 : 40)
                .padding(.top, canvasFullscreen ? 0 : F1BackButton.top + 56 + 12)
                .padding(.bottom, canvasFullscreen ? 0 : 24)
                .ignoresSafeArea(edges: canvasFullscreen ? .all : [])
        }
        .overlay(alignment: .topTrailing) { canvasControls }
        .statusBarHidden(canvasFullscreen)
        .animation(.smooth(duration: 0.35), value: canvasFullscreen)
        // The same back button, in the same place, as every other screen
        .overlay(alignment: .topLeading) {
            if !canvasFullscreen {
                F1BackButton(label: "Back to Explain") { activeInputMode = nil }
                    .padding(.leading, F1BackButton.leading)
                    .padding(.top, F1BackButton.top)
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
        .onAppear {
            if inputMode == .keyboard { isFieldFocused = true }
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
        let shape = RoundedRectangle(cornerRadius: canvasFullscreen ? 0 : 28, style: .continuous)
        return ZStack(alignment: .topLeading) {
            canvasDotGrid
            canvasInteractiveContent
                .padding(.top, inputMode == .keyboard ? 110 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if inputMode == .pencil {
                // What the handwriting reads as, kept short; it scrolls when it is longer
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recognised handwriting")
                            .f1Font(size: 13, weight: .semibold)
                            .foregroundStyle(.white.opacity(0.6))
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(sketchText.isEmpty ? "Your handwriting appears here as you write" : sketchText)
                                .f1Font(size: 17)
                                .foregroundStyle(sketchText.isEmpty ? .white.opacity(0.45) : .white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 72)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.35))
                }
            }

            // Notes on the canvas, which can be dragged anywhere on it
            FreeformNote(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    topicTitleHeader
                    Text("Your answer")
                        .f1Font(size: 15, weight: .medium)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            FreeformNote(alignment: .topTrailing) {
                radioCard(message: currentRadioMessage ?? "“\(stageRadioMessage)”", compact: true)
                    .frame(width: 340)
            }
        }
        .background(shape.fill(Color(white: 0.08).opacity(0.94)))
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(canvasFullscreen ? 0 : 0.18), lineWidth: 0.75))
        .shadow(color: Color.black.opacity(canvasFullscreen ? 0 : 0.35), radius: 24, y: 10)
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

    /// Full screen and Done, top right where Settings is on the other screens.
    private var canvasControls: some View {
        HStack(spacing: 12) {
            Button {
                canvasFullscreen.toggle()
            } label: {
                Image(systemName: canvasFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.f1Spring)
            .contentShape(Circle())
            .accessibilityLabel(canvasFullscreen ? "Exit full screen" : "Full screen")

            Button { submitWrittenAnswer() } label: {
                Text("Done")
                    .f1Font(size: 17, weight: .semibold)
                    .frame(minWidth: 72, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Color.blue)
            .hoverEffect(.lift)
        }
        .padding(.top, 24)
        .padding(.trailing, 24)
    }

    // MARK: - Canvas Interactive Content (Accepts Pencil Drawing & Keyboard Text)
    private var canvasInteractiveContent: some View {
        ZStack(alignment: .topLeading) {
            // Text Area Layer (Keyboard Mode Only - Write Mode has NO text inside the box)
            if inputMode == .keyboard {
                ZStack(alignment: .topLeading) {
                    if typedText.isEmpty {
                        Text("Type your explanation here...")
                            .f1Font(size: 20, weight: .regular)
                            .foregroundStyle(Color.white.opacity(0.40))
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $typedText)
                        .focused($isFieldFocused)
                        .f1Font(size: 20, weight: .regular)
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
                    .f1Font(size: 26, weight: .bold)
                    .foregroundStyle(Color.white)
                
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            
            // Character with Video
            ZStack(alignment: .bottom) {
                LoopingPlayerView(videoName: activeVideoName, videoExtension: "mov")
                    .id(activeVideoName)
                    .scaledToFit()
                    .frame(maxHeight: 380)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            Spacer(minLength: 4)
        }
        .frame(height: 480)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 20, y: 10)
    }
    
    // MARK: - Right Top Radio Card (Figma 1057:1533, 1057:6056)
    private func radioCard(message: String, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Callsign Number on left, Driver Name + Radio on right
            HStack(alignment: .top) {
                Text("\(driverNumber)")
                    .f1Font(size: 38, weight: .bold)
                    .italic()
                    .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(driverName.isEmpty ? "Aarushi" : driverName)
                        .f1Font(size: 19, weight: .bold)
                        .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
                    
                    Text("Radio")
                        .f1Font(size: 15, weight: .bold)
                        .foregroundStyle(Color.white)
                }
            }
            
            // Row 2: Live Animated Equalizer Waveform Bars across the card (Figma 1057:1533, 1057:6056)
            if !compact {
                RadioEqualizerWaveformView(isRecording: isRecording || isActivelyExplaining, isActive: isRecording || voice.isSpeaking)
            }
            
            // Row 3: Radio Message Quote
            Text(voice.displayText(for: message))
                .f1Font(size: 16, weight: .medium)
                .foregroundStyle(Color.white)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: 0.12), value: voice.revealedText)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 16, y: 8)
    }
    
    // MARK: - Helper Design Components (Figma 1264:2970 & 1264:3088)
    private var topicTitleHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Topic :")
                .f1Font(size: 24, weight: .bold)
                .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
            
            Text(activeTopicTitle)
                .f1Font(size: 24, weight: .bold)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
    
    private var resolvedConcepts: [(title: String, isMastered: Bool)] {
        if let report = engineReport {
            return report.right.map { ($0, true) }
                + (report.corrections + report.missing + report.vague + report.conflicts).map { ($0, false) }
        }
        let clean = activeTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchedTopic = NCERTTopic.sampleChapter.first(where: {
            let t = $0.title.lowercased()
            let c = $0.chapter.lowercased()
            return t.contains(clean) || clean.contains(t) || c.contains(clean) || clean.contains(c)
        })
        
        let c1: String
        let c2: String
        let c3: String
        
        if clean.contains("double coincidence") || clean.contains("money and credit") {
            c1 = "Mutual Needs Match"
            c2 = "Barter Deadlock"
            c3 = "Medium of Exchange"
        } else if clean.contains("motion") || clean.contains("newton") {
            c1 = "Newton's First Law"
            c2 = "Unbalanced Forces"
            c3 = "Inertia of Rest"
        } else if clean.contains("refraction") || clean.contains("light") {
            c1 = "Speed of Light Change"
            c2 = "Optical Density Transition"
            c3 = "Bending Towards Normal"
        } else if clean.contains("sky") || clean.contains("blue") {
            c1 = "Rayleigh Scattering"
            c2 = "Short Wavelength Absorption"
            c3 = "Atmospheric Vacuum in Space"
        } else if clean.contains("redox") {
            c1 = "Oxidation Principle"
            c2 = "Reduction Mechanism"
            c3 = "Simultaneous Electron Transfer"
        } else if clean.contains("villi") || clean.contains("digestion") {
            c1 = "Surface Area Multiplication"
            c2 = "Epithelial Diffusion"
            c3 = "Capillary Blood Transport"
        } else if clean.contains("cramp") || clean.contains("respiration") {
            c1 = "Anaerobic Energy Deficit"
            c2 = "Pyruvate Conversion"
            c3 = "Lactic Acid Accumulation"
        } else if clean.contains("collateral") {
            c1 = "Pledged Asset Guarantee"
            c2 = "Default Recovery Mechanism"
            c3 = "Lender Security Rights"
        } else if clean.contains("power sharing") {
            c1 = "Social Conflict Mitigation"
            c2 = "Constitutional Checks"
            c3 = "Democratic Stability"
        } else if clean.contains("non-cooperation") || clean.contains("swaraj") {
            c1 = "Colonial Consent Principle"
            c2 = "Boycott of Institutions"
            c3 = "Administrative Collapse / Swaraj"
        } else {
            c1 = matchedTopic?.ib.groups.first?.label ?? "Newton's First Law"
            c2 = matchedTopic?.parakh.groups.first?.label ?? "Unbalanced Forces"
            c3 = (matchedTopic?.parakh.groups.count ?? 0) > 1 ? matchedTopic!.parakh.groups[1].label : (matchedTopic?.ib.groups.count ?? 0 > 1 ? matchedTopic!.ib.groups[1].label : "Inertia of Rest")
        }
        
        if clarityScore >= 80 {
            return [
                (c1, true),
                (c2, true),
                (c3, true)
            ]
        } else {
            let p1 = latestEvaluationResult?.passedIB ?? true
            let p2 = latestEvaluationResult?.passedParakh ?? (clarityScore >= 50)
            return [
                (c1, p1),
                (c2, p2),
                (c3, false)
            ]
        }
    }
    
    private var debriefDiagnosticRows: (passed: String, vague: String, missing: String) {
        if let report = engineReport {
            let right = F1FeedbackPhrasing.summary(report.right, phrase: F1FeedbackPhrasing.right, more: "ideas")
            let missing: String
            if let fix = report.corrections.first {
                missing = "Remember: \(fix)" + (report.corrections.count > 1 ? " (and \(report.corrections.count - 1) more to fix)" : "")
            } else {
                missing = F1FeedbackPhrasing.summary(report.missing + report.conflicts, phrase: F1FeedbackPhrasing.missing, more: "ideas to cover")
            }
            let vague: String
            if let question = report.followUp {
                vague = "Think about this: \(question)"
            } else {
                vague = F1FeedbackPhrasing.summary(report.vague, phrase: { "Be more specific: " + F1FeedbackPhrasing.missing($0).replacingOccurrences(of: "Try to ", with: "") }, more: "points")
            }
            return (right, vague, missing)
        }
        if feedback.result != nil {
            let r = feedback.report
            return (r.right, r.vague, r.missing)
        }
        let clean = activeTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchedTopic = NCERTTopic.sampleChapter.first(where: {
            let t = $0.title.lowercased()
            let c = $0.chapter.lowercased()
            return t.contains(clean) || clean.contains(t) || c.contains(clean) || clean.contains(c)
        })
        
        let passed = (latestEvaluationResult?.passedIB == true)
            ? "Accurately stated motion principles."
            : (matchedTopic != nil ? "Stated foundational terminology for \(activeTopicTitle)." : "Accurately stated motion principles.")
        
        let vague: String
        if let g = latestEvaluationResult?.nextGuidingQuestion, !g.isEmpty {
            vague = g.hasPrefix("2. ") ? String(g.dropFirst(3)) : g
        } else {
            vague = "You said 'it moves.' Try saying how: speeds up, slows down, or changes direction"
        }
        
        let missing: String
        if let m = latestEvaluationResult?.feynmanGap, !m.isEmpty {
            missing = m.hasPrefix("1. ") ? String(m.dropFirst(3)) : m
        } else {
            missing = "Mentioning acceleration rate formulas."
        }
        
        return (passed, vague, missing)
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
            ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        Image("engineer_confused")
                            .resizable()
                            .scaledToFit()
                            .frame(height: height * 0.52)
                            .padding(.trailing, width * 0.02)
                            .accessibilityHidden(true)
                    }
                }

                topicTitleHeader
                    .padding(.leading, width * 0.06)
                    .padding(.top, height * 0.04)

                debriefPanel
                    .frame(width: width * 0.63, height: height * 0.72)
                    .padding(.leading, width * 0.05)
                    .padding(.top, height * 0.15)

                radioCard(message: debriefRadioMessage)
                    .frame(width: width * 0.25)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, width * 0.025)
                    .padding(.top, height * 0.155)
            }
            .onAppear {
                debriefShown = false
                withAnimation(.smooth(duration: 0.5)) { debriefShown = true }
            }
            .onDisappear { debriefShown = false }
        }
    }

    private var debriefPanel: some View {
        let rows = debriefDiagnosticRows
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 26) {
                debriefRow(order: 0, icon: "xmark.square", color: Color(red: 233/255, green: 30/255, blue: 30/255), label: "What was missing: ",
                           text: rows.missing.isEmpty ? "Nothing important, you covered the main ideas." : rows.missing)
                debriefRow(order: 1, icon: "exclamationmark.triangle.fill", color: Color(red: 255/255, green: 197/255, blue: 89/255), label: "What was vague: ",
                           text: rows.vague.isEmpty ? "Nothing vague, your explanation was clear." : rows.vague)
                debriefRow(order: 2, icon: "checkmark.square.fill", color: Color(red: 58/255, green: 221/255, blue: 1/255), label: "What was right: ",
                           text: rows.passed.isEmpty ? "You gave it a go. Start with the main idea of \(activeTopicTitle) and build from there." : rows.passed)
            }
            .animation(.smooth(duration: 0.4), value: rows.missing + rows.vague + rows.passed)

            Spacer(minLength: 16)

            HStack(spacing: 28) {
                Spacer()
                Button { restartAttempt() } label: {
                    Text("Try again")
                        .f1Font(size: 18, weight: .medium)
                        .foregroundStyle(.white)
                        .frame(width: 180, height: 54)
                        .background(Color(red: 10/255, green: 110/255, blue: 255/255), in: Capsule())
                }
                .buttonStyle(.f1Spring)
                if attemptPassed {
                    Button {
                        withAnimation(.smooth(duration: 0.45)) { showSummary = true }
                    } label: {
                        Text("Session Summary")
                            .f1Font(size: 18, weight: .medium)
                            .foregroundStyle(.white)
                            .frame(width: 200, height: 54)
                            .background(Color(red: 10/255, green: 110/255, blue: 255/255), in: Capsule())
                    }
                    .buttonStyle(.f1Spring)
                } else {
                    Button { getHints() } label: {
                        HStack(spacing: 8) {
                            Text("Get Hints")
                                .f1Font(size: 18, weight: .medium)
                            miniCoin
                            Text("3")
                                .f1Font(size: 18, weight: .bold)
                                .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 190, height: 54)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.f1Spring)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 44)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.75))
        .alert("Not enough coins", isPresented: $showNotEnoughCoins) {
            Button("OK") {}
        } message: {
            Text("Hints cost 3 coins. Finish a focus session to earn more.")
        }
    }

    private func debriefRow(order: Int, icon: String, color: Color, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32)
            Text(label + text)
                .f1Font(size: 26, weight: .regular)
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
            Text("$").f1Font(size: 14, weight: .bold).foregroundStyle(Color(red: 150/255, green: 100/255, blue: 10/255))
        }
    }

    /// Hints cost 3 coins, charged once per attempt.
    private func getHints() {
        if !hintsPaid {
            guard spendCoins(F1SessionProgressManager.hintCost) else { showNotEnoughCoins = true; return }
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
        let clean = activeTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows: [(isPassed: Bool, label: String, detail: String)] = []
        
        for concept in resolvedConcepts {
            if concept.isMastered {
                let detail: String
                if clean.contains("motion") || clean.contains("newton") {
                    if concept.title.contains("First") || concept.title.contains("Motion") {
                        detail = "Accurately stated motion principles."
                    } else if concept.title.contains("Force") || concept.title.contains("Unbalanced") {
                        detail = "Perfectly explained velocity vs. time."
                    } else {
                        detail = "Nailed the acceleration rate formulas."
                    }
                } else if clean.contains("double coincidence") || clean.contains("money") {
                    if concept.title.contains("Needs") || concept.title.contains("Mutual") {
                        detail = "Accurately explained mutual desires requirement."
                    } else if concept.title.contains("Barter") || concept.title.contains("Deadlock") {
                        detail = "Clearly highlighted barter economy deadlocks."
                    } else {
                        detail = "Perfectly defined money as an intermediate medium."
                    }
                } else if clean.contains("refraction") || clean.contains("light") {
                    if concept.title.contains("Speed") {
                        detail = "Accurately identified optical speed transitions."
                    } else if concept.title.contains("Density") {
                        detail = "Correctly related medium density changes."
                    } else {
                        detail = "Nailed ray deviation angles towards normal."
                    }
                } else if clean.contains("sky") || clean.contains("blue") {
                    if concept.title.contains("Rayleigh") {
                        detail = "Accurately explained light scattering principles."
                    } else if concept.title.contains("Wavelength") {
                        detail = "Correctly identified short wavelength absorption."
                    } else {
                        detail = "Nailed vacuum atmosphere behavior in space."
                    }
                } else {
                    detail = "Accurately explained \(concept.title)."
                }
                rows.append((true, "What you got right", detail))
            } else {
                let detail: String
                if clean.contains("motion") || clean.contains("newton") {
                    detail = "Mentioning acceleration rate formulas and external net forces."
                } else if clean.contains("double coincidence") || clean.contains("money") {
                    detail = "Clearly highlighting barter deadlocks and intermediate exchange."
                } else {
                    detail = "Key mechanisms of \(concept.title) need clearer explanation."
                }
                rows.append((false, "Needs review", detail))
            }
        }
        return rows
    }

    // MARK: - Session summary (Figma: times, radio line, coins, per-concept status, Revise / Done)
    private var wellDoneSummaryView: some View {
        ZStack {
            VStack {
                Spacer()
                Image("engineer_success")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 560)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 18) {
                        (Text("Current Topic").foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255)) + Text(" : \(activeTopicTitle)").foregroundStyle(.white))
                            .f1Font(size: 28, weight: .regular)
                            .lineLimit(3)
                            .frame(maxWidth: 360, alignment: .leading)
                        timeTile(seconds: explainSeconds, label: "EXPLAIN TIME")
                        timeTile(seconds: studySeconds, label: "FOCUS TIME")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 14) {
                        radioCard(message: "“\(summaryRadioLine)”")
                            .frame(width: 330)
                        VStack(spacing: 2) {
                            (Text("Coins Gained: ").foregroundStyle(.white) + Text("+\(coinsEarned)").foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255)))
                                .f1Font(size: 26, weight: .regular)
                            Text(coinsEarned >= 2 ? "Half-way +1, finished +1" : coinsEarned == 1 ? "Half-way +1" : "Finish a focus session to earn coins")
                                .f1Font(size: 15)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(width: 330)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 8)

                Spacer()

                perConceptPanel
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)

                HStack(spacing: 24) {
                    summaryButton("Revise") {
                        if let onNavigateToRevise { onNavigateToRevise() } else { getHints() }
                    }
                    summaryButton("Done") { onDone() }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            }

            VStack {
                Spacer()
                HStack {
                    streakLabel
                    Spacer()
                }
            }
            .padding(.leading, 36)
            .padding(.bottom, 18)
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

    private func timeTile(seconds: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 32, weight: .regular).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .f1Font(size: 22, weight: .regular)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 330, height: 120)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var perConceptPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Per-Concept Status (Got it / Needs review)")
                .f1Font(size: 17, weight: .regular)
                .foregroundStyle(.white)
            ForEach(Array(resolvedConcepts.prefix(4).enumerated()), id: \.offset) { _, concept in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: concept.isMastered ? "checkmark.square.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(concept.isMastered ? Color(red: 58/255, green: 221/255, blue: 1/255) : Color(red: 255/255, green: 197/255, blue: 89/255))
                    Text("\(concept.title) — \(concept.isMastered ? "Got it" : "Needs review")")
                        .f1Font(size: 17, weight: .regular)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }
        }
        .padding(24)
        .frame(width: 520, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.75))
    }

    private func summaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .f1Font(size: 18, weight: .medium)
                .foregroundStyle(.white)
                .frame(width: 170, height: 52)
                .background(Color(red: 10/255, green: 110/255, blue: 255/255), in: Capsule())
        }
        .buttonStyle(.f1Spring)
    }

    private var streakLabel: some View {
        let days = F1SessionProgressManager.shared.weeklyStreaks.filter { $0 }.count
        return HStack(spacing: 10) {
            Text("\(max(days, 1))-DAY ACTIVE STREAK")
                .f1Font(size: 22, weight: .semibold)
                .foregroundStyle(.white)
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Modal: USE REWARDS (Figma 802:3825)
    private var useRewardsModal: some View {
        VStack(spacing: 20) {
            Text("USE REWARDS")
                .f1Font(size: 17, weight: .bold)
                .foregroundStyle(Color.white)
                .padding(.top, 24)
            
            HStack(spacing: 6) {
                Text("Spend 3")
                    .f1Font(size: 16, weight: .regular)
                    .foregroundStyle(Color.white.opacity(0.85))
                
                Text("🪙")
                    .f1Font(size: 16)
                
                Text("to reveal answers")
                    .f1Font(size: 16, weight: .regular)
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
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Color(red: 255/255, green: 56/255, blue: 60/255))
                .contentShape(Capsule())
                .hoverEffect(.lift)
                .frame(maxWidth: .infinity)
                
                // "Accept" (Official Apple Bordered Prominent)
                Button("Accept") {
                    withAnimation {
                        showRewardActionSheet = false
                        showWhatYouMissedView = true
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Color(red: 0/255, green: 136/255, blue: 255/255))
                .contentShape(Capsule())
                .hoverEffect(.lift)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 320)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
struct PencilDrawingCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var isPencilMode: Bool = true
    var onDrawingChanged: (() -> Void)? = nil

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .white, width: 3)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = context.coordinator
        
        if isPencilMode {
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
            context.coordinator.toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }
        
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if isPencilMode {
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: uiView)
            context.coordinator.toolPicker.addObserver(uiView)
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else {
            context.coordinator.toolPicker.setVisible(false, forFirstResponder: uiView)
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
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

        init(_ parent: PencilDrawingCanvasView) {
            self.parent = parent
        }

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
struct F1CoinCounter: View {
    let count: Int
    var body: some View {

        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(red: 188/255, green: 144/255, blue: 62/255),
                                Color(red: 217/255, green: 188/255, blue: 114/255),
                                Color(red: 255/255, green: 197/255, blue: 89/255),
                                Color(red: 175/255, green: 126/255, blue: 29/255),
                                Color(red: 188/255, green: 144/255, blue: 62/255)
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Circle()
                    .fill(Color(red: 176/255, green: 119/255, blue: 13/255))
                    .frame(width: 28, height: 28)
                
                Text("$")
                    .f1Font(size: 18, weight: .bold)
                    .foregroundStyle(Color(red: 203/255, green: 167/255, blue: 89/255))
            }
            
            Text("\(count)")
                .f1Font(size: 22, weight: .bold)
                .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                .contentTransition(.numericText())
                .animation(.smooth, value: count)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
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
            .padding(.top, alignment == .topTrailing ? 70 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
