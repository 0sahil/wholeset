// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// The Watch home screen: today's routine (or rest day), other routines, empty workout.
///
/// The queries follow the store, so routines and plan changes arriving from iCloud while
/// the app runs show up here without a relaunch.
struct HomeView: View {
    let controller: WorkoutController

    @Query private var routines: [Routine]
    @Query private var planDays: [WeekPlanDay]
    @Environment(StoreCoordinator.self) private var store

    var body: some View {
        let today = Date.now
        let plan = TodayPlanResolver.resolve(planDays: planDays, routines: routines, on: today, calendar: .current)
        NavigationStack {
            List {
                TodayCard(plan: plan, date: today, isLookingInICloud: store.isWaitingForStarterDecision) { routine in
                    controller.start(routine)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                NavigationLink {
                    RoutineListView(routines: routines, planDays: planDays) { routine in
                        controller.start(routine)
                    }
                } label: {
                    Text(plan.startableRoutine == nil ? "Start a routine" : "Other routine")
                }
                .disabled(routines.isEmpty)

                Button("Empty workout") {
                    controller.startEmpty()
                }
                .accessibilityHint("Starts a workout without a routine; add exercises as you go.")
            }
            .navigationTitle {
                Text("Wholeset")
                    .foregroundStyle(Theme.accent)
            }
            .containerBackground(.black, for: .navigation)
        }
    }
}

/// The large card at the top of Home.
private struct TodayCard: View {
    let plan: TodayPlan
    let date: Date
    /// The Watch is waiting for iCloud before it decides about starter routines.
    let isLookingInICloud: Bool
    let start: (Routine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date, format: .dateTime.weekday(.wide))
                .font(.footnote)
                .foregroundStyle(.secondary)
            switch plan {
            case .planned(let routine), .unplanned(let routine):
                Text(routine.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text("^[\(exerciseCount(routine)) exercise](inflect: true)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Start") { start(routine) }
                    .buttonStyle(AccentButtonStyle())
                    .padding(.top, 6)
                    .accessibilityLabel("Start \(routine.name)")
            case .restDay(let next):
                Text("Rest day")
                    .font(.title3.weight(.semibold))
                if let next {
                    Text(nextLabel(next))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .noRoutines where isLookingInICloud:
                Text("No routines yet")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    ProgressView()
                        .fixedSize()
                    Text("Checking iCloud for your routines…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .noRoutines:
                Text("No routines")
                    .font(.title3.weight(.semibold))
                Text("Add a routine on iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func exerciseCount(_ routine: Routine) -> Int {
        routine.sortedItems.count { $0.exercise != nil }
    }

    private func nextLabel(_ next: UpcomingDay) -> String {
        if next.daysAhead == 1 {
            return String(localized: "Next: \(next.routine.name), tomorrow")
        }
        let symbols = Calendar.current.weekdaySymbols
        let day = symbols.indices.contains(next.weekday - 1) ? symbols[next.weekday - 1] : ""
        return String(localized: "Next: \(next.routine.name), \(day)")
    }
}

/// All routines in list order, with the weekdays each is planned on.
struct RoutineListView: View {
    let routines: [Routine]
    let planDays: [WeekPlanDay]
    let start: (Routine) -> Void

    var body: some View {
        List(TodayPlanResolver.sortedRoutines(routines)) { routine in
            Button {
                start(routine)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(routine.name)
                            .lineLimit(2)
                        Text("^[\(routine.sortedItems.count { $0.exercise != nil }) exercise](inflect: true)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(weekdays(for: routine))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHint("Starts this routine.")
        }
        .navigationTitle("Routines")
    }

    private func weekdays(for routine: Routine) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return TodayPlanResolver.plannedWeekdays(for: routine, in: planDays)
            .compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
            .formatted(.list(type: .and, width: .narrow))
    }
}
