// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// An exercise's settings, opened from the ⋯ button of its detail screen: muscle, its Watch
/// settings (equipment, progression step, default rest), the names it matches in imports,
/// and its alternatives. Custom exercises can be archived and restored.
struct ExerciseSettingsView: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var modelContext
    /// Oldest first, like Settings: the row that survives a sync merge.
    @Query(sort: \AppSettings.createdAt) private var settingsRows: [AppSettings]

    private var alternatives: [Exercise] {
        (exercise.alternatives ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Primary Muscle", value: exercise.primaryMuscle.label)
                LabeledContent("Source", value: exercise.isCustom ? String(localized: "Custom") : String(localized: "Built-in library"))
            }
            ExerciseWatchSettings(exercise: exercise, settings: settingsRows.first)
            Section {
                if alternatives.isEmpty {
                    Text("None yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(alternatives) { alternative in
                        Text(alternative.name)
                    }
                }
            } header: {
                Text("Alternatives")
            } footer: {
                Text("Set alternatives when editing a routine that uses this exercise.")
            }
            if !exercise.aliases.isEmpty {
                Section {
                    ForEach(exercise.aliases, id: \.self) { alias in
                        Text(alias)
                    }
                } header: {
                    Text("Names in Imports")
                } footer: {
                    Text("Workouts imported from other apps under these names count as this exercise. Names you match during an import are added here.")
                }
            }
            if exercise.isCustom {
                Section {
                    Button(exercise.isArchived ? "Restore Exercise" : "Archive Exercise", role: exercise.isArchived ? nil : .destructive) {
                        ExerciseCatalog.setArchived(!exercise.isArchived, exercise)
                        modelContext.saveLogged()
                    }
                } footer: {
                    Text(exercise.isArchived
                        ? "Archived exercises are hidden from lists but keep their history."
                        : "Archiving hides the exercise from lists. Its history and routines stay as they are.")
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The "Watch" section: equipment, progression step and default rest, each saved at once.
private struct ExerciseWatchSettings: View {
    let exercise: Exercise
    /// The settings row, for the unit and the defaults; `nil` until it exists.
    let settings: AppSettings?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @State private var customStep: CustomStepRequest?

    var body: some View {
        let unit = settings?.unit ?? .kg
        Section {
            Picker("Equipment", selection: write(\.equipment) { ExerciseEditing.setEquipment($0, on: $1) }) {
                ForEach(Equipment.allCases, id: \.self) { equipment in
                    Text(equipment.label).tag(equipment)
                }
            }
            if exercise.equipment != .bodyweight {
                Picker("Progression Step", selection: stepSelection(unit: unit)) {
                    Text(defaultStepLabel(unit: unit)).tag(StepChoice.followDefault)
                    ForEach(ProgressionStepChoices.options(for: unit, including: exercise.progressionStepKg), id: \.self) { kilograms in
                        StepOptionLabel(kilograms: kilograms, unit: unit, isDefault: false)
                            .tag(StepChoice.step(kilograms))
                    }
                    Section {
                        Text("Custom…")
                            .accessibilityLabel("Custom step")
                            .tag(StepChoice.custom)
                    }
                }
            }
            RestPicker(
                String(localized: "Default Rest"),
                seconds: write(\.defaultRestSeconds) { ExerciseEditing.setDefaultRest($0, on: $1) },
                default: RestPicker.DefaultOption(
                    summary: String(localized: "Default (\(Formatting.rest(appDefaultRest)))"),
                    explanation: String(localized: "The default rest in Settings, now \(Formatting.rest(appDefaultRest))."),
                    seconds: appDefaultRest
                ),
                isExpanded: revealsRest
            )
        } header: {
            Text("Watch")
        } footer: {
            if exercise.equipment == .bodyweight {
                Text("Bodyweight exercises suggest one more rep instead of more weight. Default rest applies when the routine doesn't set one.")
            } else {
                Text("The progression step is what the ↑ suggestion on Apple Watch adds. Default rest applies when the routine doesn't set one.")
            }
        }
        .sheet(item: $customStep) { request in
            CustomStepSheet(subject: exercise.name, unit: unit, kilograms: request.kilograms) { kilograms in
                ExerciseEditing.setProgressionStep(kilograms: kilograms, on: exercise)
                modelContext.saveLogged()
            }
        }
    }

    /// The rest from Settings that "Default" stands for.
    private var appDefaultRest: Int {
        settings?.defaultRestSeconds ?? RestTimer.fallbackSeconds
    }

    /// Whether the DEBUG demo harness shows the rest picker open.
    private var revealsRest: Bool {
        #if DEBUG
        navigation.demoReveal == .restPicker
        #else
        false
        #endif
    }

    /// "Default (2.5 kg)": the step from Settings for this equipment.
    private func defaultStepLabel(unit: WeightUnit) -> String {
        guard let step = defaultStep(unit: unit) else { return String(localized: "Default") }
        return String(localized: "Default (\(StepFormat.string(kilograms: step, unit: unit)))")
    }

    /// The step from Settings for this equipment, in kilograms.
    private func defaultStep(unit: WeightUnit) -> Double? {
        settings.map { ProgressionSettings($0) }?.defaultStep(for: exercise.equipment)
            ?? ProgressionStep.builtInDefault(for: exercise.equipment, unit: unit)
    }

    /// Writes through `ExerciseEditing` and saves; "Custom…" opens the sheet to type a step.
    private func stepSelection(unit: WeightUnit) -> Binding<StepChoice> {
        Binding(
            get: { exercise.progressionStepKg.map { .step(ProgressionStepChoices.tag(for: $0, unit: unit)) } ?? .followDefault },
            set: { choice in
                switch choice {
                case .followDefault:
                    ExerciseEditing.setProgressionStep(kilograms: nil, on: exercise)
                    modelContext.saveLogged()
                case .step(let kilograms):
                    ExerciseEditing.setProgressionStep(kilograms: kilograms, on: exercise)
                    modelContext.saveLogged()
                case .custom:
                    customStep = CustomStepRequest(equipment: nil, kilograms: exercise.progressionStepKg ?? defaultStep(unit: unit))
                }
            }
        )
    }

    /// A binding that writes through an `ExerciseEditing` function and saves.
    private func write<Value>(_ keyPath: KeyPath<Exercise, Value>, _ edit: @escaping (Value, Exercise) -> Void) -> Binding<Value> {
        Binding(
            get: { exercise[keyPath: keyPath] },
            set: { value in
                edit(value, exercise)
                modelContext.saveLogged()
            }
        )
    }
}
