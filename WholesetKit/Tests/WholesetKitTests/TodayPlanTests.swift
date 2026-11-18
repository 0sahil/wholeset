// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Today's plan")
struct TodayPlanTests {
    /// Wednesday 18 November 2026, 09:00 UTC (weekday 4).
    private let wednesday = Date(timeIntervalSince1970: 1_794_992_400)

    private func planDay(_ weekday: Int, _ routine: Routine?, in context: ModelContext, updated: TimeInterval = 0) -> WeekPlanDay {
        let day = WeekPlanDay(weekday: weekday)
        context.insert(day)
        day.routine = routine
        day.updatedAt = Date(timeIntervalSince1970: updated)
        return day
    }

    private func resolve(_ context: ModelContext, at date: Date? = nil) throws -> TodayPlan {
        TodayPlanResolver.resolve(
            planDays: try context.all(WeekPlanDay.self),
            routines: try context.all(Routine.self),
            on: date ?? wednesday,
            calendar: utcCalendar
        )
    }

    @Test func fixtureDateIsAWednesday() {
        #expect(utcCalendar.component(.weekday, from: wednesday) == 4)
    }

    @Test func plannedRoutineForToday() throws {
        let context = try makeInMemoryContext()
        let push = insertRoutine("Push", sortIndex: 1, items: [], in: context)
        let pull = insertRoutine("Pull", sortIndex: 0, items: [], in: context)
        _ = planDay(4, push, in: context)
        _ = planDay(5, pull, in: context)
        let plan = try resolve(context)
        #expect(plan == .planned(push))
        #expect(plan.startableRoutine === push)
    }

    @Test func restDayNamesTheNextPlannedDay() throws {
        let context = try makeInMemoryContext()
        let legs = insertRoutine("Legs", items: [], in: context)
        let push = insertRoutine("Push", items: [], in: context)
        _ = planDay(4, nil, in: context)
        _ = planDay(6, legs, in: context)
        _ = planDay(2, push, in: context)
        let plan = try resolve(context)
        #expect(plan == .restDay(next: UpcomingDay(routine: legs, daysAhead: 2, weekday: 6)))
        #expect(plan.startableRoutine == nil)
    }

    @Test func nextPlannedDayWrapsIntoNextWeek() throws {
        let context = try makeInMemoryContext()
        let push = insertRoutine("Push", items: [], in: context)
        _ = planDay(4, nil, in: context)
        _ = planDay(5, nil, in: context)
        _ = planDay(2, push, in: context) // Monday
        let plan = try resolve(context)
        #expect(plan == .restDay(next: UpcomingDay(routine: push, daysAhead: 5, weekday: 2)))
    }

    @Test func restDayWithNothingElsePlanned() throws {
        let context = try makeInMemoryContext()
        _ = insertRoutine("Push", items: [], in: context)
        _ = planDay(4, nil, in: context)
        #expect(try resolve(context) == .restDay(next: nil))
    }

    @Test func noPlanSuggestsFirstRoutineBySortIndex() throws {
        let context = try makeInMemoryContext()
        _ = insertRoutine("Legs", sortIndex: 2, items: [], in: context)
        let pull = insertRoutine("Pull", sortIndex: 0, items: [], in: context)
        _ = insertRoutine("Push", sortIndex: 1, items: [], in: context)
        #expect(try resolve(context) == .unplanned(suggested: pull))
    }

    @Test func planForOtherDaysOnlyStillSuggestsFirstRoutine() throws {
        let context = try makeInMemoryContext()
        let push = insertRoutine("Push", sortIndex: 0, items: [], in: context)
        let legs = insertRoutine("Legs", sortIndex: 1, items: [], in: context)
        _ = planDay(5, legs, in: context)
        #expect(try resolve(context) == .unplanned(suggested: push))
    }

    @Test func noRoutinesAtAll() throws {
        let context = try makeInMemoryContext()
        #expect(try resolve(context) == .noRoutines)
    }

    @Test func duplicateRowsUseTheMostRecentlyUpdated() throws {
        let context = try makeInMemoryContext()
        let push = insertRoutine("Push", items: [], in: context)
        _ = planDay(4, push, in: context, updated: 100)
        _ = planDay(4, nil, in: context, updated: 200)
        #expect(try resolve(context) == .restDay(next: nil))
    }

    @Test func invalidWeekdaysAreIgnored() throws {
        let context = try makeInMemoryContext()
        let push = insertRoutine("Push", items: [], in: context)
        _ = planDay(0, nil, in: context)
        _ = planDay(11, nil, in: context)
        #expect(try resolve(context) == .unplanned(suggested: push))
    }

    @Test func firstWeekdaySettingDoesNotShiftDays() throws {
        let context = try makeInMemoryContext()
        let push = insertRoutine("Push", items: [], in: context)
        _ = planDay(4, push, in: context)
        var mondayFirst = utcCalendar
        mondayFirst.firstWeekday = 2
        let plan = TodayPlanResolver.resolve(
            planDays: try context.all(WeekPlanDay.self),
            routines: try context.all(Routine.self),
            on: wednesday,
            calendar: mondayFirst
        )
        #expect(plan == .planned(push))
    }

    @Test func timeZoneDecidesTheDay() throws {
        let context = try makeInMemoryContext()
        let push = insertRoutine("Push", items: [], in: context)
        _ = planDay(3, push, in: context) // Tuesday
        var losAngeles = utcCalendar
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        // 09:00 UTC Wednesday is 01:00 Wednesday in LA; 05:00 UTC is still Tuesday there.
        let earlyUTC = wednesday.addingTimeInterval(-4 * 3600)
        let plan = TodayPlanResolver.resolve(
            planDays: try context.all(WeekPlanDay.self),
            routines: try context.all(Routine.self),
            on: earlyUTC,
            calendar: losAngeles
        )
        #expect(plan == .planned(push))
    }

    @Test func sortedRoutinesBreakTiesByName() throws {
        let context = try makeInMemoryContext()
        let b = insertRoutine("B", sortIndex: 0, items: [], in: context)
        let a = insertRoutine("A", sortIndex: 0, items: [], in: context)
        let c = insertRoutine("C", sortIndex: -1, items: [], in: context)
        #expect(TodayPlanResolver.sortedRoutines([b, a, c]).map(\.name) == ["C", "A", "B"])
    }

    @Test func plannedWeekdaysForARoutine() throws {
        let context = try makeInMemoryContext()
        let push = insertRoutine("Push", items: [], in: context)
        let legs = insertRoutine("Legs", items: [], in: context)
        _ = planDay(6, push, in: context)
        _ = planDay(2, push, in: context)
        _ = planDay(4, legs, in: context)
        let days = try context.all(WeekPlanDay.self)
        #expect(TodayPlanResolver.plannedWeekdays(for: push, in: days) == [2, 6])
        #expect(TodayPlanResolver.plannedWeekdays(for: legs, in: days) == [4])
    }
}
