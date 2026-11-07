import Foundation
import Combine
import Speech
import AVFoundation

/// Captures the microphone and transcribes it live.
///
/// The transcription runs on `SpeechAnalyzer` with a `SpeechTranscriber` module (iOS 26): audio is converted to
/// the analyzer's format and streamed in as one continuous `AsyncStream`, so a pause never ends or restarts the
/// session and the words already spoken stay put. Volatile results show the words as they are heard; a final
/// result replaces them once the analyzer is sure. The older `SFSpeechRecognizer` is used only on a device or
/// locale the new transcriber does not support.
@MainActor
final class LiveSpeechRecorder: ObservableObject {
    @Published var isRecording = false

    /// Chapter terms that prime the recogniser (khadar, regur, palar pani…). At most 100 are used.
    var contextualStrings: [String] = []

    /// Both engines run on the device; audio leaves it only if the fallback has to use Apple's servers.
    var isOnDevice: Bool { usingFallback ? (fallback?.isOnDevice ?? false) : true }

    /// Mean confidence of the final results in this recording, or nil when there were none (then the answer is
    /// not judged unintelligible).
    var finalConfidence: Double? {
        if usingFallback { return fallback?.finalConfidence }
        return confidenceCount > 0 ? confidenceSum / Double(confidenceCount) : nil
    }

    // MARK: SpeechAnalyzer state

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var activeCallback: ((String) -> Void)?

    /// Text the analyzer has finalised, and the words it is still working on.
    private var finalizedText = ""
    private var volatileText = ""
    private var confidenceSum = 0.0
    private var confidenceCount = 0

    private var cachedLocale: Locale?
    private var assetsReady = false

    // MARK: Fallback

    private var fallback: LegacyDictationSession?
    private var usingFallback = false

    // MARK: - Public

    /// Finds the locale and installs its speech model ahead of the first recording, so Speak starts at once.
    func prepare() async {
        guard SpeechTranscriber.isAvailable, !assetsReady, let locale = await preferredLocale() else { return }
        let transcriber = makeTranscriber(locale: locale)
        do {
            try await installAssets(for: transcriber)
            assetsReady = true
        } catch {
            assetsReady = false
        }
    }

    func toggleRecording(onTranscriptUpdate: @escaping (String) -> Void) {
        if isRecording {
            stopRecording()
            return
        }
        guard startTask == nil else { return }
        activeCallback = onTranscriptUpdate
        finalizedText = ""
        volatileText = ""
        confidenceSum = 0
        confidenceCount = 0
        usingFallback = false

        startTask = Task { [weak self] in
            guard let self else { return }
            defer { self.startTask = nil }
            guard await self.requestMicrophone() else { return }
            do {
                try await self.startAnalyzer()
            } catch {
                #if DEBUG
                print("🎙️ SpeechAnalyzer unavailable (\(error)); using the dictation fallback")
                #endif
                self.teardownAnalyzer()
                self.startFallback()
            }
        }
    }

    /// Stops listening. The words still in flight are finalised in the background; call `waitUntilFinalized()`
    /// before reading the transcript for good.
    func stopRecording() {
        startTask?.cancel()
        startTask = nil
        if usingFallback {
            fallback?.stop()
            isRecording = false
            return
        }
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil
        let analyzer = analyzer
        let results = resultsTask
        finishTask = Task { [weak self] in
            await Self.finish(analyzer: analyzer, results: results)
            self?.commitVolatile()
            self?.analyzer = nil
            self?.resultsTask = nil
        }
    }

    /// Waits (briefly) for the analyzer to deliver the last words after `stopRecording()`.
    func waitUntilFinalized() async {
        await finishTask?.value
    }

    // MARK: - SpeechAnalyzer

    private func startAnalyzer() async throws {
        guard SpeechTranscriber.isAvailable, let locale = await preferredLocale() else { throw RecorderError.unsupported }
        let transcriber = makeTranscriber(locale: locale)
        if !assetsReady {
            try await installAssets(for: transcriber)
            assetsReady = true
        }
        try Task.checkCancellation()

        let session = AVAudioSession.sharedInstance()
        // The default mode keeps the system's gain control and noise handling on, which gives the recogniser a
        // cleaner signal than `.measurement`; the speaker stays the output so the engineer's voice is not muffled.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        // No usable microphone: installing a tap would raise an Objective-C exception and abort the app.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noMicrophone }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: inputFormat) else {
            throw RecorderError.unsupported
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .lingering))
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(contextualStrings.prefix(100))
        try await analyzer.setContext(context)
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        try Task.checkCancellation()

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.analyzer = analyzer
        self.inputContinuation = continuation

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.handle(result)
                }
            } catch {
                #if DEBUG
                print("🎙️ Transcriber stopped: \(error)")
                #endif
            }
        }

        try await analyzer.start(inputSequence: stream)

        let converter = AudioBufferConverter(outputFormat: analyzerFormat)
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat,
                                         block: Self.makeTap(converter: converter, continuation: continuation))
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    /// The tap runs on the audio thread, so it is built outside the main actor.
    nonisolated private static func makeTap(converter: AudioBufferConverter,
                                            continuation: AsyncStream<AnalyzerInput>.Continuation) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            if let converted = converter.convert(buffer) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    private func handle(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isFinal {
            if !text.isEmpty { finalizedText = join(finalizedText, text) }
            volatileText = ""
            for run in result.text.runs {
                if let confidence = run.transcriptionConfidence, confidence > 0 {
                    confidenceSum += confidence
                    confidenceCount += 1
                }
            }
        } else {
            volatileText = text
        }
        publish()
    }

    /// Whatever the analyzer was still working on when listening stopped becomes part of the transcript.
    private func commitVolatile() {
        if !volatileText.isEmpty {
            finalizedText = join(finalizedText, volatileText)
            volatileText = ""
        }
        publish()
    }

    private func publish() {
        activeCallback?(join(finalizedText, volatileText))
    }

    private func join(_ head: String, _ tail: String) -> String {
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }

    private func teardownAnalyzer() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
    }

    /// Ends the analyzer's session once the input is closed, giving the last words up to two seconds to arrive.
    nonisolated private static func finish(analyzer: SpeechAnalyzer?, results: Task<Void, Never>?) async {
        guard let analyzer else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
            group.addTask { try? await Task.sleep(for: .seconds(2)) }
            await group.next()
            group.cancelAll()
        }
        await analyzer.cancelAndFinishNow()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await results?.value }
            group.addTask { try? await Task.sleep(for: .seconds(1)) }
            await group.next()
            group.cancelAll()
        }
        results?.cancel()
    }

    // MARK: - Locale and assets

    private func preferredLocale() async -> Locale? {
        if let cachedLocale { return cachedLocale }
        for identifier in ["en-IN", "en-US"] {
            if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) {
                cachedLocale = locale
                return locale
            }
        }
        return nil
    }

    private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        // Volatile results show the words as they are heard; confidence feeds the "unintelligible" check.
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.transcriptionConfidence])
    }

    private func installAssets(for transcriber: SpeechTranscriber) async throws {
        if await AssetInventory.status(forModules: [transcriber]) == .installed { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    // MARK: - Permission

    private func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
    }

    private enum RecorderError: Error {
        case unsupported
        case noMicrophone
    }

    // MARK: - Fallback

    private func startFallback() {
        usingFallback = true
        let session = LegacyDictationSession()
        session.contextualStrings = contextualStrings
        session.onTranscript = { [weak self] text in self?.activeCallback?(text) }
        session.onStopped = { [weak self] in self?.isRecording = false }
        fallback = session
        session.start { [weak self] started in
            self?.isRecording = started
        }
    }
}

/// Converts microphone buffers to the format `SpeechAnalyzer` asked for. Used only from the audio thread.
nonisolated final class AudioBufferConverter: @unchecked Sendable {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == outputFormat { return buffer }
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            // No priming frames: the analyzer's timeline should follow the microphone's.
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}

/// The `SFSpeechRecognizer` path, kept for a device or locale `SpeechTranscriber` does not support. A pause ends
/// the recogniser's task, so the text so far is kept and a new task takes over without a gap.
nonisolated final class LegacyDictationSession: @unchecked Sendable {
    var contextualStrings: [String] = []
    var onTranscript: (@MainActor (String) -> Void)?
    var onStopped: (@MainActor () -> Void)?

    private let speechRecognizer: SFSpeechRecognizer? = {
        let candidates = ["en-IN", "en-US"].compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
        return candidates.first(where: \.supportsOnDeviceRecognition) ?? candidates.first ?? SFSpeechRecognizer()
    }()
    var isOnDevice: Bool { speechRecognizer?.supportsOnDeviceRecognition ?? false }

    private var confidenceSum = 0.0
    private var confidenceCount = 0
    var finalConfidence: Double? { confidenceCount > 0 ? confidenceSum / Double(confidenceCount) : nil }

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var accumulatedTranscript = ""
    private var latestFullTranscript = ""
    private var running = false
    private var isRestarting = false

    func start(completion: @escaping @MainActor (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self, status == .authorized else {
                Task { @MainActor in completion(false) }
                return
            }
            DispatchQueue.main.async {
                self.accumulatedTranscript = ""
                self.latestFullTranscript = ""
                self.running = true
                let started = self.startEngine()
                if !started { self.running = false }
                Task { @MainActor in completion(started) }
            }
        }
    }

    func stop() {
        running = false
        isRestarting = false
        if !latestFullTranscript.isEmpty { accumulatedTranscript = latestFullTranscript }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    @discardableResult
    private func startEngine() -> Bool {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request
        guard let recognizer = speechRecognizer else { return false }

        request.taskHint = .dictation
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = Array(contextualStrings.prefix(100))
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            recognitionRequest = nil
            return false
        }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        try? audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let current = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !current.isEmpty {
                    let full = self.accumulatedTranscript.isEmpty ? current : self.accumulatedTranscript + " " + current
                    self.latestFullTranscript = full
                    Task { @MainActor in self.onTranscript?(full) }
                }
                if result.isFinal {
                    let scored = result.bestTranscription.segments.map { Double($0.confidence) }.filter { $0 > 0 }
                    if !scored.isEmpty {
                        self.confidenceSum += scored.reduce(0, +)
                        self.confidenceCount += scored.count
                    }
                    self.restartSeamlessly()
                    return
                }
            }
            if error != nil { self.restartSeamlessly() }
        }
        return true
    }

    private func restartSeamlessly() {
        DispatchQueue.main.async {
            guard self.running, !self.isRestarting else { return }
            self.isRestarting = true
            if !self.latestFullTranscript.isEmpty { self.accumulatedTranscript = self.latestFullTranscript }
            self.audioEngine.stop()
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.recognitionRequest?.endAudio()
            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            self.recognitionRequest = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.isRestarting = false
                if self.running {
                    if !self.startEngine() {
                        self.running = false
                        Task { @MainActor in self.onStopped?() }
                    }
                }
            }
        }
    }
}
