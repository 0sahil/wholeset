// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// The Exercises tab: the built-in library plus custom exercises, with search, muscle-group
/// and equipment filters, and archived exercises on request.
struct ExercisesView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(StoreCoordinator.self) private var store
    @Environment(HistoryModel.self) private var history
    @Query private var exercises: [Exercise]
    @State private var filter = ExerciseCatalog.Filter()
    @State private var showsNewExercise = false

    private var shown: [Exercise] { ExerciseCatalog.filtered(exercises, by: filter) }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.exercisePath) {
            List {
                Section {
                    MuscleGroupChips(selection: $filter.group)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                ForEach(sections, id: \.group) { section in
                    Section(section.group.label) {
                        ForEach(section.exercises) { exercise in
                            NavigationLink(value: AppDestination.exercise(exercise.id)) {
                                ExerciseRow(exercise: exercise, lastTopSet: history.timeline(forExercise: exercise.id)?.lastTopSet)
                            }
                        }
                    }
                }
            }
            .overlay {
                if exercises.isEmpty && store.isWaitingForFirstImport {
                    LibraryWaitingView()
                } else if shown.isEmpty {
                    if filter.searchText.isEmpty {
                        ContentUnavailableView("No Exercises", systemImage: "dumbbell", description: Text("Nothing matches these filters."))
                    } else {
                        ContentUnavailableView.search(text: filter.searchText)
                    }
                }
            }
            .searchable(text: $filter.searchText, prompt: Text("Search"))
            .navigationTitle("Exercises")
            .appDestinations()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Exercise", systemImage: "plus") { showsNewExercise = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Equipment", selection: $filter.equipment) {
                            Text("All Equipment").tag(Equipment?.none)
                            ForEach(Equipment.allCases, id: \.self) { equipment in
                                Text(equipment.label).tag(Equipment?.some(equipment))
                            }
                        }
                        Toggle("Show Archived", isOn: $filter.includesArchived)
                    } label: {
                        Label(
                            "Filter",
                            systemImage: filter.equipment == nil && !filter.includesArchived
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                    .accessibilityLabel("Filter exercises")
                }
            }
            .sheet(isPresented: $showsNewExercise) {
                NewExerciseView { created in
                    navigation.exercisePath = [.exercise(created.id)]
                }
            }
        }
    }

    /// The filtered exercises grouped by muscle group, in group order.
    private var sections: [(group: MuscleGroup, exercises: [Exercise])] {
        let grouped = Dictionary(grouping: shown) { MuscleGroup($0.primaryMuscle) }
        return MuscleGroup.allCases.compactMap { group in
            guard let exercises = grouped[group], !exercises.isEmpty else { return nil }
            return (group, exercises)
        }
    }
}

/// Shown while the built-in library waits for the first iCloud download of this launch.
struct LibraryWaitingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Checking iCloud", systemImage: "icloud.and.arrow.down")
        } description: {
            Text("The exercise library is added once Wholeset has seen what's already in your iCloud, so nothing is added twice.")
        } actions: {
            ProgressView()
        }
    }
}

/// An exercise in a list: name, equipment, whether it is custom or archived, and the last
/// top set ("62.5 × 10", or "—" if never done).
private struct ExerciseRow: View {
    let exercise: Exercise
    let lastTopSet: TopSet?
    @Environment(\.weightUnit) private var unit

    var body: some View {
        LabeledContent {
            Text(lastTopSetText)
                .monospacedDigit()
        } label: {
            Text(exercise.name)
                .foregroundStyle(exercise.isArchived ? .secondary : .primary)
            Text(detail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name), \(detail)")
        .accessibilityValue(spokenTopSet)
    }

    private var lastTopSetText: String {
        guard let lastTopSet else { return "—" }
        return HistoryFormat.compactSet(weightKg: lastTopSet.weightKg, reps: lastTopSet.reps, unit: unit)
    }

    private var spokenTopSet: String {
        guard let lastTopSet else { return String(localized: "Never done") }
        return String(localized: "Last top set \(HistoryFormat.spokenSet(weightKg: lastTopSet.weightKg, reps: lastTopSet.reps, unit: unit))")
    }

    private var detail: String {
        var parts = [exercise.equipment.label]
        if exercise.isCustom { parts.append(String(localized: "Custom")) }
        if exercise.isArchived { parts.append(String(localized: "Archived")) }
        return parts.joined(separator: " · ")
    }
}
