// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// Picks exercises from the library and custom exercises: search, a muscle-group filter,
/// an equipment filter and multiple selection. A search without a match offers to create
/// a custom exercise.
struct ExercisePickerView: View {
    let title: LocalizedStringKey
    /// The most exercises that can be picked, or `nil` for no limit.
    let limit: Int?
    /// Exercises not offered (already chosen).
    let excluded: Set<UUID>
    let onPick: ([Exercise]) -> Void

    @Query private var exercises: [Exercise]
    @Environment(StoreCoordinator.self) private var store
    @State private var filter = ExerciseCatalog.Filter()
    @State private var selection: [UUID] = []
    @State private var creatingName: NewExerciseRequest?
    @Environment(\.dismiss) private var dismiss

    private var available: [Exercise] {
        exercises.filter { !excluded.contains($0.id) }
    }

    private var shown: [Exercise] {
        ExerciseCatalog.filtered(available, by: filter)
    }

    private var isFull: Bool {
        guard let limit else { return false }
        return selection.count >= limit
    }

    /// The search text when no exercise has exactly that name.
    private var nameToCreate: String? {
        let trimmed = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              case .success = ExerciseCatalog.validateNewName(trimmed, existing: exercises) else { return nil }
        return trimmed
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MuscleGroupChips(selection: $filter.group)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let name = nameToCreate {
                    Section {
                        Button("Create “\(name)”", systemImage: "plus.circle") {
                            creatingName = NewExerciseRequest(name: name)
                        }
                    } footer: {
                        Text("Adds a custom exercise with this name.")
                    }
                }
                Section {
                    ForEach(shown) { exercise in
                        row(exercise)
                    }
                } footer: {
                    if let limit {
                        Text("Choose up to \(limit).")
                    }
                }
            }
            .overlay {
                if exercises.isEmpty && store.isWaitingForFirstImport {
                    LibraryWaitingView()
                } else if shown.isEmpty && nameToCreate == nil {
                    ContentUnavailableView.search(text: filter.searchText)
                }
            }
            .searchable(text: $filter.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search \(available.count) exercises"))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.isEmpty ? String(localized: "Add") : String(localized: "Add (\(selection.count))")) {
                        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                        onPick(selection.compactMap { byID[$0] })
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EquipmentFilterMenu(selection: $filter.equipment)
                }
            }
            .sheet(item: $creatingName) { request in
                NewExerciseView(initialName: request.name) { created in
                    if !isFull {
                        selection.append(created.id)
                    }
                    filter.searchText = ""
                }
            }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        let isSelected = selection.contains(exercise.id)
        return Button {
            if isSelected {
                selection.removeAll { $0 == exercise.id }
            } else if !isFull {
                selection.append(exercise.id)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                    Text(exercise.detailLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
            .listRowButtonLabel()
            .contentShape(Rectangle())
        }
        .disabled(!isSelected && isFull)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A name to start a new custom exercise with.
struct NewExerciseRequest: Identifiable {
    let name: String
    var id: String { name }
}

/// Muscle-group filter chips: All, Chest, Back, …
struct MuscleGroupChips: View {
    @Binding var selection: MuscleGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: String(localized: "All"), isSelected: selection == nil) { selection = nil }
                ForEach(MuscleGroup.allCases) { group in
                    FilterChip(title: group.label, isSelected: selection == group) {
                        selection = selection == group ? nil : group
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Muscle group")
    }
}

/// A toolbar menu to filter by equipment.
struct EquipmentFilterMenu: View {
    @Binding var selection: Equipment?

    var body: some View {
        Menu {
            Picker("Equipment", selection: $selection) {
                Text("All Equipment").tag(Equipment?.none)
                ForEach(Equipment.allCases, id: \.self) { equipment in
                    Text(equipment.label).tag(Equipment?.some(equipment))
                }
            }
        } label: {
            Label(
                selection?.label ?? String(localized: "Equipment"),
                systemImage: selection == nil
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .accessibilityLabel("Filter by equipment")
        .accessibilityValue(selection?.label ?? String(localized: "All equipment"))
    }
}
