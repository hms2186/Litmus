//
//  F1HomeDashboardView.swift
//  Home screen, matching the Figma "Home" frame: greeting and Weekly Streaks on top, the
//  "Ready for the session?" card in the middle, and the Revise card with Study analysis below.
//  Chapters and topics come from the loaded NCERT curriculum, so a chosen topic is exactly what
//  the engine grades.
//

import SwiftUI

struct F1HomeDashboardView: View {
    @Binding var customTopicText: String
    /// The curriculum topic picked here; the Explain screens grade and title exactly this one.
    @Binding var chosenTopic: NCERTTopic?
    @Binding var studentCountry: StudentCountry
    var activeProfile: LearnerUserProfile
    var onStartLap: () -> Void
    /// Opens the deck of a chapter: its name and its subject
    var onNavigateToRevise: ((String, String) -> Void)? = nil

    @ObservedObject private var catalog = CurriculumCatalog.shared
    @ObservedObject private var progressManager = F1SessionProgressManager.shared
    @State private var subject: Subject = .science
    @State private var chapterName = ""
    /// The chapter whose topics are open (pushed on the navigation stack)
    @State private var openChapter: OpenChapter?
    @State private var topicSearch = ""
    @StateObject private var voiceSearch = LiveSpeechRecorder()
    private struct OpenChapter: Identifiable { let id: String }
    @State private var startButtonWidth: CGFloat = 146
    @State private var revisePage = 0
    @State private var reviseChapters: [F1DeckChapter] = []
    @State private var chapterCovers: [String: String] = [:]
    @State private var isVisible = false
    @State private var topicEntryID = ""
    @State private var chapterQuery = ""
    @State private var topicQuery = ""
    @FocusState private var focusedField: Field?
    private enum Field { case chapter, topic }
    /// The width of the screen: measured from a spacer that the content cannot widen
    @State private var screenWidth: CGFloat = 1194
    @State private var hasMeasured = false
    @State private var firstScreenHeight: CGFloat = 730
    /// The Figma frame is 1312 points wide; everything on the first screen is sized from it and scales with the screen.
    private var isPortrait: Bool { screenWidth < 1100 }
    private var scale: CGFloat { screenWidth / (isPortrait ? 820 : 1312) }


    private enum Subject: String, CaseIterable, Identifiable {
        case science = "Science"
        case socialScience = "Social Science"
        var id: String { rawValue }
    }

    // Figma palette
    private let yellow = Color(red: 255/255, green: 193/255, blue: 7/255)
    private let teal = Color(red: 26/255, green: 188/255, blue: 156/255)
    private let dayLabels = ["S", "M", "T", "W", "Th", "F", "Sa"]

    init(
        customTopicText: Binding<String>,
        chosenTopic: Binding<NCERTTopic?> = .constant(nil),
        studentCountry: Binding<StudentCountry> = .constant(.india),
        activeProfile: LearnerUserProfile = sampleLearnerProfiles[0],
        onStartLap: @escaping () -> Void,
        onNavigateToRevise: ((String, String) -> Void)? = nil
    ) {
        self._customTopicText = customTopicText
        self._chosenTopic = chosenTopic
        self._studentCountry = studentCountry
        self.activeProfile = activeProfile
        self.onStartLap = onStartLap
        self.onNavigateToRevise = onNavigateToRevise
    }

    // MARK: - Curriculum choices

    /// "Grade 10" in the profile is "Class 10" in the curriculum files; only classes 9 and 10 are loaded.
    private var grade: String {
        let digits = activeProfile.academicYear.filter(\.isNumber)
        return catalog.grades.contains("Class \(digits)") ? "Class \(digits)" : "Class 10"
    }

    private var chapters: [ChapterData] {
        switch subject {
        case .science:
            return catalog.chapters(forGrade: grade, subject: "Science")
        case .socialScience:
            var seen = Set<String>()
            return catalog.socialBranches
                .flatMap { catalog.chapters(forGrade: grade, subject: "Social Science", branch: $0) }
                .filter { seen.insert($0.chapterName).inserted }
        }
    }

    private var topics: [NCERTTopic] {
        guard let chapter = chapters.first(where: { $0.chapterName == chapterName }) else { return [] }
        return catalog.topics(forChapter: chapter)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 4..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private func d(_ figma: CGFloat) -> CGFloat { figma * scale }

    // MARK: - Layout

    /// Greeting and subject on the left, Weekly Streaks (with the engineer waving) on the right; then the chapters to pick
    /// from, the topics of the chosen one with Start, and last Revise beside Study analysis. In portrait the top row stacks.
    private var firstScreen: some View {
        VStack(alignment: .leading, spacing: d(28)) {
            if isPortrait {
                VStack(alignment: .leading, spacing: d(20)) {
                    greetingHeader
                    weeklyStreaksCard.frame(height: d(140))
                }
            } else {
                HStack(alignment: .top, spacing: d(36)) {
                    greetingHeader
                    Spacer(minLength: 0)
                    weeklyStreaksCard
                        .frame(width: d(480), height: d(140))
                }
            }

            chapterSection
            // Room above the box for the engineer, who leans on its top edge and points down at it
            continueSection
                .padding(.top, d(isPortrait ? 110 : 120))
                .overlay(alignment: .topTrailing) {
                    // Centred over the Start button, leaning on the box's top edge
                    engineerPointing
                        .padding(.trailing, d(22) + startButtonWidth / 2 - d(170) * 1.02 / 2)
                        .padding(.top, d(isPortrait ? 110 : 120))
                }

            HStack(alignment: .top, spacing: d(24)) {
                reviseCard
                    .frame(width: reviseSide, height: reviseSide)
                studyAnalysisCard
                    .frame(maxHeight: reviseSide)
            }
        }
    }

    /// The Revise banner is a square; Study analysis takes the rest of the row, as tall as the banner.
    private var reviseSide: CGFloat { isPortrait ? d(330) : d(420) }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 24) {
            // The width of the screen, read from a spacer the content cannot widen
            Color.clear
                .frame(height: 0)
                .onSettledWidth { width in
                    // Eases to the new layout once, after the sidebar (or a turn of the iPad) has finished moving
                    if hasMeasured { withAnimation(.smooth(duration: 0.35)) { screenWidth = width + 116 } } else { screenWidth = width + 116; hasMeasured = true }
                }
            firstScreen
                .id("home_bottom_cards")
        }
        .padding(.leading, 40)
        .padding(.trailing, 28)
        .padding(.bottom, 48)
        .f1Feedback(.selection, trigger: subject)
        .task { restoreSelection() }
        .task(id: grade) {
            let science = F1FlashcardLibrary.chapters(subject: "Science", grade: grade)
            reviseChapters = science.filter { $0.coverImage != nil }
            let social = F1FlashcardLibrary.chapters(subject: "Social Science", grade: grade)
            chapterCovers = Dictionary(uniqueKeysWithValues: (science + social).compactMap { chapter in chapter.coverImage.map { (chapter.title, $0) } })
        }
        .sheet(item: $openChapter) { chapter in
            chapterSheet(named: chapter.id)
                .presentationSizing(.page)
                .presentationCornerRadius(36)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: "\(revisePages.count)-\(isVisible)") {
            // The banner turns to the next page by itself, but only while Home is on screen
            guard isVisible, revisePages.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.6)) { revisePage = (revisePage + 1) % revisePages.count }
            }
        }
        }
    }

    /// Coming back to Home keeps what was chosen.
    private func restoreSelection() {
        guard let chosenTopic, chosenTopic.title == customTopicText else { return }
        subject = chosenTopic.subject == "Science" ? .science : .socialScience
        chapterName = chosenTopic.chapter
        topicEntryID = subject.rawValue + chosenTopic.chapter + chosenTopic.title
        chapterQuery = chosenTopic.chapter
        topicQuery = chosenTopic.title
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
                .foregroundStyle(.white)
            Text(activeProfile.name.isEmpty ? "Driver" : activeProfile.name)
                .foregroundStyle(yellow)
        }
        .f1Font(size: d(58), weight: .semibold)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }

    /// The engineer leans on the session card's top-left edge and points straight down at "Ready for a new session?".
    /// His arm overlaps the card by about a fifth of his height; the greeting above stays clear.
    private var engineerPointing: some View {
        // The picture is 1005 x 985. The ledge he leans on is the straight edge 80.2% of the way down, and his pointing
        // hand hangs below it. Anchored to the card itself, that edge sits exactly on the card's top edge, his left
        // arm starts at the card's left edge, and the fingertip lands just above the title.
        let height = d(170)
        return Image("race_engineer_pointing")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
            .offset(y: -height * 0.802)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Weekly Streaks

    /// Compact: the title and the seven days fill the card edge to edge, centred, with no empty corner.
    private var weeklyStreaksCard: some View {
        VStack(alignment: .leading, spacing: d(14)) {
            (Text("Weekly ").foregroundStyle(.white) + Text("Streaks").foregroundStyle(yellow))
                .f1Font(size: d(32), weight: .semibold)
                .lineLimit(1)
            HStack(spacing: 0) {
                ForEach(dayLabels.indices, id: \.self) { index in
                    streakToken(index)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, d(26))
        .padding(.vertical, d(20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .glassCard(cornerRadius: d(28))
    }

    private func streakToken(_ index: Int) -> some View {
        let today = Calendar.current.component(.weekday, from: Date()) - 1
        let done = index < progressManager.weeklyStreaks.count && progressManager.weeklyStreaks[index]
        let fill: Color = index == today ? yellow : (done ? teal : Color.white.opacity(0.10))
        return Text(dayLabels[index])
            .f1Font(size: 17, weight: .medium)
            .foregroundStyle(index == today ? Color.black.opacity(0.75) : .white)
            .frame(width: d(44), height: d(44))
            .background(Circle().fill(fill))
            .overlay(alignment: .topTrailing) {
                if done && index == today {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, teal)
                        .offset(x: 4, y: -4)
                }
            }
            .accessibilityLabel("\(dayLabels[index]), \(done ? "studied" : "not studied")\(index == today ? ", today" : "")")
    }

    // MARK: - Ready for the session?

    private struct TopicEntry: Identifiable {
        let topic: NCERTTopic
        let chapter: ChapterData
        let subject: Subject
        var id: String { subject.rawValue + chapter.chapterName + topic.title }
    }

    private func chapters(in subject: Subject) -> [ChapterData] {
        switch subject {
        case .science:
            return catalog.chapters(forGrade: grade, subject: "Science")
        case .socialScience:
            var seen = Set<String>()
            return catalog.socialBranches
                .flatMap { catalog.chapters(forGrade: grade, subject: "Social Science", branch: $0) }
                .filter { seen.insert($0.chapterName).inserted }
        }
    }

    /// Which topic is chosen (so topics with the same title in different chapters stay apart)
    private var topicEntries: [TopicEntry] {
        if let chapter = chapters(in: subject).first(where: { $0.chapterName == chapterName }) {
            return catalog.topics(forChapter: chapter).map { TopicEntry(topic: $0, chapter: chapter, subject: subject) }
        }
        return chapters(in: subject).flatMap { chapter in
            catalog.topics(forChapter: chapter).map { TopicEntry(topic: $0, chapter: chapter, subject: subject) }
        }
    }

    /// Chapters matching what was typed, the chosen subject first.
    private var chapterSuggestions: [(chapter: ChapterData, subject: Subject)] {
        let query = chapterQuery.trimmingCharacters(in: .whitespaces)
        guard focusedField == .chapter, query != chapterName else { return [] }
        let ordered = [subject] + Subject.allCases.filter { $0 != subject }
        return ordered
            .flatMap { s in chapters(in: s).map { (chapter: $0, subject: s) } }
            .filter { query.isEmpty || $0.chapter.chapterName.localizedCaseInsensitiveContains(query) }
            .prefix(7).map { $0 }
    }

    /// Topics matching what was typed: inside the chosen chapter, or across the grade when none is chosen.
    private var topicSuggestions: [TopicEntry] {
        let query = topicQuery.trimmingCharacters(in: .whitespaces)
        guard focusedField == .topic, query != customTopicText else { return [] }
        let pool: [TopicEntry]
        if chapterName.isEmpty {
            guard !query.isEmpty else { return [] }
            let ordered = [subject] + Subject.allCases.filter { $0 != subject }
            pool = ordered.flatMap { s in
                chapters(in: s).flatMap { chapter in catalog.topics(forChapter: chapter).map { TopicEntry(topic: $0, chapter: chapter, subject: s) } }
            }
        } else {
            pool = topicEntries
        }
        return pool.filter { query.isEmpty || $0.topic.title.localizedCaseInsensitiveContains(query) }.prefix(7).map { $0 }
    }

    private func choose(chapter: ChapterData, in newSubject: Subject, thenTopic: Bool = true) {
        subject = newSubject
        if chapterName != chapter.chapterName {
            customTopicText = ""; chosenTopic = nil; topicEntryID = ""; topicQuery = ""
        }
        chapterName = chapter.chapterName
        chapterQuery = chapter.chapterName
        focusedField = thenTopic ? .topic : nil
    }

    /// Choosing a topic also fills in its chapter and subject.
    private func choose(_ entry: TopicEntry) {
        subject = entry.subject
        chapterName = entry.chapter.chapterName
        chapterQuery = entry.chapter.chapterName
        topicQuery = entry.topic.title
        topicEntryID = entry.id
        customTopicText = entry.topic.title
        chosenTopic = entry.topic
        focusedField = nil
    }

    private var chapterPick: Binding<String> {
        Binding(get: { chapterName }, set: { name in
            if let chapter = chapters(in: subject).first(where: { $0.chapterName == name }) { choose(chapter: chapter, in: subject, thenTopic: false) }
        })
    }

    private var topicPick: Binding<String> {
        Binding(get: { topicEntryID }, set: { id in
            if let entry = topicEntries.first(where: { $0.id == id }) { choose(entry) }
        })
    }

    private var subjectBinding: Binding<Subject> {
        Binding(get: { subject }, set: { newValue in
            subject = newValue
            if !chapters(in: newValue).contains(where: { $0.chapterName == chapterName }) {
                chapterName = ""; chapterQuery = ""; topicQuery = ""; topicEntryID = ""; customTopicText = ""; chosenTopic = nil
            }
        })
    }

    private func subjectPicker(width: CGFloat) -> some View {
        Picker("Subject", selection: subjectBinding) {
            ForEach(Subject.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: width)
    }

    // MARK: - Chapters

    private var chapterSection: some View {
        VStack(alignment: .leading, spacing: d(16)) {
            HStack(alignment: .center, spacing: d(20)) {
                Text("What chapter do you want to study")
                    .f1Font(size: d(32), weight: .semibold)
                    .foregroundStyle(Color(red: 255/255, green: 240/255, blue: 225/255))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                subjectPicker(width: d(330))
            }
            let list = chapters(in: subject)
            // The glass shelf is the width of the screen's content, and the tiles scroll inside it
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: d(20)) {
                    ForEach(Array(list.enumerated()), id: \.element.chapterName) { index, chapter in
                        chapterCard(chapter, number: index + 1)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .padding(d(16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: d(40), style: .continuous))
        }
    }

    private func chapterCard(_ chapter: ChapterData, number: Int) -> some View {
        let selected = chapter.chapterName == chapterName
        let cover = chapterCovers[chapter.chapterName]
        let titled = F1DeckChapter.coverHasTitle(chapter.chapterName)
        let side = d(isPortrait ? 250 : 290)
        let width = side
        let shape = RoundedRectangle(cornerRadius: d(26), style: .continuous)
        return Button {
            withAnimation(.smooth(duration: 0.25)) { choose(chapter: chapter, in: subject, thenTopic: false) }
            openChapter = OpenChapter(id: chapter.chapterName)
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let cover, titled {
                    Image(cover).resizable().scaledToFill()
                } else if let cover {
                    // A textbook diagram, shown whole on a light page
                    Color(red: 238/255, green: 242/255, blue: 250/255)
                    Image(cover).resizable().scaledToFit().padding(d(20)).padding(.bottom, d(40))
                } else {
                    LinearGradient(colors: [Color(red: 70/255, green: 24/255, blue: 30/255), Color(red: 18/255, green: 18/255, blue: 24/255)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: d(70)))
                        .foregroundStyle(.white.opacity(0.18))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, d(30))
                }
                // A soft shade behind the chapter number and topic count, so they read on any picture
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.28))
                if !titled {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    Text(chapter.chapterName)
                        .f1Font(size: d(22), weight: .semibold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(d(14))
                }
            }
            .frame(width: width, height: side)
            .clipShape(shape)
            .overlay(alignment: .top) {
                HStack {
                    Text(String(format: "CH %02d", number))
                    Spacer()
                    Text("\(catalog.topics(forChapter: chapter).count) Topics")
                }
                .f1Font(size: d(14), weight: .medium)
                .foregroundStyle(.white)
                .padding(d(12))
                .shadow(color: .black.opacity(0.6), radius: 4)
            }
            .overlay(shape.stroke(selected ? Color(red: 255/255, green: 59/255, blue: 48/255) : Color.white.opacity(0.18), lineWidth: selected ? 3.5 : 1))
            .shadow(color: selected ? Color.red.opacity(0.35) : .clear, radius: 14)
            .contentShape(shape)
        }
        .buttonStyle(.f1CardSpring)
        .accessibilityLabel("\(chapter.chapterName), \(catalog.topics(forChapter: chapter).count) topics")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Chapter sheet: pick a topic (Choose Activities style: a search field, a list with selection circles, a tick)

    private func chapterSheet(named name: String) -> some View {
        let matches = topicEntries.filter { topicSearch.isEmpty || $0.topic.title.localizedCaseInsensitiveContains(topicSearch) }
        return NavigationStack {
            List {
                ForEach(matches) { entry in
                    let picked = entry.id == topicEntryID
                    Button { withAnimation(.smooth(duration: 0.2)) { choose(entry) } } label: {
                        HStack(spacing: 14) {
                            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24))
                                .foregroundStyle(picked ? Color.blue : Color.white.opacity(0.35))
                            Text(entry.topic.title)
                                .f1Font(size: 19)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
                if matches.isEmpty {
                    Text("No topics match \u{201C}\(topicSearch)\u{201D}")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { topicSearchField }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { openChapter = nil } label: { Image(systemName: "xmark") }
                        .tint(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Not the system confirm role, which takes the app's red accent
                    Button {
                        onStartLap()
                        if !customTopicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { openChapter = nil }
                    } label: { Image(systemName: "checkmark").fontWeight(.semibold) }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(Color(red: 10/255, green: 132/255, blue: 255/255))
                    .disabled(topicEntryID.isEmpty)
                    .accessibilityLabel("Start")
                }
            }
            .background { AppleMusicDarkGradientBackground().ignoresSafeArea() }
        }
        .tint(.blue)
        .preferredColorScheme(.dark)
        .onDisappear { topicSearch = ""; voiceSearch.stopRecording() }
    }

    /// The search field of the topic sheet: type, or tap the mic and say the topic.
    private var topicSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
            TextField("Search topics", text: $topicSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)
                .submitLabel(.search)
                .foregroundStyle(.white)
            if !topicSearch.isEmpty {
                Button { topicSearch = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5)) }
                    .accessibilityLabel("Clear search")
            }
            Button {
                voiceSearch.toggleRecording { text in topicSearch = text }
            } label: {
                Image(systemName: voiceSearch.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(voiceSearch.isRecording ? Color.red : .white.opacity(0.8))
                    .symbolEffect(.pulse, isActive: voiceSearch.isRecording)
            }
            .accessibilityLabel(voiceSearch.isRecording ? "Stop voice search" : "Search by voice")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Continue where you left off

    /// The latest session whose explanation needed another look.
    private var pendingReview: F1SessionRecord? {
        progressManager.sessions.first(where: { $0.reviewNote != nil })
    }

    private var continueSection: some View {
        let pending = pendingReview
        return HStack(alignment: .center, spacing: d(20)) {
            VStack(alignment: .leading, spacing: d(8)) {
                Text("Continue where you left off")
                    .f1Font(size: d(32), weight: .semibold)
                    .foregroundStyle(Color(red: 255/255, green: 240/255, blue: 225/255))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let pending {
                    Text(pending.topic)
                        .f1Font(size: d(22), weight: .medium)
                        .foregroundStyle(yellow)
                        .lineLimit(1)
                    Text(pending.reviewNote ?? "")
                        .f1Font(size: d(17))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                } else {
                    Text("Nothing to revisit yet. Pick a chapter above to begin.")
                        .f1Font(size: d(20))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { continueLastSession() } label: {
                Text("Start")
                    .f1Font(size: d(18), weight: .semibold)
                    .frame(minWidth: d(146) - 40, minHeight: d(70) - 28)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .tint(Color(red: 0/255, green: 102/255, blue: 255/255))
            .disabled(pending == nil)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { startButtonWidth = $0 }
        }
        .padding(d(22))
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 28)
    }

    /// Start: straight to the topic the student explained last and was told to review again.
    private func continueLastSession() {
        guard let record = pendingReview else { return }
        let catalog = CurriculumCatalog.shared
        let all = catalog.allChapters.flatMap { catalog.topics(forChapter: $0) }
        guard let topic = all.first(where: { $0.title == record.topic && $0.chapter == record.chapter })
            ?? all.first(where: { $0.title == record.topic }) else { return }
        chosenTopic = topic
        customTopicText = topic.title
        Task { @MainActor in onStartLap() }
    }

    // MARK: - Revise
    // Each page is a chapter with an NCERT textbook diagram, so the card shows something to revise.

    private struct RevisePage: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let image: String?
        /// Where tapping it goes: the deck of this chapter
        var chapter = ""
        var subject = "Science"
    }

    /// The topics studied in the last five days, newest first; before any session, the chapters with diagrams.
    private var revisePages: [RevisePage] {
        let recent = progressManager.recentTopics(days: 5, limit: 5)
        if !recent.isEmpty {
            return recent.map { record in
                RevisePage(id: record.id.uuidString, title: record.topic, subtitle: "\(record.chapter) · \(dayLabel(for: record.date))", image: chapterCovers[record.chapter], chapter: record.chapter, subject: record.subject.isEmpty ? "Science" : record.subject)
            }
        }
        if reviseChapters.isEmpty { return [RevisePage(id: "flashcards", title: "Flashcards", subtitle: "", image: nil)] }
        return reviseChapters.prefix(5).map { RevisePage(id: $0.id, title: $0.title, subtitle: "", image: $0.coverImage, chapter: $0.title, subject: $0.subject) }
    }

    private func dayLabel(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    /// A square banner: the chapter's cover picture fills it edge to edge, REVISE on the lower part, page dots under it.
    private var reviseCard: some View {
        let pages = revisePages
        return Button {
            if let page = pages.indices.contains(revisePage) ? pages[revisePage] : pages.first, !page.chapter.isEmpty { onNavigateToRevise?(page.chapter, page.subject) }
        } label: {
            ZStack(alignment: .top) {
                TabView(selection: $revisePage) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        revisePage(title: page.title, subtitle: page.subtitle, image: page.image).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                // The same soft shade the chapter cards have behind their labels, then the word raised off the picture
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.28))
                    .allowsHitTesting(false)
                reviseWord
                    .padding(.top, d(18))
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.07, green: 0.07, blue: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: d(26), style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
        }
        .buttonStyle(.f1CardSpring)
        .onChange(of: pages.count) { _, count in if revisePage >= count { revisePage = 0 } }
        .accessibilityLabel("Revise flashcards")
    }

    /// REVISE with depth: stacked darker copies make the thickness, a light-to-warm face sits on top, and a soft shadow lifts it.
    private var reviseWord: some View {
        let word = Text("REVISE").f1Font(size: d(40), weight: .heavy).tracking(1.5)
        return ZStack {
            ForEach(1..<7, id: \.self) { layer in
                word.foregroundStyle(Color(red: 0.45, green: 0.05, blue: 0.08).opacity(0.9)).offset(y: CGFloat(layer) * 1.4)
            }
            word.foregroundStyle(LinearGradient(colors: [.white, Color(red: 1, green: 0.86, blue: 0.7)], startPoint: .top, endPoint: .bottom))
        }
        .shadow(color: .black.opacity(0.5), radius: 10, y: 10)
        .compositingGroup()
    }

    private func revisePage(title: String, subtitle: String, image: String?) -> some View {
        Group {
            if let image {
                // The cover fills the whole banner
                Color.clear.overlay { Image(image).resizable().scaledToFill() }
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                VStack(spacing: 6) {
                    Text(title)
                        .f1Font(size: 30, weight: .bold)
                        .foregroundStyle(Color.black.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.top, 22)
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(Color(red: 0.25, green: 0.4, blue: 0.8).opacity(0.5))
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, 110)
                }
            }
        }
    }

    // MARK: - Study analysis

    private var studyAnalysisCard: some View {
        let minutes = progressManager.dailyStudyMinutes
        let values = dayLabels.indices.map { minutes.indices.contains($0) ? minutes[$0] : 0 }
        let top = max(100.0, values.max() ?? 100)
        // The chart takes what is left of the card under the title
        let chartH = max(80, reviseSide - 150)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(red: 255/255, green: 24/255, blue: 36/255))
                Text("Study analysis")
                    .f1Font(size: 26, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach([100, 80, 60, 40, 20, 0], id: \.self) { tick in
                        Text(tick == 0 ? "0 min" : "\(Int(top) * tick / 100) min")
                            .f1Font(size: 12, weight: .medium)
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxHeight: .infinity, alignment: tick == 0 ? .bottom : .top)
                    }
                }
                .frame(width: 56, height: chartH)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(dayLabels.indices, id: \.self) { index in
                        VStack(spacing: 8) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(teal)
                                .frame(maxWidth: 28, minHeight: 0).frame(height: values[index] > 0 ? max(3, CGFloat(values[index] / top) * chartH) : 0)
                            Text(dayLabels[index])
                                .f1Font(size: 13, weight: .medium)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: chartH + 28)
                .background(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(0..<6) { _ in
                            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                            Spacer()
                        }
                    }
                    .frame(height: chartH)
                }
            }
            .animation(AppMotionSystem.smooth, value: values)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Minutes studied per day this week")
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 32)
    }
}

private extension View {
    /// A tile in the system's Liquid Glass (regular variant), with the system's own edge and highlights.
    func glassCard(cornerRadius: CGFloat) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Lays the topics out as wrapping rows, so all of them show at once without scrolling.
private struct TopicFlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? 700, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
