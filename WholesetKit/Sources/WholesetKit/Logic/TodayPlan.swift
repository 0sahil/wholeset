// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// What the Watch home screen offers today, derived from the weekly plan.
public enum TodayPlan: Equatable {
    /// The weekly plan names this routine for today.
    case planned(Routine)
    /// Today is a rest day in the plan. `next` is the next planned training day in the
    /// coming week, if there is one.
    case restDay(next: UpcomingDay?)
    /// The plan says nothing about today; suggests the first routine in list order.
    case unplanned(suggested: Routine)
    /// There are no routines at all.
    case noRoutines

    /// The routine the Start button starts, if any. Rest days have none.
    public var startableRoutine: Routine? {
        switch self {
        case .planned(let routine), .unplanned(let routine): routine
        case .restDay, .noRoutines: nil
        }
    }
}

/// A future day in the weekly plan with a routine on it.
public struct UpcomingDay: Equatable {
    /// The planned routine.
    public let routine: Routine
    /// Days from today: 1 is tomorrow.
    public let daysAhead: Int
    /// `Calendar` weekday number (1 = Sunday … 7 = Saturday).
    public let weekday: Int
}

/// Resolves the home screen state from the weekly plan.
public enum TodayPlanResolver {
    /// Works out what to offer on `date`.
    ///
    /// Rules:
    /// - a plan row for today with a routine: that routine;
    /// - a plan row for today without one: a rest day, plus the next planned day within six days;
    /// - no plan row for today: the first routine by ``sortedRoutines(_:)``.
    ///
    /// If sync left several rows for one weekday, the most recently updated one wins
    /// (ties broken by `id`), so every device picks the same row. Rows with a weekday
    /// outside 1...7 are ignored.
    ///
    /// - Parameters:
    ///   - planDays: All weekly plan rows.
    ///   - routines: All routines.
    ///   - date: The moment to resolve for, usually now.
    ///   - calendar: Determines the weekday of `date`.
    public static func resolve(
        planDays: [WeekPlanDay],
        routines: [Routine],
        on date: Date,
        calendar: Calendar
    ) -> TodayPlan {
        let rows = effectiveRows(planDays)
        let today = calendar.component(.weekday, from: date)

        if let row = rows[today] {
            if let routine = row.routine {
                return .planned(routine)
            }
            return .restDay(next: nextPlannedDay(after: today, rows: rows))
        }
        guard let first = sortedRoutines(routines).first else { return .noRoutines }
        return .unplanned(suggested: first)
    }

    /// Routines in list order: `sortIndex`, then name, then `id`.
    public static func sortedRoutines(_ routines: [Routine]) -> [Routine] {
        routines.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            let byName = lhs.name.localizedStandardCompare(rhs.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The weekdays (1...7, ascending) on which `routine` is planned.
    public static func plannedWeekdays(for routine: Routine, in planDays: [WeekPlanDay]) -> [Int] {
        effectiveRows(planDays)
            .filter { $0.value.routine?.persistentModelID == routine.persistentModelID }
            .map(\.key)
            .sorted()
    }

    /// One row per valid weekday, picking the newest when there are duplicates.
    private static func effectiveRows(_ planDays: [WeekPlanDay]) -> [Int: WeekPlanDay] {
        var rows: [Int: WeekPlanDay] = [:]
        for day in planDays where (1...7).contains(day.weekday) {
            if let existing = rows[day.weekday], !isNewer(day, than: existing) { continue }
            rows[day.weekday] = day
        }
        return rows
    }

    private static func isNewer(_ lhs: WeekPlanDay, than rhs: WeekPlanDay) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func nextPlannedDay(after today: Int, rows: [Int: WeekPlanDay]) -> UpcomingDay? {
        for offset in 1...6 {
            let weekday = (today - 1 + offset) % 7 + 1
            if let routine = rows[weekday]?.routine {
                return UpcomingDay(routine: routine, daysAhead: offset, weekday: weekday)
            }
        }
        return nil
    }
}
