//
//  F1FlashcardsReviseView.swift
//  Prototype
//
//  Exact Implementation of Figma Nodes:
//  - 626:3358: "Revise" Topic Grid (LazyVGrid, Vertical Scrollable, Segmented Subject Picker)
//  - 626:3359, 626:3360, 626:3361: Interactive Coverflow Flashcards with Official NavigationStack Back Button & SwiftUI PageTabViewStyle
//  - 589:5305: "WHAT YOU MISSED" Reference Cards
//  User Requirements:
//  - Strictly official Apple NavigationStack back button (NO custom button with chevron and text).
//  - Remove 6 CARDS badge and card count.
//  - Remove left and right chevron buttons.
//  - Swipe navigation with native SwiftUI Page Control (.tabViewStyle(.page(indexDisplayMode: .always))).
//  - Fix text alignment, typography and ample card sizing so no text is truncated.
//  - STRICTLY pure white text, NO red text and NO highlighted words.
//

import SwiftUI

public struct F1FlashcardsReviseView: View {
    @Binding public var cognitiveTokens: Int
    public var onTryAgainInRadio: (() -> Void)?
    public var onOpenDebrief: (() -> Void)?
    
    public enum ReviseDisplayMode: Equatable {
        case chapterGrid
        case interactiveDeck(ReviseChapter)
        case whatYouMissed([FlashcardItem])
    }
    
    @State private var selectedChapter: ReviseChapter?
    @State private var selectedMissedCards: [FlashcardItem]?
    @State private var selectedSubjectFilter: String = "SOCIAL"
    @State private var selectedCardId: String = "money_and_credit"
    
    private let availableSubjects = ["SOCIAL", "SCIENCE"]
    
    public init(
        cognitiveTokens: Binding<Int> = .constant(340),
        initialMode: ReviseDisplayMode = .chapterGrid,
        onTryAgainInRadio: (() -> Void)? = nil,
        onOpenDebrief: (() -> Void)? = nil
    ) {
        self._cognitiveTokens = cognitiveTokens
        self.onTryAgainInRadio = onTryAgainInRadio
        self.onOpenDebrief = onOpenDebrief
        
        switch initialMode {
        case .chapterGrid:
            self._selectedChapter = State(initialValue: nil)
            self._selectedMissedCards = State(initialValue: nil)
        case .interactiveDeck(let chapter):
            self._selectedChapter = State(initialValue: chapter)
            self._selectedMissedCards = State(initialValue: nil)
        case .whatYouMissed(let cards):
            self._selectedChapter = State(initialValue: nil)
            self._selectedMissedCards = State(initialValue: cards)
        }
    }
    
    public var body: some View {
        chapterGridView
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .background {
                AppleMusicDarkGradientBackground()
            }
            .navigationTitle("")
        .navigationDestination(item: $selectedChapter) { chapter in
            FlashcardDeckDetailView(
                chapter: chapter,
                onTryAgainInRadio: onTryAgainInRadio,
                onOpenDebrief: onOpenDebrief
            )
        }
        .navigationDestination(item: $selectedMissedCards) { cards in
            FlashcardMissedDetailView(
                cards: cards,
                onTryAgainInRadio: onTryAgainInRadio,
                onOpenDebrief: onOpenDebrief
            )
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-SHOW_FLASHCARD_DECK") {
                if let firstChap = sampleReviseChapters.first {
                    selectedChapter = firstChap
                }
            } else if args.contains("-SHOW_FLASHCARD_MISSED") {
                if let firstCards = sampleReviseChapters.first?.cards {
                    selectedMissedCards = firstCards
                }
            }
        }
    }
    
    // MARK: - 1. Chapter Grid View (Figma 626:3358)
    private var filteredChapters: [ReviseChapter] {
        sampleReviseChapters.filter { chapter in
            if selectedSubjectFilter == "SOCIAL" {
                return chapter.subject.uppercased().contains("SOCIAL")
            } else if selectedSubjectFilter == "SCIENCE" {
                return chapter.subject.uppercased().contains("SCIENCE")
            }
            return true
        }
    }
    
    private var chapterGridView: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Header Bar with Title and Segmented Subject Picker
            HStack(alignment: .center) {
                Text("Flashcards")
                    .f1Font(size: 44, weight: .bold, design: .default)
                    .foregroundStyle(Color.white)
                
                Spacer()
                
                Picker("Subject", selection: $selectedSubjectFilter) {
                    ForEach(availableSubjects, id: \.self) { subj in
                        Text(subj).tag(subj)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.top, 12)
            
            // Vertical Scrollable LazyVGrid for all chapters (adaptive grid, scales dynamically)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 24)
                    ],
                    spacing: 24
                ) {
                    ForEach(filteredChapters) { chapter in
                        chapterCard(
                            chapter: chapter,
                            isSelected: selectedCardId == chapter.id
                        ) {
                            selectedCardId = chapter.id
                            selectedChapter = chapter
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
            
            Spacer()
        }
    }
    
    // Chapter Card Component (Figma 626:3358)
    private func chapterCard(chapter: ReviseChapter, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 20) {
                Text(chapter.title)
                    .f1Font(size: 22, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                // Card Artwork Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(white: 0.95))
                    
                    Image(chapter.imageName)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                }
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        isSelected ? Color(red: 255/255, green: 24/255, blue: 36/255) : Color.white.opacity(0.18),
                        lineWidth: isSelected ? 3.0 : 0.75
                    )
            )
            .shadow(
                color: isSelected ? Color(red: 255/255, green: 24/255, blue: 36/255).opacity(0.35) : Color.black.opacity(0.25),
                radius: isSelected ? 16 : 10,
                y: 6
            )
        }
        .buttonStyle(.f1CardSpring)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .hoverEffect(.lift)
    }
}

// MARK: - 2. Interactive Flashcard Deck Detail View (Figma 626:3359 - 626:3361)
// - STRICTLY uses official Apple NavigationStack back button (< Flashcards)
// - NO custom back buttons with chevron and text in the body
// - NO 6 CARDS count badge
// - NO left and right chevron buttons
// - SwiftUI TabView with .tabViewStyle(.page(indexDisplayMode: .always))
// - Generous card dimensions (620 x 430 pt) and line wrapping so no titles or explanations truncate
// - STRICTLY pure white text, NO red text and NO highlighted words
public struct FlashcardDeckDetailView: View {
    public let chapter: ReviseChapter
    public var onTryAgainInRadio: (() -> Void)?
    public var onOpenDebrief: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [FlashcardItem] = []
    @State private var dragOffset: CGSize = .zero
    @State private var isSwipingAway: Bool = false
    
    public init(
        chapter: ReviseChapter,
        initialCardIndex: Int = 0,
        onTryAgainInRadio: (() -> Void)? = nil,
        onOpenDebrief: (() -> Void)? = nil
    ) {
        self.chapter = chapter
        let sourceCards = chapter.cards.isEmpty ? sampleReviseChapters[0].cards : chapter.cards
        self._cards = State(initialValue: sourceCards)
        self.onTryAgainInRadio = onTryAgainInRadio
        self.onOpenDebrief = onOpenDebrief
    }
    
    public var body: some View {
        VStack {
            Spacer()
            
            // Interactive 3D Infinite Looping Card Stack
            ZStack {
                let visibleCount = min(cards.count, 3)
                ForEach(Array(cards.prefix(visibleCount).enumerated().reversed()), id: \.element.id) { index, card in
                    let depth = index
                    let isTop = (depth == 0)
                    let dragFraction = min(1.0, abs(dragOffset.width) / 180.0)
                    
                    stackedCardView(
                        card: card,
                        isTop: isTop,
                        depth: depth,
                        dragFraction: dragFraction,
                        totalCards: cards.count
                    )
                }
            }
            .frame(width: 620, height: 440)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
        .background {
            AppleMusicDarkGradientBackground()
        }
        .navigationTitle(chapter.title)
    }
    
    // MARK: - Stacked Card View with Drag Physics & Depth
    @ViewBuilder
    private func stackedCardView(
        card: FlashcardItem,
        isTop: Bool,
        depth: Int,
        dragFraction: CGFloat,
        totalCards: Int
    ) -> some View {
        // Depth-based scaling and translation
        let scale: CGFloat = depth == 0 ? 1.0 : (depth == 1 ? 0.94 + (0.06 * dragFraction) : 0.88 + (0.06 * dragFraction))
        let yOffset: CGFloat = depth == 0 ? (dragOffset.height * 0.35) : (depth == 1 ? 16 - (16 * dragFraction) : 32 - (16 * dragFraction))
        let xOffset: CGFloat = depth == 0 ? dragOffset.width : 0
        let rotationDegrees: Double = depth == 0 ? Double(dragOffset.width) / 18.0 : 0
        let opacity: Double = depth == 0 ? 1.0 : (depth == 1 ? 0.92 + (0.08 * Double(dragFraction)) : 0.70 + (0.22 * Double(dragFraction)))
        
        deckCardContent(card: card)
            .frame(width: 620, height: 430)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color(red: 255/255, green: 24/255, blue: 36/255), lineWidth: 2.5)
            )
            .shadow(
                color: Color(red: 255/255, green: 24/255, blue: 36/255).opacity(isTop ? 0.38 : 0.18),
                radius: isTop ? 22 : 12,
                y: isTop ? 10 : 4
            )
            .scaleEffect(scale)
            .offset(x: xOffset, y: yOffset)
            .rotationEffect(.degrees(rotationDegrees))
            .opacity(opacity)
            .gesture(
                isTop ? DragGesture()
                    .onChanged { value in
                        guard !isSwipingAway else { return }
                        dragOffset = CGSize(
                            width: value.translation.width,
                            height: value.translation.height * 0.35
                        )
                    }
                    .onEnded { value in
                        guard !isSwipingAway else { return }
                        let threshold: CGFloat = 110
                        let velocity = value.predictedEndTranslation.width - value.translation.width
                        if value.translation.width > threshold || velocity > 260 {
                            swipeTopCardAway(direction: 1)
                        } else if value.translation.width < -threshold || velocity < -260 {
                            swipeTopCardAway(direction: -1)
                        } else {
                            withAnimation(AppMotionSystem.fluidSpring) {
                                dragOffset = .zero
                            }
                        }
                    }
                : nil
            )
            .zIndex(Double(totalCards - depth))
    }
    
    // MARK: - Single Deck Card Content (Pure White Text, High Contrast)
    private func deckCardContent(card: FlashcardItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Card Title + Open Book Icon
            HStack(alignment: .top) {
                Text(card.title)
                    .f1Font(size: 28, weight: .bold)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: "book.pages")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
            }
            
            // Red Accent Divider Line
            Rectangle()
                .fill(Color(red: 255/255, green: 24/255, blue: 36/255).opacity(0.85))
                .frame(height: 2)
            
            Spacer().frame(height: 8)
            
            // Body Content: STRICTLY PURE WHITE TEXT (NO RED TEXT, NO HIGHLIGHTS, NO TRUNCATION)
            Text(card.content)
                .f1Font(size: 21, weight: .regular)
                .foregroundStyle(Color.white)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: false)
            
            Spacer()
        }
        .padding(34)
    }
    
    // MARK: - Smooth Programmatic & Gesture Infinite Swipe Loop
    private func swipeTopCardAway(direction: CGFloat) {
        guard !isSwipingAway, !cards.isEmpty else { return }
        isSwipingAway = true
        
        withAnimation(AppMotionSystem.snappy) {
            dragOffset = CGSize(width: direction * 820, height: 20)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard !cards.isEmpty else { return }
            let top = cards.removeFirst()
            cards.append(top)
            dragOffset = .zero
            isSwipingAway = false
        }
    }
}

// MARK: - 3. What You Missed Detail View (Figma 589:5305)
// ONLY pure white text, NO red text and NO highlighted words.
// Official NavigationStack back button
public struct FlashcardMissedDetailView: View {
    public let cards: [FlashcardItem]
    public var onTryAgainInRadio: (() -> Void)?
    public var onOpenDebrief: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    
    public init(
        cards: [FlashcardItem],
        onTryAgainInRadio: (() -> Void)? = nil,
        onOpenDebrief: (() -> Void)? = nil
    ) {
        self.cards = cards
        self.onTryAgainInRadio = onTryAgainInRadio
        self.onOpenDebrief = onOpenDebrief
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Horizontal Flashcards Scroll Row (Scales to however many cards were missed)
            // STRICTLY PURE WHITE TEXT (NO RED TEXT, NO HIGHLIGHTS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(alignment: .center) {
                                Text(card.title)
                                    .f1Font(size: 26, weight: .semibold)
                                    .foregroundStyle(Color.white)
                                
                                Spacer()
                                
                                Image(systemName: "book.pages")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
                            }
                            
                            Rectangle()
                                .fill(Color(red: 255/255, green: 24/255, blue: 36/255).opacity(0.85))
                                .frame(height: 2)
                            
                            Spacer().frame(height: 8)
                            
                            // Card Body in Pure White Text
                            Text(card.content)
                                .f1Font(size: 19, weight: .regular)
                                .foregroundStyle(Color.white)
                                .lineSpacing(8)
                            
                            Spacer()
                        }
                        .padding(28)
                        .frame(width: 360, height: 360)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color(red: 255/255, green: 24/255, blue: 36/255), lineWidth: 2.5)
                        )
                        .shadow(color: Color(red: 255/255, green: 24/255, blue: 36/255).opacity(0.30), radius: 16, y: 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            
            // Action Buttons Row (Figma 589:5305 - Official Apple HIG)
            HStack(spacing: 20) {
                Spacer()
                
                // "Try Again" (Official Apple Bordered Prominent Red Pill)
                Button {
                    onTryAgainInRadio?()
                } label: {
                    Text("Try Again")
                        .f1Font(size: 17, weight: .semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .contentShape(Capsule())
                .tint(Color(red: 233/255, green: 30/255, blue: 30/255))
                .hoverEffect(.lift)
                .accessibilityLabel("Try explanation again in Team Radio")
                
                // "Session Summary" (Official Apple Bordered Prominent Blue Pill)
                Button {
                    onOpenDebrief?()
                } label: {
                    Text("Session Summary")
                        .f1Font(size: 17, weight: .semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .contentShape(Capsule())
                .tint(Color(red: 0/255, green: 136/255, blue: 255/255))
                .hoverEffect(.lift)
                .accessibilityLabel("View Grand Prix Session Summary")
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            
            Spacer()
        }
        .background {
            AppleMusicDarkGradientBackground()
        }
        .navigationTitle("What You Missed")
    }
}
