// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// The steps of the first launch, in order.
enum OnboardingStep: Hashable, CaseIterable {
    case welcome
    case units
    case health
}

/// First launch on this iPhone: welcome, weight unit, then Apple Health explained before
/// the system asks. Shown once per device; "Not now" leaves the app fully usable.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @State private var step: OnboardingStep
    @State private var unit: WeightUnit = .kg
    @State private var isRequestingHealth = false

    init(step: OnboardingStep = .welcome) {
        _step = State(initialValue: step)
    }

    var body: some View {
        Group {
            switch step {
            case .welcome:
                OnboardingPage(
                    title: "Wholeset",
                    message: "Log every set on Apple Watch. Plan routines and your week on iPhone. Nothing is capped: routines, exercises and history are all yours.",
                    isLargeTitle: true
                ) {
                    Button("Continue") { advance(to: .units) }
                        .buttonStyle(AccentFillButtonStyle())
                }
            case .units:
                UnitsPage(unit: $unit) {
                    saveUnit()
                    advance(to: .health)
                }
            case .health:
                OnboardingPage(
                    title: "Apple Health",
                    message: "Your Apple Watch saves each workout to Apple Health, so it shows in Fitness and counts toward your Activity rings. During a workout it reads your heart rate and active energy.\n\nSets, reps and weights stay in Wholeset; Health has no place for them."
                ) {
                    Button("Continue") {
                        Task {
                            isRequestingHealth = true
                            await model.health.request()
                            model.finishOnboarding()
                        }
                    }
                    .buttonStyle(AccentFillButtonStyle())
                    .disabled(isRequestingHealth)
                    Button("Not Now") { model.finishOnboarding() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .animation(.default, value: step)
        .onAppear(perform: preselectUnit)
    }

    private func advance(to next: OnboardingStep) {
        step = next
    }

    /// The unit already chosen (for example on another device, synced), else the region's.
    private func preselectUnit() {
        guard let settings = try? AppSettings.current(in: modelContext) else { return }
        unit = settings.wasEdited ? settings.unit : WeightUnit.preferred(for: .current)
    }

    private func saveUnit() {
        guard let settings = try? AppSettings.current(in: modelContext) else { return }
        // Counts as a choice even if it is the default, so it wins over the Watch's untouched row.
        SettingsEditing.setUnit(unit, on: settings, isExplicitChoice: true)
        modelContext.saveLogged()
    }
}

/// The weight unit step: the choices as an inset-grouped list with a checkmark on the
/// selected one, and Continue at the bottom.
private struct UnitsPage: View {
    @Binding var unit: WeightUnit
    let onContinue: () -> Void

    var body: some View {
        List {
            Section {
                choice("Kilograms (kg)", for: .kg)
                choice("Pounds (lb)", for: .lb)
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Units")
                        .font(.title.bold())
                        .foregroundStyle(Color.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Weights are shown and entered in this unit, on iPhone and on Apple Watch. You can change it later in Settings.")
                        .font(.title3)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textCase(nil)
                .padding(.top, 72)
                .padding(.bottom, 12)
            }
        }
        .listStyle(.insetGrouped)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Continue", action: onContinue)
                .buttonStyle(AccentFillButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }

    private func choice(_ title: LocalizedStringKey, for option: WeightUnit) -> some View {
        Button {
            unit = option
        } label: {
            HStack {
                Text(title)
                Spacer()
                if unit == option {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .listRowButtonLabel()
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(unit == option ? [.isSelected] : [])
    }
}

/// One full-screen onboarding page: a title, a message and the page's controls at the bottom.
private struct OnboardingPage<Controls: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var isLargeTitle = false
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(isLargeTitle ? .largeTitle.bold() : .title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 72)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 12) {
                controls
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
    }
}
