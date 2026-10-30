//
//  F1StartLightsSound.swift
//  The sounds of the start lights: a clean beep as each light comes on, rising a little with each one, and a single
//  rising rush when the lights go out. They are made here as tones, so the app needs no audio files, and they follow the
//  Sound Effects switch in Settings.
//

import AVFoundation

@MainActor
final class F1StartLightsSound {
    static let shared = F1StartLightsSound()

    private var players: [AVAudioPlayer] = []
    private let sampleRate = 44_100.0

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: F1EngineerVoice.soundSettingKey) as? Bool ?? true
    }

    /// Light number 1...5: each beep a little higher than the one before.
    func light(_ number: Int) {
        play(tone(frequency: 740 + Double(number) * 70, duration: 0.16, volume: 0.55))
    }

    /// The recorded start sequence (LightsOut.mp3): five beeps, one a second, with 3 s of silence in front that is skipped.
    /// Played alongside the five lights. False when the file is missing (the lights then use the tones above).
    @discardableResult
    func startSequence() -> Bool {
        playFile("LightsOut", volume: 0.9, from: 3.0)
    }

    /// The lights go out: a rising rush, for when the recording is missing.
    func lightsOut() {
        play(sweep(from: 180, to: 1_100, duration: 0.7, volume: 0.6))
    }

    /// The radio click-in heard on opening the Explain screen (f1_radio_notification.mp3).
    func radioNotification() {
        playFile("f1_radio_notification", volume: 0.8)
    }

    @discardableResult
    private func playFile(_ name: String, volume: Float, from start: TimeInterval = 0) -> Bool {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return false }
        guard enabled else { return true }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player.volume = volume
        player.currentTime = start
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.play()
        return true
    }

    // MARK: Playing

    private func play(_ data: Data?) {
        guard enabled, let data, let player = try? AVAudioPlayer(data: data) else { return }
        // Ambient: follows the silent switch and does not interrupt other audio
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.play()
    }

    // MARK: Making the tones

    private func tone(frequency: Double, duration: Double, volume: Double) -> Data? {
        wave(duration: duration) { t, progress in
            let envelope = min(1, progress / 0.08) * min(1, (1 - progress) / 0.35)
            return sin(2 * .pi * frequency * t) * envelope * volume
        }
    }

    private func sweep(from: Double, to: Double, duration: Double, volume: Double) -> Data? {
        var phase = 0.0
        return wave(duration: duration) { _, progress in
            let frequency = from + (to - from) * progress * progress
            phase += 2 * .pi * frequency / self.sampleRate
            let envelope = min(1, progress / 0.05) * pow(1 - progress, 1.4)
            return (sin(phase) * 0.8 + sin(phase * 0.5) * 0.4) * envelope * volume
        }
    }

    /// 16-bit mono PCM in a WAV container
    private func wave(duration: Double, sample: (Double, Double) -> Double) -> Data? {
        let count = Int(duration * sampleRate)
        var pcm = Data(capacity: count * 2)
        for index in 0..<count {
            let t = Double(index) / sampleRate
            let value = Int16(max(-1, min(1, sample(t, Double(index) / Double(count)))) * Double(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        header.append("RIFF".data(using: .ascii)!); append(UInt32(36 + pcm.count))
        header.append("WAVEfmt ".data(using: .ascii)!); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        header.append("data".data(using: .ascii)!); append(UInt32(pcm.count))
        return header + pcm
    }
}
