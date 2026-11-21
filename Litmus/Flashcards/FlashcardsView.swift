//
//  FlashcardsView.swift
//  The Revise, Study Deck and Flashcards screens, following the Figma frames: a 3D card carousel
//  with an orange selected card, a grid of chapter cards, and a stacked deck.
//

import SwiftUI
import UIKit
import Combine
import AVFoundation

// MARK: - Shared pieces

/// The coin: a gold rim, a bronze face and a $, one drawing used wherever coins appear.
struct CoinIcon: View {
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: [
                Color(red: 188/255, green: 144/255, blue: 62/255), Color(red: 255/255, green: 224/255, blue: 140/255),
                Color(red: 255/255, green: 197/255, blue: 89/255), Color(red: 175/255, green: 126/255, blue: 29/255),
                Color(red: 188/255, green: 144/255, blue: 62/255)], center: .center))
            Circle().fill(Color(red: 176/255, green: 119/255, blue: 13/255)).padding(size * 0.1)
            Text("$").font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 255/255, green: 224/255, blue: 140/255))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Set by a pushed screen that wants the tab bar out of the way while it is open.
struct HidesTabBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct CoinBadge: View {
    let count: Int
    /// A toolbar already puts its items on glass, so the badge adds none of its own there
    var inToolbar = true
    /// Nil leaves the height to the toolbar; the Explain screen sets it to match the settings button
    var height: CGFloat? = nil

    var body: some View {
        HStack(spacing: 8) {
            CoinIcon(size: height == nil ? 28 : 30)
            Text("\(count)")
                .font(.system(size: height == nil ? 20 : 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                .contentTransition(.numericText())
                .animation(.smooth, value: count)
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .padding(.vertical, height == nil ? 6 : 0)
        .modifier(CoinBadgeGlass(enabled: !inToolbar))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) coins")
    }
}

/// The coin balance in a navigation bar: the same 44 pt glass capsule as on the other screens, with the bar's own
/// shared background hidden so it is not drawn twice.
struct CoinToolbarItem: ToolbarContent {
    let count: Int
    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarTrailing) { CoinBadge(count: count, inToolbar: false, height: 48) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { CoinBadge(count: count, inToolbar: false, height: 48) }
        }
    }
}

/// Settings as a 44 pt round glass button with the `gear` symbol, like the one on the Explain screen.
struct GearToolbarItem: ToolbarContent {
    let action: () -> Void
    var body: some ToolbarContent {
        RoundToolbarItem(symbol: "gear", label: "Settings", placement: .topBarTrailing, symbolSize: 24, action: action)
    }
}

/// A 48 pt round glass button in a navigation bar, with the bar's own shared background hidden so it is not drawn twice.
struct RoundToolbarItem: ToolbarContent {
    let symbol: String
    let label: String
    let placement: ToolbarItemPlacement
    var symbolSize: CGFloat = 18
    let action: () -> Void
    private var button: some View {
        Button(action: action) {
            Label(label, systemImage: symbol).labelStyle(.iconOnly)
                .font(.system(size: symbolSize, weight: .semibold)).frame(width: 48, height: 48)
        }
        .litmusGlassButton().buttonBorderShape(.circle).tint(.white)
    }
    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: placement) { button }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { button }
        }
    }
}

private struct CoinBadgeGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.litmusGlass(in: Capsule()) } else { content }
    }
}

private let deckOrange = Color(red: 255/255, green: 120/255, blue: 24/255)

/// The carousel from the Hints, Revise and Flashcards frames: the selected card is centred with an
/// orange border; neighbours sit behind it and can be dragged or tapped into place.
///
/// Kept cheap while the finger is down (see "Improving your app's performance"): the drag lives in `DeckStrip`, whose
/// body only moves, scales and tilts the cards; the cards themselves are `Equatable` faces that are not laid out
/// again until something they show changes.
struct DeckCarousel: View {
    let cards: [FlashcardCard]
    @Binding var index: Int
    var size = CGSize(width: 450, height: 380)
    /// Draws the whole carousel larger, text and all, where the screen has room to spare.
    var scale: CGFloat = 1
    var showsBulb = false
    /// Short cards (the hints) have nothing more to show full screen, so they leave the button out.
    var showsEnlarge = true
    /// The key pitfall is open: the bulb is filled and glows.
    var bulbOn = false
    var onBulb: () -> Void = {}

    @StateObject private var narrator = CardNarrator()
    @State private var zoomed: ZoomImage?
    @State private var enlarged: FlashcardCard?
    /// The card grows into full screen and shrinks back into place (a zoom navigation transition)
    @Namespace private var enlargeNamespace
    @State private var showsRate = false
    @AppStorage(CardNarrator.rateKey) private var speechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        DeckStrip(count: cards.count, index: index, size: size, reduceMotion: reduceMotion, onMove: move(to:)) { position, offset in
            face(for: cards[position], position: position, selected: offset == 0)
        }
        .frame(height: size.height + 40)
        .scaleEffect(scale)
        .frame(height: (size.height + 40) * scale)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if showsRate { rateControl.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .onChange(of: index) { _, _ in narrator.stop(); showsRate = false }
        .onDisappear { narrator.stop(); showsRate = false }
        .fullScreenCover(item: $zoomed) { ImageZoomView(image: $0) }
        .fullScreenCover(item: $enlarged) {
            CardFullScreenView(card: $0)
                .navigationTransition(.zoom(sourceID: $0.id, in: enlargeNamespace))
        }
        .haptic(.selection, trigger: index)
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            move(to: direction == .increment ? index + 1 : index - 1)
        }
    }

    /// Siri's "Speaking Rate" slider: tortoise for slow, hare for fast. Shown once the speaker is tapped.
    private var rateControl: some View {
        HStack(spacing: 12) {
            Text("Reading speed")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)
                .fixedSize()
            Image(systemName: "tortoise.fill").foregroundStyle(.white.opacity(0.8))
            Slider(value: $speechRate, in: Double(CardNarrator.rateRange.lowerBound)...Double(CardNarrator.rateRange.upperBound)) { editing in
                if !editing { narrator.rateChanged() }
            }
            .tint(AppTheme.accent)
            Image(systemName: "hare.fill").foregroundStyle(.white.opacity(0.8))
        }
        .scaledFont(size: 19)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: 440)
        .litmusGlass(in: Capsule())
        .padding(.trailing, 28)
        .padding(.bottom, -56)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reading speed")
    }

    private func move(to target: Int) {
        guard cards.indices.contains(target) else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45, extraBounce: 0.08)) { index = target }
    }

    /// The word being read, relative to the card's text (the narration starts with the title).
    private func bodySpokenRange(for card: FlashcardCard) -> NSRange? {
        guard narrator.narratingCardID == card.id, let range = narrator.spokenRange else { return nil }
        let offset = (card.title + ". ").utf16.count
        guard range.location >= offset else { return nil }
        return NSRange(location: range.location - offset, length: range.length)
    }

    private func face(for card: FlashcardCard, position: Int, selected: Bool) -> some View {
        DeckCardFace(
            card: card, position: position, count: cards.count, selected: selected, size: size,
            showsBulb: showsBulb, bulbOn: bulbOn, showsEnlarge: showsEnlarge,
            reading: selected && narrator.narratingCardID == card.id,
            spokenRange: selected ? bodySpokenRange(for: card) : nil,
            onSpeaker: {
                narrator.toggle(cardID: card.id, title: card.title, body: card.body)
                withAnimation(.smooth(duration: 0.3)) { showsRate = narrator.narratingCardID == card.id }
            },
            onEnlarge: { narrator.stop(); showsRate = false; enlarged = card },
            onZoom: { if let name = card.imageName { zoomed = ZoomImage(name: name, title: card.title) } },
            onBulb: onBulb
        )
        .equatable()
        // Only the card itself is the zoom's source; on the whole strip it would clip the cards beside the front one
        .matchedTransitionSource(id: card.id, in: enlargeNamespace) { $0.clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous)) }
    }
}

/// Lays the cards along one continuous position (their slot plus the finger's drag), so scale, tilt and fade move
/// together with the finger and carry on smoothly into the spring when it lets go. Only this view's body runs per frame.
private struct DeckStrip<Face: View>: View {
    let count: Int
    let index: Int
    let size: CGSize
    let reduceMotion: Bool
    let onMove: (Int) -> Void
    @ViewBuilder let face: (_ position: Int, _ offset: Int) -> Face

    /// Lets go with a spring, so a drag that is not far enough settles back instead of snapping
    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.32))) private var drag: CGFloat = 0

    var body: some View {
        let step = size.width * 0.72
        ZStack {
            if count > 0 {
                ForEach(max(0, index - 2)...min(count - 1, index + 2), id: \.self) { position in
                    let offset = position - index
                    let pos = CGFloat(offset) + drag / step
                    let distance = min(abs(pos), 2)
                    face(position, offset)
                        .scaleEffect(1 - 0.1 * min(distance, 1) - 0.05 * max(0, distance - 1))
                        .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(-pos) * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .opacity(1 - 0.2 * Double(max(0, distance - 1)))
                        // Only the card in front is sharp; the ones behind it are soft
                        .blur(radius: reduceMotion ? 0 : 9 * min(distance, 1))
                        .offset(x: pos * step)
                        .zIndex(10 - Double(distance))
                        .onTapGesture { onMove(position) }
                        .accessibilityHidden(offset != 0)
                }
            }
        }
        .contentShape(Rectangle())
        // Alongside the text's own scrolling and the buttons, so a sideways swipe starts a move wherever the finger lands
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .updating($drag) { value, state, _ in
                    // Only a sideways drag moves the cards; up and down drags scroll the text
                    state = abs(value.translation.width) > abs(value.translation.height) ? value.translation.width : 0
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    // Part of the way across, or a flick that would have carried it there
                    let reach = step * 0.14
                    let travel = abs(value.translation.width) > abs(value.predictedEndTranslation.width) * 0.5 ? value.translation.width : value.predictedEndTranslation.width
                    if travel < -reach { onMove(index + 1) }
                    else if travel > reach { onMove(index - 1) }
                }
        )
    }
}

/// One card. Every card has the same layout whether it is in front or beside it (only the front one scrolls and has
/// buttons), so a card changing place never changes what it looks like part-way through the move.
private struct DeckCardFace: View, Equatable {
    @Environment(\.appReduceMotion) private var reduceMotion
    /// On a phone the card is too narrow for the title beside the corner buttons, so the title sits under them.
    @Environment(\.horizontalSizeClass) private var sizeClass
    let card: FlashcardCard
    let position: Int
    let count: Int
    let selected: Bool
    let size: CGSize
    let showsBulb: Bool
    let bulbOn: Bool
    let showsEnlarge: Bool
    let reading: Bool
    let spokenRange: NSRange?
    let onSpeaker: () -> Void
    let onEnlarge: () -> Void
    let onZoom: () -> Void
    let onBulb: () -> Void

    nonisolated static func == (a: DeckCardFace, b: DeckCardFace) -> Bool {
        a.card.id == b.card.id && a.position == b.position && a.count == b.count && a.selected == b.selected && a.size == b.size
            && a.showsBulb == b.showsBulb && a.bulbOn == b.bulbOn && a.showsEnlarge == b.showsEnlarge && a.reading == b.reading && a.spokenRange == b.spokenRange
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 34, style: .continuous) }

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .background {
                // The shadow comes from a plain shape behind the card, not from the card's text and picture
                shape
                    .fill(Color(red: selected ? 0.10 : 0.07, green: selected ? 0.10 : 0.07, blue: selected ? 0.11 : 0.08))
            }
            .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
            .clipShape(shape)
            .modifier(FlattenedWhenBehind(flatten: !selected))
    }

    private var content: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Text(card.title)
                    .scaledFont(size: 32, weight: .medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    // Clear of the two round buttons in the corner: beside them on iPad, under them on a phone
                    .padding(.leading, sizeClass == .compact ? 8 : (showsEnlarge ? 44 : 62))
                    .padding(.trailing, sizeClass == .compact ? 8 : (showsEnlarge ? 112 : 62))
                    .padding(.top, sizeClass == .compact && selected ? 56 : 0)
                    .frame(maxWidth: .infinity)
                if selected {
                    HStack(spacing: 10) {
                        if showsEnlarge {
                            Button(action: onEnlarge) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .litmusGlassButton()
                            .buttonBorderShape(.circle)
                            .accessibilityLabel("Full screen")
                        }
                        Button(action: onSpeaker) {
                            Image(systemName: reading ? "speaker.wave.2.fill" : "speaker.wave.2")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(reading ? Color(red: 255/255, green: 197/255, blue: 89/255) : .white)
                                .frame(width: 40, height: 40)
                                .symbolEffect(.variableColor.iterative, isActive: reading && !reduceMotion)
                        }
                        .litmusGlassButton()
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(reading ? "Stop reading this card" : "Read this card aloud")
                    }
                    .offset(x: 6, y: -8)
                }
            }
            .padding(.top, 26)
            .padding(.horizontal, 18)
            Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1).padding(.horizontal, 30)
            if selected {
                // The whole text is always reachable: long text scrolls inside the card, and the diagram scrolls with it
                NarratedText(text: card.body, keywords: card.keywords, spokenRange: spokenRange,
                             imageName: card.imageName, imageMaxHeight: max(128, size.height * 0.27),
                             imageLabel: "NCERT diagram: \(card.title)", figureCaption: card.figureCaption, onZoom: card.imageName == nil ? nil : onZoom)
            } else {
                // The same text in the same place, fixed: the cards beside the front one are not scrolled
                // laid out exactly like the front card's scrolling content (picture first, then the text), so the two match
                // while the deck moves and the blur-to-sharp change is only the blur
                VStack(alignment: .leading, spacing: 0) {
                    if let name = card.imageName {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Image(name)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: max(128, size.height * 0.27))
                                .padding(6)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                    }
                    Text(card.body)
                        .scaledFont(size: 25, weight: .regular)
                        .foregroundStyle(.white.opacity(0.97))
                        .lineSpacing(7)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
            ZStack {
                Text("\(position + 1)/\(count)")
                    .scaledFont(size: 18)
                    .foregroundStyle(.white.opacity(0.7))
                if selected && showsBulb && card.pitfall != nil {
                    HStack {
                        Spacer()
                        Button(action: onBulb) {
                            Image(systemName: bulbOn ? "lightbulb.fill" : "lightbulb")
                                .font(.system(size: 26))
                                .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                                .shadow(color: Color(red: 255/255, green: 197/255, blue: 89/255).opacity(bulbOn ? 0.95 : 0), radius: 10)
                                .shadow(color: Color(red: 255/255, green: 160/255, blue: 40/255).opacity(bulbOn ? 0.7 : 0), radius: 22)
                                .frame(width: 44, height: 44)
                                .animation(.smooth(duration: 0.35), value: bulbOn)
                        }
                        .accessibilityLabel("Show key pitfall to avoid")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }
}

/// A card beside the front one is drawn once into a single layer, so moving it costs one texture, not its whole tree.
private struct FlattenedWhenBehind: ViewModifier {
    let flatten: Bool
    func body(content: Content) -> some View {
        if flatten {
            content.drawingGroup()
        } else {
            content
        }
    }
}

// MARK: - Revise (Figma "Revise" and "Revise, key pitfall")

struct ReviseView: View {
    let cards: [FlashcardCard]
    let coins: Int
    let onDone: () -> Void

    @State private var index = 0
    @State private var showPitfall = false
    @State private var pitfallHeight: CGFloat = 0
    @State private var showSettings = false
    @State private var screenHeight: CGFloat = 834
    @Environment(\.dismiss) private var dismiss

    /// The card is as large as the screen allows while leaving room for the reading-speed slider under it,
    /// the pitfall panel when it is open, and the Done button.
    private var cardScale: CGFloat {
        let cardHeight: CGFloat = (showPitfall ? 380 : 520) + 40
        let reserved: CGFloat = showPitfall ? 420 : 300
        return min(1.15, max(0.8, (screenHeight - reserved) / cardHeight))
    }

    var body: some View {
        NavigationStack {
        ZStack {
            AppBackground()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }

            VStack(spacing: 0) {
                Spacer()

                DeckCarousel(cards: cards, index: $index, size: CGSize(width: 680, height: showPitfall ? 380 : 520), scale: cardScale, showsBulb: true, bulbOn: showPitfall) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showPitfall.toggle() }
                }

                if showPitfall, let pitfall = cards[safe: index]?.pitfall {
                    pitfallPanel(pitfall)
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()

                HStack {
                    if showPitfall { Spacer() }
                    doneButton
                    if showPitfall { Spacer().frame(width: 60) }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 44)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Revise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A full-screen cover closes with the standard Close button
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close Revise")
            }
        }
        // The coin counter and Settings sit where they do on the other screens: the same capsule and 44 pt round button,
        // in the same corner, rather than in the navigation bar
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 12) {
                CoinCounter(count: coins)
                Button { showSettings = true } label: { Label("Settings", systemImage: "gear") }
                    .litmusGlassButton()
                    .buttonBorderShape(.circle)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .padding(.top, 24)
            .padding(.trailing, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .ignoresSafeArea(edges: .top)
        }
        }
        .onChange(of: index) { _, _ in showPitfall = false }
        .fullScreenCover(isPresented: $showSettings) { SettingsView() }
    }

    /// "Key Pitfall to Avoid": as wide as the card, tall enough for the whole text; longer text scrolls.
    private func pitfallPanel(_ pitfall: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Pitfall to Avoid")
                .scaledFont(size: 18, weight: .semibold)
                .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
            ScrollView(.vertical, showsIndicators: true) {
                Text(pitfall)
                    .scaledFont(size: 21)
                    .lineSpacing(4)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pitfallHeight = $0 }
            }
            .frame(height: min(max(pitfallHeight, 60), 150))
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(22)
        .frame(width: 680, alignment: .leading)
        .litmusGlass(tint: Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color(red: 255/255, green: 197/255, blue: 89/255).opacity(0.5), lineWidth: 1.5))
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .scaledFont(size: 18, weight: .medium)
                .foregroundStyle(.white)
                .frame(width: 190, height: 58)
        }
        .litmusProminentGlassButton()
        .buttonBorderShape(.capsule)
        .tint(AppTheme.accent)
    }
}

// MARK: - Study Deck (Figma "Study Deck")

/// Open this chapter's deck straight away: from the Revise tile on Home, a widget or a reminder.
struct DeckRequest: Equatable {
    let chapter: String
    let subject: String
}

struct FlashcardsView: View {
    @Namespace private var zoomNamespace
    let grade: String
    @Binding var request: DeckRequest?
    @State private var subject = "Science"
    /// Class 9 Social Science is two books; which one the tiles show
    @State private var socialPart: SocialPart = .one
    /// Class 10 Social Science is four books; which one the tiles show
    @State private var socialBranch: SocialBranch = .history
    @State private var chapters: [DeckChapter] = []
    @State private var selected: DeckChapter?
    @State private var highlighted: String?
    let coins: Int
    /// The topic chosen on Home: its subject and chapter are shown first and ringed in orange.
    var topic: NCERTTopic? = nil
    /// The screen width, measured like Home's, so the pickers here match Home's in size.
    @State private var screenWidth: CGFloat = 1194

    /// A design width scaled the way Home scales it (820-point portrait frame, 1312-point landscape
    /// frame), never wider than the screen minus the side margins.
    private func pickerWidth(_ figma: CGFloat) -> CGFloat {
        let scaled = figma * screenWidth / (screenWidth < 1100 ? 820 : 1312)
        return min(scaled, max(0, screenWidth - 40))
    }

    var body: some View {
        // One scrolling page: the title is the navigation bar's large title ("Study Deck", set where the tab's bar is configured
        // in MainTabView), which collapses into the bar as the tiles scroll, so the header no longer holds screen space
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // The screen width, so the pickers come out the size Home's do. Home's measurement lands on the screen width
                    // itself; this spacer reads about 5 points under it (checked on the iPad Pro 13-inch: both pickers 414 points)
                    Color.clear
                        .frame(height: 0)
                        .onSettledWidth { screenWidth = $0 + 5 }
                    // The title is the page's own large heading: it scrolls away with the tiles, so no second, small title is
                    // left sitting under the tab bar
                    Text("Study Deck")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    // On the right, at the same scaled widths as Home's pickers (330 and 480 design points)
                    Picker("Subject", selection: $subject) {
                        Text("Science").tag("Science")
                        Text("Social Science").tag("Social Science")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: pickerWidth(330))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    if showsPartPicker {
                        Picker("Book", selection: $socialPart) {
                            ForEach(SocialPart.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: pickerWidth(330))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if showsBranchPicker {
                        Picker("Book", selection: $socialBranch) {
                            ForEach(SocialBranch.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: pickerWidth(480))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 420), spacing: 36)], spacing: 36) {
                        ForEach(shownChapters) { chapter in
                            chapterCard(chapter).id(chapter.id)
                        }
                    }
                    .padding(.vertical, 8)

                    if chapters.isEmpty {
                        Text("No flashcards for this subject in \(grade) yet.")
                            .scaledFont(size: 20)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                // The large title's own side margin, so the title, the pickers and the tiles share one left edge (and one right)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .onChange(of: chapters) { _, loaded in
                openRequestedDeck()
                guard let topic, let match = loaded.first(where: { $0.title == topic.chapter }) else { return }
                if showsPartPicker { socialPart = FlashcardLibrary.isInPart(match.title, part: .two) ? .two : .one }
                if showsBranchPicker, let branch = FlashcardLibrary.branch(of: match.title) { socialBranch = branch }
                highlighted = match.id
                proxy.scrollTo(match.id, anchor: .center)
            }
        }
        .background { AppBackground() }
        .navigationDestination(item: $selected) { chapter in
            DeckView(chapter: chapter, coins: coins)
                .minimalBackButton()
                // The tile you tapped grows into the deck, and shrinks back into place on return
                .navigationTransition(.zoom(sourceID: chapter.id, in: zoomNamespace))
        }
        .onAppear {
            if let topic, let wanted = ["Science", "Social Science"].first(where: { $0 == topic.subject }), subject != wanted { subject = wanted }
        }
        .task(id: subject) { chapters = FlashcardLibrary.chapters(subject: subject, grade: grade) }
        .onChange(of: request) { _, _ in openRequestedDeck() }
        .onAppear { openRequestedDeck() }
    }

    /// Goes inside the requested chapter's deck, switching subject first when it is in the other one.
    private func openRequestedDeck() {
        guard let request else { return }
        if subject != request.subject { subject = request.subject; return }
        if let match = chapters.first(where: { $0.title == request.chapter }) {
            if grade == "Class 10", subject == "Social Science", let branch = FlashcardLibrary.branch(of: match.title) { socialBranch = branch }
            if grade == "Class 9", subject == "Social Science" { socialPart = FlashcardLibrary.isInPart(match.title, part: .two) ? .two : .one }
            self.request = nil
            selected = match
        }
    }

    private var showsPartPicker: Bool { subject == "Social Science" && grade == "Class 9" }

    private var showsBranchPicker: Bool { subject == "Social Science" && grade == "Class 10" }

    private var shownChapters: [DeckChapter] {
        if showsPartPicker { return chapters.filter { FlashcardLibrary.isInPart($0.title, part: socialPart) } }
        if showsBranchPicker { return chapters.filter { FlashcardLibrary.branch(of: $0.title) == socialBranch } }
        return chapters
    }

    private func chapterCard(_ chapter: DeckChapter) -> some View {
        Button {
            highlighted = chapter.id
            selected = chapter
        } label: {
            // A square banner. The picture is an overlay, so its own size never decides the size of the card, and the
            // cover fills the banner edge to edge.
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 250/255, green: 240/255, blue: 225/255), Color(red: 232/255, green: 240/255, blue: 252/255)],
                                     startPoint: .top, endPoint: .bottom))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack(alignment: .top) {
                        if chapter.coverHasTitle, let cover = chapter.coverImage {
                            Color.clear.overlay { Image(cover).resizable().scaledToFill() }
                                .accessibilityHidden(true)
                        } else if let cover = chapter.coverImage {
                            Image(cover)
                                .resizable()
                                .scaledToFit()
                                .padding(.top, 84)
                                .padding(.bottom, 16)
                                .padding(.horizontal, 20)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Color(red: 0.2, green: 0.35, blue: 0.7).opacity(0.5))
                                .frame(maxHeight: .infinity)
                                .padding(.top, 60)
                                .accessibilityHidden(true)
                        }
                        if !chapter.coverHasTitle {
                            Text(chapter.title)
                                .scaledFont(size: 30, weight: .bold)
                                .foregroundStyle(Color.black.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .padding(.top, 18)
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.cardPressSpring)
        .matchedTransitionSource(id: chapter.id, in: zoomNamespace)
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content.opacity(phase.isIdentity ? 1 : 0.55).scaleEffect(phase.isIdentity ? 1 : 0.96)
        }
        .accessibilityLabel("\(chapter.title), \(chapter.cards.count) flashcards")
    }
}

// MARK: - Flashcards (Figma "Flashcards")

struct DeckView: View {
    let chapter: DeckChapter
    let coins: Int
    @State private var index = 0
    @State private var screen = CGSize(width: 1210, height: 834)
    @Environment(\.dismiss) private var dismiss

    /// The buttons sit a comfortable way in from the corners, not on them
    private let sideInset: CGFloat = 56
    private let topInset: CGFloat = 48

    /// The card takes the area under the header: about two thirds of the width in landscape (the neighbouring cards peek out
    /// either side) and all the height that is left, with room under it for the reading-speed slider.
    private var cardSize: CGSize {
        let landscape = screen.width > screen.height
        let width = min(screen.width * (landscape ? 0.66 : 0.8), 900)
        let height = min(max(screen.height - 270, 480), 760)
        return CGSize(width: width, height: height)
    }

    var body: some View {
        ZStack {
            AppBackground()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                DeckCarousel(cards: chapter.cards, index: $index, size: cardSize)
                Spacer(minLength: 0)
                Color.clear.frame(height: 56)   // the reading-speed slider hangs below the card
            }
        }
        // The system's back button returns to the study deck; the tab bar steps aside while a deck is open
        .centeredTitle("Flashcards")
        .toolbarVisibility(.hidden, for: .tabBar)
        .preference(key: HidesTabBarKey.self, value: true)
        // No coin counter here: an open deck is for reading the cards, so the study deck's own coin badge is not repeated over it
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}


/// The card's text, split into sentences so the reading can be followed: the one being spoken is kept in the middle of the
/// card, scrolling by itself as the narration moves on, and the word being said is lit.
struct NarratedText: View {
    let text: String
    let keywords: [String]
    let spokenRange: NSRange?
    /// 25 on the deck card; larger on the full-screen card
    var fontSize: CGFloat = 25
    /// A diagram shown above the text, inside the same scroll, so the picture and the words move together
    var imageName: String?
    var imageMaxHeight: CGFloat = 160
    var imageLabel: String = ""
    /// Printed under the diagram: its figure number and caption
    var figureCaption: String?
    var onZoom: (() -> Void)?
    @Environment(\.appReduceMotion) private var reduceMotion

    private struct Sentence: Identifiable {
        let id: Int
        let text: String
        let location: Int     // UTF-16 offset in the whole text
        var length: Int { text.utf16.count }
    }

    /// Split once, when the card's text is first shown, not on every redraw.
    private let sentences: [Sentence]

    init(text: String, keywords: [String], spokenRange: NSRange?, fontSize: CGFloat = 25,
         imageName: String? = nil, imageMaxHeight: CGFloat = 160, imageLabel: String = "", figureCaption: String? = nil, onZoom: (() -> Void)? = nil) {
        self.fontSize = fontSize
        self.figureCaption = figureCaption
        self.imageName = imageName
        self.imageMaxHeight = imageMaxHeight
        self.imageLabel = imageLabel
        self.onZoom = onZoom
        self.text = text
        self.keywords = keywords
        self.spokenRange = spokenRange
        var result: [Sentence] = []
        var current = ""
        var start = 0
        var offset = 0
        for character in text {
            let width = String(character).utf16.count
            // Space or a line break between two sentences belongs to neither: it would indent the next one
            if current.isEmpty && character.isWhitespace {
                offset += width
                start = offset
                continue
            }
            current.append(character)
            offset += width
            if ".!?\n".contains(character) {
                result.append(Sentence(id: result.count, text: current, location: start))
                current = ""
                start = offset
            }
        }
        if !current.isEmpty { result.append(Sentence(id: result.count, text: current, location: start)) }
        sentences = result
    }

    private func index(of range: NSRange?) -> Int? {
        guard let range else { return nil }
        return sentences.last(where: { $0.location <= range.location })?.id
    }

    var body: some View {
        let parts = sentences
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    if let imageName {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            diagram(imageName)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                    }
                    ForEach(parts) { sentence in
                        Text(KeywordHighlighter.attributed(sentence.text, keywords: keywords, spokenRange: relativeRange(in: sentence)))
                            .scaledFont(size: fontSize, weight: .regular)
                            .foregroundStyle(.white.opacity(0.97))
                            .lineSpacing(fontSize * 0.28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(sentence.id)
                    }
                }
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 30)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: index(of: spokenRange)) { _, sentence in
                guard let sentence else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { proxy.scrollTo(sentence, anchor: .center) }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .frame(maxHeight: .infinity)
    }

    private func diagram(_ name: String) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: imageMaxHeight)
                    .padding(6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(imageLabel)
                if let onZoom {
                    Button(action: onZoom) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.7), in: Circle())
                    }
                    .accessibilityLabel("Zoom into the diagram")
                    .offset(x: 10, y: 10)
                }
            }
            .onTapGesture { onZoom?() }
            if let figureCaption, !figureCaption.isEmpty {
                Text(figureCaption)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The spoken word, relative to one sentence; nil when it is in another.
    private func relativeRange(in sentence: Sentence) -> NSRange? {
        guard let spokenRange, spokenRange.location >= sentence.location, spokenRange.location < sentence.location + sentence.length else { return nil }
        let length = min(spokenRange.length, sentence.location + sentence.length - spokenRange.location)
        return NSRange(location: spokenRange.location - sentence.location, length: length)
    }
}


/// One card shown across the whole screen, for reading from further away: a larger title and text, the diagram when the
/// card has one, and the same Close button as the other full-screen pages.
struct CardFullScreenView: View {
    let card: FlashcardCard
    @Environment(\.dismiss) private var dismiss
    @StateObject private var narrator = CardNarrator()
    @State private var showsRate = false
    @State private var zoomedImage: ZoomImage?
    @AppStorage(CardNarrator.rateKey) private var speechRate = Double(AVSpeechUtteranceDefaultSpeechRate)

    private var reading: Bool { narrator.narratingCardID == card.id }

    /// The word being read, relative to the card's text (the narration starts with the title).
    private var bodySpokenRange: NSRange? {
        guard reading, let range = narrator.spokenRange else { return nil }
        let offset = (card.title + ". ").utf16.count
        guard range.location >= offset else { return nil }
        return NSRange(location: range.location - offset, length: range.length)
    }

    /// Same control as under the deck card: tortoise to hare, shown once the speaker has been tapped.
    private var rateControl: some View {
        HStack(spacing: 12) {
            Text("Reading speed").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).fixedSize()
            Image(systemName: "tortoise.fill").foregroundStyle(.white.opacity(0.8))
            Slider(value: $speechRate, in: Double(CardNarrator.rateRange.lowerBound)...Double(CardNarrator.rateRange.upperBound)) { editing in
                if !editing { narrator.rateChanged() }
            }
            .tint(AppTheme.accent)
            Image(systemName: "hare.fill").foregroundStyle(.white.opacity(0.8))
        }
        .font(.system(size: 19))
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(width: 440)
        .litmusGlass(in: Capsule())
        .padding(.bottom, 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reading speed")
    }

    private func cornerButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol).labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40)
        }
        .litmusGlassButton().buttonBorderShape(.circle).tint(.white)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // The same backdrop as the deck behind it, edge to edge, so the zoom lands on an identical scene
                AppBackground().ignoresSafeArea()
                // Dimmed to the same dark scene as the deck behind it
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 20) {
                    // The same highlighted keywords and read-along as on the deck card, set larger; the diagram scrolls with it
                    NarratedText(text: card.body, keywords: card.keywords, spokenRange: bodySpokenRange, fontSize: 34,
                                 imageName: card.imageName, imageMaxHeight: 300,
                                 imageLabel: "NCERT diagram: \(card.title)", figureCaption: card.figureCaption,
                                 onZoom: card.imageName == nil ? nil : { zoomedImage = ZoomImage(name: card.imageName ?? "", title: card.title) })
                        .frame(maxWidth: 900)
                }
                .padding(.horizontal, 48)
                .padding(.top, 88)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            // The slider is glass and floats over the text
            .overlay(alignment: .bottom) {
                if showsRate { rateControl.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            // Buttons sit inside the corners, clear of the bezel, and the zoom never carries them past the display edge
            .overlay(alignment: .top) {
                ZStack {
                    Text(card.title).font(.headline).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 96)
                    HStack {
                        cornerButton(symbol: "arrow.down.right.and.arrow.up.left", label: "Exit full screen") { narrator.stop(); dismiss() }
                        Spacer()
                        cornerButton(symbol: reading ? "speaker.wave.2.fill" : "speaker.wave.2", label: reading ? "Stop reading this card" : "Read this card aloud") {
                            narrator.toggle(cardID: card.id, title: card.title, body: card.body)
                            withAnimation(.smooth(duration: 0.3)) { showsRate = narrator.narratingCardID == card.id }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $zoomedImage) { ImageZoomView(image: $0) }
        .onDisappear { narrator.stop() }
        .preferredColorScheme(.dark)
    }
}
