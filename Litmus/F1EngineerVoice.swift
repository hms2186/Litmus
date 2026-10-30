//
//  F1EngineerVoice.swift
//  The race engineer's voice. It reads the radio box aloud and reveals the words in the box as they
//  are spoken, so the text and the voice stay together. Muted by the "Sound Effects" setting, and
//  silent while the microphone is recording. The speaking itself is VoiceEngineService.
//

import Foundation
import Combine

@MainActor
final class F1EngineerVoice: NSObject, ObservableObject {

    static let soundSettingKey = "settings_sound_effects"

    /// The part of the current line spoken so far.
    @Published private(set) var revealedText = ""
    @Published private(set) var isSpeaking = false

    private let service = VoiceEngineService()
    private var line = ""          // what is shown in the radio box
    private var spoken = ""        // what is read aloud (the same without quotation marks)

    override init() {
        super.init()
        service.onWord = { [weak self] range in self?.reveal(upTo: range.location + range.length) }
        service.onFinish = { [weak self] in
            self?.isSpeaking = false
            self?.revealedText = ""
        }
    }

    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.soundSettingKey) as? Bool ?? true
    }

    /// What the radio box should show for `message`: the words spoken so far while it is being read,
    /// otherwise the whole message.
    func displayText(for message: String) -> String {
        guard isSpeaking, message == line, !revealedText.isEmpty else { return message }
        return revealedText
    }

    func speak(_ message: String) {
        stop()
        guard soundEnabled else { return }
        let text = message.trimmingCharacters(in: CharacterSet(charactersIn: "“”\" ")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        line = message
        spoken = text
        revealedText = ""
        isSpeaking = true
        service.speak(text)
    }

    func stop() {
        service.stop()
        isSpeaking = false
        revealedText = ""
    }

    private func reveal(upTo end: Int) {
        guard isSpeaking else { return }
        let prefix = String(spoken.prefix(min(end, spoken.count)))
        // Keep the quotation marks of the box while revealing
        revealedText = line.hasPrefix("“") ? "“" + prefix + (end >= spoken.count ? "”" : "") : prefix
    }
}
