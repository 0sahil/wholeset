// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("History list")
struct HistoryListTests {
    private let bench = UUID()
    private let squat = UUID()

    private func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, in zone: String) throws -> Date {
        try #require(calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func session(at date: Date, name: String = "Push", _ entries: [HistoryEntry] = []) -> HistorySession {
        HistorySession(name: name, startedAt: date, endedAt: date.addingTimeInterval(3_600), entries: entries)
    }

    @Test func groupsByMonthNewestFirstAcrossAYearBoundary() throws {
        let sessions = [
            session(at: try date(2025, 12, 30, 18, in: "UTC")),
            session(at: try date(2026, 1, 2, 18, in: "UTC")),
            session(at: try date(2025, 11, 5, 18, in: "UTC")),
            session(at: try date(2026, 1, 20, 18, in: "UTC")),
        ]
        let rows = HistoryList.rows(from: sessions, records: .empty)
        #expect(rows.map(\.id) == [sessions[3].id, sessions[1].id, sessions[0].id, sessions[2].id])
        let months = HistoryList.months(rows, calendar: try calendar("UTC"))
        #expect(months.map(\.id) == [2026_01, 2025_12, 2025_11])
        #expect(months.map(\.rows.count) == [2, 1, 1])
        #expect(months.first?.start == (try date(2026, 1, 1, 0, in: "UTC")))
    }

    @Test func monthFollowsTheCalendarsTimeZone() throws {
        // 00:30 on 1 January in UTC is still 31 December in New York.
        let newYear = session(at: try date(2026, 1, 1, 0, in: "UTC").addingTimeInterval(1_800))
        let rows = HistoryList.rows(from: [newYear], records: .empty)
        #expect(HistoryList.months(rows, calendar: try calendar("UTC")).map(\.id) == [2026_01])
        #expect(HistoryList.months(rows, calendar: try calendar("America/New_York")).map(\.id) == [2025_12])
        #expect(HistoryList.months(rows, calendar: try calendar("Asia/Tokyo")).map(\.id) == [2026_01])
    }

    @Test func rowsCarryTheirValues() throws {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        let second = H.session(day: 2, name: "Pull", source: .importHevy, [
            H.entry(bench, [H.set(40, 10, warmup: true)] + H.sets([(65, 10), (65, 8)])),
        ])
        let records = PersonalRecords.compute(from: [first, second])
        let rows = HistoryList.rows(from: [first, second], records: records)
        let row = try #require(rows.first)
        #expect(row.id == second.id)
        #expect(row.name == "Pull")
        #expect(row.duration == 3_600)
        #expect(row.workingSets == 2)
        #expect(row.volumeKg == 65 * 18)
        #expect(row.prCount == 3)
        #expect(row.isImported)
        #expect(rows.last?.prCount == 0)
        #expect(rows.last?.isImported == false)
    }

    @Test func searchMatchesSessionRoutineOrExerciseNames() {
        let push = HistorySession(name: "Push Day", startedAt: H.t0, endedAt: H.t0, entries: [
            H.entry(bench, name: "Bench Press", H.sets([(60, 10)])),
        ])
        let legs = HistorySession(name: "", routineName: "Légs", startedAt: H.t0.addingTimeInterval(10), endedAt: H.t0, entries: [
            H.entry(squat, name: "Back Squat", H.sets([(100, 5)])),
        ])
        let rows = HistoryList.rows(from: [push, legs], records: .empty)
        #expect(HistoryList.filter(rows, matching: "squat").map(\.id) == [legs.id])
        #expect(HistoryList.filter(rows, matching: "  BENCH ").map(\.id) == [push.id])
        #expect(HistoryList.filter(rows, matching: "legs").map(\.id) == [legs.id])
        #expect(HistoryList.filter(rows, matching: "push d").map(\.id) == [push.id])
        #expect(HistoryList.filter(rows, matching: "").count == 2)
        #expect(HistoryList.filter(rows, matching: "deadlift").isEmpty)
        #expect(HistoryList.sections(rows, matching: "press", calendar: utcCalendar).flatMap(\.rows).map(\.id) == [push.id])
    }

    @Test func searchIgnoresDiacriticsInExerciseNames() {
        let session = HistorySession(name: "A", startedAt: H.t0, endedAt: H.t0, entries: [
            H.entry(bench, name: "Développé couché", []),
        ])
        let rows = HistoryList.rows(from: [session], records: .empty)
        #expect(HistoryList.filter(rows, matching: "developpe").count == 1)
        #expect(HistoryList.filter(rows, matching: "COUCHÉ").count == 1)
    }

    @Test func inProgressSessionsNeverAppear() throws {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "Bench Press")
        context.insert(bench)
        insertSession(startedAt: H.t0, entries: [(bench, [(60, 10, false)])], in: context)
        insertSession(startedAt: H.t0.addingTimeInterval(H.day), ended: false, name: "Running", entries: [(bench, [(70, 10, false)])], in: context)
        try context.save()
        let index = HistoryIndex(sessions: try HistorySnapshot.load(in: context))
        #expect(index.rows.count == 1)
        #expect(index.rows.first?.name == "Past")
        #expect(index.records.records(forExercise: bench.id)?.heaviest?.weightKg == 60)
    }
}
