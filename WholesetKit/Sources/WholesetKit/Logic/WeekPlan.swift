// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// The weekly plan: for each weekday, a routine or a rest day. It repeats every week.
///
/// A weekday has a plan row once the user set it; a row without a routine is a rest day,
/// and a weekday without a row is unplanned. If sync left several rows for one weekday, the
/// most recently updated one counts (ties broken by `id`), on every device alike.
public enum WeekPlan {
    /// One weekday of the plan.
    public struct Day: Identifiable, Equatable {
        /// `Calendar` weekday number: 1 = Sunday … 7 = Saturday.
        public let weekday: Int
        /// The planned routine; `nil` for a rest day or an unplanned day.
        public let routine: Routine?
        /// Whether the user set this day (to a routine or to rest).
        public let isPlanned: Bool

        public var id: Int { weekday }

        /// Whether the day is an explicit rest day.
        public var isRest: Bool { isPlanned && routine == nil }
    }

    /// The weekdays 1...7 starting at the calendar's first weekday (Monday in most of
    /// Europe, Sunday in the US).
    public static func orderedWeekdays(calendar: Calendar) -> [Int] {
        let first = (1...7).contains(calendar.firstWeekday) ? calendar.firstWeekday : 1
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// The seven days in the calendar's order.
    public static func days(planDays: [WeekPlanDay], calendar: Calendar) -> [Day] {
        let rows = effectiveRows(planDays)
        return orderedWeekdays(calendar: calendar).map { weekday in
            Day(weekday: weekday, routine: rows[weekday]?.routine, isPlanned: rows[weekday] != nil)
        }
    }

    /// The routine planned on `weekday`, if any.
    public static func routine(on weekday: Int, planDays: [WeekPlanDay]) -> Routine? {
        effectiveRows(planDays)[weekday]?.routine
    }

    /// What to offer on `date`: see ``TodayPlanResolver/resolve(planDays:routines:on:calendar:)``.
    public static func today(planDays: [WeekPlanDay], routines: [Routine], on date: Date, calendar: Calendar) -> TodayPlan {
        TodayPlanResolver.resolve(planDays: planDays, routines: routines, on: date, calendar: calendar)
    }

    /// The next day after `date` (within six days) with a routine planned.
    public static func nextPlannedDay(after date: Date, planDays: [WeekPlanDay], calendar: Calendar) -> UpcomingDay? {
        let today = calendar.component(.weekday, from: date)
        return TodayPlanResolver.nextPlannedDay(after: today, rows: effectiveRows(planDays))
    }

    /// Plans `routine` on `weekday`, or a rest day when `routine` is `nil`. Updates the
    /// weekday's row, or inserts one. Does not save.
    public static func set(_ routine: Routine?, on weekday: Int, in context: ModelContext, now: Date = .now) throws {
        guard (1...7).contains(weekday) else { return }
        let days = try context.fetch(FetchDescriptor<WeekPlanDay>(predicate: #Predicate { $0.weekday == weekday }))
        if let row = effectiveRow(in: days) {
            guard row.routine?.persistentModelID != routine?.persistentModelID else { return }
            row.routine = routine
            row.updatedAt = now
            return
        }
        let row = WeekPlanDay(weekday: weekday)
        row.createdAt = now
        row.updatedAt = now
        context.insert(row)
        row.routine = routine
    }

    /// Removes the plan for `weekday`, making it unplanned. Does not save.
    public static func clear(_ weekday: Int, in context: ModelContext) throws {
        let days = try context.fetch(FetchDescriptor<WeekPlanDay>(predicate: #Predicate { $0.weekday == weekday }))
        for day in days {
            context.delete(day)
        }
    }

    /// One row per valid weekday, picking the newest when there are duplicates.
    public static func effectiveRows(_ planDays: [WeekPlanDay]) -> [Int: WeekPlanDay] {
        var rows: [Int: WeekPlanDay] = [:]
        for day in planDays where (1...7).contains(day.weekday) {
            if let existing = rows[day.weekday], !isNewer(day, than: existing) { continue }
            rows[day.weekday] = day
        }
        return rows
    }

    /// The newest of `rows` (by `updatedAt`, then the higher `id`).
    public static func effectiveRow(in rows: [WeekPlanDay]) -> WeekPlanDay? {
        rows.reduce(nil) { best, day in
            guard let best else { return day }
            return isNewer(day, than: best) ? day : best
        }
    }

    private static func isNewer(_ lhs: WeekPlanDay, than rhs: WeekPlanDay) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
