// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// The Plan tab: today's routine, the weekly plan and the routines list.
struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppModel.self) private var model
    @Query private var routineRows: [Routine]
    @Query private var planDays: [WeekPlanDay]
    @State private var routinePendingDeletion: Routine?
    @State private var editMode: EditMode = .inactive

    private var routines: [Routine] { TodayPlanResolver.sortedRoutines(routineRows) }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack {
            Group {
                if routines.isEmpty {
                    PlanEmptyView(
                        newRoutine: { navigation.planSheet = .newRoutine },
                        importHistory: { model.beginImport() },
                        addStarters: addStarters
                    )
                } else {
                    planList
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Routine", systemImage: "plus") {
                        navigation.planSheet = .newRoutine
                    }
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let routine = routineRows.first(where: { $0.persistentModelID == id }) {
                    RoutineDetailView(routine: routine)
                }
            }
        }
        .sheet(item: $navigation.planSheet) { sheet in
            switch sheet {
            case .newRoutine:
                RoutineEditorView(draft: RoutineDraft())
            case let .editRoutine(id, showsPicker):
                if let routine = routineRows.first(where: { $0.id == id }) {
                    RoutineEditorView(draft: RoutineDraft(routine: routine), showsPickerInitially: showsPicker)
                } else {
                    ContentUnavailableView("Routine Deleted", systemImage: "trash", description: Text("This routine was deleted, possibly on another device."))
                }
            case .day(let weekday):
                DayRoutinePicker(weekday: weekday, routines: routines, planDays: planDays)
            }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { routinePendingDeletion != nil },
                set: { if !$0 { routinePendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: routinePendingDeletion
        ) { routine in
            Button("Delete Routine", role: .destructive) { delete(routine) }
        } message: { _ in
            Text("Past workouts keep their records. Days planned with this routine become rest days.")
        }
    }

    private var planList: some View {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.component(.weekday, from: now)
        return List {
            Section("Today") {
                TodaySummary(plan: WeekPlan.today(planDays: planDays, routines: routines, on: now, calendar: calendar), date: now)
            }
            Section {
                ForEach(WeekPlan.days(planDays: planDays, calendar: calendar)) { day in
                    Button {
                        navigation.planSheet = .day(day.weekday)
                    } label: {
                        WeekdayRow(day: day, isToday: day.weekday == today)
                            .listRowButtonLabel()
                    }
                }
            } header: {
                Text("This Week")
            } footer: {
                Text("Your Apple Watch offers the day's routine on its Home screen. The plan repeats every week.")
            }
            Section {
                ForEach(routines) { routine in
                    NavigationLink(value: routine.persistentModelID) {
                        RoutineRow(routine: routine, planDays: planDays)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            routinePendingDeletion = routine
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            duplicate(routine)
                        }
                        .tint(.accentColor)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {
                            navigation.planSheet = .editRoutine(routine.id)
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(routine) }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            routinePendingDeletion = routine
                        }
                    }
                }
                .onMove(perform: moveRoutines)
            } header: {
                HStack {
                    Text("Routines")
                    Spacer()
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.subheadline)
                    .textCase(nil)
                }
            } footer: {
                Text("Apple Watch lists routines in this order.")
            }
        }
        .environment(\.editMode, $editMode)
    }

    private var deletionTitle: String {
        guard let routine = routinePendingDeletion else { return "" }
        return String(localized: "Delete “\(routine.name)”?")
    }

    // MARK: Actions

    private func addStarters() {
        do {
            try StarterRoutines.seed(in: modelContext)
        } catch {
            modelContext.rollback()
        }
    }

    private func duplicate(_ routine: Routine) {
        do {
            try RoutineEditing.duplicate(routine, in: modelContext)
            modelContext.saveLogged()
        } catch {
            modelContext.rollback()
        }
    }

    private func delete(_ routine: Routine) {
        RoutineEditing.delete(routine, in: modelContext)
        modelContext.saveLogged()
        routinePendingDeletion = nil
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        RoutineEditing.moveRoutines(routines, fromOffsets: source, toOffset: destination)
        modelContext.saveLogged()
    }
}

/// Shown until the first routine exists.
private struct PlanEmptyView: View {
    let newRoutine: () -> Void
    let importHistory: () -> Void
    let addStarters: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label("No Routines Yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Build a routine, then put it on the days you train. Your Apple Watch shows the day's routine.")
                }
                Button("New Routine", action: newRoutine)
                    .buttonStyle(AccentFillButtonStyle())
                Button(action: importHistory) {
                    Text("Import from Another App")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Brings in your workouts from Strong, Hevy, FitNotes or another app, and offers routines made from them.")
                Button(action: addStarters) {
                    Text("Start with Push, Pull and Legs")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityHint("Adds three ready-made routines you can edit.")
            }
            .padding(.horizontal, 24)
        }
    }
}

/// What today holds, at the top of the Plan tab.
private struct TodaySummary: View {
    let plan: TodayPlan
    let date: Date

    var body: some View {
        switch plan {
        case .planned(let routine):
            NavigationLink(value: routine.persistentModelID) {
                summary(title: routine.name, detail: exerciseCount(routine))
            }
        case .restDay(let next):
            summary(title: String(localized: "Rest Day"), detail: next.map(nextLabel) ?? String(localized: "Nothing else planned this week."))
        case .unplanned(let suggested):
            summary(
                title: String(localized: "Nothing Planned"),
                detail: String(localized: "Your Apple Watch will suggest \(suggested.name).")
            )
        case .noRoutines:
            summary(title: String(localized: "No Routines"), detail: "")
        }
    }

    private func summary(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date, format: .dateTime.weekday(.wide))
                .font(.subheadline)
                .foregroundStyle(.tint)
            Text(title)
                .font(.title3.weight(.semibold))
            if !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func exerciseCount(_ routine: Routine) -> String {
        inflectedString("^[\(routine.sortedItems.count { $0.exercise != nil }) exercise](inflect: true)")
    }

    private func nextLabel(_ next: UpcomingDay) -> String {
        if next.daysAhead == 1 {
            return String(localized: "Next: \(next.routine.name), tomorrow")
        }
        return String(localized: "Next: \(next.routine.name) on \(Formatting.weekdayName(next.weekday))")
    }
}

/// One weekday of the plan.
private struct WeekdayRow: View {
    let day: WeekPlan.Day
    let isToday: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(Formatting.weekdayName(day.weekday))
                .frame(minWidth: 0, alignment: .leading)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(day.routine == nil ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
            if isToday {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Choose a routine or a rest day.")
    }

    private var value: String {
        if let routine = day.routine { return routine.name }
        return day.isRest ? String(localized: "Rest") : String(localized: "Not planned")
    }
}

/// A routine in the routines list.
private struct RoutineRow: View {
    let routine: Routine
    let planDays: [WeekPlanDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(routine.name)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        let count = inflectedString("^[\(routine.sortedItems.count { $0.exercise != nil }) exercise](inflect: true)")
        let days = TodayPlanResolver.plannedWeekdays(for: routine, in: planDays).map { Formatting.shortWeekdayName($0) }
        guard !days.isEmpty else { return count }
        return "\(count) · \(days.formatted(.list(type: .and, width: .narrow)))"
    }
}
