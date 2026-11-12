//
//  F1CircuitOutline.swift
//  The circuit from the Figma "Circuit" frame as a few points along its centre line, in a unit box, for the places that draw
//  it small: the Live Activity. The app's own timer screen uses the full trace. Part of both targets.
//

import CoreGraphics

enum F1CircuitOutline {
    /// Along the lap, from the start/finish line: sector 1 (red), sector 2 (blue), sector 3 (yellow)
    static let points: [CGPoint] = [
        CGPoint(x: 0.1715, y: 0.7789),
        CGPoint(x: 0.0469, y: 0.9129),
        CGPoint(x: 0.0085, y: 0.9497),
        CGPoint(x: 0.0522, y: 0.7571),
        CGPoint(x: 0.1193, y: 0.6231),
        CGPoint(x: 0.2013, y: 0.4640),
        CGPoint(x: 0.2780, y: 0.3970),
        CGPoint(x: 0.3770, y: 0.2714),
        CGPoint(x: 0.5687, y: 0.1290),
        CGPoint(x: 0.7551, y: 0.0000),
        CGPoint(x: 0.8083, y: 0.0419),
        CGPoint(x: 0.8882, y: 0.0151),
        CGPoint(x: 0.9894, y: 0.1792),
        CGPoint(x: 0.9734, y: 0.2630),
        CGPoint(x: 0.8935, y: 0.1658),
        CGPoint(x: 0.7284, y: 0.2379),
        CGPoint(x: 0.6379, y: 0.3719),
        CGPoint(x: 0.6858, y: 0.5059),
        CGPoint(x: 0.8190, y: 0.5678),
        CGPoint(x: 0.8722, y: 0.6650),
        CGPoint(x: 0.9201, y: 0.7739),
        CGPoint(x: 0.9925, y: 0.8660),
        CGPoint(x: 0.9521, y: 0.9799),
        CGPoint(x: 0.8509, y: 0.9749),
        CGPoint(x: 0.7284, y: 0.8241),
        CGPoint(x: 0.6379, y: 0.6516),
        CGPoint(x: 0.5261, y: 0.5946),
        CGPoint(x: 0.4196, y: 0.6650),
        CGPoint(x: 0.3291, y: 0.7203),
        CGPoint(x: 0.2460, y: 0.7353),
        CGPoint(x: 0.2300, y: 0.7052)
    ]
    /// Index of the point where sector 1 ends, and where sector 2 ends
    static let sector1End = 8
    static let sector2End = 21
    /// Width over height
    static let aspect: CGFloat = 1.5729
}
