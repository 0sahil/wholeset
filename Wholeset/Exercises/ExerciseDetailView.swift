// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// What an exercise is: equipment, muscle, the names it matches in imports, and its
/// alternatives. Custom exercises can be archived and restored.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var modelContext

    private var alternatives: [Exercise] {
        (exercise.alternatives ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Equipment", value: exercise.equipment.label)
                LabeledContent("Primary Muscle", value: exercise.primaryMuscle.label)
                LabeledContent("Source", value: exercise.isCustom ? String(localized: "Custom") : String(localized: "Built-in library"))
            }
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
