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

// MARK: - Shared look of the settings screens

/// Every settings screen is groups of rows, each group one native Liquid Glass card (`litmusGlass`) on the app background. Inside
/// the card the rows are a real (non-scrolling) `List`, so the rows, their layout and the separators between them are the system's,
/// exactly as in the Settings app; the card's height follows the list's content.
enum SettingsStyle {}

extension View {
    /// Kept so every row reads the same; the list gives a row its own padding and height
    func settingsRow() -> some View { self }
}

/// The button style of a row that is itself a button: the whole row is the target and it dims while pressed
struct SettingsRowButton: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// The title above a group, drawn by the system as a real `Section("…")` header (the standard header style, as in a `Form`): a
/// list that holds only that section, so its text style, size and position are the official ones.
private struct SettingsSectionHeader: View {
    let title: String
    var body: some View {
        List {
            Section {
                Color.clear.frame(height: 0)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text(title)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .listSectionSpacing(0)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(height: 34)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A group of rows in one glass card: a prominent header above it, a footer below it. The rows are a native plain `List` with
/// system separators (starting `inset` points in; 58 clears a row's tile).
struct SettingsGroup<Content: View>: View {
    var header: String?
    var footer: String?
    var inset: CGFloat = 16
    @ViewBuilder var content: Content
    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header { SettingsSectionHeader(title: header) }
            List {
                // One section, with the separators above its first row and below its last hidden, so only the lines between rows show
                Section {
                    content
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
                        .alignmentGuide(.listRowSeparatorLeading) { _ in inset - 16 }
                }
                .listSectionSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(Color.white.opacity(0.16))
            .environment(\.defaultMinListRowHeight, 58)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in listHeight = height }
            .frame(height: max(listHeight, 44))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .litmusGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A settings screen's scrolling body: groups stacked 22 pt apart, held to a readable width on a wide screen, with the soft edge
/// under the bar. The large title and background come from `settingsScreen`.
struct SettingsScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 22) { content }
                .frame(maxWidth: 680)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .litmusSoftTopEdge()
    }
}

/// True inside the split view, where one app background sits behind both columns so it runs unbroken between them
private struct SettingsSplitKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var settingsSplit: Bool {
        get { self[SettingsSplitKey.self] }
        set { self[SettingsSplitKey.self] = newValue }
    }
}

/// The size of the whole split view, so each column can draw its part of one app background
private struct SettingsSplitSizeKey: EnvironmentKey { static let defaultValue = CGSize.zero }
extension EnvironmentValues {
    var settingsSplitSize: CGSize {
        get { self[SettingsSplitSizeKey.self] }
        set { self[SettingsSplitSizeKey.self] = newValue }
    }
}

/// One column's share of a single app background laid across the whole split view: the full-size background is drawn and shifted so
/// that it lines up with the other column, with no seam between them
private struct SpanningBackground: View {
    @Environment(\.settingsSplitSize) private var full
    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            AppBackground()
                .frame(width: full.width, height: full.height)
                .offset(x: -frame.minX, y: -frame.minY)
        }
        .ignoresSafeArea()
    }
}

private struct SettingsScreenBackground: ViewModifier {
    @Environment(\.settingsSplit) private var inSplit
    func body(content: Content) -> some View {
        if inSplit { content.background { SpanningBackground() } } else { content.background { AppBackground().ignoresSafeArea() } }
    }
}

extension View {
    /// A settings screen's native large title (it collapses into the bar as the screen scrolls) over the app background
    func settingsScreen(_ title: String) -> some View {
        largeTitle(title).modifier(SettingsScreenBackground())
    }
}

/// The coloured rounded tile with a white symbol, as in the system's Settings: a system colour, regular weight to match the row's
/// text, one colour (monochrome). Decorative, so hidden from VoiceOver (the row carries the label).
struct SettingsTile: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A row's leading tile and title
struct SettingsLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var body: some View {
        HStack(spacing: 12) {
            SettingsTile(symbol: symbol, color: color)
            Text(title)
        }
    }
}

// MARK: - Settings

/// Settings. On a phone it is one list under a large "Settings" title that collapses as it scrolls, each screen pushed with the
/// bar's back button. On an iPad it is a split view: the list is the sidebar (titled "Settings") and the chosen screen is the
/// detail, each with its own navigation title.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
    @State private var selection: Screen = .about

    /// Pushed on a navigation stack that already exists (from the gear): the stack's own back button returns. Presented
    /// on its own (from Revise): it brings a stack, with a Close button.
    var embedded = false
    @Environment(\.openURL) private var openURL
    @State private var showReminderDenied = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Close")
                        }
                    }
            }
        }
    }

    private var content: some View {
        Group {
            // The size class decides, not orientation: an iPad is regular both upright and sideways
            if sizeClass == .regular { splitLayout } else { stackLayout }
        }
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

    private func title(for screen: Screen) -> String {
        switch screen {
        case .about: return "About You"
        case .accessibility: return "Accessibility"
        case .appBlocking: return "App Blocking"
        case .privacy: return "Privacy & Data"
        }
    }

    @ViewBuilder private func destination(_ screen: Screen) -> some View {
        switch screen {
        case .about: AboutYouView()
        case .accessibility: AccessibilitySettingsView()
        case .appBlocking: AppBlockingView()
        case .privacy: PrivacyView()
        }
    }

    private var stackLayout: some View {
        SettingsScroll { groups(split: false) }
            .settingsScreen("Settings")
    }

    /// A split view with its sidebar always showing: the list is titled "Settings", the screen beside it carries its own title.
    private var splitLayout: some View {
        GeometryReader { geo in
            splitColumns
                .environment(\.settingsSplit, true)
                .environment(\.settingsSplitSize, CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                                                          height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom))
        }
        .ignoresSafeArea()
    }

    private var splitColumns: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsScroll { groups(split: true) }
                // A blur over the background, as in the system's Settings, so the sidebar reads as its own pane
                .background { Rectangle().fill(.ultraThinMaterial).opacity(0.45).ignoresSafeArea() }
                .settingsScreen("Settings")
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    // The split view brings its own bars, so the pushing stack's bar is hidden and its place is taken here by the
                    // standard back button (or Close, when Settings was presented on its own)
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: embedded ? "chevron.backward" : "xmark") }
                            .accessibilityLabel(embedded ? "Back" : "Close")
                    }
                }
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } detail: {
            NavigationStack { destination(selection).id(selection) }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: The groups

    @ViewBuilder private func groups(split: Bool) -> some View {
        SettingsGroup {
            navRow(.about, split: split) { profileRow }
        }
        SettingsGroup(inset: 58) {
            toggleRow("Notifications", "bell.badge.fill", .red, $reminders)
            toggleRow("Sound Effects", "speaker.wave.3.fill", .pink, $soundEffects)
            toggleRow("Widget Timer", "timer", .orange, $widgetTimer)
            navRow(.appBlocking, split: split) {
                HStack {
                    SettingsLabel(title: "App Blocking", symbol: "hourglass", color: .indigo)
                    Spacer(minLength: 8)
                    Text(blocker.isAppBlockingEnabled ? "On" : "Off").foregroundStyle(.secondary)
                }
            }
        }
        SettingsGroup(inset: 58) {
            navRow(.accessibility, split: split) { SettingsLabel(title: "Accessibility", symbol: "accessibility", color: .blue) }
            navRow(.privacy, split: split) { SettingsLabel(title: "Privacy & Data", symbol: "hand.raised.fill", color: .blue) }
            // English is the only language, so this is a plain value, not something to open
            LabeledContent {
                Text("English")
            } label: {
                SettingsLabel(title: "Language", symbol: "globe", color: .gray)
            }
            .settingsRow()
        }
        // Last and apart from the rest: erases everything on this iPad and returns to first-time setup
        SettingsGroup(inset: 58) {
            Button(role: .destructive) { showResetApp = true } label: {
                SettingsLabel(title: "Reset App", symbol: "arrow.counterclockwise", color: .red)
                    .foregroundStyle(.red)
            }
            .buttonStyle(SettingsRowButton())
        }
    }

    /// A row that opens a screen: a native link (with the system's chevron) on its own, or selecting the screen beside the list in
    /// the split view
    @ViewBuilder
    private func navRow<Label: View>(_ screen: Screen, split: Bool, @ViewBuilder label: () -> Label) -> some View {
        if split {
            Button { selection = screen } label: { label() }
                .buttonStyle(SettingsRowButton())
                .listRowBackground(selection == screen ? Color.white.opacity(0.18) : Color.clear)
                .accessibilityAddTraits(selection == screen ? .isSelected : [])
        } else {
            NavigationLink { destination(screen) } label: { label() }
        }
    }

    /// The learner at the top: picture, name, and what they study
    private var profileRow: some View {
        HStack(spacing: 14) {
            ProfileAvatar(index: learnerAvatar, size: 56, ring: .clear, name: learnerName)
            VStack(alignment: .leading, spacing: 2) {
                Text(learnerName.isEmpty ? "Driver" : learnerName).font(.title3.weight(.semibold)).lineLimit(1)
                Text("\(learnerCurriculum) · \(learnerGrade)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("About You, \(learnerName.isEmpty ? "Driver" : learnerName), \(learnerCurriculum), \(learnerGrade)")
    }

    private func toggleRow(_ title: String, _ symbol: String, _ color: Color, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { SettingsLabel(title: title, symbol: symbol, color: color) }
            .tint(.green)
            .settingsRow()
    }
}

// MARK: - About You

/// About You as grouped lists under a large title, the same upright and sideways: the learner at the top, then Profile, Study,
/// Recent Sessions, and the one destructive action last and apart.
struct AboutYouView: View {
    @ObservedObject private var progress = StudyProgressManager.shared
    @ObservedObject private var profileStore = ProfileStore.shared
    @State private var confirmDeleteProfile = false
    @AppStorage("learner_name") private var name = ""
    @AppStorage("learner_curriculum") private var curriculum = "NCERT"
    @AppStorage("learner_grade") private var grade = "Grade 10"
    @AppStorage("learner_daily_goal_minutes") private var dailyGoal = 120
    @AppStorage("learner_avatar") private var avatar = 0

    @State private var showAllSessions = false
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var editingAvatar = false
    @State private var editingGoal = false
    @State private var showCalendar = false
    /// The daily goal when its sheet opened, so Cancel can put it back
    @State private var goalAtOpen: Int?

    private let curricula = ["NCERT", "ICSE", "NGSS", "International Baccalaureate"]

    var body: some View {
        SettingsScroll {
            header
            SettingsGroup(header: "Profile", footer: "Deleting a profile removes this learner’s coins, streaks and study history.") { profileRows }
            SettingsGroup(header: "Study") { studyRows }
            if !progress.sessions.isEmpty {
                SettingsGroup(header: "Recent Sessions") { recentRows }
            }
        }
        .settingsScreen("About You")
        .alert("Your Name", isPresented: $editingName) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        .alert("Delete “\(name.isEmpty ? "this profile" : name)”?", isPresented: $confirmDeleteProfile) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { profileStore.deleteActive() }
        } message: {
            Text(profileStore.isOnlyProfile
                 ? "This is the only profile. Deleting it removes its coins, streaks and study history and starts setup again. This can’t be undone."
                 : "Its coins, streaks and study history will be removed. This can’t be undone.")
        }
        .sheet(isPresented: $editingAvatar) { AvatarPicker(selection: $avatar) }
        .sheet(isPresented: $editingGoal) { goalEditor }
        .sheet(isPresented: $showAllSessions) { allSessionsSheet }
        .sheet(isPresented: $showCalendar) { StudyCalendarSheet().presentationSizing(.page) }
    }

    // MARK: Header

    /// Centred, like the system's account page: the picture (itself the control, with "edit" along its lower edge), the name, and
    /// what they study
    private var header: some View {
        VStack(spacing: 6) {
            Button { editingAvatar = true } label: { EditablePicture(index: avatar, name: name, size: 104) }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit profile picture")
            Text(name.isEmpty ? "Driver" : name)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .padding(.top, 6)
            Text("\(curriculum) · \(ordinal(grade))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: Profile

    @ViewBuilder private var profileRows: some View {
        Button { nameDraft = name; editingName = true } label: {
            LabeledContent("Name") { Text(name.isEmpty ? "Driver" : name) }
        }
        .buttonStyle(SettingsRowButton())
        // Each value is chosen with the system pop-up picker: tap it, pick from the list
        LabeledContent("Curriculum") {
            Picker("Curriculum", selection: $curriculum) { ForEach(curricula, id: \.self) { Text($0).tag($0) } }
                .labelsHidden()
                .pickerStyle(.menu)
        }
        .settingsRow()
        LabeledContent("Grade") {
            Picker("Grade", selection: $grade) { ForEach(6...10, id: \.self) { Text("\($0)th").tag("Grade \($0)") } }
                .labelsHidden()
                .pickerStyle(.menu)
        }
        .settingsRow()
        // The one destructive action, last in the card: red, and it asks before anything is removed
        Button(role: .destructive) { confirmDeleteProfile = true } label: {
            Text("Delete Profile").foregroundStyle(.red)
        }
        .buttonStyle(SettingsRowButton())
    }

    // MARK: Study

    @ViewBuilder private var studyRows: some View {
        let minutes = Int(progress.studiedMinutesToday.rounded())
        let fraction = min(1, progress.studiedMinutesToday / Double(max(dailyGoal, 1)))
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                Spacer()
                Button("Edit Goal") { editingGoal = true }
                    .litmusGlassButton()
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
            Text(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m")
                .font(.largeTitle.weight(.bold))
                .contentTransition(.numericText())
            // The system's own progress view, goal as its total. Drawn at its standard 4 pt it reads as a hairline, so the bar alone
            // is scaled to a thicker track and its labels sit outside it
            HStack {
                Text("Daily Goal").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fraction * 100))% of \(goalLabel(dailyGoal))").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ProgressView(value: min(progress.studiedMinutesToday, Double(max(dailyGoal, 1))), total: Double(max(dailyGoal, 1)))
                .progressViewStyle(.linear)
                .tint(settingsRed)
                .scaleEffect(x: 1, y: 2.6, anchor: .center)
                .padding(.vertical, 5)
                .accessibilityLabel("Daily goal")
                .accessibilityValue("\(Int(fraction * 100)) percent of \(goalLabel(dailyGoal))")
                .animation(.smooth, value: fraction)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)

        if let last = progress.sessions.first {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last Session")
                HStack(spacing: 14) {
                    sessionThumb(last, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(last.topic).font(.headline).lineLimit(2)
                        Text("\(last.subject.isEmpty ? "Science" : last.subject) · \(when(last.date)) · \(max(1, last.seconds / 60)) min")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let note = last.reviewNote {
                    Label("Needs review: \(note)", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.yellow)
                } else {
                    Label("Nothing to review", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent("Last Session") { Text("None yet") }.settingsRow()
        }

        // The whole row opens the month calendar (a year of history); the chevron is the standard disclosure indicator
        Button { showCalendar = true } label: {
            HStack {
                SettingsLabel(title: "Calendar", symbol: "calendar", color: .red)
                Spacer(minLength: 8)
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(SettingsRowButton())
        .accessibilityHint("Opens the month calendar")
    }

    @ViewBuilder private var recentRows: some View {
        ForEach(progress.sessions.prefix(3)) { record in sessionRow(record) }
        if progress.sessions.count > 3 {
            // The rest opens in a sheet, so this screen stays short
            Button("Show All") { showAllSessions = true }
                .buttonStyle(SettingsRowButton())
                .foregroundStyle(AppTheme.accent)
                .accessibilityHint("Opens every recent session")
        }
    }

    private func sessionRow(_ record: StudySession) -> some View {
        HStack(spacing: 12) {
            sessionThumb(record, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.topic).lineLimit(1)
                Text(when(record.date)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(max(1, record.seconds / 60)) min").foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Every recent session in a sheet: a plain list under a title, closed with Done
    private var allSessionsSheet: some View {
        NavigationStack {
            List(progress.sessions.prefix(30)) { record in sessionRow(record).listRowBackground(Color.white.opacity(0.08)) }
                .scrollContentBackground(.hidden)
                .navigationTitle("Recent Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAllSessions = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .preferredColorScheme(.dark)
    }

    private func sessionThumb(_ record: StudySession, size: CGFloat) -> some View {
        let image = AboutYouView.diagram(for: record.topic)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.35), Color(red: 0.35, green: 0.05, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image {
                Image(image).resizable().scaledToFit().padding(4).background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(3)
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
}

// MARK: - Privacy & Data

struct PrivacyView: View {
    @ObservedObject private var progress = StudyProgressManager.shared
    @State private var confirmDelete = false

    var body: some View {
        SettingsScroll {
            SettingsGroup(inset: 58) {
                note("mic", .red, "Your voice stays on this iPad", "Speech is recognised on the device when it can be, and recordings are not kept after your explanation is checked.")
                note("cpu", .indigo, "Answers are checked on the device", "Your explanations are graded by the on-device model. Nothing you say or write is sent to a server.")
                note("internaldrive", .gray, "What is saved", "Your name, grade, coins, streaks, study minutes and a short list of recent sessions are saved on this iPad only.")
            }
            SettingsGroup(footer: "Streaks, study minutes and sessions are cleared. Your coins stay.") {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text("Delete My Study History").foregroundStyle(.red).frame(maxWidth: .infinity)
                }
                .buttonStyle(SettingsRowButton())
            }
        }
        .settingsScreen("Privacy & Data")
        .confirmationDialog("Delete your study history?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete History", role: .destructive) { progress.clearStudyData() }
        } message: {
            Text("Streaks, study minutes and sessions will be cleared. Your coins stay.")
        }
    }

    private func note(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsLabel(title: title, symbol: symbol, color: color).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .settingsRow()
        .accessibilityElement(children: .combine)
    }
}

/// A profile picture that is its own edit control: a soft shade with "edit" always along its lower edge (touch has no
/// hover). No highlight plate and no ring.
private struct EditablePicture: View {
    var index: Int
    var name: String
    var size: CGFloat = 128

    var body: some View {
        ProfileAvatar(index: index, size: size, ring: .clear, name: name)
            .overlay(alignment: .bottom) {
                Text("edit")
                    .scaledFont(size: size < 110 ? 13 : 15, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16).padding(.bottom, size < 110 ? 6 : 10)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(Circle())
            .contentShape(Circle())
    }
}
