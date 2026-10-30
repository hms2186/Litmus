//
//  F1HintsCarouselView.swift
//  Prototype
//
//  Exact Implementation of Figma Node 1264:2792 ("feynman Screen 5" - Hints 3D Carousel).
//  Follows Apple HIG for iPadOS 18 with fluid swipeable carousel, neon orange active card highlight,
//  and native capsule actions.
//

import SwiftUI

public struct F1HintCardItem: Identifiable, Equatable {
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
enum F1HintCardBuilder {
    static func cards(state: AttemptState, concept: CompiledConcept?, decision: Decision?, fallback: [F1HintCardItem] = [], keywords: [String] = []) -> [F1HintCardItem] {
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
            F1HintCardItem(id: index, title: "Hint \(index + 1)", bodyText: text, indexLabel: "\(index + 1)/\(min(final.count, 5))", keywords: keywords)
        }
    }
}

public struct F1HintsCarouselView: View {
    public var coinBalance: Int
    public var hintCards: [F1HintCardItem]
    public var onTryAgain: () -> Void
    public var onSessionSummary: () -> Void

    @State private var activeIndex: Int = 0
    @State private var rootWidth: CGFloat = 1194

    public init(
        hintCards: [F1HintCardItem],
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

            // Main Overlay Content
            VStack(spacing: 0) {
                // Top Header Row: Hints Title (Left) + Coin Badge (Right)
                HStack(alignment: .center) {
                    HStack(spacing: 12) {
                        Text("Hints")
                            .f1Font(size: 52, weight: .bold)
                            .foregroundStyle(Color.white)
                        
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                            .shadow(color: Color(red: 255/255, green: 197/255, blue: 89/255).opacity(0.6), radius: 14)
                    }
                    .padding(.leading, 40)
                    
                    Spacer()
                    
                    coinBadge(count: coinBalance)
                        .padding(.trailing, 40)
                }
                .padding(.top, 88)
                
                Spacer(minLength: 20)
                
                // 3D Horizontal Carousel (Figma 1264:2792)
                carouselCardsView
                    .frame(height: 440)
                        .offset(x: -rootWidth * 0.066)
                
                Spacer(minLength: 20)
                
                // Bottom Action Buttons Row (Figma 1264:2792)
                HStack(spacing: 24) {
                    Button(action: onTryAgain) {
                        Text("Try again")
                            .f1Font(size: 17, weight: .semibold)
                            .frame(width: 140, height: 48)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(Color(red: 0/255, green: 145/255, blue: 255/255))
                    .contentShape(Capsule())
                    .hoverEffect(.lift)
                    
                    Button(action: onSessionSummary) {
                        Text("Session Summary")
                            .f1Font(size: 17, weight: .semibold)
                            .frame(width: 160, height: 48)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(Color(red: 0/255, green: 145/255, blue: 255/255))
                    .contentShape(Capsule())
                    .hoverEffect(.lift)
                }
                .offset(x: -rootWidth * 0.16)
                .padding(.bottom, 48)
            }
        }
        .onSettledWidth { width in rootWidth = width }
    }
    
    // MARK: - Carousel Cards View
    private var carouselCardsView: some View {
        F1DeckCarousel(
            cards: hintCards.map { F1DeckCard(id: "\($0.id)", title: $0.title, body: $0.bodyText, imageName: nil, pitfall: nil, keywords: $0.keywords) },
            index: $activeIndex,
            size: CGSize(width: 450, height: 380)
        )
    }
    
    // MARK: - Coin Badge Helper
    private func coinBadge(count: Int) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(red: 188/255, green: 144/255, blue: 62/255),
                                Color(red: 217/255, green: 188/255, blue: 114/255),
                                Color(red: 255/255, green: 197/255, blue: 89/255),
                                Color(red: 175/255, green: 126/255, blue: 29/255),
                                Color(red: 188/255, green: 144/255, blue: 62/255)
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Circle()
                    .fill(Color(red: 176/255, green: 119/255, blue: 13/255))
                    .frame(width: 28, height: 28)
                
                Text("$")
                    .f1Font(size: 18, weight: .bold)
                    .foregroundStyle(Color(red: 203/255, green: 167/255, blue: 89/255))
            }
            
            Text("\(count)")
                .f1Font(size: 22, weight: .bold)
                .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
    }
}
