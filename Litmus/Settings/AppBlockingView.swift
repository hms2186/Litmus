//
//  AppBlockingView.swift
//  Litmus
//
//  App Blocking inside Settings: Screen Time app shielding (FamilyControls and ManagedSettings) while a focus timer runs.
//  Kept to what a student decides: whether to block, how strict to be, and which apps. A grouped list like the rest of Settings;
//  the access prompt appears only while permission is missing; the test tools exist only in the simulator.
//

import SwiftUI
import FamilyControls

public struct AppBlockingView: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @ObservedObject var manager: ScreenTimeManager = .shared
    // As in Apple's FamilyActivityPicker sample: the selection and the presentation flag are this view's own state, and the manager
    // is told when the person confirms. (Binding the picker straight to the manager republished and rebuilt the screen while the
    // picker was open, which is what made choosing a category glitch.)
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false

    public init() {}

    public var body: some View {
        SettingsScroll {
            // Only while permission is missing: nothing else on this screen works without it
            if !manager.isAuthorized { accessSection }

            SettingsGroup(footer: "Chosen apps are blocked while a timer runs. Strict Mode does not let a session be paused or stopped early.", inset: 58) {
                Toggle(isOn: $manager.isAppBlockingEnabled) {
                    SettingsLabel(title: "Block Apps During Focus", symbol: "hourglass", color: .indigo)
                }
                .tint(.green)
                .settingsRow()
                Toggle(isOn: $manager.isStrictMode) {
                    SettingsLabel(title: "Strict Mode", symbol: "flame.fill", color: .orange)
                }
                .tint(.green)
                .settingsRow()
            }

            SettingsGroup(footer: readiness, inset: 58) {
                Button(action: chooseApps) {
                    HStack {
                        SettingsLabel(title: "Apps to Block", symbol: "apps.ipad", color: .blue)
                        Spacer(minLength: 8)
                        Text(selectionSummary).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(SettingsRowButton())
                .accessibilityHint("Opens the list of apps and categories to block")
                if manager.hasSelection {
                    Button(role: .destructive) {
                        withAnimation(reduceMotion ? nil : AppMotionSystem.interactiveSpring) { manager.clearSelection(); selection = FamilyActivitySelection() }
                    } label: {
                        Text("Clear Selection").foregroundStyle(.red)
                    }
                    .buttonStyle(SettingsRowButton())
                }
            }
        }
        .settingsScreen("App Blocking")
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .tabBar)
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { _, newSelection in manager.selection = newSelection }
        .onAppear { selection = manager.selection }
    }

    // MARK: Apps to block

    /// Says whether the next timer will block anything, and what is missing when it will not (the timer starts blocking only when
    /// all three are true: blocking is on, Screen Time access is granted, and at least one app, category or site is chosen)
    private var readiness: String {
        if !manager.isAppBlockingEnabled { return "Blocking is off. Turn on Block Apps During Focus." }
        if !manager.isAuthorized { return "Not blocking yet: allow Screen Time access above." }
        if !manager.hasSelection { return "Not blocking yet: choose at least one app or category." }
        return "Ready: \(selectionSummary) will be blocked while a timer runs."
    }

    /// The system's picker needs Screen Time access first (presenting it without it is what made it misbehave), so access is asked
    /// for when missing and the picker opens once it is granted
    private func chooseApps() {
        if manager.isAuthorized {
            showPicker = true
        } else {
            Task { if await manager.requestAuthorization() { showPicker = true } }
        }
    }

    /// "None", or what is chosen in words: "3 apps, 1 category"
    private var selectionSummary: String {
        guard manager.hasSelection else { return "None" }
        let apps = manager.selection.applicationTokens.count
        let categories = manager.selection.categoryTokens.count
        let sites = manager.selection.webDomainTokens.count
        var parts: [String] = []
        if apps > 0 { parts.append(apps == 1 ? "1 app" : "\(apps) apps") }
        if categories > 0 { parts.append(categories == 1 ? "1 category" : "\(categories) categories") }
        if sites > 0 { parts.append(sites == 1 ? "1 site" : "\(sites) sites") }
        return parts.joined(separator: ", ")
    }

    // MARK: Screen Time access

    private var accessSection: some View {
        let denied = manager.status == .denied
        return SettingsGroup {
            VStack(alignment: .leading, spacing: 12) {
                SettingsLabel(title: denied ? "Screen Time Access Is Off" : "Allow Screen Time Access",
                              symbol: denied ? "xmark.shield.fill" : "lock.shield.fill", color: denied ? .red : .orange)
                    .font(.headline)
                Text(denied ? "Allow Litmus in iPadOS Settings so it can block apps while you focus."
                            : "Litmus needs it to block apps while you focus.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if denied { manager.openSystemSettings() } else { Task { if await manager.requestAuthorization() { showPicker = true } } }
                } label: {
                    HStack(spacing: 8) {
                        if manager.isRequestingAuth { ProgressView() }
                        Text(denied ? "Open Settings" : "Allow Access").font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(AppTheme.accent)
                .disabled(manager.isRequestingAuth)
                if !manager.statusMessage.isEmpty {
                    Label(manager.statusMessage, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsRow()
        }
    }
}
