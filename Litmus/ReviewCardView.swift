//
//  ReviewCardView.swift
//  Shown before a new answer when a background re-grade found a problem with a saved Likely mastered
//  answer (v3.2): the student's own words and the date, then what to fix. Framed as a review, not a
//  failure. Dismissing it deletes the stored transcript.
//

import SwiftUI

struct ReviewCardView: View {
    let card: ReviewCardInfo
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Let's revisit this", systemImage: "arrow.counterclockwise.circle.fill")
                .font(.caption.bold())
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.15), in: Capsule())

            Text("What you said on \(card.answeredOn.formatted(date: .abbreviated, time: .omitted)):")
                .font(.subheadline.bold())
                .foregroundColor(.white)
            Text("“\(card.transcripts.joined(separator: " "))”")
                .font(.subheadline.italic())
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if !card.notes.isEmpty {
                Text("Looking at it again:")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                ForEach(card.notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill").foregroundColor(.yellow)
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text("Got it, let me try")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.f1Spring)
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: 620)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.65)))
        )
    }
}
