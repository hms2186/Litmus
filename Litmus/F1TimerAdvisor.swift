//
//  F1TimerAdvisor.swift
//  Recommends a timer length for a topic. The estimate comes from how much there is to explain: the
//  number of core ideas, the length of the topic's text and its common mistakes, then it is rounded to
//  the nearest timer on offer. It is a starting point; the student can pick any timer.
//

import Foundation

public struct F1TimerRecommendation: Equatable {
    public let minutes: Int
    public let note: String

    public init(minutes: Int, note: String) {
        self.minutes = minutes
        self.note = note
    }
}

@MainActor
enum F1TimerAdvisor {
    static let presets = [15, 25, 45, 60, 80]

    static func recommend(for topic: NCERTTopic) -> F1TimerRecommendation {
        let estimate: Double
        let note: String
        if let concept = CompiledCurriculumStore.shared.entry(forLabel: topic.title)?.concept {
            let core = concept.keyPoints.filter { $0.role == .core }.count
            let words = concept.cardText.split(whereSeparator: \.isWhitespace).count
            estimate = 8 + 5 * Double(core) + Double(words) / 30 + 2 * Double(concept.misconceptions.count)
            note = "\(core) core idea\(core == 1 ? "" : "s") to explain"
        } else {
            let groups = topic.ib.groups.count + topic.parakh.groups.count
            let words = (topic.coreIdeaIB + " " + topic.causeEffectParakh + " " + topic.samplePassAnswer)
                .split(whereSeparator: \.isWhitespace).count
            estimate = 10 + 4 * Double(groups) + Double(words) / 20
            note = "about \(max(groups, 1)) ideas to cover"
        }
        // Spread the estimate over the whole range of timers: across the curriculum it runs from about
        // 14 (a short single idea) to about 47 (a long topic with many ideas), so 14 maps to the shortest
        // timer and 47 to the longest.
        let minutes = min(90, max(10, 15 + (estimate - 14) * 1.97))
        let nearest = presets.min { abs(Double($0) - minutes) < abs(Double($1) - minutes) } ?? 25
        return F1TimerRecommendation(minutes: nearest, note: note)
    }
}
