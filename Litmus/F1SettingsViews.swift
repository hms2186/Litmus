//
//  F1SettingsViews.swift
//  Settings, About You and Privacy & Data, following the Figma frames. The gear button on the home
//  screens opens Settings; the toggles are saved on the device and used where they apply:
//  Widget Timer (the Live Activity during a lap), Study Reminders (a daily notification) and Sound
//  Effects (the engineer's voice). App Blocking is saved as a preference only.
//

import SwiftUI
import FamilyControls
import UserNotifications

private let settingsRed = Color(red: 255/255, green: 24/255, blue: 48/255)

/// A daily study reminder at 5 pm, added or removed from Settings.
enum F1StudyReminder {
    private static let identifier = "study_reminder_daily"

    static func setEnabled(_ enabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return true }
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Time to study"
        content.body = "A short focus session keeps your streak going."
        content.sound = .default
        var time = DateComponents()
        time.hour = 17
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true))
        return (try? await center.add(request)) != nil
    }
}

struct F1SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var progress = F1SessionProgressManager.shared

    @AppStorage("settings_app_blocking") private var appBlocking = false
    @ObservedObject private var blocker = F1AppBlocker.shared
    @State private var showsAppPicker = false
    @State private var showBlockingDenied = false
    @AppStorage("settings_widget_timer") private var widgetTimer = true
    @AppStorage("settings_study_reminders") private var reminders = false
    @AppStorage(F1EngineerVoice.soundSettingKey) private var soundEffects = true

    private enum Screen: Hashable { case about, accessibility, privacy }
    /// Pushed on a navigation stack that already exists (from the gear): the stack's own back button returns. Presented
    /// on its own (from Revise): it brings a stack, with a back button that closes it.
    var embedded = false
    @State private var showLanguageNote = false
    @State private var showReminderDenied = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                                .accessibilityLabel("Back")
                        }
                    }
            }
        }
    }

    private var content: some View {
        ZStack {
            AppleMusicDarkGradientBackground().ignoresSafeArea()
            settingsList
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
        .alert("Language", isPresented: $showLanguageNote) {
            Button("OK") {}
        } message: {
            Text("English is the only language available right now.")
        }
        .alert("Notifications are off", isPresented: $showReminderDenied) {
            Button("OK") {}
        } message: {
            Text("Allow notifications for this app in the Settings app to get study reminders.")
        }
    }

    @ViewBuilder
    private func destination(for screen: Screen) -> some View {
        switch screen {
        case .about:
            F1AboutYouView()
                .padding(.horizontal, 32).padding(.bottom, 24)
                .background { AppleMusicDarkGradientBackground().ignoresSafeArea() }
                .navigationTitle("About You")
                .navigationBarTitleDisplayMode(.inline)
        case .accessibility:
            F1AccessibilitySettingsView()
        case .privacy:
            F1PrivacyView()
                .padding(.horizontal, 32).padding(.bottom, 24)
                .background { AppleMusicDarkGradientBackground().ignoresSafeArea() }
                .navigationTitle("Privacy & Data")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var settingsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                row(icon: "person", title: "About You", link: .about) { chevron }
                row(icon: "accessibility", title: "Accessibility", link: .accessibility) { chevron }
                row(icon: "iphone", title: "App Blocking") { toggle($appBlocking) }
                if appBlocking && blocker.isAuthorized {
                    row(icon: "apps.iphone", title: "Choose Apps to Block", onTap: { showsAppPicker = true }) {
                        HStack(spacing: 12) {
                            Text(blocker.hasSelection ? "\(blocker.selectionCount) chosen" : "None chosen").foregroundStyle(.white.opacity(0.7))
                            chevron
                        }
                        .f1Font(size: 20)
                    }
                }
                row(icon: "square.grid.2x2", title: "Widget Timer") { toggle($widgetTimer) }
                row(icon: "bell", title: "Study Reminders") {
                    toggle($reminders)
                }
                row(icon: "speaker.wave.2", title: "Sound Effects") { toggle($soundEffects) }
                row(icon: "shield", title: "Privacy & Data", link: .privacy) { chevron }
                row(icon: "globe", title: "Language", onTap: { showLanguageNote = true }) {
                    HStack(spacing: 12) {
                        Text("English").foregroundStyle(.white.opacity(0.7))
                        chevron
                    }
                    .f1Font(size: 20)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .familyActivityPicker(isPresented: $showsAppPicker, selection: $blocker.selection)
        .onChange(of: appBlocking) { _, enabled in
            guard enabled else { F1AppBlocker.shared.stopBlocking(); return }
            Task {
                // Screen Time access first; the apps to block are chosen right after
                if await F1AppBlocker.shared.requestAuthorization() { showsAppPicker = !blocker.hasSelection }
                else { appBlocking = false; showBlockingDenied = true }
            }
        }
        .alert("Screen Time access needed", isPresented: $showBlockingDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("App Blocking uses Screen Time. Allow Litmus in Settings > Screen Time, then turn App Blocking on again.")
        }
        .onChange(of: reminders) { _, enabled in
            Task {
                let ok = await F1StudyReminder.setEnabled(enabled)
                if enabled && !ok { reminders = false; showReminderDenied = true }
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .labelsHidden()
            .tint(settingsRed)
    }

    @ViewBuilder
    private func row<Trailing: View>(icon: String, title: String, link: Screen? = nil, onTap: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) -> some View {
        let content = HStack(spacing: 22) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 50, height: 50)
                .background(settingsRed.opacity(0.28), in: Circle())
            Text(title)
                .f1Font(size: 21)
                .foregroundStyle(.white)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

        if let link {
            NavigationLink { destination(for: link) } label: { content }.buttonStyle(.f1CardSpring)
        } else if let onTap {
            Button(action: onTap) { content }.buttonStyle(.f1CardSpring)
        } else {
            content
        }
    }
}

// MARK: - About You

struct F1AboutYouView: View {
    @ObservedObject private var progress = F1SessionProgressManager.shared
    @AppStorage("learner_name") private var name = ""
    @AppStorage("learner_driver_number") private var driverNumber = 44
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
    @State private var aboutDraft = ""
    @State private var editingAvatar = false
    @State private var editingGoal = false

    private let numbers = [1, 4, 11, 13, 14, 16, 23, 24, 31, 44, 55, 63, 77, 81]
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
                let width = (geo.size.width - gap * 2)
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
        .alert("Your name", isPresented: $editingName) {
            TextField("Name", text: $nameDraft)
            Button("Save") { name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $editingAvatar) { F1AvatarPicker(selection: $avatar) }
        .sheet(isPresented: $editingGoal) { goalEditor }
        .sheet(isPresented: $editingAbout) {
            NavigationStack {
                TextEditor(text: $aboutDraft)
                    .padding()
                    .navigationTitle("About Me")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingAbout = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { aboutMe = aboutDraft; editingAbout = false } }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: Cards

    private func card<Content: View>(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .f1Font(size: 16, weight: .bold)
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var todayCard: some View {
        let minutes = Int(progress.studiedMinutesToday.rounded())
        let fraction = min(1, progress.studiedMinutesToday / Double(max(dailyGoal, 1)))
        return card("TODAY", trailing: AnyView(
            Button { editingGoal = true } label: {
                Label("Edit goal", systemImage: "pencil")
                    .f1Font(size: 16, weight: .medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.f1Spring)
            .accessibilityLabel("Edit daily goal")
        )) {
            Spacer(minLength: 0)
            Text(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m")
                .f1Font(size: 58, weight: .bold)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text("Study time")
                .f1Font(size: 22)
                .foregroundStyle(.white.opacity(0.7))
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(settingsRed).frame(width: bar.size.width * fraction)
                }
            }
            .frame(height: 12)
            HStack {
                Text("\(Int(fraction * 100))%")
                Spacer()
                Text("\(goalLabel(dailyGoal)) goal")
            }
            .f1Font(size: 18)
            .foregroundStyle(.white.opacity(0.75))
            .animation(.smooth, value: fraction)
        }
    }

    private func sessionThumb(_ record: F1SessionRecord, size: CGFloat) -> some View {
        let image = F1AboutYouView.diagram(for: record.topic)
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
        return F1FlashcardLibrary.cards(for: match).first(where: { $0.imageName != nil })?.imageName
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
                        Text(last.topic).f1Font(size: 26).foregroundStyle(.white).lineLimit(2)
                        Label(last.subject.isEmpty ? "Science" : last.subject, systemImage: "book").f1Font(size: 17).foregroundStyle(.white.opacity(0.7))
                        Label("\(when(last.date))  |  \(max(1, last.seconds / 60)) min", systemImage: "calendar").f1Font(size: 16).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Divider().overlay(Color.white.opacity(0.12))
                if let note = last.reviewNote {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 255/255, green: 197/255, blue: 89/255))
                        Text("Needs review: \(note)").f1Font(size: 19).foregroundStyle(.white).lineLimit(2)
                    }
                } else {
                    Label("Nothing to review", systemImage: "checkmark.circle.fill").f1Font(size: 19).foregroundStyle(.white.opacity(0.8))
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
                    .f1Font(size: 17).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: Capsule())
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
                                    Text(record.topic).f1Font(size: 19).foregroundStyle(.white).lineLimit(1)
                                    Text(when(record.date)).f1Font(size: 14).foregroundStyle(.white.opacity(0.65))
                                }
                                Spacer()
                                Text("\(max(1, record.seconds / 60)) min").f1Font(size: 18).foregroundStyle(.white.opacity(0.85))
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        card("LEARNING SUMMARY") {
            summaryRow(icon: "book", number: progress.sessionsThisWeek, label: "sessions this week")
            summaryRow(icon: "scope", number: progress.topicsToRevisit, label: "concepts to revisit")
        }
    }

    private func summaryRow(icon: String, number: Int, label: String) -> some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(settingsRed.opacity(0.3), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text("\(number)").f1Font(size: 38, weight: .bold).foregroundStyle(.white).contentTransition(.numericText())
                Text(label).f1Font(size: 18).foregroundStyle(.white.opacity(0.7)).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).f1Font(size: 18).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity, minHeight: 90)
    }

    // MARK: Profile

    private var profileCard: some View {
        VStack(spacing: 14) {
            F1ProfileAvatar(index: avatar, size: 128, name: name)
            Button { editingAvatar = true } label: {
                Label("Edit", systemImage: "pencil")
                    .f1Font(size: 17, weight: .medium)
                    .foregroundStyle(settingsRed)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.f1Spring)
            .accessibilityLabel("Edit profile picture")
            HStack(spacing: 12) {
                Text(name.isEmpty ? "Driver" : name).f1Font(size: 40, weight: .bold).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                pencil { nameDraft = name; editingName = true }
            }
            Divider().overlay(Color.white.opacity(0.12))
            profileRow(icon: "flag.checkered", label: "Driver Number", value: "\(driverNumber)") {
                Menu { Picker("Driver number", selection: $driverNumber) { ForEach(numbers, id: \.self) { Text("\($0)").tag($0) } } } label: { pencilIcon }
            }
            profileRow(icon: "book", label: "Curriculum", value: curriculum) {
                Menu { Picker("Curriculum", selection: $curriculum) { ForEach(curricula, id: \.self) { Text($0).tag($0) } } } label: { pencilIcon }
            }
            profileRow(icon: "graduationcap", label: "Grade", value: ordinal(grade)) {
                Menu { Picker("Grade", selection: $grade) { ForEach(6...10, id: \.self) { Text("\($0)th").tag("Grade \($0)") } } } label: { pencilIcon }
            }
            Divider().overlay(Color.white.opacity(0.12))
            HStack {
                Image(systemName: "doc.text").font(.system(size: 22)).foregroundStyle(.white).frame(width: 44)
                Text("About Me").f1Font(size: 19).foregroundStyle(.white.opacity(0.85))
                Spacer()
                pencil { aboutDraft = aboutMe; editingAbout = true }
            }
            Text(aboutMe.isEmpty ? "Tell us a little about yourself." : aboutMe)
                .f1Font(size: 18)
                .foregroundStyle(aboutMe.isEmpty ? .white.opacity(0.5) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    // MARK: Daily goal

    private func goalLabel(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    private var goalEditor: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text(goalLabel(dailyGoal))
                    .f1Font(size: 64, weight: .bold)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.2), value: dailyGoal)
                Stepper("Daily goal", value: $dailyGoal, in: 15...480, step: 15)
                    .labelsHidden()
                    .scaleEffect(1.25)
                HStack(spacing: 10) {
                    ForEach([30, 60, 90, 120, 180], id: \.self) { preset in
                        Button { dailyGoal = preset } label: {
                            Text(goalLabel(preset))
                                .f1Font(size: 16, weight: .medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .glassEffect(.regular.interactive(), in: Capsule())
                                .overlay(Capsule().stroke(dailyGoal == preset ? Color(red: 10/255, green: 132/255, blue: 255/255) : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.f1Spring)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Daily Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { editingGoal = false } }
            }
        }
        .presentationDetents([.height(380)])
        .preferredColorScheme(.dark)
    }

    private func ordinal(_ grade: String) -> String {
        let digits = grade.filter(\.isNumber)
        return digits.isEmpty ? grade : "\(digits)th"
    }

    private var pencilIcon: some View {
        Image(systemName: "pencil")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(settingsRed)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
    }

    private func pencil(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { pencilIcon }.buttonStyle(.f1Spring).accessibilityLabel("Edit")
    }

    private func profileRow<Edit: View>(icon: String, label: String, value: String, @ViewBuilder edit: () -> Edit) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.white.opacity(0.9)).frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).f1Font(size: 17).foregroundStyle(.white.opacity(0.65))
                Text(value).f1Font(size: 22, weight: .medium).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            edit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Privacy & Data

struct F1PrivacyView: View {
    @ObservedObject private var progress = F1SessionProgressManager.shared
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            note("mic", "Your voice stays on this iPad", "Speech is recognised on the device when it can be, and recordings are not kept after your explanation is checked.")
            note("cpu", "Answers are checked on the device", "Your explanations are graded by the on-device model. Nothing you say or write is sent to a server.")
            note("internaldrive", "What is saved", "Your name, grade, coins, streaks, study minutes and a short list of recent sessions are saved on this iPad only.")
            Spacer()
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Delete my study history")
                    .f1Font(size: 19, weight: .medium)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(settingsRed.opacity(0.25), in: Capsule())
                    .foregroundStyle(.white)
            }
            .confirmationDialog("Delete your study history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete history", role: .destructive) { progress.clearStudyData() }
            } message: {
                Text("This clears your streaks, study minutes and session list. Your coins stay.")
            }
        }
        .padding(.top, 6)
    }

    private func note(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.white).frame(width: 58, height: 58).background(settingsRed.opacity(0.28), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).f1Font(size: 22, weight: .semibold).foregroundStyle(.white)
                Text(text).f1Font(size: 18).foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
