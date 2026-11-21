//
//  EngineerVoice.swift
//  The race engineer's voice. It reads the radio box aloud and reveals the words in the box as they
//  are spoken, so the text and the voice stay together. Muted by the "Sound Effects" setting, and
//  silent while the microphone is recording. The speaking itself is VoiceEngineService.
//

import Foundation
import Combine

@MainActor
final class EngineerVoice: NSObject, ObservableObject {

    static let soundSettingKey = "settings_sound_effects"

    /// The part of the current line spoken so far.
    @Published private(set) var revealedText = ""
    @Published private(set) var isSpeaking = false
    /// A line about to be spoken: its box stays empty (at full size) until the voice starts, so the text never shows ahead of it.
    @Published private(set) var pending = ""

    private let service = VoiceEngineService()
    /// If the voice goes quiet for a few seconds mid-line, the box shows the whole line instead of staying cut short.
    private var watchdog: Task<Void, Never>?
    /// Where the voice last reported being (UTF-16 offset in `spoken`), when, and how fast it reads, so the text keeps
    /// pace between the system's word callbacks instead of waiting on each one.
    private var anchorEnd = 0
    private var anchorTime = Date()
    private var charsPerSecond = 14.0
    private var shownEnd = 0
    private var ticker: Task<Void, Never>?
    private var line = ""          // what is shown in the radio box
    private var spoken = ""        // what is read aloud (the same without quotation marks)

    override init() {
        super.init()
        service.onWord = { [weak self] range in self?.reveal(upTo: range.location + range.length) }
        service.onFinish = { [weak self] in
            self?.watchdog?.cancel()
            self?.ticker?.cancel()
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

    /// The message split into what has been spoken and what is still to come, so the box can keep its full size.
    func displayParts(for message: String) -> (shown: String, hidden: String) {
        if !isSpeaking, !pending.isEmpty, message == pending { return ("", message) }
        guard isSpeaking, message == line else { return (message, "") }
        let shown = revealedText
        guard shown.count < message.count else { return (message, "") }
        return (shown, String(message.dropFirst(shown.count)))
    }

    /// The line is about to be spoken; hold its text back until the voice reaches each word.
    func expect(_ message: String) {
        if soundEnabled { pending = message }
    }

    func clearPending() { pending = "" }

    func speak(_ message: String) {
        stop()
        guard soundEnabled else { return }
        let text = message.trimmingCharacters(in: CharacterSet(charactersIn: "“”\" ")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        line = message
        spoken = text
        revealedText = ""
        isSpeaking = true
        anchorEnd = 0
        shownEnd = 0
        anchorTime = Date()
        service.speak(text)
        armWatchdog(seconds: 6)
        startTicker()
    }

    /// Between word callbacks the text moves on at the voice's own pace, but never more than the next word ahead.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self, self.isSpeaking else { return }
                // Nothing is shown until the voice has actually begun
                guard self.anchorEnd > 0 else { continue }
                let elapsed = Date().timeIntervalSince(self.anchorTime)
                let estimate = self.anchorEnd + Int(self.charsPerSecond * elapsed)
                // A whole word at a time: the next one appears once the voice is about halfway through it
                let (start, end) = self.nextWord(after: self.anchorEnd)
                if estimate >= (start + end) / 2, end > self.shownEnd { self.show(upTo: end) }
            }
        }
    }

    private func nextWord(after offset: Int) -> (start: Int, end: Int) {
        let ns = spoken as NSString
        var i = min(offset, ns.length)
        while i < ns.length, ns.character(at: i) == 32 { i += 1 }
        let start = i
        while i < ns.length, ns.character(at: i) != 32 { i += 1 }
        return (start, i)
    }

    private func show(upTo end: Int) {
        let ns = spoken as NSString
        let clamped = min(end, ns.length)
        shownEnd = clamped
        let prefix = ns.substring(to: clamped)
        // Keep the quotation marks of the box while revealing
        revealedText = line.hasPrefix("“") ? "“" + prefix + (clamped >= ns.length ? "”" : "") : prefix
    }

    private func armWatchdog(seconds: Double) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.isSpeaking else { return }
            self.service.stop()
            self.isSpeaking = false
            self.revealedText = ""
        }
    }

    func stop() {
        ticker?.cancel()
        watchdog?.cancel()
        pending = ""
        service.stop()
        isSpeaking = false
        revealedText = ""
    }

    private func reveal(upTo end: Int) {
        guard isSpeaking else { return }
        armWatchdog(seconds: 3)
        // Learn how fast this voice reads from the gap between callbacks
        let now = Date()
        let dt = now.timeIntervalSince(anchorTime)
        let advanced = end - anchorEnd
        if anchorEnd > 0, dt > 0.05, advanced > 0 {
            charsPerSecond = 0.7 * charsPerSecond + 0.3 * min(max(Double(advanced) / dt, 6), 30)
        }
        anchorEnd = max(end, anchorEnd)
        anchorTime = now
        if end > shownEnd { show(upTo: end) }
    }
}
