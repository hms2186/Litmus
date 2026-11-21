//
//  EngineerAvatarView.swift
//  Litmus
//
//  The race engineer as a live character. Nothing here is a video: he is driven by what the student is doing (the
//  `EngineerPose`) and by the app's inputs (`isSpeaking`, Reduce Motion), and animates in
//  real time.
//
//  How it is built (nothing is redrawn - every pixel is the approved artwork):
//    * One still per pose in the asset catalog. All share one 1086x1448 canvas, so a pose change is a short cross-fade.
//    * He is ONE picture that breathes and sways very gently. (Splitting him into separately moving head and body layers made
//      the neck seam and hair edge shimmer, so he is not split.) Motion eases in when the screen appears, and the images are
//      decoded before they are first drawn, so he never jerks while the screen is still settling.
//    * Eyelids are drawn on the eyes in the skin colour measured from the art, so he blinks at natural, irregular times,
//      sometimes twice in a row.
//    * Reduce Motion (the app's switch or the system's) freezes everything but the pose cross-fade.
//

import SwiftUI
import UIKit

/// What the engineer is doing. One per still in the asset catalog.
enum EngineerPose: Equatable {
    /// Waiting at the desk, headset round his neck.
    case idle
    /// Headset on, listening to the student (or thinking about the answer).
    case listening
    /// The explanation needs a correction: a puzzled "hmm".
    case needsCorrection
    /// The student got it: thumbs up.
    case mastered

    fileprivate var assetName: String {
        switch self {
        case .idle: return "race_engineer"
        case .listening: return "engineer_listening"
        case .needsCorrection: return "engineer_confused"
        case .mastered: return "engineer_success"
        }
    }

    /// Where the eyes are in the 1086x1448 artwork, measured from the stills.
    fileprivate var eyes: [EngineerEye] {
        switch self {
        case .idle:
            return [EngineerEye(x: 488, y: 365, w: 64, h: 46, tilt: 9.8, skin: Color(red: 0.942, green: 0.643, blue: 0.473)),
                    EngineerEye(x: 609, y: 386, w: 64, h: 46, tilt: 9.8, skin: Color(red: 0.965, green: 0.676, blue: 0.508))]
        case .listening:
            return [EngineerEye(x: 536, y: 455, w: 72, h: 54, tilt: 14.5, skin: Color(red: 0.949, green: 0.644, blue: 0.468)),
                    EngineerEye(x: 679, y: 492, w: 72, h: 54, tilt: 14.5, skin: Color(red: 0.949, green: 0.656, blue: 0.489))]
        case .needsCorrection:
            return [EngineerEye(x: 480, y: 434, w: 68, h: 50, tilt: -17.7, skin: Color(red: 0.960, green: 0.654, blue: 0.473)),
                    EngineerEye(x: 608, y: 393, w: 68, h: 50, tilt: -17.7, skin: Color(red: 0.977, green: 0.679, blue: 0.504))]
        case .mastered:
            return [EngineerEye(x: 488, y: 365, w: 64, h: 46, tilt: 9.8, skin: Color(red: 0.942, green: 0.640, blue: 0.468)),
                    EngineerEye(x: 609, y: 386, w: 64, h: 46, tilt: 9.8, skin: Color(red: 0.965, green: 0.672, blue: 0.502))]
        }
    }
}

private struct EngineerEye {
    var x: CGFloat, y: CGFloat      // centre, artwork pixels
    var w: CGFloat, h: CGFloat      // size of the open eye
    var tilt: Double                // degrees clockwise: the line through both eyes
    var skin: Color                 // eyelid colour
}

/// How the character is laid out in the space he is given.
enum EngineerLayout {
    /// The whole screen. The stills are 3:4, exactly an upright iPad, so in portrait the art covers the screen and the
    /// screen edges are its edges (the dock hides the desk cut). In landscape it fits the height and the cut sides fade out.
    case fill
    /// The whole picture, centred inside a smaller box (the result card).
    case fit
}

struct EngineerAvatarView: View {
    var pose: EngineerPose
    /// True while the engineer's voice is reading a line aloud.
    var isSpeaking: Bool = false
    var layout: EngineerLayout = .fill

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var appearedAt: TimeInterval?

    init(pose: EngineerPose, isSpeaking: Bool = false, layout: EngineerLayout = .fill) {
        self.pose = pose; self.isSpeaking = isSpeaking; self.layout = layout
        EngineerImages.warmInBackground()
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let portrait = w <= h
            let scale = (layout == .fill && !portrait) ? h / EngineerArt.height : min(w / EngineerArt.width, h / EngineerArt.height)
            let x0 = (w - EngineerArt.width * scale) / 2
            let y0 = layout == .fill ? h - EngineerArt.height * scale : (h - EngineerArt.height * scale) / 2
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let t = reduceMotion ? 0 : now
                // Motion eases in over the first second and a half on screen
                let ramp = reduceMotion ? 0 : easeIn((now - (appearedAt ?? now)) / 1.5)
                ZStack(alignment: .topLeading) {
                    // A new pose is a new view identity, so SwiftUI fades the old one out and the new one in
                    EngineerPoseLayer(pose: pose, t: t, ramp: ramp, isSpeaking: isSpeaking, still: reduceMotion)
                        .id(pose)
                        .transition(.opacity)
                }
                .frame(width: EngineerArt.width, height: EngineerArt.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: x0, y: y0)
                .frame(width: w, height: h, alignment: .topLeading)
                .mask { sideFade(w: w, x0: x0, artWidth: EngineerArt.width * scale, fade: layout == .fill && !portrait) }
            }
            .animation(.easeInOut(duration: 0.35), value: pose)
        }
        .onAppear { if appearedAt == nil { appearedAt = Date().timeIntervalSinceReferenceDate } }
        .accessibilityHidden(true)
    }

    private func easeIn(_ x: Double) -> Double { let u = max(0, min(1, x)); return u * u * (3 - 2 * u) }

    /// Where the picture is narrower than the screen its cut sides fade out instead of ending in a hard line.
    private func sideFade(w: CGFloat, x0: CGFloat, artWidth: CGFloat, fade: Bool) -> some View {
        let f = fade ? min(0.12, 90 / max(artWidth, 1)) : 0
        let l = max(0, x0 / w), r = min(1, (x0 + artWidth) / w)
        let span = r - l
        return LinearGradient(stops: fade ? [
            .init(color: .white, location: 0), .init(color: .white, location: l),
            .init(color: .white.opacity(0.0), location: l + 0.0001),
            .init(color: .white, location: l + span * f), .init(color: .white, location: r - span * f),
            .init(color: .white.opacity(0.0), location: r), .init(color: .white.opacity(0.0), location: 1)
        ] : [.init(color: .white, location: 0), .init(color: .white, location: 1)],
                              startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Images

/// The stills are large; they are decoded once, off the main thread, before the Explain screen first draws them.
@MainActor
enum EngineerImages {
    private static var cache: [String: UIImage] = [:]
    private static var warming = false
    private static let names = ["race_engineer", "engineer_listening", "engineer_confused", "engineer_success"]

    static func image(_ name: String) -> UIImage {
        if let c = cache[name] { return c }
        let img = UIImage(named: name)?.preparingForDisplay() ?? UIImage(named: name) ?? UIImage()
        cache[name] = img
        return img
    }

    static func warmInBackground() {
        guard !warming else { return }
        warming = true
        Task.detached(priority: .userInitiated) {
            let decoded: [(String, UIImage)] = names.compactMap { n in UIImage(named: n)?.preparingForDisplay().map { (n, $0) } }
            await MainActor.run { for (n, i) in decoded where cache[n] == nil { cache[n] = i } }
        }
    }
}

// MARK: - One pose

private enum EngineerArt {
    static let width: CGFloat = 1086
    static let height: CGFloat = 1448
}

private struct EngineerPoseLayer: View {
    let pose: EngineerPose
    let t: TimeInterval
    let ramp: Double
    let isSpeaking: Bool
    let still: Bool

    var body: some View {
        let m = EngineerMotion(pose: pose, t: t, ramp: ramp, speaking: isSpeaking, still: still)
        let blink = still ? (0.0, 0.0) : (EngineerBlink.amount(t, delay: 0), EngineerBlink.amount(t, delay: 0.012))
        // One piece: the picture and its eyelids move together, so there is no seam to crawl or shimmer
        ZStack(alignment: .topLeading) {
            Image(uiImage: EngineerImages.image(pose.assetName))
                .resizable()
                .frame(width: EngineerArt.width, height: EngineerArt.height)
            EngineerEyelids(imageName: pose.assetName, eyes: pose.eyes, closing: [blink.0, blink.1])
        }
        .frame(width: EngineerArt.width, height: EngineerArt.height, alignment: .topLeading)
        .modifier(EngineerMotionEffect(motion: m))
    }
}

private struct EngineerMotionEffect: ViewModifier {
    let motion: EngineerMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(motion.scale, anchor: .bottom)
            .rotationEffect(.degrees(motion.rotation), anchor: UnitPoint(x: 0.5, y: 0.62))
            .offset(x: motion.x, y: motion.y)
    }
}

// MARK: - Motion

/// How he sits at time `t`: a slow breath and a barely-there sway. Deliberately small and slow, and eased in from nothing
/// when the screen appears; big or quick movement reads as a glitch on a picture this large.
private struct EngineerMotion {
    var rotation = 0.0       // degrees about the bottom centre
    var x: CGFloat = 0       // artwork pixels
    var y: CGFloat = 0
    var scale: CGFloat = 1

    init(pose: EngineerPose, t: TimeInterval, ramp: Double, speaking: Bool, still: Bool) {
        guard !still, ramp > 0 else { return }
        let tau = 2 * Double.pi
        let breath = 0.5 + 0.5 * sin(tau * t / 4.2 - .pi / 2)
        var rot = 0.0, dx = 0.0, dy = 0.0
        switch pose {
        case .idle:
            rot = 0.34 * sin(tau * t / 9.3) + 0.16 * sin(tau * t / 5.1 + 1.1)
            dx = 2.4 * sin(tau * t / 9.3 + 0.7) + 1.0 * sin(tau * t / 6.4)
            dy = 1.6 * sin(tau * t / 7.7 + 0.4)
        case .listening:
            rot = 0.30 * sin(tau * t / 8.1) + 0.14 * sin(tau * t / 4.7 + 0.6)
            dx = 2.0 * sin(tau * t / 8.1) + 0.8 * sin(tau * t / 5.9)
            dy = 1.4 * sin(tau * t / 6.9 + 1.0)
        case .needsCorrection:
            rot = 0.35 * sin(tau * t / 5.5); dx = 2.2 * sin(tau * t / 5.5)
        case .mastered:
            rot = 0.2 * sin(tau * t / 7); dy = -2.0 * sin(tau * t / 3.5 - .pi / 2) - 2.0
        }
        if speaking { dy += 1.8 * sin(tau * t / 1.3) }          // a soft, slow nod while he talks
        scale = 1 + CGFloat(ramp) * 0.0035 * CGFloat(breath)
        rotation = rot * ramp
        x = CGFloat(dx * ramp)
        y = CGFloat(dy * ramp)
    }
}

// MARK: - Blinking

private enum EngineerBlink {
    /// 0 = open, 1 = closed. One blink (sometimes two quick ones) per 3.6 s window, at an irregular moment inside it.
    static func amount(_ t: TimeInterval, delay: TimeInterval) -> Double {
        let window = 3.6
        let t = t - delay
        let k = floor(t / window)
        let start = k * window + 0.4 + 2.4 * hash(k)
        let double = hash(k + 31) > 0.78
        return max(single(t - start), double ? single(t - start - 0.30) : 0)
    }

    /// Eyelids fall quickly, stay shut for a beat, then open a little slower: close 0.08 s, hold 0.04 s, open 0.15 s.
    private static func single(_ u: Double) -> Double {
        guard u >= 0, u < 0.27 else { return 0 }
        if u < 0.08 { let x = u / 0.08; return x * x }                                 // ease in (accelerating)
        if u < 0.12 { return 1 }
        let x = (u - 0.12) / 0.15; return 1 - (1 - (1 - x) * (1 - x))                   // ease out (decelerating)
    }

    private static func hash(_ k: Double) -> Double {
        let s = sin(k * 12.9898) * 43758.5453
        return s - floor(s)
    }
}

/// The lids live inside the outline of the eye: a curtain of skin that comes down from the top edge with a curved lower edge,
/// and a thin lash line along that edge when the eye is shut. Nothing is painted outside the eye.
private struct EngineerEyelids: View {
    let imageName: String
    let eyes: [EngineerEye]
    let closing: [Double]

    var body: some View {
        Canvas { context, _ in
            let art = context.resolve(Image(uiImage: EngineerImages.image(imageName)))
            for (eye, amount) in zip(eyes, closing) where amount > 0.03 {
                var c = context
                c.translateBy(x: eye.x, y: eye.y)
                c.rotate(by: .degrees(eye.tilt))
                let rx = eye.w / 2 * 1.17, ry = eye.h / 2 * 1.22
                let eyeShape = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
                let edgeY = -ry + 2 * ry * CGFloat(amount) * 1.06          // lower edge of the lid
                let bow = ry * 0.34 * CGFloat(min(1, amount * 1.4))        // the edge curves down in the middle
                var lid = Path()
                lid.move(to: CGPoint(x: -rx - 6, y: -ry - 6))
                lid.addLine(to: CGPoint(x: rx + 6, y: -ry - 6))
                lid.addLine(to: CGPoint(x: rx + 6, y: edgeY))
                lid.addQuadCurve(to: CGPoint(x: -rx - 6, y: edgeY), control: CGPoint(x: 0, y: edgeY + bow * 2))
                lid.closeSubpath()
                // The lid is a copy of the skin just below the eye (the cheek), so its colour, shading and grain always match the
                // face in every pose and light. A soft shade at the top gives the lid its place under the brow.
                let shift = eye.h * 1.2
                let shade = Gradient(colors: [Color.black.opacity(0.16), Color.black.opacity(0.05), Color.black.opacity(0)])
                c.drawLayer { outer in
                    outer.addFilter(.blur(radius: 2.2))
                    outer.drawLayer { layer in
                        layer.clip(to: lid)
                        layer.clip(to: eyeShape)
                        layer.drawLayer { skin in
                            skin.translateBy(x: 0, y: -shift)
                            skin.rotate(by: .degrees(-eye.tilt))
                            skin.translateBy(x: -eye.x, y: -eye.y)
                            skin.draw(art, in: CGRect(x: 0, y: 0, width: EngineerArt.width, height: EngineerArt.height))
                        }
                        layer.fill(Path(CGRect(x: -rx - 6, y: -ry - 6, width: rx * 2 + 12, height: ry * 2 + 12)),
                                   with: .linearGradient(shade, startPoint: CGPoint(x: 0, y: -ry), endPoint: CGPoint(x: 0, y: ry)))
                    }
                }
                // lash line along the curved edge, fading in as the eye closes
                if amount > 0.45 {
                    var lash = Path()
                    lash.move(to: CGPoint(x: -rx * 0.98, y: edgeY))
                    lash.addQuadCurve(to: CGPoint(x: rx * 0.98, y: edgeY), control: CGPoint(x: 0, y: edgeY + bow * 2))
                    let a = min(1, (amount - 0.45) / 0.35)
                    c.drawLayer { layer in
                        layer.addFilter(.blur(radius: 0.5))
                        layer.stroke(lash, with: .color(Color(red: 0.17, green: 0.08, blue: 0.06).opacity(0.9 * a)),
                                     style: StrokeStyle(lineWidth: max(2.2, eye.w * 0.04), lineCap: .round))
                    }
                }
            }
        }
        .frame(width: EngineerArt.width, height: EngineerArt.height)
        .allowsHitTesting(false)
    }
}
