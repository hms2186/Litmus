import AVFoundation
import Foundation

@MainActor
final class VoiceEngineService: NSObject, AVSpeechSynthesizerDelegate {

    /// The engineer's voice: a male Indian English voice, the best one installed, found once.
    static let voice: AVSpeechSynthesisVoice? = bestVoice()

    /// The voice, pitch and pacing every spoken line uses, so the engineer sounds the same everywhere in the app.
    static func configure(_ utterance: AVSpeechUtterance, rate: Float? = nil) {
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-IN")
        utterance.rate = rate ?? defaultRate
        // A little lower than the voice's own pitch, and a breath before and after, so it sounds spoken rather than read
        utterance.pitchMultiplier = 0.94
        utterance.volume = 1
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.1
    }

    /// A touch slower than the system default: Indian English voices rush at the default rate
    static let defaultRate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.96

    /// Called with the range of the word about to be spoken, in the text passed to `speak`.
    var onWord: ((NSRange) -> Void)?
    /// Called when the speech ends or is stopped.
    var onFinish: (() -> Void)?

    var rate: Float = VoiceEngineService.defaultRate

    private let synthesizer = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        configureAudioSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        Self.configure(utterance, rate: rate)
        current = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        current = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    // MARK: - Voice search

    /// Male Indian English first (en-IN), then other male English; within each, premium before enhanced before the rest.
    /// Install "Rishi" in Settings > Accessibility > Spoken Content > Voices (Enhanced or Premium) for the most natural sound.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        func quality(_ voice: AVSpeechSynthesisVoice) -> Int {
            switch voice.quality {
            case .premium: 2
            case .enhanced: 1
            default: 0
            }
        }
        func score(_ voice: AVSpeechSynthesisVoice) -> (Int, Int, Int, String) {
            let indian = voice.language == "en-IN" ? 2 : (voice.language.hasPrefix("en") ? 1 : 0)
            let male = voice.gender == .male ? 1 : 0
            return (indian * 2 + male, quality(voice), voice.name == "Rishi" ? 1 : 0, voice.name)
        }
        let english = all.filter { $0.language.hasPrefix("en") }
        let indianMale = english.filter { $0.language == "en-IN" && $0.gender == .male }
        let pool = !indianMale.isEmpty ? indianMale : (english.filter { $0.gender == .male }.isEmpty ? english : english.filter { $0.gender == .male })
        return pool.max { score($0) < score($1) }
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.current else { return }
            self.onWord?(characterRange)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.current else { return }
            self.current = nil
            self.onFinish?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.current else { return }
            self.current = nil
            self.onFinish?()
        }
    }
}
