//
//  SettingsView.swift
//  Settings, About You and Privacy & Data, following the Figma frames. The gear button on the home
//  screens opens Settings; the toggles are saved on the device and used where they apply:
//  Widget Timer (the Live Activity during a lap), Study Reminders (a daily notification) and Sound
//  Effects (the engineer's voice). App Blocking is saved as a preference only.
//

import SwiftUI
import UserNotifications

private let settingsRed = Color(red: 255/255, green: 24/255, blue: 48/255)

/// A daily study reminder at 5 pm, added or removed from Settings.
enum StudyReminder {
    static let identifier = "study_reminder_daily"

    static func setEnabled(_ enabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else {
            // Off means off: every scheduled notification (timer, revisit, revise, streak) goes, and no push either
            NotificationManager.shared.cancelAll()
            UIApplication.shared.unregisterForRemoteNotifications()
            return true
        }
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return false }
        await PushRegistration.registerIfAuthorized()
        return await schedule(name: ProfileStore.shared.active.name, topic: LitmusWidgetStore.load().topics.first?.topic)
    }

    /// The daily reminder, named for the student and pointing at what they studied last. Rewritten whenever the app
    /// leaves the screen, so its words stay current.
    static func schedule(name: String, topic: String?) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        let first = name.trimmingCharacters(in: .whitespaces)
        content.title = first.isEmpty ? "Time to study" : "Time to study, \(first)"
        if let topic, !topic.isEmpty {
            content.body = "Pick up where you left off: \(topic). A short focus session keeps your streak going."
        } else {
            content.body = "A short focus session keeps your streak going."
        }
        content.threadIdentifier = "litmus.daily"
        content.sound = .default
        var time = DateComponents()
        time.hour = 17
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true))
        return (try? await center.add(request)) != nil
    }
}

/// Tells a settings screen it is shown in the right-hand pane, which already has the app background behind it.
private struct InSettingsPaneKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var inSettingsPane: Bool {
        get { self[InSettingsPaneKey.self] }
        set { self[InSettingsPaneKey.self] = newValue }
    }
}

/// Settings laid out like the iPad's own Settings app: a sidebar of grouped rows with coloured icon tiles on the left
/// and the chosen screen on the right. On a phone-sized width the same rows push their screens one by one.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var progress = StudyProgressManager.shared

    @ObservedObject private var blocker = ScreenTimeManager.shared
    @ObservedObject private var profileStore = ProfileStore.shared
    @State private var showResetApp = false
    @AppStorage("settings_widget_timer") private var widgetTimer = true
    @AppStorage("settings_study_reminders") private var reminders = false
    @AppStorage(EngineerVoice.soundSettingKey) private var soundEffects = true
    @AppStorage("learner_name") private var learnerName = ""
    @AppStorage("learner_avatar") private var learnerAvatar = 0
    @AppStorage("learner_grade") private var learnerGrade = "Grade 10"
    @AppStorage("learner_curriculum") private var learnerCurriculum = "NCERT"

    private enum Screen: Hashable { case about, accessibility, appBlocking, privacy }
    /// Pushed on a navigation stack that already exists (from the gear): the stack's own back button returns. Presented
    /// on its own (from Revise): it brings a stack, with a back button that closes it.
    var embedded = false
    @Environment(\.openURL) private var openURL
    @State private var showReminderDenied = false
    /// Wide enough for the sidebar and a screen side by side
    @State private var isSplit = false
    @State private var selection: Screen = .about

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        if !isSplit {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                                    .accessibilityLabel("Close")
                            }
                        }
                    }
            }
        }
    }

    private var content: some View {
        Group {
            if isSplit { splitLayout } else { compactLayout }
        }
        .onSettledWidth { isSplit = $0 >= 820 }
        .background { AppBackground().ignoresSafeArea() }
        .toolbarVisibility(isSplit ? .hidden : .visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onChange(of: reminders) { _, enabled in
            Task {
                let ok = await StudyReminder.setEnabled(enabled)
                if enabled && !ok { reminders = false; showReminderDenied = true }
            }
        }
        // Actionable, so an alert fits: it offers the one thing that fixes it
        .alert("Notifications Are Off", isPresented: $showReminderDenied) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Allow notifications for Litmus in Settings to get study reminders.")
        }
        // An alert: it says what will be lost, the destructive choice is named for what it does, and Cancel sits beside it
        .alert("Reset Litmus?", isPresented: $showResetApp) {
            Button("Cancel", role: .cancel) {}
            Button("Reset App", role: .destructive) {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                profileStore.resetAll()
                dismiss()
            }
        } message: {
            Text("All profiles, coins, streaks and study history on this iPad will be deleted, and Litmus will start setup again. This can’t be undone.")
        }
    }

    // MARK: Layouts

    private var compactLayout: some View {
        // The scroll view is the root of the screen, so the large title collapses with it
        ScrollView(.vertical, showsIndicators: false) {
            sidebarRows
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .largeTitle("Settings")
    }

    private func title(for screen: Screen) -> String {
        switch screen {
        case .about: return "About You"
        case .accessibility: return "Accessibility"
        case .appBlocking: return "App Blocking"
        case .privacy: return "Privacy & Data"
        }
    }

    /// Both columns start with a header of the same height, so the two titles sit on one line, and share the same side margins
    private let headerHeight: CGFloat = 60
    private let sideMargin: CGFloat = 16
    /// Room above both headers, so nothing sits against the top edge
    private let topInset: CGFloat = 36

    private var splitLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Button { dismiss() } label: {
                        Image(systemName: embedded ? "chevron.left" : "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 28, height: 28)
                    }
                    .litmusGlassButton()
                    .buttonBorderShape(.circle)
                    .tint(.white)
                    .accessibilityLabel(embedded ? "Back" : "Close")
                    Text("Settings").scaledFont(size: 32, weight: .bold).foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, sideMargin)
                .padding(.top, topInset)
                .frame(height: headerHeight + topInset)
                ScrollView(.vertical, showsIndicators: false) {
                    sidebarRows
                        .padding(.horizontal, sideMargin)
                        .padding(.bottom, 48)
                }
            }
            .frame(width: 380)
            Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(title(for: selection))
                    .scaledFont(size: 32, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 32)
                    .padding(.top, topInset)
                    .frame(maxWidth: .infinity, minHeight: headerHeight + topInset, maxHeight: headerHeight + topInset, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                destination(for: selection)
                    .id(selection)
                    .environment(\.inSettingsPane, true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Content runs under the home indicator instead of stopping above it; the lists keep their own bottom padding
        .ignoresSafeArea(.container, edges: .bottom)
    }

    @ViewBuilder
    private func destination(for screen: Screen) -> some View {
        switch screen {
        case .about:
            AboutYouView()
                .padding(.horizontal, 32).padding(.bottom, isSplit ? 0 : 24)
                .background { if !isSplit { AppBackground().ignoresSafeArea() } }
                // The Name alert's keyboard must not squeeze the cards behind it
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .ignoresSafeArea(.container, edges: isSplit ? .bottom : [])
                .centeredTitle("About You")
        case .accessibility:
            AccessibilitySettingsView()
        case .appBlocking:
            AppBlockingView()
        case .privacy:
            PrivacyView()
                .padding(.horizontal, 32).padding(.bottom, isSplit ? 0 : 24)
                .background { if !isSplit { AppBackground().ignoresSafeArea() } }
                .centeredTitle("Privacy & Data")
        }
    }

    // MARK: Sidebar rows

    private var sidebarRows: some View {
        VStack(spacing: 22) {
            // The learner, like the Apple Account row at the top of the iPad's Settings
            group { profileRow }
            group {
                toggleRow("bell.badge.fill", Color(red: 1.0, green: 0.27, blue: 0.23), "Notifications", $reminders)
                separator
                toggleRow("speaker.wave.3.fill", Color(red: 1.0, green: 0.18, blue: 0.33), "Sound Effects", $soundEffects)
                separator
                toggleRow("timer", Color(red: 1.0, green: 0.62, blue: 0.04), "Widget Timer", $widgetTimer)
                separator
                navRow(.appBlocking, "hourglass", Color(red: 0.35, green: 0.34, blue: 0.84), "App Blocking", value: blocker.isAppBlockingEnabled ? "On" : "Off")
            }
            group {
                navRow(.accessibility, "accessibility", Color(red: 0.04, green: 0.52, blue: 1.0), "Accessibility")
                separator
                navRow(.privacy, "hand.raised.fill", Color(red: 0.04, green: 0.52, blue: 1.0), "Privacy & Data")
                separator
                // English is the only language, so this is a plain value, not something to open
                valueRow("globe", Color(red: 0.56, green: 0.56, blue: 0.58), "Language", "English")
            }
            group { resetRow }
        }
        .padding(.top, 4)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .litmusGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.leading, 64)
    }

    /// The coloured rounded tile with a white symbol, as in the system's Settings
    private func tile(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
    }

    private func rowBody<Trailing: View>(_ symbol: String, _ color: Color, _ title: String, selected: Bool = false, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            tile(symbol, color)
            Text(title).scaledFont(size: 19).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background {
            if selected { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.16)).padding(.horizontal, 4) }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func navRow(_ screen: Screen, _ symbol: String, _ color: Color, _ title: String, value: String? = nil) -> some View {
        let body = rowBody(symbol, color, title, selected: isSplit && selection == screen) {
            HStack(spacing: 8) {
                if let value { Text(value).scaledFont(size: 18).foregroundStyle(.white.opacity(0.6)) }
                if !isSplit { chevron }
            }
        }
        if isSplit {
            Button { selection = screen } label: { body }.buttonStyle(.plain)
        } else {
            NavigationLink { destination(for: screen).minimalBackButton() } label: { body }.buttonStyle(.plain)
        }
    }

    private func toggleRow(_ symbol: String, _ color: Color, _ title: String, _ binding: Binding<Bool>) -> some View {
        rowBody(symbol, color, title) {
            Toggle("", isOn: binding).labelsHidden().tint(Color(red: 0.20, green: 0.78, blue: 0.35))
        }
        .accessibilityElement(children: .combine)
    }

    private func valueRow(_ symbol: String, _ color: Color, _ title: String, _ value: String) -> some View {
        rowBody(symbol, color, title) {
            Text(value).scaledFont(size: 18).foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
    }

    /// The learner at the top: picture, name, and what they study
    @ViewBuilder
    private var profileRow: some View {
        let label = HStack(spacing: 14) {
            ProfileAvatar(index: learnerAvatar, size: 58, ring: .clear, name: learnerName)
            VStack(alignment: .leading, spacing: 2) {
                Text(learnerName.isEmpty ? "Driver" : learnerName).scaledFont(size: 22, weight: .semibold).foregroundStyle(.white).lineLimit(1)
                Text("About You · \(learnerCurriculum) · \(learnerGrade)").scaledFont(size: 14).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !isSplit { chevron }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background {
            if isSplit && selection == .about { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.16)).padding(.horizontal, 4) }
        }
        .contentShape(Rectangle())
        if isSplit {
            Button { selection = .about } label: { label }.buttonStyle(.plain)
        } else {
            NavigationLink { destination(for: .about).minimalBackButton() } label: { label }.buttonStyle(.plain)
        }
    }

    /// The last row: erases everything on this iPad and returns to first-time setup.
    private var resetRow: some View {
        Button { showResetApp = true } label: {
            rowBody("arrow.counterclockwise", Color(red: 1.0, green: 0.27, blue: 0.23), "Reset App") { EmptyView() }
                .foregroundStyle(Color(red: 255/255, green: 69/255, blue: 58/255))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About You

struct AboutYouView: View {
    @ObservedObject private var progress = StudyProgressManager.shared
    @ObservedObject private var profileStore = ProfileStore.shared
    @State private var confirmDeleteProfile = false
    @AppStorage("learner_name") private var name = ""
    @AppStorage("learner_curriculum") private var curriculum = "NCERT"
    @AppStorage("learner_grade") private var grade = "Grade 10"
    @AppStorage("learner_about") private var aboutMe = ""
    @AppStorage("learner_daily_goal_minutes") private var dailyGoal = 120
    @AppStorage("learner_avatar") private var avatar = 0

    @State private var showAllSessions = false
    @State private var isNarrow = false
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var editingAbout = false
    @State private var confirmDiscardAbout = false
    @State private var aboutDraft = ""
    @State private var editingAvatar = false
    @State private var editingGoal = false
    @State private var showCalendar = false
    /// The daily goal when its sheet opened, so Cancel can put it back
    @State private var goalAtOpen: Int?

    private let curricula = ["NCERT", "ICSE", "NGSS", "International Baccalaureate"]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 20
            if isNarrow {
                // Portrait and narrow windows: one column that scrolls, so no text is squeezed
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: gap) {
                        profileCard
                        todayCard.frame(height: 280)
                        lastSessionCard.frame(minHeight: 260)
                        summaryCard.frame(minHeight: 260)
                        recentCard.frame(minHeight: 340)
                    }
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea(edges: .bottom)
            } else {
                let width = max(0, geo.size.width - gap * 2)
                HStack(alignment: .top, spacing: gap) {
                    VStack(spacing: gap) {
                        todayCard.frame(height: geo.size.height * 0.46)
                        recentCard
                    }
                    .frame(width: width * 0.31)
                    VStack(spacing: gap) {
                        lastSessionCard.frame(height: geo.size.height * 0.46)
                        summaryCard
                    }
                    .frame(width: width * 0.31)
                    profileCard
                        .frame(width: width * 0.38)
                }
            }
        }
        // Switches between the columns and the single column once, after the sidebar has finished moving
        .onSettledWidth { width in isNarrow = width < 900 }
        .alert("Your Name", isPresented: $editingName) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        .sheet(isPresented: $editingAvatar) { AvatarPicker(selection: $avatar) }
        .sheet(isPresented: $editingGoal) { goalEditor }
        .sheet(isPresented: $showCalendar) { StudyCalendarSheet().presentationSizing(.page) }
        .sheet(isPresented: $editingAbout) {
            NavigationStack {
                TextEditor(text: $aboutDraft)
                    .padding()
                    .navigationTitle("About Me")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        // Cancel on the left, Save on the right. With edits not yet saved, Cancel asks before throwing them away
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { if aboutDraft == aboutMe { editingAbout = false } else { confirmDiscardAbout = true } }
                                .confirmationDialog("Discard your changes?", isPresented: $confirmDiscardAbout, titleVisibility: .visible) {
                                    Button("Discard Changes", role: .destructive) { editingAbout = false }
                                    Button("Keep Editing", role: .cancel) {}
                                }
                        }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { aboutMe = aboutDraft; editingAbout = false } }
                    }
            }
            // Half height to start, and up to full height: the keyboard takes much of an iPhone screen, so the text needs the room
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            // Swiping the sheet away would lose the edits, so it waits for Save or Cancel until something has changed
            .interactiveDismissDisabled(aboutDraft != aboutMe)
        }
    }

    // MARK: Cards

    private func card<Content: View>(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .scaledFont(size: 16, weight: .bold)
                    .tracking(1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(settingsRed)
                Spacer()
                if let trailing { trailing }
            }
            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .litmusGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var todayCard: some View {
        let minutes = Int(progress.studiedMinutesToday.rounded())
        let fraction = min(1, progress.studiedMinutesToday / Double(max(dailyGoal, 1)))
        return card("TODAY", trailing: AnyView(
            Button { editingGoal = true } label: {
                Label("Edit goal", systemImage: "pencil")
                    .scaledFont(size: 16, weight: .medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .litmusGlassButton()
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Edit daily goal")
        )) {
            Spacer(minLength: 0)
            Text(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m")
                .scaledFont(size: 58, weight: .bold)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text("Study time")
                .scaledFont(size: 22)
                .foregroundStyle(.white.opacity(0.7))
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(settingsRed).frame(width: max(0, bar.size.width * (fraction.isFinite ? fraction : 0)))
                }
            }
            .frame(height: 12)
            HStack {
                Text("\(Int(fraction * 100))%")
                Spacer()
                Text("\(goalLabel(dailyGoal)) goal")
            }
            .scaledFont(size: 18)
            .foregroundStyle(.white.opacity(0.75))
            .animation(.smooth, value: fraction)
        }
    }

    private func sessionThumb(_ record: StudySession, size: CGFloat) -> some View {
        let image = AboutYouView.diagram(for: record.topic)
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.35), Color(red: 0.35, green: 0.05, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image {
                Image(image).resizable().scaledToFit().padding(6).background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous)).padding(4)
            } else {
                Image(systemName: "atom").font(.system(size: size * 0.45)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static func diagram(for topic: String) -> String? {
        guard let match = CurriculumCatalog.shared.topic(withTitle: topic) else { return nil }
        return FlashcardLibrary.cards(for: match).first(where: { $0.imageName != nil })?.imageName
    }

    private func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today, \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return date.formatted(.dateTime.day().month(.abbreviated)) + ", " + time
    }

    private var lastSessionCard: some View {
        card("LAST SESSION") {
            if let last = progress.sessions.first {
                HStack(spacing: 18) {
                    sessionThumb(last, size: 96)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(last.topic).scaledFont(size: 26).foregroundStyle(.white).lineLimit(2)
                        Label(last.subject.isEmpty ? "Science" : last.subject, systemImage: "book").scaledFont(size: 17).foregroundStyle(.white.opacity(0.7))
                        Label("\(when(last.date))  |  \(max(1, last.seconds / 60)) min", systemImage: "calendar").scaledFont(size: 16).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Divider().overlay(Color.white.opacity(0.12))
                if let note = last.reviewNote {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                        Text("Needs review: \(note)").scaledFont(size: 19).foregroundStyle(.white).lineLimit(2)
                    }
                } else {
                    Label("Nothing to review", systemImage: "checkmark.circle.fill").scaledFont(size: 19).foregroundStyle(.white.opacity(0.8))
                }
            } else {
                emptyNote("Finish a focus session to see it here.")
            }
        }
    }

    private var recentCard: some View {
        card("RECENT SESSIONS", trailing: AnyView(
            Button { withAnimation(.smooth) { showAllSessions.toggle() } } label: {
                Text(showAllSessions ? "Show less" : "View All")
                    .scaledFont(size: 17).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .litmusGlass(interactive: true, in: Capsule())
            }
        )) {
            if progress.sessions.isEmpty {
                emptyNote("No sessions yet.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(progress.sessions.prefix(showAllSessions ? 12 : 2)) { record in
                            HStack(spacing: 14) {
                                sessionThumb(record, size: 64)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.topic).scaledFont(size: 19).foregroundStyle(.white).lineLimit(1)
                                    Text(when(record.date)).scaledFont(size: 14).foregroundStyle(.white.opacity(0.65))
                                }
                                Spacer()
                                Text("\(max(1, record.seconds / 60)) min").scaledFont(size: 18).foregroundStyle(.white.opacity(0.85))
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    /// Today's date with what was covered, and a chevron that opens the month calendar (a year of history).
    private var summaryCard: some View {
        card("CALENDAR", trailing: AnyView(
            Button { showCalendar = true } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
            }
            .litmusGlassButton()
            .buttonBorderShape(.circle)
            .accessibilityLabel("Open calendar")
        )) {
            CalendarTodayContent(progress: progress)
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).scaledFont(size: 18).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity, minHeight: 90)
    }

    // MARK: Profile

    /// At the bottom of the profile: removes this learner (the only profile too: the app then starts setup again).
    private var deleteProfileButton: some View {
        let shownName = name.isEmpty ? "this profile" : name
        return VStack(spacing: 6) {
            Button(role: .destructive) { confirmDeleteProfile = true } label: {
                Text("Delete Profile")
                    .scaledFont(size: 19, weight: .medium)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color(red: 255/255, green: 69/255, blue: 58/255))
            }
            .litmusGlassButton()
            .buttonBorderShape(.capsule)
        }
        .alert("Delete “\(shownName)”?", isPresented: $confirmDeleteProfile) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { profileStore.deleteActive() }
        } message: {
            Text(profileStore.isOnlyProfile
                 ? "This is the only profile. Deleting it removes its coins, streaks and study history and starts setup again. This can’t be undone."
                 : "Its coins, streaks and study history will be removed. This can’t be undone.")
        }
    }

    private var profileCard: some View {
        VStack(spacing: 14) {
            // The picture is itself the control, with "edit" along its lower edge
            Button { editingAvatar = true } label: {
                EditablePicture(index: avatar, name: name)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile picture")
            HStack(spacing: 12) {
                Text(name.isEmpty ? "Driver" : name).scaledFont(size: 40, weight: .bold).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                pencil { nameDraft = name; editingName = true }
            }
            Divider().overlay(Color.white.opacity(0.12))
            // Each value is chosen with the system pop-up picker: tap it, pick from the list
            pickerRow(icon: "book", label: "Curriculum") {
                Picker("Curriculum", selection: $curriculum) { ForEach(curricula, id: \.self) { Text($0).tag($0) } }
            }
            pickerRow(icon: "graduationcap", label: "Grade") {
                Picker("Grade", selection: $grade) { ForEach(6...10, id: \.self) { Text("\($0)th").tag("Grade \($0)") } }
            }
            Divider().overlay(Color.white.opacity(0.12))
            HStack {
                Image(systemName: "doc.text").font(.system(size: 22)).foregroundStyle(.white).frame(width: 44)
                Text("About Me").scaledFont(size: 19).foregroundStyle(.white.opacity(0.85))
                Spacer()
                pencil { aboutDraft = aboutMe; editingAbout = true }
            }
            Text(aboutMe.isEmpty ? "Tell us a little about yourself." : aboutMe)
                .scaledFont(size: 18)
                .foregroundStyle(aboutMe.isEmpty ? .white.opacity(0.5) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 0)
            deleteProfileButton
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    // MARK: Daily goal

    private func goalLabel(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// One preset chip of the goal sheet: a capsule on a single line, never broken across lines
    private func goalPreset(_ preset: Int) -> some View {
        Button { dailyGoal = preset } label: {
            Text(goalLabel(preset))
                .scaledFont(size: 16, weight: .medium)
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16).padding(.vertical, 9)
        }
        .litmusGlassStyle(prominent: dailyGoal == preset)
        .buttonBorderShape(.capsule)
    }

    private var goalEditor: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text(goalLabel(dailyGoal))
                    .scaledFont(size: 64, weight: .bold)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.2), value: dailyGoal)
                Stepper("Daily goal", value: $dailyGoal, in: 15...480, step: 15)
                    .labelsHidden()
                    .scaleEffect(1.25)
                // One row where the five presets fit (iPad); on a narrow iPhone, or at a large text size, they wrap onto two
                // rows instead of squeezing until the labels break letter by letter
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ForEach([30, 60, 90, 120, 180], id: \.self) { goalPreset($0) }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach([30, 60, 90, 120, 180], id: \.self) { goalPreset($0).frame(maxWidth: .infinity) }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Daily Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel on the left puts the goal back as it was when the sheet opened; Done on the right keeps the one chosen
                // (the stepper and the presets change it as they are used, so Cancel has something to undo)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let goalAtOpen { dailyGoal = goalAtOpen }
                        editingGoal = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { editingGoal = false } }
            }
            .onAppear { goalAtOpen = dailyGoal }
        }
        // At large text sizes the content needs more than 380 points, so the sheet can be pulled up, and the grabber shows it can
        .presentationDetents([.height(380), .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func ordinal(_ grade: String) -> String {
        let digits = grade.filter(\.isNumber)
        return digits.isEmpty ? grade : "\(digits)th"
    }

    private var pencilIcon: some View {
        Image(systemName: "pencil")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
    }

    private func pencil(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { pencilIcon }.litmusGlassButton().buttonBorderShape(.circle).accessibilityLabel("Edit")
    }

    private func pickerRow<P: View>(icon: String, label: String, @ViewBuilder picker: () -> P) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.white.opacity(0.9)).frame(width: 44)
            Text(label).scaledFont(size: 19).foregroundStyle(.white.opacity(0.85))
            Spacer()
            picker()
                .pickerStyle(.menu)
                .labelsHidden()
                .buttonBorderShape(.capsule)
                .tint(.white)
        }
        .frame(minHeight: 52)
    }
}

// MARK: - Privacy & Data

struct PrivacyView: View {
    @ObservedObject private var progress = StudyProgressManager.shared
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            note("mic", "Your voice stays on this iPad", "Speech is recognised on the device when it can be, and recordings are not kept after your explanation is checked.")
            note("cpu", "Answers are checked on the device", "Your explanations are graded by the on-device model. Nothing you say or write is sent to a server.")
            note("internaldrive", "What is saved", "Your name, grade, coins, streaks, study minutes and a short list of recent sessions are saved on this iPad only.")
            Spacer()
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Delete my study history")
                    .scaledFont(size: 19, weight: .medium)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(settingsRed.opacity(0.25), in: Capsule())
                    .foregroundStyle(.white)
            }
            .confirmationDialog("Delete your study history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete history", role: .destructive) { progress.clearStudyData() }
            } message: {
                Text("Streaks, study minutes and sessions will be cleared. Your coins stay.")
            }
        }
        .padding(.top, 6)
    }

    private func note(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.white).frame(width: 58, height: 58).background(settingsRed.opacity(0.28), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).scaledFont(size: 22, weight: .semibold).foregroundStyle(.white)
                Text(text).scaledFont(size: 18).foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
        }
        .padding(18)
        .litmusGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}


/// A profile picture that is its own edit control: a soft shade with "edit" always along its lower edge (touch has no
/// hover). No highlight plate and no ring.
private struct EditablePicture: View {
    var index: Int
    var name: String

    var body: some View {
        ProfileAvatar(index: index, size: 128, ring: .clear, name: name)
            .overlay(alignment: .bottom) {
                Text("edit")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20).padding(.bottom, 10)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(Circle())
            .contentShape(Circle())
    }
}
