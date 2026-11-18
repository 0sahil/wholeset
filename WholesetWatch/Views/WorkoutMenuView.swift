// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The ••• menu: swap, set changes and skip for the current exercise, the exercise list,
/// adding an exercise, and End. Works from the done and skipped pages too.
struct WorkoutMenuView: View {
    @Bindable var controller: WorkoutController

    var body: some View {
        NavigationStack(path: $controller.menuPath) {
            Group {
                if let engine = controller.engine {
                    MenuList(controller: controller, engine: engine)
                }
            }
            .navigationDestination(for: MenuDestination.self) { destination in
                if let engine = controller.engine {
                    switch destination {
                    case .swap:
                        SwapView(controller: controller, engine: engine)
                    case .exercises(let purpose):
                        ExercisePickerView(controller: controller, engine: engine, purpose: purpose)
                    case .muscleGroup(let group, let purpose):
                        MuscleGroupExercisesView(controller: controller, engine: engine, group: group, purpose: purpose)
                    case .allExercises(let editing):
                        AllExercisesView(controller: controller, engine: engine, isEditing: editing)
                    }
                }
            }
        }
    }
}

/// The menu's top level, most-used first.
private struct MenuList: View {
    let controller: WorkoutController
    let engine: WorkoutEngine

    var body: some View {
        let entry = engine.currentEntry
        List {
            if entry != nil {
                NavigationLink(value: MenuDestination.swap) {
                    Label("Swap exercise", systemImage: "arrow.left.arrow.right")
                }
                .disabled(!engine.canSwapCurrentExercise)
                Button {
                    controller.addSet()
                    controller.sheet = nil
                } label: {
                    Label("Add set", systemImage: "plus")
                }
                .disabled(!engine.canAddSet)
                Button {
                    controller.removeSet()
                    controller.sheet = nil
                } label: {
                    Label("Remove set", systemImage: "minus")
                }
                .disabled(!engine.canRemoveSet)
                Button {
                    controller.toggleWarmup()
                    controller.sheet = nil
                } label: {
                    Label(
                        engine.currentSet?.isWarmup == true ? "Mark as working set" : "Mark as warm-up",
                        systemImage: "flame"
                    )
                }
                .disabled(engine.currentSet == nil)
            }
            if let entry {
                Button {
                    controller.setSkipped(!entry.isSkipped, for: entry)
                    controller.sheet = nil
                } label: {
                    if entry.isSkipped {
                        Label("Resume exercise", systemImage: "arrow.uturn.backward")
                    } else {
                        Label("Skip exercise", systemImage: "forward")
                    }
                }
                .disabled(!entry.isSkipped && engine.isDone(entry))
            }
            NavigationLink(value: MenuDestination.allExercises(editing: false)) {
                Label("All exercises", systemImage: "list.bullet")
            }
            .disabled(engine.entries.isEmpty)
            NavigationLink(value: MenuDestination.exercises(.add)) {
                Label("Add exercise", systemImage: "plus.circle")
            }
            Button(role: .destructive) {
                controller.sheet = .endConfirm
            } label: {
                Label("End workout", systemImage: "xmark.circle")
            }
        }
        .navigationTitle(entry?.exercise?.name ?? engine.session.name)
    }
}

/// "Instead of Bench Press": the exercise's alternatives (set on iPhone) with what was done
/// last time, then "Other…" for the full list.
private struct SwapView: View {
    let controller: WorkoutController
    let engine: WorkoutEngine

    var body: some View {
        let current = engine.currentEntry?.exercise
        List {
            Section {
                ForEach(alternatives(of: current)) { exercise in
                    Button {
                        controller.swapCurrentExercise(to: exercise)
                    } label: {
                        ExerciseRowLabel(exercise: exercise, detail: lastText(for: exercise))
                    }
                    .accessibilityHint("Swaps to this exercise. Sets already logged stay with \(current?.name ?? "")")
                }
                NavigationLink(value: MenuDestination.exercises(.swap)) {
                    Text("Other…")
                }
            } header: {
                Text("Instead of \(current?.name ?? "")")
                    .textCase(nil)
            }
        }
        .navigationTitle("Swap")
    }

    private func alternatives(of exercise: Exercise?) -> [Exercise] {
        guard let exercise else { return [] }
        let candidates = (exercise.alternatives ?? []).filter { !$0.isArchived && $0 !== exercise }
        return Array(ExerciseCatalog.filtered(candidates, by: ExerciseCatalog.Filter()).prefix(ExerciseRules.maxAlternatives))
    }

    /// "26×10": the best working set of last time.
    private func lastText(for exercise: Exercise) -> String? {
        engine.lastPerformance(of: exercise)?.topSet.map { WatchSetText.compact($0.values, scale: controller.scale) }
    }
}

/// Recent exercises, then the library by muscle group. No typing.
private struct ExercisePickerView: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    let purpose: ExercisePickPurpose

    @State private var recent: [Exercise] = []
    @State private var groups: [MuscleGroup] = []

    var body: some View {
        List {
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent) { exercise in
                        ExercisePickButton(controller: controller, engine: engine, exercise: exercise, purpose: purpose)
                    }
                }
            }
            Section("All exercises") {
                ForEach(groups) { group in
                    NavigationLink(value: MenuDestination.muscleGroup(group, purpose)) {
                        Text(group.watchLabel)
                    }
                }
            }
        }
        .navigationTitle(purpose == .add ? "Add" : "Swap")
        .task {
            recent = controller.recentExercises().filter { $0 !== engine.currentEntry?.exercise || purpose == .add }
            groups = controller.muscleGroups()
        }
    }
}

/// The library exercises of one muscle group.
private struct MuscleGroupExercisesView: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    let group: MuscleGroup
    let purpose: ExercisePickPurpose

    @State private var exercises: [Exercise] = []

    var body: some View {
        List(exercises) { exercise in
            ExercisePickButton(controller: controller, engine: engine, exercise: exercise, purpose: purpose)
        }
        .navigationTitle(group.watchLabel)
        .task {
            exercises = controller.exercises(in: group)
        }
    }
}

/// One exercise in a pick list: adds it, or swaps to it.
private struct ExercisePickButton: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    let exercise: Exercise
    let purpose: ExercisePickPurpose

    var body: some View {
        let isCurrent = purpose == .swap && exercise === engine.currentEntry?.exercise
        Button {
            switch purpose {
            case .add: controller.addExercise(exercise)
            case .swap: controller.swapCurrentExercise(to: exercise)
            }
        } label: {
            ExerciseRowLabel(exercise: exercise, detail: nil)
        }
        .disabled(isCurrent)
        .accessibilityHint(purpose == .add ? "Adds it at the end of the workout." : "Swaps to this exercise.")
    }
}

private struct ExerciseRowLabel: View {
    let exercise: Exercise
    let detail: String?

    var body: some View {
        HStack {
            Text(exercise.name)
                .lineLimit(2)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Every exercise with its progress; tap one to go to it. Edit mode shows, per row, buttons
/// to move it up or down and to skip or resume it (watchOS has no reliable drag to reorder).
private struct AllExercisesView: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    @State var isEditing: Bool

    var body: some View {
        List(Array(engine.entries.enumerated()), id: \.element.id) { index, entry in
            let isCurrent = index == engine.currentIndex
            Group {
                if isEditing {
                    EditRow(controller: controller, engine: engine, entry: entry, index: index)
                } else {
                    Button {
                        controller.jumpToEntry(at: index)
                    } label: {
                        ProgressRow(engine: engine, entry: entry, isCurrent: isCurrent)
                    }
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.tile)
                    .strokeBorder(isCurrent && !isEditing ? Color.white : .clear, lineWidth: 2)
            )
        }
        .navigationTitle(engine.session.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
                .accessibilityHint(isEditing ? "" : "Reorder or skip exercises.")
            }
        }
    }
}

/// Name and "1/3" (in the accent once complete) or "Skipped", for the exercise lists of the
/// ••• menu and the Stats page. VoiceOver reads e.g. "Bench Press, 3 of 3 sets logged, current".
struct ProgressRow: View {
    let engine: WorkoutEngine
    let entry: SessionExercise
    /// Whether this is the exercise on the exercise page.
    var isCurrent = false

    var body: some View {
        let progress = engine.progress(of: entry)
        HStack {
            Text(entry.exercise?.name ?? "")
                .lineLimit(2)
                .foregroundStyle(entry.isSkipped ? .secondary : .primary)
            Spacer(minLength: 4)
            Group {
                if progress.isSkipped {
                    Text("Skipped")
                } else {
                    Text("\(progress.completed)/\(progress.total)")
                }
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(progress.isDone && !progress.isSkipped ? Theme.accent : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.exercise?.name ?? "")
        .accessibilityValue(spokenProgress(progress))
    }

    private func spokenProgress(_ progress: ExerciseProgress) -> String {
        let text = progress.isSkipped
            ? String(localized: "Skipped")
            : inflectedString("\(progress.completed) of ^[\(progress.total) set](inflect: true) logged")
        return isCurrent ? String(localized: "\(text), current") : text
    }
}

/// Edit mode: the name, then move up, move down and skip/resume.
private struct EditRow: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    let entry: SessionExercise
    let index: Int

    var body: some View {
        let name = entry.exercise?.name ?? ""
        VStack(alignment: .leading, spacing: 6) {
            ProgressRow(engine: engine, entry: entry)
            HStack(spacing: 6) {
                RowControl(systemImage: "chevron.up", label: "Move \(name) up") {
                    controller.moveEntry(at: index, by: -1)
                }
                .disabled(index == 0)
                RowControl(systemImage: "chevron.down", label: "Move \(name) down") {
                    controller.moveEntry(at: index, by: 1)
                }
                .disabled(index == engine.entries.count - 1)
                RowControl(
                    systemImage: entry.isSkipped ? "arrow.uturn.backward" : "forward",
                    label: entry.isSkipped ? "Resume \(name)" : "Skip \(name)"
                ) {
                    controller.setSkipped(!entry.isSkipped, for: entry)
                }
                .disabled(!entry.isSkipped && engine.isDone(entry))
            }
        }
        .padding(.vertical, 2)
    }
}

/// A round icon button inside an edit row; its own tap target, separate from the row.
private struct RowControl: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Theme.control, in: Capsule())
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension MuscleGroup {
    /// The name shown in the Watch's exercise lists.
    var watchLabel: String {
        switch self {
        case .chest: String(localized: "Chest")
        case .back: String(localized: "Back")
        case .shoulders: String(localized: "Shoulders")
        case .arms: String(localized: "Arms")
        case .legs: String(localized: "Legs")
        case .core: String(localized: "Core")
        case .other: String(localized: "Other")
        }
    }
}

/// Compact set text for the Watch's small lines.
enum WatchSetText {
    /// "60×10", or "×12" without weight.
    static func compact(_ values: SetValues, scale: WeightScale) -> String {
        let reps = values.reps.map { "\($0)" } ?? "–"
        guard let weight = values.weightKg else { return "×\(reps)" }
        return "\(WeightFormat.string(kilograms: weight, scale: scale))×\(reps)"
    }

    /// "60 × 10", or "12 reps" without weight.
    static func spaced(_ values: SetValues, scale: WeightScale) -> String {
        let reps = values.reps.map { "\($0)" } ?? "–"
        guard let weight = values.weightKg else { return String(localized: "\(reps) reps") }
        return "\(WeightFormat.string(kilograms: weight, scale: scale)) × \(reps)"
    }

    /// "60 kilograms, 10 reps", for VoiceOver.
    static func spoken(_ values: SetValues, scale: WeightScale) -> String {
        var parts: [String] = []
        if let weight = values.weightKg {
            parts.append(SpokenWeight.string(kilograms: weight, scale: scale))
        }
        parts.append(values.reps.map { inflectedString("^[\($0) rep](inflect: true)") } ?? String(localized: "reps not set"))
        return parts.formatted(.list(type: .and, width: .narrow))
    }
}
