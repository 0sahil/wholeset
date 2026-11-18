// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftData
import SwiftUI
import WholesetKit

/// The routine editor's state: a draft copy of the routine, so Cancel can throw it away.
@Observable
final class RoutineEditorModel {
    var draft: RoutineDraft
    @ObservationIgnored let original: RoutineDraft

    init(draft: RoutineDraft) {
        self.draft = draft
        original = draft
    }

    /// Whether anything differs from the routine as it was opened.
    var hasChanges: Bool { draft != original }
}

/// Edits a routine in a sheet: name, ordered exercises with targets and alternatives, notes.
/// Nothing is written until Save.
struct RoutineEditorView: View {
    @State private var model: RoutineEditorModel
    @State private var showsPicker: Bool
    @State private var confirmsDiscard = false
    @State private var editMode: EditMode = .inactive
    @State private var saveFailed = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]

    init(draft: RoutineDraft, showsPickerInitially: Bool = false) {
        _model = State(initialValue: RoutineEditorModel(draft: draft))
        _showsPicker = State(initialValue: showsPickerInitially)
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    TextField("Routine Name", text: $model.draft.name)
                        .font(.title3.weight(.semibold))
                        .submitLabel(.done)
                }
                Section {
                    ForEach(model.draft.items) { item in
                        NavigationLink(value: item.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.exerciseName)
                                Text(itemDetail(item))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .onDelete { model.draft.removeItems(atOffsets: $0) }
                    .onMove { model.draft.moveItems(fromOffsets: $0, toOffset: $1) }
                    Button("Add Exercises", systemImage: "plus") { showsPicker = true }
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        if model.draft.items.count > 1 {
                            Button(editMode.isEditing ? "Done" : "Reorder") {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            }
                            .font(.subheadline)
                            .textCase(nil)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Notes for this routine", text: $model.draft.notes, axis: .vertical)
                        .lineLimit(2...8)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(model.draft.routineID == nil ? "New Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                RoutineItemEditor(model: model, itemID: id, exercises: exercises)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model.hasChanges {
                            confirmsDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!model.draft.canSave)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .alert("Couldn't Save", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This routine may have been deleted on another device.")
            }
            .sheet(isPresented: $showsPicker) {
                ExercisePickerView(title: "Add Exercises", limit: nil, excluded: []) { picked in
                    model.draft.addExercises(picked.map { (id: $0.id, name: $0.name) })
                }
            }
        }
        .interactiveDismissDisabled(model.hasChanges)
    }

    private func itemDetail(_ item: RoutineDraft.Item) -> String {
        let targets = Formatting.targets(sets: item.targetSets, repLow: item.repLow, repHigh: item.repHigh)
        guard let rest = item.restSeconds else { return targets }
        return "\(targets) · \(String(localized: "rest \(Formatting.rest(rest))"))"
    }

    private func save() {
        do {
            try model.draft.apply(in: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveFailed = true
        }
    }
}

/// One exercise of the routine being edited: sets, rep range, rest and alternatives.
struct RoutineItemEditor: View {
    @Bindable var model: RoutineEditorModel
    let itemID: UUID
    let exercises: [Exercise]

    @State private var showsAlternativePicker = false
    @Environment(\.dismiss) private var dismiss
    /// Oldest first, like Settings: the row that survives a sync merge.
    @Query(sort: \AppSettings.createdAt) private var settingsRows: [AppSettings]

    var body: some View {
        if let item = model.draft.item(id: itemID) {
            form(for: item)
        } else {
            ContentUnavailableView("Exercise Removed", systemImage: "trash")
        }
    }

    private func form(for item: RoutineDraft.Item) -> some View {
        let alternatives = alternativeIDs(of: item.exerciseID)
        return Form {
            Section {
                Stepper(value: binding(\.targetSets, set: { model.draft.setTargetSets($0, forItem: itemID) }), in: RoutineRules.setsRange) {
                    LabeledContent("Sets", value: "\(item.targetSets)")
                }
            }
            Section {
                RepRangeWheels(
                    low: binding(\.repLow, set: { model.draft.setRepLow($0, forItem: itemID) }),
                    high: binding(\.repHigh, set: { model.draft.setRepHigh($0, forItem: itemID) })
                )
            } header: {
                Text("Reps")
            } footer: {
                Text("Aim for \(item.repLow == item.repHigh ? "\(item.repLow)" : "\(item.repLow) to \(item.repHigh)") reps in each set.")
            }
            Section {
                RestPicker(
                    String(localized: "Rest"),
                    seconds: binding(\.restSeconds, set: { model.draft.setRest($0, forItem: itemID) }),
                    default: exerciseDefaultRest(for: item.exerciseID)
                )
            } footer: {
                Text("The rest timer on Apple Watch starts after each logged set.")
            }
            Section {
                ForEach(alternatives, id: \.self) { id in
                    Text(name(of: id))
                }
                .onDelete { offsets in
                    let remaining = alternatives.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
                    model.draft.setAlternatives(remaining, of: item.exerciseID)
                }
                if alternatives.count < ExerciseRules.maxAlternatives {
                    Button("Add Alternative", systemImage: "plus") { showsAlternativePicker = true }
                }
            } header: {
                Text("Alternatives")
            } footer: {
                Text("Up to \(ExerciseRules.maxAlternatives). Alternatives belong to the exercise, so every routine that uses it shares them.")
            }
            Section {
                Button("Remove from Routine", role: .destructive) {
                    model.draft.removeItem(id: itemID)
                    dismiss()
                }
            }
        }
        .navigationTitle(item.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsAlternativePicker) {
            ExercisePickerView(
                title: "Add Alternatives",
                limit: ExerciseRules.maxAlternatives - alternatives.count,
                excluded: Set(alternatives + [item.exerciseID])
            ) { picked in
                model.draft.setAlternatives(alternatives + picked.map(\.id), of: item.exerciseID)
            }
        }
    }

    /// The exercise's alternatives as edited in the draft, else as stored, by name.
    private func alternativeIDs(of exerciseID: UUID) -> [UUID] {
        let stored = exercises.first { $0.id == exerciseID }?.alternatives ?? []
        let current = stored
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.id)
        return model.draft.alternatives(of: exerciseID, current: current)
    }

    /// What "use the default" means for this item: the exercise's own default rest, else the
    /// one in Settings.
    private func exerciseDefaultRest(for exerciseID: UUID) -> RestPicker.DefaultOption {
        let own = exercises.first { $0.id == exerciseID }?.defaultRestSeconds
        let seconds = own ?? settingsRows.first?.defaultRestSeconds ?? RestTimer.fallbackSeconds
        let rest = Formatting.rest(seconds)
        return RestPicker.DefaultOption(
            summary: String(localized: "Exercise default (\(rest))"),
            explanation: own == nil
                ? String(localized: "The default rest in Settings, now \(rest).")
                : String(localized: "This exercise's default rest, now \(rest)."),
            seconds: seconds
        )
    }

    private func name(of id: UUID) -> String {
        exercises.first { $0.id == id }?.name ?? ""
    }

    /// A binding to one value of this item that writes through a validating draft method.
    /// If the item was removed meanwhile, it reads the defaults of a new item.
    private func binding<Value>(_ keyPath: KeyPath<RoutineDraft.Item, Value>, set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: {
                let item = model.draft.item(id: itemID) ?? RoutineDraft.Item(exerciseID: UUID(), exerciseName: "")
                return item[keyPath: keyPath]
            },
            set: { value in set(value) }
        )
    }
}

/// Two wheels for the bottom and top of a rep range. Moving one past the other moves both.
private struct RepRangeWheels: View {
    @Binding var low: Int
    @Binding var high: Int

    var body: some View {
        HStack(spacing: 0) {
            wheel(String(localized: "From"), selection: $low)
            Text(verbatim: "–")
                .font(.title3)
                .accessibilityHidden(true)
            wheel(String(localized: "To"), selection: $high)
        }
    }

    private func wheel(_ title: String, selection: Binding<Int>) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Picker(title, selection: selection) {
                ForEach(Array(RoutineRules.repsRange), id: \.self) { reps in
                    Text("\(reps)").monospacedDigit().tag(reps)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: 140)
            .clipped()
            .accessibilityLabel(String(localized: "\(title) reps"))
        }
    }
}
