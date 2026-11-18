// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// Adds a custom exercise: name, equipment and primary muscle. Names must be new
/// (ignoring case), archived exercises included.
struct NewExerciseView: View {
    var onCreate: (Exercise) -> Void = { _ in }

    @State private var name: String
    @State private var equipment: Equipment = .barbell
    @State private var muscle: Muscle = .chest
    @Query private var exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    init(initialName: String = "", onCreate: @escaping (Exercise) -> Void = { _ in }) {
        _name = State(initialValue: initialName)
        self.onCreate = onCreate
    }

    private var validation: Result<String, ExerciseCatalog.NameProblem> {
        ExerciseCatalog.validateNewName(name, existing: exercises)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    if case .failure(.duplicate(let existing, let isArchived)) = validation {
                        Text(isArchived
                            ? "“\(existing)” already exists but is archived. Show archived exercises in Exercises to restore it."
                            : "“\(existing)” already exists.")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Primary Muscle", selection: $muscle) {
                        ForEach(MuscleGroup.allCases) { group in
                            Section(group.label) {
                                ForEach(group.muscles, id: \.self) { Text($0.label).tag($0) }
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("Equipment sets the starting weight on Apple Watch when a set has none yet.")
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: create)
                        .disabled((try? validation.get()) == nil)
                }
            }
        }
    }

    private func create() {
        do {
            let exercise = try ExerciseCatalog.createCustomExercise(named: name, equipment: equipment, muscle: muscle, in: modelContext)
            try modelContext.save()
            onCreate(exercise)
            dismiss()
        } catch {
            modelContext.rollback()
        }
    }
}
