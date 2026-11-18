// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Weekly plan")
struct WeekPlanTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = utcCalendar
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// A date on `weekday` (1 = Sunday) in UTC.
    private func date(onWeekday weekday: Int) -> Date {
        // 2027-01-03 is a Sunday.
        let sunday = Date(timeIntervalSince1970: 1_798_934_400)
        return sunday.addingTimeInterval(Double(weekday - 1) * 86_400 + 12 * 3_600)
    }

    @Test func listsDaysInTheLocaleOrder() {
        #expect(WeekPlan.orderedWeekdays(calendar: calendar(firstWeekday: 2)) == [2, 3, 4, 5, 6, 7, 1])
        #expect(WeekPlan.orderedWeekdays(calendar: calendar(firstWeekday: 1)) == [1, 2, 3, 4, 5, 6, 7])
        #expect(WeekPlan.orderedWeekdays(calendar: calendar(firstWeekday: 7)) == [7, 1, 2, 3, 4, 5, 6])
        #expect(WeekPlan.orderedWeekdays(calendar: Calendar(identifier: .gregorian)).count == 7)
        #expect(utcCalendar.component(.weekday, from: date(onWeekday: 1)) == 1)
    }

    @Test func setsAndReadsEachWeekday() throws {
        let context = try makeInMemoryContext()
        let push = Routine(name: "Push")
        let legs = Routine(name: "Legs")
        context.insertAll(push, legs)
        try WeekPlan.set(push, on: 2, in: context, now: t0)
        try WeekPlan.set(legs, on: 5, in: context, now: t0)
        try WeekPlan.set(nil, on: 4, in: context, now: t0)
        try context.save()

        let days = WeekPlan.days(planDays: try context.all(WeekPlanDay.self), calendar: calendar(firstWeekday: 2))
        #expect(days.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
        #expect(days[0].routine === push)
        #expect(days[1].routine == nil && !days[1].isPlanned && !days[1].isRest)
        #expect(days[2].isRest)
        #expect(days[3].routine === legs)

        let sundayFirst = WeekPlan.days(planDays: try context.all(WeekPlanDay.self), calendar: calendar(firstWeekday: 1))
        #expect(sundayFirst.map(\.weekday) == [1, 2, 3, 4, 5, 6, 7])
        #expect(sundayFirst[1].routine === push)
    }

    @Test func changingADayUpdatesItsRowInsteadOfAddingOne() throws {
        let context = try makeInMemoryContext()
        let push = Routine(name: "Push")
        let pull = Routine(name: "Pull")
        context.insertAll(push, pull)
        try WeekPlan.set(push, on: 3, in: context, now: t0)
        try WeekPlan.set(pull, on: 3, in: context, now: t0.addingTimeInterval(60))
        let rows = try context.all(WeekPlanDay.self)
        #expect(rows.count == 1)
        #expect(rows.first?.routine === pull)
        #expect(rows.first?.updatedAt == t0.addingTimeInterval(60))

        try WeekPlan.set(pull, on: 3, in: context, now: t0.addingTimeInterval(120))
        #expect(rows.first?.updatedAt == t0.addingTimeInterval(60))
        try WeekPlan.set(nil, on: 3, in: context, now: t0.addingTimeInterval(180))
        #expect(rows.first?.routine == nil)

        try WeekPlan.clear(3, in: context)
        #expect(try context.count(WeekPlanDay.self) == 0)
        try WeekPlan.set(push, on: 9, in: context, now: t0)
        #expect(try context.count(WeekPlanDay.self) == 0)
    }

    @Test func todayAndNextPlannedDayWithMondayFirst() throws {
        try checkTodayAndNext(calendar: calendar(firstWeekday: 2))
    }

    @Test func todayAndNextPlannedDayWithSundayFirst() throws {
        try checkTodayAndNext(calendar: calendar(firstWeekday: 1))
    }

    /// The order a week is listed in never changes what today is or what comes next.
    private func checkTodayAndNext(calendar: Calendar) throws {
        let context = try makeInMemoryContext()
        let push = Routine(name: "Push", sortIndex: 0)
        let legs = Routine(name: "Legs", sortIndex: 1)
        context.insertAll(push, legs)
        try WeekPlan.set(push, on: 2, in: context, now: t0)
        try WeekPlan.set(nil, on: 3, in: context, now: t0)
        try WeekPlan.set(legs, on: 6, in: context, now: t0)
        let days = try context.all(WeekPlanDay.self)
        let routines = [push, legs]

        #expect(WeekPlan.today(planDays: days, routines: routines, on: date(onWeekday: 2), calendar: calendar) == .planned(push))
        guard case .restDay(let next) = WeekPlan.today(planDays: days, routines: routines, on: date(onWeekday: 3), calendar: calendar) else {
            Issue.record("Tuesday should be a rest day")
            return
        }
        #expect(next?.routine === legs)
        #expect(next?.daysAhead == 3)
        #expect(WeekPlan.today(planDays: days, routines: routines, on: date(onWeekday: 1), calendar: calendar) == .unplanned(suggested: push))

        // From Saturday the next planned day wraps round to Monday.
        let fromSaturday = WeekPlan.nextPlannedDay(after: date(onWeekday: 7), planDays: days, calendar: calendar)
        #expect(fromSaturday?.routine === push)
        #expect(fromSaturday?.weekday == 2)
        #expect(fromSaturday?.daysAhead == 2)
    }

    @Test func newestRowWinsForAWeekday() throws {
        let context = try makeInMemoryContext()
        let push = Routine(name: "Push")
        context.insert(push)
        let rest = WeekPlanDay(weekday: 2)
        rest.updatedAt = t0.addingTimeInterval(60)
        let planned = WeekPlanDay(weekday: 2)
        planned.updatedAt = t0
        context.insertAll(rest, planned)
        planned.routine = push
        #expect(WeekPlan.effectiveRow(in: [planned, rest]) === rest)
        #expect(WeekPlan.routine(on: 2, planDays: [planned, rest]) == nil)
    }
}
