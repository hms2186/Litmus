//
//  HintsView.swift
//  Prototype
//
//  Exact Implementation of Figma Node 1264:2792 ("feynman Screen 5" - Hints 3D Carousel).
//  Follows Apple HIG for iPadOS 18 with fluid swipeable carousel, neon orange active card highlight,
//  and native capsule actions.
//

import SwiftUI

public struct HintCard: Identifiable, Equatable {
    public let id: Int
    public let title: String
    public let bodyText: String
    public let indexLabel: String
    public let keywords: [String]
    
    public init(id: Int, title: String, bodyText: String, indexLabel: String, keywords: [String] = []) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.indexLabel = indexLabel
        self.keywords = keywords
    }
}

/// Builds the hint cards. The follow-up question, what was missing or vague and what was right are
/// shown on the debrief screen; this page holds only hints: the concept's own hint, plus the nudge
/// questions for the key points that were not yet explained.
enum HintCardBuilder {
    static func cards(state: AttemptState, concept: CompiledConcept?, decision: Decision?, fallback: [HintCard] = [], keywords: [String] = []) -> [HintCard] {
        guard let concept else { return fallback }
        var hints: [String] = [concept.hint]
        let asked = decision?.report.followUp
        for keyPoint in concept.keyPoints {
            guard let nudge = keyPoint.followUp, nudge != asked, !hints.contains(nudge),
                  let outcome = decision?.keyPointOutcomes[keyPoint.id], outcome != .pass else { continue }
            hints.append(nudge)
        }
        let texts = hints.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let final = texts.isEmpty ? [concept.probe] : texts
        return final.prefix(5).enumerated().map { index, text in
            HintCard(id: index, title: "Hint \(index + 1)", bodyText: text, indexLabel: "\(index + 1)/\(min(final.count, 5))", keywords: keywords)
        }
    }
}

public struct HintsView: View {
    public var coinBalance: Int
    public var hintCards: [HintCard]
    public var onTryAgain: () -> Void
    public var onSessionSummary: () -> Void

    @State private var activeIndex: Int = 0
    @State private var rootWidth: CGFloat = 1194

    public init(
        hintCards: [HintCard],
        coinBalance: Int = 7,
        onTryAgain: @escaping () -> Void,
        onSessionSummary: @escaping () -> Void
    ) {
        self.hintCards = hintCards
        self.coinBalance = coinBalance
        self.onTryAgain = onTryAgain
        self.onSessionSummary = onSessionSummary
    }

    
    public var body: some View {
        ZStack {
            // Authentic F1 Pit Wall Atmosphere Background
            Color.black
                .ignoresSafeArea()
            
            Image("race_engineer_workspace_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            
            // The engineer points at the cards from the bottom right (Figma "Hints")
            GeometryReader { geo in
                Image("engineer_hints")
                    .resizable()
                    .scaledToFit()
                    .frame(height: geo.size.height * 0.58)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: geo.size.width * 0.037)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // Main Overlay Content: one left column, so the title, cards and buttons share a centre line
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Hints")
                        .scaledFont(size: 52, weight: .bold)
                        .foregroundStyle(Color.white)
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                        .shadow(color: Color(red: 255/255, green: 197/255, blue: 89/255).opacity(0.6), radius: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The same place as the Topic heading on the other Explain screens
                .padding(.leading, 28)
                // The larger title is centred on the line the Topic heading (34 pt, top 70) sits on
                .padding(.top, 60)

                Spacer(minLength: 20)

                // 3D Horizontal Carousel (Figma 1264:2792)
                carouselCardsView
                    .frame(height: 440)

                Spacer(minLength: 20)

                HStack(spacing: 20) {
                    Button(action: onTryAgain) {
                        Text("Try again")
                            .scaledFont(size: 17, weight: .semibold)
                            .frame(width: 170, height: 48)
                    }
                    .litmusProminentGlassButton()
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(AppTheme.accent)

                    Button(action: onSessionSummary) {
                        Text("Session Summary")
                            .scaledFont(size: 17, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(width: 170, height: 48)
                    }
                    .litmusGlassButton()
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
                .padding(.bottom, 64)
            }
            .frame(width: rootWidth * 0.66)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onSettledWidth { width in rootWidth = width }
    }
    
    // MARK: - Carousel Cards View
    private var carouselCardsView: some View {
        DeckCarousel(
            cards: hintCards.map { FlashcardCard(id: "\($0.id)", title: $0.title, body: $0.bodyText, imageName: nil, pitfall: nil, keywords: $0.keywords) },
            index: $activeIndex,
            size: CGSize(width: 450, height: 380),
            showsEnlarge: false
        )
    }
}
