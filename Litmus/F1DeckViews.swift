//
//  F1DeckViews.swift
//  The Revise, Study Deck and Flashcards screens, following the Figma frames: a 3D card carousel
//  with an orange selected card, a grid of chapter cards, and a stacked deck.
//

import SwiftUI
import AVFoundation

// MARK: - Shared pieces

struct F1CoinBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color(red: 255/255, green: 197/255, blue: 89/255)).frame(width: 34, height: 34)
                Circle().fill(Color(red: 176/255, green: 119/255, blue: 13/255)).frame(width: 28, height: 28)
                Text("$").f1Font(size: 17, weight: .bold)
                    .foregroundStyle(Color(red: 255/255, green: 214/255, blue: 130/255))
            }
            Text("\(count)")
                .f1Font(size: 26, weight: .bold)
                .foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) coins")
    }
}

private let deckOrange = Color(red: 255/255, green: 120/255, blue: 24/255)

/// The carousel from the Hints, Revise and Flashcards frames: the selected card is centred with an
/// orange border; neighbours sit behind it and can be dragged or tapped into place.
///
/// Kept cheap while the finger is down (see "Improving your app's performance"): the drag lives in `DeckStrip`, whose
/// body only moves, scales and tilts the cards; the cards themselves are `Equatable` faces that are not laid out
/// again until something they show changes.
struct F1DeckCarousel: View {
    let cards: [F1DeckCard]
    @Binding var index: Int
    var size = CGSize(width: 450, height: 380)
    /// Draws the whole carousel larger, text and all, where the screen has room to spare.
    var scale: CGFloat = 1
    var showsBulb = false
    /// The key pitfall is open: the bulb is filled and glows.
    var bulbOn = false
    var onBulb: () -> Void = {}

    @StateObject private var narrator = F1CardNarrator()
    @State private var zoomed: F1ZoomImage?
    @State private var showsRate = false
    @AppStorage(F1CardNarrator.rateKey) private var speechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @Environment(\.f1ReduceMotion) private var reduceMotion

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
        .fullScreenCover(item: $zoomed) { F1ImageZoomView(image: $0) }
        .f1Feedback(.selection, trigger: index)
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            move(to: direction == .increment ? index + 1 : index - 1)
        }
    }

    /// Siri's "Speaking Rate" slider: tortoise for slow, hare for fast. Shown once the speaker is tapped.
    private var rateControl: some View {
        HStack(spacing: 12) {
            Text("Reading speed")
                .f1Font(size: 15, weight: .semibold)
                .foregroundStyle(.white)
                .fixedSize()
            Image(systemName: "tortoise.fill").foregroundStyle(.white.opacity(0.8))
            Slider(value: $speechRate, in: Double(F1CardNarrator.rateRange.lowerBound)...Double(F1CardNarrator.rateRange.upperBound)) { editing in
                if !editing { narrator.rateChanged() }
            }
            .tint(Color(red: 10/255, green: 132/255, blue: 255/255))
            Image(systemName: "hare.fill").foregroundStyle(.white.opacity(0.8))
        }
        .f1Font(size: 19)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: 440)
        .glassEffect(.regular, in: Capsule())
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
    private func bodySpokenRange(for card: F1DeckCard) -> NSRange? {
        guard narrator.narratingCardID == card.id, let range = narrator.spokenRange else { return nil }
        let offset = (card.title + ". ").utf16.count
        guard range.location >= offset else { return nil }
        return NSRange(location: range.location - offset, length: range.length)
    }

    private func face(for card: F1DeckCard, position: Int, selected: Bool) -> some View {
        DeckCardFace(
            card: card, position: position, count: cards.count, selected: selected, size: size,
            showsBulb: showsBulb, bulbOn: bulbOn,
            reading: selected && narrator.narratingCardID == card.id,
            spokenRange: selected ? bodySpokenRange(for: card) : nil,
            onSpeaker: {
                narrator.toggle(cardID: card.id, title: card.title, body: card.body)
                withAnimation(.smooth(duration: 0.3)) { showsRate = narrator.narratingCardID == card.id }
            },
            onZoom: { if let name = card.imageName { zoomed = F1ZoomImage(name: name, title: card.title) } },
            onBulb: onBulb
        )
        .equatable()
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
    let card: F1DeckCard
    let position: Int
    let count: Int
    let selected: Bool
    let size: CGSize
    let showsBulb: Bool
    let bulbOn: Bool
    let reading: Bool
    let spokenRange: NSRange?
    let onSpeaker: () -> Void
    let onZoom: () -> Void
    let onBulb: () -> Void

    nonisolated static func == (a: DeckCardFace, b: DeckCardFace) -> Bool {
        a.card.id == b.card.id && a.position == b.position && a.count == b.count && a.selected == b.selected && a.size == b.size
            && a.showsBulb == b.showsBulb && a.bulbOn == b.bulbOn && a.reading == b.reading && a.spokenRange == b.spokenRange
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 34, style: .continuous) }

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .background {
                // The shadow comes from a plain shape behind the card, not from the card's text and picture
                shape
                    .fill(Color(red: selected ? 0.10 : 0.07, green: selected ? 0.10 : 0.07, blue: selected ? 0.11 : 0.08))
                    .shadow(color: deckOrange.opacity(selected ? 0.35 : 0), radius: selected ? 22 : 0, y: 8)
            }
            .overlay(shape.stroke(selected ? deckOrange : Color.white.opacity(0.75), lineWidth: selected ? 6 : 4))
            .clipShape(shape)
            .modifier(FlattenedWhenBehind(flatten: !selected))
    }

    private var content: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Text(card.title)
                    .f1Font(size: 32, weight: .medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 44)
                    .frame(maxWidth: .infinity)
                if selected {
                    Button(action: onSpeaker) {
                        Image(systemName: reading ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(reading ? Color(red: 255/255, green: 197/255, blue: 89/255) : .white.opacity(0.85))
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(reading ? 0.2 : 0.1), in: Circle())
                            .symbolEffect(.variableColor.iterative, isActive: reading)
                    }
                    .accessibilityLabel(reading ? "Stop reading this card" : "Read this card aloud")
                    .offset(x: 6, y: -8)
                }
            }
            .padding(.top, 26)
            .padding(.horizontal, 18)
            Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1).padding(.horizontal, 30)
            if let name = card.imageName {
                ZStack(alignment: .bottomTrailing) {
                    Image(name)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: max(128, size.height * 0.27))
                        .padding(6)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("NCERT diagram: \(card.title)")
                    if selected {
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
                .onTapGesture { if selected { onZoom() } }
            }
            if selected {
                // The whole text is always reachable: long text scrolls inside the card
                F1NarratedBody(text: card.body, keywords: card.keywords, spokenRange: spokenRange)
            } else {
                // The same text in the same place, fixed: the cards beside the front one are not scrolled
                Text(card.body)
                    .f1Font(size: 25, weight: .regular)
                    .foregroundStyle(.white.opacity(0.97))
                    .lineSpacing(7)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
            ZStack {
                Text("\(position + 1)/\(count)")
                    .f1Font(size: 18)
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

struct F1ReviseView: View {
    let cards: [F1DeckCard]
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
        ZStack {
            AppleMusicDarkGradientBackground()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 18) {
                    F1BackButton(label: "Close Revise") { dismiss() }
                    Text("Revise")
                        .f1Font(size: 60, weight: .bold)
                        .foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 14) {
                        F1CoinBadge(count: coins)
                        Button { showSettings = true } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .glassEffect(.regular.interactive(), in: Circle())
                        }
                        .buttonStyle(.f1Spring)
                        .contentShape(Circle())
                        .hoverEffect(.lift)
                        .accessibilityLabel("Settings")
                    }
                }
                .padding(.leading, F1BackButton.leading)
                .padding(.trailing, 44)
                .padding(.top, F1BackButton.top)

                Spacer()

                F1DeckCarousel(cards: cards, index: $index, size: CGSize(width: 680, height: showPitfall ? 380 : 520), scale: cardScale, showsBulb: true, bulbOn: showPitfall) {
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
        .onChange(of: index) { _, _ in showPitfall = false }
        .fullScreenCover(isPresented: $showSettings) { F1SettingsView() }
    }

    /// "Key Pitfall to Avoid": as wide as the card, tall enough for the whole text; longer text scrolls.
    private func pitfallPanel(_ pitfall: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Pitfall to Avoid")
                .f1Font(size: 18, weight: .semibold)
                .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
            ScrollView(.vertical, showsIndicators: true) {
                Text(pitfall)
                    .f1Font(size: 21)
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
        .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color(red: 255/255, green: 197/255, blue: 89/255).opacity(0.5), lineWidth: 1.5))
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .f1Font(size: 18, weight: .medium)
                .foregroundStyle(.white)
                .frame(width: 190, height: 58)
                .background(Color(red: 10/255, green: 110/255, blue: 255/255), in: Capsule())
        }
        .buttonStyle(.f1Spring)
    }
}

// MARK: - Study Deck (Figma "Study Deck")

/// Open this chapter's deck straight away: from the Revise tile on Home, a widget or a reminder.
struct F1DeckRequest: Equatable {
    let chapter: String
    let subject: String
}

struct F1StudyDeckView: View {
    @Namespace private var zoomNamespace
    let grade: String
    @Binding var request: F1DeckRequest?
    @State private var subject = "Science"
    @State private var chapters: [F1DeckChapter] = []
    @State private var selected: F1DeckChapter?
    @State private var highlighted: String?
    let coins: Int
    /// The topic chosen on Home: its subject and chapter are shown first and ringed in orange.
    var topic: NCERTTopic? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center) {
                Text("Study Deck")
                    .f1Font(size: 64, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 16)
                Picker("Subject", selection: $subject) {
                    Text("Science").tag("Science")
                    Text("Social Science").tag("Social Science")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 450)
            }
            .padding(.top, 50)

            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 420), spacing: 36)], spacing: 36) {
                    ForEach(chapters) { chapter in
                        chapterCard(chapter).id(chapter.id)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)

                if chapters.isEmpty {
                    Text("No flashcards for this subject in \(grade) yet.")
                        .f1Font(size: 20)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .onChange(of: chapters) { _, loaded in
                openRequestedDeck()
                guard let topic, let match = loaded.first(where: { $0.title == topic.chapter }) else { return }
                highlighted = match.id
                proxy.scrollTo(match.id, anchor: .center)
            }
            }
        }
        .padding(.horizontal, 44)
        .background { AppleMusicDarkGradientBackground() }
        .navigationDestination(item: $selected) { chapter in
            F1FlashcardsDeckView(chapter: chapter, coins: coins)
                // The tile you tapped grows into the deck, and shrinks back into place on return
                .navigationTransition(.zoom(sourceID: chapter.id, in: zoomNamespace))
        }
        .onAppear {
            if let topic, let wanted = ["Science", "Social Science"].first(where: { $0 == topic.subject }), subject != wanted { subject = wanted }
        }
        .task(id: subject) { chapters = F1FlashcardLibrary.chapters(subject: subject, grade: grade) }
        .onChange(of: request) { _, _ in openRequestedDeck() }
        .onAppear { openRequestedDeck() }
    }

    /// Goes inside the requested chapter's deck, switching subject first when it is in the other one.
    private func openRequestedDeck() {
        guard let request else { return }
        if subject != request.subject { subject = request.subject; return }
        if let match = chapters.first(where: { $0.title == request.chapter }) {
            self.request = nil
            selected = match
        }
    }

    private func chapterCard(_ chapter: F1DeckChapter) -> some View {
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
                                .f1Font(size: 30, weight: .bold)
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
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(highlighted == chapter.id ? deckOrange : .clear, lineWidth: 6)
            )
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.f1CardSpring)
        .matchedTransitionSource(id: chapter.id, in: zoomNamespace)
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content.opacity(phase.isIdentity ? 1 : 0.55).scaleEffect(phase.isIdentity ? 1 : 0.96)
        }
        .accessibilityLabel("\(chapter.title), \(chapter.cards.count) flashcards")
    }
}

// MARK: - Flashcards (Figma "Flashcards")

struct F1FlashcardsDeckView: View {
    let chapter: F1DeckChapter
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
            AppleMusicDarkGradientBackground()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    F1BackButton(label: "Back to Study Deck") { dismiss() }
                    Text("Flashcards")
                        .f1Font(size: 56, weight: .bold)
                        .foregroundStyle(.white)
                    Spacer()
                    F1CoinBadge(count: coins)
                }
                .padding(.horizontal, sideInset)
                .padding(.top, topInset)

                Spacer(minLength: 0)
                F1DeckCarousel(cards: chapter.cards, index: $index, size: cardSize)
                Spacer(minLength: 0)
                Color.clear.frame(height: 56)   // the reading-speed slider hangs below the card
            }
        }
        // A deck is full screen: the tab bar steps aside while it is open
        .navigationBarBackButtonHidden(true)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}


/// The card's text, split into sentences so the reading can be followed: the one being spoken is kept in the middle of the
/// card, scrolling by itself as the narration moves on, and the word being said is lit.
private struct F1NarratedBody: View {
    let text: String
    let keywords: [String]
    let spokenRange: NSRange?
    @Environment(\.f1ReduceMotion) private var reduceMotion

    private struct Sentence: Identifiable {
        let id: Int
        let text: String
        let location: Int     // UTF-16 offset in the whole text
        var length: Int { text.utf16.count }
    }

    /// Split once, when the card's text is first shown, not on every redraw.
    private let sentences: [Sentence]

    init(text: String, keywords: [String], spokenRange: NSRange?) {
        self.text = text
        self.keywords = keywords
        self.spokenRange = spokenRange
        var result: [Sentence] = []
        var current = ""
        var start = 0
        var offset = 0
        for character in text {
            current.append(character)
            offset += String(character).utf16.count
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(parts) { sentence in
                        Text(F1KeywordHighlighter.attributed(sentence.text, keywords: keywords, spokenRange: relativeRange(in: sentence)))
                            .f1Font(size: 25, weight: .regular)
                            .foregroundStyle(.white.opacity(0.97))
                            .lineSpacing(7)
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

    /// The spoken word, relative to one sentence; nil when it is in another.
    private func relativeRange(in sentence: Sentence) -> NSRange? {
        guard let spokenRange, spokenRange.location >= sentence.location, spokenRange.location < sentence.location + sentence.length else { return nil }
        let length = min(spokenRange.length, sentence.location + sentence.length - spokenRange.location)
        return NSRange(location: spokenRange.location - sentence.location, length: length)
    }
}
