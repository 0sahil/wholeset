// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// Chooses the routine for one weekday, or a rest day. One tap sets it and closes the sheet.
struct DayRoutinePicker: View {
    let weekday: Int
    let routines: [Routine]
    let planDays: [WeekPlanDay]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var day: WeekPlan.Day? {
        WeekPlan.days(planDays: planDays, calendar: .current).first { $0.weekday == weekday }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(routines) { routine in
                        choice(routine.name, isSelected: day?.routine?.persistentModelID == routine.persistentModelID) {
                            set(routine)
                        }
                    }
                }
                Section {
                    choice(String(localized: "Rest"), isSelected: day?.isRest == true) {
                        set(nil)
                    }
                } footer: {
                    Text("This applies every week.")
                }
            }
            .navigationTitle(Formatting.weekdayName(weekday))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func choice(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .listRowButtonLabel()
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func set(_ routine: Routine?) {
        do {
            try WeekPlan.set(routine, on: weekday, in: modelContext)
            modelContext.saveLogged()
        } catch {
            modelContext.rollback()
        }
        dismiss()
    }
}
