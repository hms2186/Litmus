//
//  EngineFeedbackView.swift
//  The feedback panel for topics graded by the architecture v4.0 engine. What it shows is decided by
//  the attempt state and EvaluationOutcome.visibleLists, never worked out here.
//

import SwiftUI

struct EngineFeedbackView: View {
    @ObservedObject var model: FeedbackViewModel
    let onAnswer: () -> Void
    let onNext: () -> Void
    let onHints: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusChip
            if model.isEvaluating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking your explanation on device…")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            } else {
                content
            }
            buttons
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 620)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.65)))
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        )
    }

    // MARK: Status

    private var status: (title: String, icon: String, color: Color) {
        switch model.machine.state {
        case .ready, .grading: return ("Checking", "hourglass", .gray)
        case .reprompt: return ("Say a bit more", "mic.fill", .gray)
        case .awaitingFollowUp: return ("One more question", "questionmark.bubble.fill", .blue)
        case .correcting: return ("Needs correction", "lightbulb.fill", .purple)
        case .offTopic: return ("Different topic", "arrow.uturn.left.circle.fill", .gray)
        case .blocked: return ("Let's refocus", "arrow.uturn.left.circle.fill", .gray)
        case .finished(let outcome):
            switch outcome {
            case .mastered: return ("Mastered", "checkmark.seal.fill", .green)
            case .likelyMastered: return ("Likely mastered", "checkmark.seal", .teal)
            case .partial(let almostThere): return (almostThere ? "Almost there" : "Partly there", "circle.lefthalf.filled", .orange)
            case .notYet: return ("Not yet", "arrow.counterclockwise.circle.fill", .red)
            default: return ("Can't check this", "exclamationmark.circle", .gray)
            }
        }
    }

    private var statusChip: some View {
        Label(status.title, systemImage: status.icon)
            .font(.caption.bold())
            .foregroundColor(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.15), in: Capsule())
    }

    // MARK: Lists

    @ViewBuilder
    private var content: some View {
        let report = model.decision?.report
        let visible = Set(model.decision?.outcome.visibleLists ?? [])
        VStack(alignment: .leading, spacing: 14) {
            switch model.machine.state {
            case .reprompt, .offTopic, .blocked, .ready, .grading:
                Text(model.radioPrompt)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            case .awaitingFollowUp, .correcting, .finished:
                if let report {
                    if visible.contains(.corrections) {
                        row("lightbulb.fill", .purple, "Let's fix: ", report.corrections)
                        row("checkmark.circle.fill", .green, "You fixed this: ", report.fixedByStudent)
                    }
                    if visible.contains(.right) { row("checkmark.square.fill", .green, "What you got right: ", report.right) }
                    if visible.contains(.missing) { row("xmark.square.fill", .red, "What was missing: ", report.missing) }
                    if visible.contains(.vague) { row("exclamationmark.triangle.fill", .orange, "What was vague: ", report.vague) }
                    if visible.contains(.conflicts) { row("arrow.left.arrow.right", .yellow, "These points disagree: ", report.conflicts) }
                    if let question = report.followUp {
                        row("questionmark.bubble.fill", .blue, "Next question: ", [question])
                    }
                }
                if case .finished(.likelyMastered) = model.machine.state {
                    Text("This is saved as provisional and will be double-checked later.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ icon: String, _ color: Color, _ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 18))
                    .padding(.top, 2)
                (Text(title).bold() + Text(items.count == 1 ? items[0] : items.map { "• " + $0 }.joined(separator: "\n")))
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 16) {
            Spacer()
            switch model.machine.state {
            case .awaitingFollowUp:
                pill("Answer", primary: true, action: onAnswer)
                pill("Start over", primary: false, action: onStartOver)
            case .correcting:
                pill("Try again", primary: true, action: onAnswer)
                pill("Get hints", primary: false, action: onHints)
            case .finished(let outcome) where outcome.canAdvance:
                pill("Next concept", primary: true, action: onNext)
                pill("Try again", primary: false, action: onStartOver)
            case .finished:
                pill("Try again", primary: true, action: onStartOver)
                pill("Get hints", primary: false, action: onHints)
            case .grading:
                EmptyView()
            default:
                pill("Try again", primary: true, action: onAnswer)
            }
            Spacer()
        }
    }

    private func pill(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .frame(width: 140, height: 44)
                .background(primary ? Color.blue : Color.white.opacity(0.3))
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.f1Spring)
        .disabled(model.isEvaluating)
    }
}
