// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Exercise progress charts and log")
struct ExerciseTimelineTests {
    private let bench = UUID()
    private let dips = UUID()

    @Test func onePointPerSessionWithAWorkingSet() throws {
        let sessions = [
            H.session(day: 0, [H.entry(bench, [H.set(40, 10, warmup: true), H.set(60, 10), H.set(62.5, 8)])]),
            H.session(day: 2, [H.entry(bench, [H.set(40, 10, warmup: true)])]),
            H.session(day: 4, [H.entry(dips, name: "Dips", H.sets([(nil, 12)]))]),
            H.session(day: 6, [H.entry(bench, H.sets([(65, 13), (70, 3)]))]),
        ]
        let timeline = try #require(ExerciseTimeline.build(from: sessions.reversed())[bench])
        #expect(timeline.points.map(\.sessionID) == [sessions[0].id, sessions[3].id])
        let first = timeline.points[0]
        #expect(abs((first.estimatedOneRepMaxKg ?? 0) - 80) < 1e-9)
        #expect(first.topSetWeightKg == 62.5)
        #expect(first.volumeKg == 1_100)
        // 65 × 13 has no estimate; 70 × 3 gives 77.
        #expect(abs((timeline.points[1].estimatedOneRepMaxKg ?? 0) - 77) < 1e-9)
        #expect(timeline.points[1].topSetWeightKg == 70)
        // The warm-up-only session is in the log but not on the chart.
        #expect(timeline.sessionCount == 3)
        #expect(timeline.log.map(\.sessionID) == [sessions[3].id, sessions[1].id, sessions[0].id])
    }

    @Test func unweightedSessionsHaveNoWeightValues() throws {
        let sessions = [H.session(day: 0, [H.entry(dips, name: "Dips", H.sets([(nil, 12), (nil, 10)]))])]
        let timeline = try #require(ExerciseTimeline.build(from: sessions)[dips])
        let point = try #require(timeline.points.first)
        #expect(point.value(for: .estimatedOneRepMax) == nil)
        #expect(point.value(for: .topSet) == nil)
        #expect(point.value(for: .volume) == nil)
        #expect(timeline.latest(.topSet) == nil)
        #expect(timeline.lastTopSet?.weightKg == nil)
        #expect(timeline.lastTopSet?.reps == 12)
    }

    @Test func latestValueSkipsPointsWithoutOne() throws {
        let sessions = [
            H.session(day: 0, [H.entry(bench, H.sets([(60, 5)]))]),
            H.session(day: 2, [H.entry(bench, H.sets([(40, 15)]))]),
        ]
        let timeline = try #require(ExerciseTimeline.build(from: sessions)[bench])
        #expect(timeline.latest(.estimatedOneRepMax)?.point.sessionID == sessions[0].id)
        #expect(timeline.latest(.topSet)?.valueKg == 40)
    }

    @Test func lastTopSetIsTheHeaviestThenMostReps() {
        let sessions = [
            H.session(day: 0, [H.entry(bench, H.sets([(100, 1)]))]),
            H.session(day: 5, [H.entry(bench, [H.set(80, 12, warmup: true)] + H.sets([(62.5, 8), (62.5, 10), (60, 12), (62.5, 10)]))]),
        ]
        let top = ExerciseTimeline.build(from: sessions)[bench]?.lastTopSet
        #expect(top?.weightKg == 62.5)
        #expect(top?.reps == 10)
        #expect(top?.sessionID == sessions[1].id)
    }

    @Test func entriesOfOneExerciseAreJoinedInTheLog() throws {
        let session = H.session(day: 0, [
            H.entry(bench, H.sets([(60, 10)])),
            H.entry(dips, name: "Dips", H.sets([(nil, 10)])),
            H.entry(bench, H.sets([(50, 12)])),
        ])
        let timeline = try #require(ExerciseTimeline.build(from: [session])[bench])
        #expect(timeline.log.first?.sets.map(\.weightKg) == [60, 50])
        #expect(timeline.points.count == 1)
        #expect(timeline.points.first?.volumeKg == 1_200)
    }

    @Test func rangesAreCalendarBased() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(calendar.date(from: DateComponents(year: 2024, month: 5, day: 31, hour: 12)))
        // Three months before 31 May is 29 Feb in a leap year (no fixed 90 days).
        let threeMonths = ProgressRange.threeMonths.startDate(now: now, calendar: calendar)
        #expect(threeMonths == calendar.date(from: DateComponents(year: 2024, month: 2, day: 29, hour: 12)))
        let oneYear = ProgressRange.oneYear.startDate(now: now, calendar: calendar)
        #expect(oneYear == calendar.date(from: DateComponents(year: 2023, month: 5, day: 31, hour: 12)))
        #expect(ProgressRange.all.startDate(now: now, calendar: calendar) == nil)
    }

    @Test func pointsInRangeIncludeTheStartDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = H.t0.addingTimeInterval(400 * H.day)
        let start = try #require(calendar.date(byAdding: .month, value: -3, to: now))
        let startDay = start.timeIntervalSince(H.t0) / H.day
        let sessions = [0, 100, startDay - 0.001, startDay, 390].map { day in
            H.session(day: day, [H.entry(bench, H.sets([(60, 10)]))])
        }
        let timeline = try #require(ExerciseTimeline.build(from: sessions)[bench])
        #expect(timeline.points(in: .all, now: now, calendar: calendar).count == 5)
        #expect(timeline.points(in: .threeMonths, now: now, calendar: calendar).map(\.sessionID) == [sessions[3].id, sessions[4].id])
        #expect(timeline.points(in: .oneYear, now: now, calendar: calendar).count == 4)
        let future = now.addingTimeInterval(1_000 * H.day)
        #expect(timeline.points(in: .threeMonths, now: future, calendar: calendar).isEmpty)
    }

    @Test func groupsConsecutiveWorkingSetsByWeight() {
        let sets = [
            H.set(40, 10, warmup: true),
            H.set(62.5, 10), H.set(62.5, 9), H.set(62.500_001, 8),
            H.set(65, 5),
            H.set(62.5, 6),
            H.set(nil, 12), H.set(0, 10), H.set(nil, nil),
        ]
        #expect(SetGroup.groups(sets) == [
            SetGroup(weightKg: 62.5, reps: [10, 9, 8]),
            SetGroup(weightKg: 65, reps: [5]),
            SetGroup(weightKg: 62.5, reps: [6]),
            SetGroup(weightKg: nil, reps: [12, 10, nil]),
        ])
        #expect(SetGroup.groups([H.set(40, 10, warmup: true)]).isEmpty)
    }

    @Test func neverDoneExerciseHasNoTimeline() {
        let session = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        #expect(ExerciseTimeline.build(from: [session])[dips] == nil)
        #expect(ExerciseTimeline.build(from: []).isEmpty)
    }
}
