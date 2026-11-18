// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// What an exercise is: muscle, its Watch settings (equipment, progression step, default
/// rest), the names it matches in imports, and its alternatives. Custom exercises can be
/// archived and restored.
struct ExerciseDetailView: View {
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
                    Text("Also Known As")
                } footer: {
                    Text("Used to recognise this exercise in workouts imported from other apps.")
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
    }
}

/// The "Watch" section: equipment, progression step and default rest, each saved at once.
private struct ExerciseWatchSettings: View {
    let exercise: Exercise
    /// The settings row, for the unit and the defaults; `nil` until it exists.
    let settings: AppSettings?

    @Environment(\.modelContext) private var modelContext

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
                    Text(defaultStepLabel(unit: unit)).tag(Double?.none)
                    ForEach(ProgressionStepChoices.options(for: unit, including: exercise.progressionStepKg), id: \.self) { kilograms in
                        StepOptionLabel(kilograms: kilograms, unit: unit, isDefault: false)
                            .tag(Double?.some(kilograms))
                    }
                }
            }
            Picker("Default Rest", selection: write(\.defaultRestSeconds) { ExerciseEditing.setDefaultRest($0, on: $1) }) {
                Text(String(localized: "Default (\(Formatting.rest(settings?.defaultRestSeconds ?? RestTimer.fallbackSeconds)))"))
                    .tag(Int?.none)
                ForEach(RoutineRules.restChoices, id: \.self) { seconds in
                    Text(Formatting.rest(seconds))
                        .accessibilityLabel(Formatting.spokenRest(seconds))
                        .tag(Int?.some(seconds))
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Watch")
        } footer: {
            if exercise.equipment == .bodyweight {
                Text("Bodyweight exercises suggest one more rep instead of more weight. Default rest applies when the routine doesn't set one.")
            } else {
                Text("The progression step is what the ↑ suggestion on Apple Watch adds. Default rest applies when the routine doesn't set one.")
            }
        }
    }

    /// "Default (2.5 kg)": the step from Settings for this equipment.
    private func defaultStepLabel(unit: WeightUnit) -> String {
        let step = settings.map { ProgressionSettings($0) }?.defaultStep(for: exercise.equipment)
            ?? ProgressionStep.builtInDefault(for: exercise.equipment, unit: unit)
        guard let step else { return String(localized: "Default") }
        return String(localized: "Default (\(StepFormat.string(kilograms: step, unit: unit)))")
    }

    private func stepSelection(unit: WeightUnit) -> Binding<Double?> {
        Binding(
            get: { exercise.progressionStepKg.map { ProgressionStepChoices.tag(for: $0, unit: unit) } },
            set: { kilograms in
                ExerciseEditing.setProgressionStep(kilograms: kilograms, on: exercise)
                modelContext.saveLogged()
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
