//
//  LoopingPlayerView.swift
//  Prototype
//

import SwiftUI
import AVKit

public struct LoopingPlayerView: View {
    public var videoName: String
    public var videoExtension: String
    /// Seconds of the clip to loop, when only part of it is usable.
    public var playRange: ClosedRange<Double>?
    /// The clip has an alpha channel (HEVC with alpha): draw it on a clear layer, not in the player's black box.
    public var transparent: Bool

    @State private var player: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?

    public init(videoName: String, videoExtension: String = "mov", playRange: ClosedRange<Double>? = nil, transparent: Bool = false) {
        self.transparent = transparent
        self.videoName = videoName
        self.videoExtension = videoExtension
        self.playRange = playRange
    }

    public var body: some View {
        Group {
            if let player = player, transparent {
                ClearPlayerLayer(player: player)
                    .allowsHitTesting(false)
            } else if let player = player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .allowsHitTesting(false)
            } else {
                Color.clear
            }
        }
        .onAppear {
            // Back on screen: carry on, or load for the first time
            if let player { player.play() } else { loadPlayer() }
        }
        // Off screen (another tab, a pushed screen): stop decoding, which saves battery and heat
        .onDisappear { player?.pause() }
        .onChange(of: videoName) { _ in
            loadPlayer()
        }
    }

    private func loadPlayer() {
        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension)
            ?? Bundle.main.url(forResource: videoName, withExtension: "mp4")
            ?? Bundle.main.url(forResource: videoName, withExtension: "mov") else { return }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        if let range = playRange {
            let timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                                        end: CMTime(seconds: range.upperBound, preferredTimescale: 600))
            self.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item, timeRange: timeRange)
        } else {
            self.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        }
        queuePlayer.isMuted = true
        queuePlayer.play()
        self.player = queuePlayer
    }
}

/// A bare `AVPlayerLayer` on a clear view, so a clip with transparency shows what is behind it.
private struct ClearPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
