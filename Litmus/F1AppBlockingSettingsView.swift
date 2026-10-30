//
//  F1AppBlockingSettingsView.swift
//  Litmus
//
//  Official Apple HIG Screen Time App Shielding interface inside Settings.
//  Uses Apple's FamilyControls and ManagedSettings frameworks for on-device app self-regulation.
//

import SwiftUI
import FamilyControls

public struct F1AppBlockingSettingsView: View {
    @ObservedObject var manager: ScreenTimeManager = .shared
    @Environment(\.dismiss) private var dismiss

    private let red = Color(red: 255/255, green: 24/255, blue: 36/255)
    private let yellow = Color(red: 255/255, green: 186/255, blue: 73/255)
    private let blue = Color(red: 10/255, green: 132/255, blue: 255/255)
    private let green = Color(red: 57/255, green: 181/255, blue: 74/255)

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Section 1: Shield Master Toggle
                section(title: "Stint Shielding", systemImage: "hourglass") {
                    Toggle(isOn: $manager.isAppBlockingEnabled) {
                        HStack(spacing: 14) {
                            Image(systemName: "iphone")
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(red.opacity(0.3), in: Circle())
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Shield Apps")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text("Block selected apps while a timer is running.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .tint(red)
                    .padding(.vertical, 4)
                }

                // Section 2: Screen Time Authorization
                section(title: "Screen Time Access", systemImage: "lock.shield") {
                    if manager.isAuthorized {
                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.shield.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(green)
                                .frame(width: 40, height: 40)
                                .background(green.opacity(0.2), in: Circle())
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Authorized")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text("Screen Time shielding is active on this iPad.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            Spacer()

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(green)
                                    .frame(width: 8, height: 8)
                                Text("Active")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(green)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(green.opacity(0.15), in: Capsule())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    } else if manager.status == .denied {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "xmark.shield.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(red)
                                    .font(.system(size: 20, weight: .semibold))
                                    .accessibilityHidden(true)

                                Text("Access Denied")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }

                            Text("Screen Time permission was denied. Please allow Litmus in iPadOS Settings.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.75))

                            Button {
                                manager.openSystemSettings()
                            } label: {
                                HStack(spacing: 8) {
                                    Spacer()
                                    Image(systemName: "arrow.up.forward.app")
                                        .symbolRenderingMode(.hierarchical)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Open iPadOS Settings")
                                        .f1Font(size: 15, weight: .semibold)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .tint(.white)
                            .hoverEffect(.lift)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(yellow, .black)
                                    .font(.system(size: 20, weight: .semibold))
                                    .symbolEffect(.pulse)
                                    .accessibilityHidden(true)

                                Text("Permission Required")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }

                            Text("Screen Time access is required to shield apps during focus.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.75))

                            Button {
                                Task {
                                    await manager.requestAuthorization()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Spacer()
                                    if manager.isRequestingAuth {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "lock.shield.fill")
                                            .symbolRenderingMode(.hierarchical)
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    Text("Authorize Screen Time Access")
                                        .f1Font(size: 15, weight: .semibold)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .tint(blue)
                            .hoverEffect(.lift)
                            .disabled(manager.isRequestingAuth)

                            if !manager.statusMessage.isEmpty {
                                Label(manager.statusMessage, systemImage: "info.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }

                // Section 3: Blocked Applications
                section(title: "Blocked Apps", systemImage: "apps.ipad") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Selected Items")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text(manager.hasSelection ? "\(manager.selectionCount) selected" : "None selected")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.65))
                            }

                            Spacer()

                            Button {
                                if !manager.isAuthorized {
                                    Task {
                                        await manager.requestAuthorization()
                                    }
                                }
                                #if targetEnvironment(simulator)
                                if manager.selectionCount == 0 && manager.selection.applicationTokens.isEmpty {
                                    withAnimation(AppMotionSystem.interactiveSpring) {
                                        manager.simulatedSelectionCount = 3
                                    }
                                }
                                #endif
                                manager.isPickerPresented = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: manager.hasSelection ? "slider.horizontal.3" : "plus")
                                        .symbolRenderingMode(.hierarchical)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(manager.hasSelection ? "Edit" : "Choose Apps")
                                }
                                .f1Font(size: 14, weight: .semibold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .tint(yellow)
                            .hoverEffect(.lift)
                            .accessibilityLabel("Select apps to block")
                        }

                        if manager.hasSelection {
                            Divider().overlay(Color.white.opacity(0.12))

                            HStack(spacing: 10) {
                                let appCount = manager.selection.applicationTokens.count > 0 ? manager.selection.applicationTokens.count : (manager.selectionCount > 1 ? 2 : manager.selectionCount)
                                let catCount = manager.selection.categoryTokens.count > 0 ? manager.selection.categoryTokens.count : (manager.selectionCount > 2 ? 1 : 0)
                                let webCount = manager.selection.webDomainTokens.count

                                Label("\(appCount) Apps", systemImage: "app.badge.checkmark.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .f1Font(size: 13, weight: .medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Capsule())

                                Label("\(catCount) Categories", systemImage: "square.grid.2x2.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .f1Font(size: 13, weight: .medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Capsule())

                                if webCount > 0 {
                                    Label("\(webCount) Sites", systemImage: "globe")
                                        .symbolRenderingMode(.hierarchical)
                                        .f1Font(size: 13, weight: .medium)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Capsule())
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    withAnimation {
                                        manager.clearSelection()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                            .symbolRenderingMode(.hierarchical)
                                        Text("Clear")
                                    }
                                    .f1Font(size: 13, weight: .semibold)
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                                .tint(Color(red: 255/255, green: 80/255, blue: 80/255))
                                .hoverEffect(.lift)
                            }
                        }

                        #if targetEnvironment(simulator)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(yellow)
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Simulator Note: Empty Category Expansion")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                            }

                            Text("Apple's FamilyActivityPicker cannot show individual apps inside the simulator because Xcode Simulator has no App Store apps installed. On a real iPad, all installed apps appear under each category. On Simulator, tap the radio circle on the left of any category (e.g. Social, Games) to shield that category, or use the simulator test buttons below.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                Button("Simulate 3 Apps") {
                                    withAnimation(AppMotionSystem.interactiveSpring) {
                                        manager.simulatedSelectionCount = 3
                                    }
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                                .f1Font(size: 13, weight: .medium)

                                Button("Simulate 5 Apps") {
                                    withAnimation(AppMotionSystem.interactiveSpring) {
                                        manager.simulatedSelectionCount = 5
                                    }
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                                .f1Font(size: 13, weight: .medium)
                            }
                            .padding(.top, 4)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        #endif
                    }
                    .padding(.vertical, 4)
                }

                // Section 4: Live Shield Verification
                section(title: "Shield Status", systemImage: "bolt.shield") {
                    HStack(spacing: 14) {
                        Image(systemName: manager.isShieldActive ? "bolt.shield.fill" : "shield")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(manager.isShieldActive ? green : .white.opacity(0.6))
                            .frame(width: 40, height: 40)
                            .background(
                                (manager.isShieldActive ? green : Color.white).opacity(0.15),
                                in: Circle()
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(manager.isShieldActive ? "Shield Active" : "Shield Idle")
                                .font(.headline)
                                .foregroundStyle(.white)

                            Text(manager.isShieldActive ? "Selected apps are currently restricted." : "Shield will activate when a timer starts.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        Button {
                            withAnimation(AppMotionSystem.interactiveSpring) {
                                manager.toggleShieldTest()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: manager.isShieldActive ? "stop.circle.fill" : "play.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                Text(manager.isShieldActive ? "Lift Shield" : "Test Shield")
                            }
                            .f1Font(size: 13, weight: .semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .tint(manager.isShieldActive ? red : yellow)
                        .hoverEffect(.lift)
                        .disabled(!manager.hasSelection && !manager.isShieldActive)
                    }
                    .padding(.vertical, 4)
                }

                // Section 5: Strict Mode
                section(title: "Focus Rules", systemImage: "flame") {
                    Toggle(isOn: $manager.isStrictMode) {
                        HStack(spacing: 14) {
                            Image(systemName: "flame.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(yellow)
                                .frame(width: 40, height: 40)
                                .background(yellow.opacity(0.2), in: Circle())
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Strict Mode")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text("Prevents pausing or stopping focus stints early.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .tint(yellow)
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.automatic, for: .top)
        .background { AppleMusicDarkGradientBackground().ignoresSafeArea() }
        .navigationTitle("App Blocking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .tabBar)
        .tint(blue)
        .accentColor(blue)
        .familyActivityPicker(isPresented: $manager.isPickerPresented, selection: $manager.selection)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
