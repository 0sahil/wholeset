// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// A routine: its planned days, exercises with targets, and notes. Editing happens in a sheet.
struct RoutineDetailView: View {
    let routine: Routine

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigation.self) private var navigation
    @Query private var planDays: [WeekPlanDay]
    @State private var confirmsDeletion = false

    var body: some View {
        List {
            Section {
                ForEach(routine.sortedItems.filter { $0.exercise != nil }) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.exercise?.name ?? "")
                        Text(detail(for: item))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button("Add Exercise", systemImage: "plus") {
                    navigation.planSheet = .editRoutine(routine.id, showsPicker: true)
                }
            } header: {
                Text(subtitle)
                    .textCase(nil)
            }
            if !routine.notes.isEmpty {
                Section("Notes") {
                    Text(routine.notes)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(routine.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    navigation.planSheet = .editRoutine(routine.id)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    if (try? RoutineEditing.duplicate(routine, in: modelContext)) != nil {
                        modelContext.saveLogged()
                    }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    confirmsDeletion = true
                }
            }
        }
        .confirmationDialog(String(localized: "Delete “\(routine.name)”?"), isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete Routine", role: .destructive) {
                RoutineEditing.delete(routine, in: modelContext)
                modelContext.saveLogged()
                dismiss()
            }
        } message: {
            Text("Past workouts keep their records. Days planned with this routine become rest days.")
        }
    }

    private var subtitle: String {
        let count = inflectedString("^[\(routine.sortedItems.count { $0.exercise != nil }) exercise](inflect: true)")
        let days = TodayPlanResolver.plannedWeekdays(for: routine, in: planDays).map { Formatting.shortWeekdayName($0) }
        guard !days.isEmpty else { return count }
        return String(localized: "On \(days.formatted(.list(type: .and, width: .narrow))) · \(count)")
    }

    private func detail(for item: RoutineItem) -> String {
        var parts = [
            Formatting.targets(sets: item.targetSets, repLow: item.repLow, repHigh: item.repHigh),
            item.restSeconds.map { String(localized: "rest \(Formatting.rest($0))") } ?? String(localized: "default rest"),
        ]
        let alternatives = item.exercise?.alternatives?.count ?? 0
        if alternatives > 0 {
            parts.append(inflectedString("^[\(alternatives) alternative](inflect: true)"))
        }
        return parts.joined(separator: " · ")
    }
}
