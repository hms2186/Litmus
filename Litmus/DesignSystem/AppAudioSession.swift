//
//  AppAudioSession.swift
//  Changes the shared audio session off the main thread. AVAudioSession's setCategory and setActive can block for a
//  moment, and on the main thread that is a hang risk and a stutter in the UI, so every part of the app goes through here.
//

import AVFoundation

enum AppAudioSession {
    enum Mode: Sendable {
        /// Short effects that follow the silent switch and mix with other audio.
        case ambient
        /// Spoken lines and narration.
        case playback
        /// Recording the learner's voice, with the speaker as output.
        case record
    }

    /// Applies the session settings; safe to call from any thread, but blocks the caller, so never from the main thread.
    nonisolated static func applyBlocking(_ mode: Mode) throws {
        let session = AVAudioSession.sharedInstance()
        switch mode {
        case .ambient:
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        case .playback:
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try session.setActive(true)
        case .record:
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        }
    }

    /// The same, off the main thread. Throws what the session throws.
    static func apply(_ mode: Mode) async throws {
        try await Task.detached(priority: .userInitiated) { try applyBlocking(mode) }.value
    }
}
