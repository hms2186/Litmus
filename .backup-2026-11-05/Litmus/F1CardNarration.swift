//
//  F1CardNarration.swift
//  Optional narration for flashcards, keyword highlighting, and the image zoom screen.
//  Narration starts only when the student taps the speaker icon on a card.
//

import SwiftUI
import AVFoundation
import Combine

// MARK: - Narration

@MainActor
final class F1CardNarrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var narratingCardID: String?
    /// The word being spoken, as a range in the spoken string (UTF-16 offsets).
    @Published private(set) var spokenRange: NSRange?

    static let rateKey = "card_speech_rate"
    /// The speaking rate as Siri's slider has it: AVSpeechUtterance's own scale, default in the middle.
    static let rateRange = AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var spokenText = ""
    private var base = 0                 // where the utterance starts inside `spokenText`
    private var current: (id: String, title: String, body: String)?
    private var utterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    private var rate: Float {
        let stored = UserDefaults.standard.object(forKey: Self.rateKey) as? Double
        return Float(stored ?? Double(AVSpeechUtteranceDefaultSpeechRate))
    }

    /// Reads the card aloud (title, then text), or stops if it is already being read.
    func toggle(cardID: String, title: String, body: String) {
        if narratingCardID == cardID { stop(); return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        spokenText = title + ". " + body
        current = (cardID, title, body)
        base = 0
        speak(from: 0, cardID: cardID)
    }

    /// A new rate takes effect at once: the reading carries on from the word it had reached.
    func rateChanged() {
        guard let current, narratingCardID == current.id else { return }
        let resume = spokenRange?.location ?? base
        synthesizer.stopSpeaking(at: .immediate)
        speak(from: min(resume, spokenText.utf16.count), cardID: current.id)
    }

    private func speak(from start: Int, cardID: String) {
        base = start
        let text = String(spokenText.utf16.dropFirst(start)) ?? spokenText
        let next = AVSpeechUtterance(string: text)
        // The same voice as the engineer's radio lines; the reading speed is the one chosen with the slider
        VoiceEngineService.configure(next, rate: rate)
        utterance = next
        narratingCardID = cardID
        synthesizer.speak(next)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        utterance = nil
        narratingCardID = nil
        spokenRange = nil
        current = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.utterance else { return }
            self.spokenRange = NSRange(location: characterRange.location + self.base, length: characterRange.length)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.utterance else { return }
            self.narratingCardID = nil; self.spokenRange = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.utterance else { return }
            self.narratingCardID = nil; self.spokenRange = nil
        }
    }
}

// MARK: - Keyword highlighting

enum F1KeywordHighlighter {
    private static let keywordColor = Color(red: 255/255, green: 197/255, blue: 89/255)

    /// The card text with its key terms in bold gold. While the card is being read, the word being spoken
    /// also gets a light background. `spokenRange` is relative to the text (UTF-16 offsets).
    static func attributed(_ text: String, keywords: [String], spokenRange: NSRange?) -> AttributedString {
        var result = AttributedString(text)
        for keyword in keywords where keyword.count >= 3 {
            var cursor = result.startIndex
            while cursor < result.endIndex, let found = result[cursor...].range(of: keyword, options: .caseInsensitive) {
                result[found].foregroundColor = keywordColor
                // Bold relative to the text around it, so a key term is always the same size as the words beside it
                result[found].inlinePresentationIntent = .stronglyEmphasized
                cursor = found.upperBound
            }
        }
        if let spokenRange, spokenRange.location >= 0, spokenRange.location + spokenRange.length <= text.utf16.count {
            let plain = String(result.characters)
            let lower = String.Index(utf16Offset: spokenRange.location, in: plain)
            let upper = String.Index(utf16Offset: spokenRange.location + spokenRange.length, in: plain)
            if let a = AttributedString.Index(lower, within: result), let b = AttributedString.Index(upper, within: result), a < b {
                result[a..<b].backgroundColor = Color.white.opacity(0.28)
            }
        }
        return result
    }
}

// MARK: - Zoom

struct F1ZoomImage: Identifiable {
    let name: String
    let title: String
    var id: String { name }
}

/// A full-screen look at a diagram: pinch to zoom, drag to move, double-tap to reset.
struct F1ImageZoomView: View {
    let image: F1ZoomImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(image.name)
                .resizable()
                .scaledToFit()
                .padding(24)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(40)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = min(6, max(1, committedScale * $0.magnification)) }
                        .onEnded { _ in
                            committedScale = scale
                            if scale <= 1.01 { withAnimation(.smooth) { offset = .zero; committedOffset = .zero } }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: committedOffset.width + value.translation.width, height: committedOffset.height + value.translation.height)
                        }
                        .onEnded { _ in committedOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.smooth) {
                        let zoomIn = scale < 1.5
                        scale = zoomIn ? 2.5 : 1
                        committedScale = scale
                        offset = .zero
                        committedOffset = .zero
                    }
                }
                .accessibilityLabel("NCERT diagram: \(image.title)")
                .accessibilityHint("Pinch to zoom, double-tap to zoom in or out")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .trailing, spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .accessibilityLabel("Close")
                Text("Pinch or double-tap to zoom")
                    .f1Font(size: 14)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }
}
