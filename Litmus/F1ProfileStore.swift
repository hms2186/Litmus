//
//  F1ProfileStore.swift
//  Learner profiles, so two children can share one iPad. The active profile's name, grade, curriculum,
//  driver number, picture and daily goal are copied into the `learner_*` settings the rest of the app already
//  reads; coins, streaks and sessions follow in `F1SessionProgressManager`, and each profile after the first
//  keeps its own progress store (`LitmusApp.container(for:)`).
//

import SwiftUI
import Combine

struct F1LearnerProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    /// "" for the first profile (the keys and store the app has always used), a short suffix for the rest.
    var storageKey = ""
    var name = ""
    var grade = "Grade 10"
    var nationality = "India"
    var curriculum = "NCERT"
    var about = ""
    var driverNumber = 44
    /// Minutes of study a day the learner aims for.
    var dailyGoal = 120
    /// 0 is the original picture, 1...6 are the characters in `F1ProfileAvatar.choices`.
    var avatar = 0
}

@MainActor
final class F1ProfileStore: ObservableObject {
    static let shared = F1ProfileStore()

    @Published private(set) var profiles: [F1LearnerProfile]
    @Published private(set) var activeID: UUID

    private enum Key {
        static let list = "learner_profiles_v1"
        static let active = "learner_active_profile_v1"
    }
    private let defaults = UserDefaults.standard

    var active: F1LearnerProfile { profiles.first(where: { $0.id == activeID }) ?? profiles[0] }
    var activeStorageKey: String { active.storageKey }

    private init() {
        let saved = defaults.data(forKey: Key.list).flatMap { try? JSONDecoder().decode([F1LearnerProfile].self, from: $0) } ?? []
        if saved.isEmpty {
            // First run of this version: the learner already on the iPad becomes the first profile
            let first = F1LearnerProfile(
                name: defaults.string(forKey: "learner_name") ?? "",
                grade: defaults.string(forKey: "learner_grade") ?? "Grade 10",
                nationality: defaults.string(forKey: "learner_nationality") ?? "India",
                curriculum: defaults.string(forKey: "learner_curriculum") ?? "NCERT",
                about: defaults.string(forKey: "learner_about") ?? "",
                driverNumber: defaults.object(forKey: "learner_driver_number") as? Int ?? 44,
                dailyGoal: defaults.object(forKey: "learner_daily_goal_minutes") as? Int ?? 120,
                avatar: defaults.integer(forKey: "learner_avatar")
            )
            profiles = [first]
            activeID = first.id
        } else {
            profiles = saved
            let id = defaults.string(forKey: Key.active).flatMap(UUID.init(uuidString:))
            activeID = saved.contains(where: { $0.id == id }) ? id! : saved[0].id
        }
        persist()
        // The progress store opens on the active profile's coins, streaks and sessions
        F1SessionProgressManager.shared.switchProfile(namespace: active.storageKey)
    }

    /// Reads the settings screens' current values back into the active profile, so edits made in About You are kept.
    func captureActive() {
        guard let index = profiles.firstIndex(where: { $0.id == activeID }) else { return }
        var profile = profiles[index]
        profile.name = defaults.string(forKey: "learner_name") ?? profile.name
        profile.grade = defaults.string(forKey: "learner_grade") ?? profile.grade
        profile.nationality = defaults.string(forKey: "learner_nationality") ?? profile.nationality
        profile.curriculum = defaults.string(forKey: "learner_curriculum") ?? profile.curriculum
        profile.about = defaults.string(forKey: "learner_about") ?? profile.about
        profile.driverNumber = defaults.object(forKey: "learner_driver_number") as? Int ?? profile.driverNumber
        profile.dailyGoal = defaults.object(forKey: "learner_daily_goal_minutes") as? Int ?? profile.dailyGoal
        profile.avatar = defaults.integer(forKey: "learner_avatar")
        if profile != profiles[index] {
            profiles[index] = profile
            persist()
        }
    }

    func switchTo(_ id: UUID) {
        guard id != activeID, let target = profiles.first(where: { $0.id == id }) else { return }
        captureActive()
        apply(target)
        activeID = id
        persist()
    }

    /// A new profile from the onboarding questions, which becomes the active one.
    func add(name: String, grade: String, nationality: String, driverNumber: Int, curriculum: String) {
        captureActive()
        let profile = F1LearnerProfile(storageKey: "p" + UUID().uuidString.prefix(8).lowercased(),
                                       name: name, grade: grade, nationality: nationality, curriculum: curriculum,
                                       driverNumber: driverNumber, avatar: Int.random(in: 1...6))
        profiles.append(profile)
        apply(profile)
        activeID = profile.id
        persist()
    }

    func canDelete(_ profile: F1LearnerProfile) -> Bool {
        profiles.count > 1 && profile.id != activeID
    }

    func delete(_ profile: F1LearnerProfile) {
        guard canDelete(profile) else { return }
        profiles.removeAll { $0.id == profile.id }
        // Its progress goes with it
        let suffix = profile.storageKey.isEmpty ? "" : "_" + profile.storageKey
        if !suffix.isEmpty {
            for base in ["f1_coin_balance_v3", "f1_weekly_streaks_v3", "f1_daily_study_minutes_v3", "f1_progress_week_start_v3", "f1_active_dates_v3", "f1_sessions_v3"] {
                defaults.removeObject(forKey: base + suffix)
            }
        }
        persist()
    }

    /// Writes the profile into the settings the app reads, and loads its progress.
    private func apply(_ profile: F1LearnerProfile) {
        defaults.set(profile.name, forKey: "learner_name")
        defaults.set(profile.grade, forKey: "learner_grade")
        defaults.set(profile.nationality, forKey: "learner_nationality")
        defaults.set(profile.curriculum, forKey: "learner_curriculum")
        defaults.set(profile.about, forKey: "learner_about")
        defaults.set(profile.driverNumber, forKey: "learner_driver_number")
        defaults.set(profile.dailyGoal, forKey: "learner_daily_goal_minutes")
        defaults.set(profile.avatar, forKey: "learner_avatar")
        defaults.set(true, forKey: "hasCompletedSuperLicenseOnboarding")
        F1SessionProgressManager.shared.switchProfile(namespace: profile.storageKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Key.list) }
        defaults.set(activeID.uuidString, forKey: Key.active)
    }
}

// MARK: - Avatar

/// A learner's picture: the original one, one of the six characters, a Classic symbol picture (flowers, nature, sports,
/// music and more, drawn with SF Symbols on colour, as in the system's Suggestions picker), or a monogram.
struct F1ProfileAvatar: View {
    var index: Int
    var size: CGFloat
    var ring: Color = Color(red: 255/255, green: 24/255, blue: 48/255)
    /// The learner's name, for the monogram (the first letter).
    var name: String = ""

    static let characters = [0, 1, 2, 3, 4, 5, 6]
    /// Classic pictures are numbered from 100.
    static let classicBase = 100
    static let monogram = 99

    struct Classic {
        let symbol: String
        let colors: [Color]
        let label: String
    }

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    static let classics: [Classic] = [
        Classic(symbol: "camera.macro", colors: [c(255, 120, 150), c(214, 40, 110)], label: "Flower"),
        Classic(symbol: "sun.max.fill", colors: [c(255, 214, 10), c(255, 140, 0)], label: "Sun"),
        Classic(symbol: "leaf.fill", colors: [c(120, 210, 90), c(40, 150, 70)], label: "Leaf"),
        Classic(symbol: "moon.stars.fill", colors: [c(110, 90, 230), c(40, 30, 120)], label: "Moon"),
        Classic(symbol: "flame.fill", colors: [c(255, 160, 40), c(230, 50, 30)], label: "Flame"),
        Classic(symbol: "bolt.fill", colors: [c(190, 120, 255), c(100, 50, 200)], label: "Lightning"),
        Classic(symbol: "snowflake", colors: [c(120, 210, 255), c(30, 110, 220)], label: "Snowflake"),
        Classic(symbol: "globe.europe.africa.fill", colors: [c(70, 170, 240), c(30, 130, 90)], label: "Earth"),
        Classic(symbol: "pawprint.fill", colors: [c(205, 150, 95), c(140, 90, 50)], label: "Paw"),
        Classic(symbol: "hare.fill", colors: [c(240, 215, 190), c(200, 160, 130)], label: "Hare"),
        Classic(symbol: "tortoise.fill", colors: [c(150, 215, 110), c(70, 150, 60)], label: "Tortoise"),
        Classic(symbol: "bird.fill", colors: [c(100, 200, 255), c(40, 120, 230)], label: "Bird"),
        Classic(symbol: "fish.fill", colors: [c(255, 170, 70), c(240, 100, 40)], label: "Fish"),
        Classic(symbol: "ladybug.fill", colors: [c(255, 90, 80), c(190, 30, 40)], label: "Ladybug"),
        Classic(symbol: "soccerball", colors: [c(230, 230, 235), c(130, 135, 145)], label: "Football"),
        Classic(symbol: "basketball.fill", colors: [c(255, 150, 60), c(200, 80, 20)], label: "Basketball"),
        Classic(symbol: "tennisball.fill", colors: [c(215, 240, 70), c(130, 180, 30)], label: "Tennis"),
        Classic(symbol: "baseball.fill", colors: [c(245, 245, 245), c(190, 60, 60)], label: "Baseball"),
        Classic(symbol: "guitars.fill", colors: [c(255, 110, 90), c(170, 40, 80)], label: "Guitars"),
        Classic(symbol: "pianokeys", colors: [c(90, 90, 100), c(25, 25, 30)], label: "Piano"),
        Classic(symbol: "paintpalette.fill", colors: [c(255, 120, 200), c(120, 90, 240)], label: "Palette"),
        Classic(symbol: "atom", colors: [c(70, 220, 210), c(30, 120, 200)], label: "Atom"),
        Classic(symbol: "star.fill", colors: [c(255, 224, 80), c(240, 160, 20)], label: "Star"),
        Classic(symbol: "heart.fill", colors: [c(255, 110, 140), c(220, 30, 80)], label: "Heart")
    ]

    static var classicChoices: [Int] { Array(classicBase..<(classicBase + classics.count)) }
    static let choices = characters

    var body: some View {
        Group {
            if index == 0 {
                Image("racer_license_thinking")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.5, anchor: .top)
            } else if index >= Self.classicBase, index - Self.classicBase < Self.classics.count {
                let classic = Self.classics[index - Self.classicBase]
                ZStack {
                    LinearGradient(colors: classic.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: classic.symbol)
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: size * 0.03, y: size * 0.02)
                }
            } else if index == Self.monogram {
                ZStack {
                    LinearGradient(colors: [Self.c(255, 110, 160), Self.c(220, 60, 120)], startPoint: .top, endPoint: .bottom)
                    Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased().isEmpty ? "A" : String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else {
                Image("profile_avatar_\(min(max(index, 1), 6))")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(ring, lineWidth: max(2, size / 32)))
        .accessibilityHidden(true)
    }
}

/// The picture chooser opened by Edit under the picture in About You: the characters, then Classic pictures and a monogram.
struct F1AvatarPicker: View {
    @Binding var selection: Int
    @AppStorage("learner_name") private var learnerName = ""
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 100), spacing: 18)]
    private let blue = Color(red: 10/255, green: 132/255, blue: 255/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Characters", choices: F1ProfileAvatar.characters)
                    section("Suggestions", choices: [F1ProfileAvatar.monogram])
                    section("Classic", choices: F1ProfileAvatar.classicChoices)
                }
                .padding(24)
            }
            .navigationTitle("Profile Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func section(_ title: String, choices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(choices, id: \.self) { choice in
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { selection = choice }
                    } label: {
                        F1ProfileAvatar(index: choice, size: 84, ring: selection == choice ? blue : Color.white.opacity(0.18), name: learnerName)
                            .overlay(alignment: .bottomTrailing) {
                                if selection == choice {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 24))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, blue)
                                }
                            }
                    }
                    .buttonStyle(.f1Spring)
                    .accessibilityLabel(label(for: choice))
                    .accessibilityAddTraits(selection == choice ? .isSelected : [])
                }
            }
        }
    }

    private func label(for choice: Int) -> String {
        if choice == 0 { return "Original picture" }
        if choice == F1ProfileAvatar.monogram { return "Monogram" }
        if choice >= F1ProfileAvatar.classicBase, choice - F1ProfileAvatar.classicBase < F1ProfileAvatar.classics.count {
            return F1ProfileAvatar.classics[choice - F1ProfileAvatar.classicBase].label
        }
        return "Picture \(choice)"
    }
}

// MARK: - Switching

/// The learner's picture in the top corner, beside Settings. Tapping it opens the learners on this iPad as pictures
/// with their names (a tick on the one in use) and Add Profile; choosing a picture switches to that learner.
struct F1ProfileSwitcherButton: View {
    @ObservedObject private var store = F1ProfileStore.shared
    @State private var showsPicker = false

    var body: some View {
        Button {
            store.captureActive()
            showsPicker = true
        } label: {
            F1ProfileAvatar(index: store.active.avatar, size: 44, ring: .white.opacity(0.35), name: store.active.name)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.f1Spring)
        .hoverEffect(.lift)
        .accessibilityLabel("Profile: \(store.active.name.isEmpty ? "Driver" : store.active.name). Switch profile")
        .popover(isPresented: $showsPicker, arrowEdge: .top) {
            F1ProfilePickerPanel { showsPicker = false }
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The learners as pictures, like the profile picker on Apple TV.
private struct F1ProfilePickerPanel: View {
    @ObservedObject private var store = F1ProfileStore.shared
    var close: () -> Void
    @State private var showAdd = false
    @State private var pendingDelete: F1LearnerProfile?

    private let columns = [GridItem(.fixed(104), spacing: 22), GridItem(.fixed(104), spacing: 22), GridItem(.fixed(104), spacing: 22)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(store.profiles) { profile in
                profileButton(profile)
            }
            addButton
        }
        .padding(24)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showAdd) {
            F1SuperLicenseOnboardingView(
                initialName: "",
                initialAcademicYear: "Grade 10",
                initialNationality: "India",
                initialDriverNumber: 44,
                onSave: { name, year, nationality, number, curriculum in
                    store.add(name: name, grade: year, nationality: nationality, driverNumber: number, curriculum: curriculum)
                    showAdd = false
                    close()
                },
                onDismiss: { showAdd = false },
                showsBackChevron: true
            )
        }
        .confirmationDialog("Delete this profile?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { profile in
            Button("Delete \(profile.name.isEmpty ? "profile" : profile.name)", role: .destructive) { store.delete(profile) }
        } message: { _ in
            Text("Its coins, streaks and study history are removed from this iPad.")
        }
    }

    private func profileButton(_ profile: F1LearnerProfile) -> some View {
        let isActive = profile.id == store.activeID
        let name = profile.name.isEmpty ? "Driver" : profile.name
        return Button {
            if !isActive { withAnimation(.smooth(duration: 0.3)) { store.switchTo(profile.id) } }
            close()
        } label: {
            VStack(spacing: 8) {
                F1ProfileAvatar(index: profile.avatar, size: 96, ring: .white.opacity(0.18), name: profile.name)
                    .overlay(alignment: .topTrailing) {
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 26))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color(red: 48/255, green: 209/255, blue: 88/255))
                                .offset(x: 4, y: -4)
                        }
                    }
                Text(name)
                    .f1Font(size: 16, weight: .medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(width: 104)
            .contentShape(Rectangle())
        }
        .buttonStyle(.f1Spring)
        .contextMenu {
            if store.canDelete(profile) {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = profile }
            }
        }
        .accessibilityLabel(isActive ? "\(name), current profile" : "Switch to \(name)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Color.white.opacity(0.14), in: Circle())
                Text("Add Profile")
                    .f1Font(size: 16, weight: .medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(width: 104)
            .contentShape(Rectangle())
        }
        .buttonStyle(.f1Spring)
    }
}
