// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Records set in one session")
struct SessionRecordsTests {
    private let bench = UUID()
    private let raise = UUID()
    private let dips = UUID()

    private func records(_ session: HistorySession, after history: [HistorySession]) -> SessionRecords {
        SessionRecords(session: session, history: history)
    }

    @Test func firstSessionOfAnExerciseHasNoRecords() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10), (65, 8)]))])
        let result = records(first, after: [])
        #expect(result.isEmpty)
        #expect(result.count == 0)
        #expect(result.sessionID == first.id)

        // An exercise new today earns nothing even when another exercise has history.
        let second = H.session(day: 2, [
            H.entry(bench, H.sets([(60, 10)])),
            H.entry(raise, name: "Lateral Raise", H.sets([(12, 12)])),
        ])
        #expect(records(second, after: [first]).isEmpty)
    }

    @Test func weightRecordShowsTheSetsWeightAndReps() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10), (60, 10)]))])
        let second = H.session(day: 3, [H.entry(bench, H.sets([(62.5, 8), (65, 6)]))])
        let result = records(second, after: [first])
        // 65 × 6 is heavier; its estimate (78) is below 60 × 10 (80); volume 890 < 1,200.
        #expect(result.records == [
            SessionRecord(exerciseID: bench, exerciseName: "Bench Press", value: .weight(kilograms: 65, reps: 6)),
        ])
    }

    @Test func estimatedOneRepMaxRecordShowsTheEstimate() throws {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 5)]))])
        let second = H.session(day: 2, [H.entry(bench, H.sets([(60, 4), (55, 12)]))])
        let result = records(second, after: [first])
        // 55 × 12 = 77 beats 60 × 5 = 70; the weight is not heavier; volume 900 > 300.
        #expect(result.records.map(\.kind) == [.estimatedOneRepMax, .volume])
        let estimate = try #require(result.records.first)
        #expect(estimate.value == .estimatedOneRepMax(kilograms: 55 * (1 + 12.0 / 30)))
    }

    @Test func repRecordAtAWeightDoneBefore() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 8), (60, 8), (50, 12)]))])
        let second = H.session(day: 2, [H.entry(bench, H.sets([(60, 9), (55, 6)]))])
        let result = records(second, after: [first])
        // 60 × 9: more reps at 60 (rep record), and its estimate (78) beats 60 × 8 (76).
        let expected: [SessionRecord.Value] = [
            .estimatedOneRepMax(kilograms: 60 * (1 + 9.0 / 30)),
            .reps(9, kilograms: 60),
        ]
        #expect(result.records.map(\.value) == expected)
    }

    @Test func repRecordWithoutWeight() {
        let first = H.session(day: 0, [H.entry(dips, name: "Dips", H.sets([(nil, 10), (nil, 8)]))])
        let second = H.session(day: 2, [H.entry(dips, name: "Dips", H.sets([(nil, 12), (nil, 12)]))])
        let result = records(second, after: [first])
        #expect(result.records == [SessionRecord(exerciseID: dips, exerciseName: "Dips", value: .reps(12, kilograms: nil))])
    }

    @Test func volumeRecordShowsTheExercisesSessionVolume() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10), (60, 10)]))])
        // Same weight and reps per set, one more set: only the volume beats last time.
        let second = H.session(day: 2, [
            H.entry(bench, [H.set(20, 10, warmup: true)] + H.sets([(60, 10), (60, 10), (60, 10)])),
        ])
        let result = records(second, after: [first])
        #expect(result.records.map(\.value) == [.volume(kilograms: 1_800)])
    }

    @Test func severalKindsOnOneExerciseInWorkoutOrderThenKindOrder() {
        let first = H.session(day: 0, [
            H.entry(bench, H.sets([(60, 8), (50, 12)])),
            H.entry(raise, name: "Lateral Raise", H.sets([(10, 12)])),
        ])
        let second = H.session(day: 2, [
            H.entry(raise, name: "Lateral Raise", H.sets([(12, 12)])),
            H.entry(bench, H.sets([(65, 8), (60, 10), (50, 13)])),
        ])
        let result = records(second, after: [first])
        #expect(result.records.map(\.exerciseName) == ["Lateral Raise", "Lateral Raise", "Lateral Raise", "Bench Press", "Bench Press", "Bench Press", "Bench Press"])
        let expected: [SessionRecord.Value] = [
            .weight(kilograms: 12, reps: 12),
            .estimatedOneRepMax(kilograms: 12 * (1 + 12.0 / 30)),
            .volume(kilograms: 144),
            .weight(kilograms: 65, reps: 8),
            .estimatedOneRepMax(kilograms: 65 * (1 + 8.0 / 30)),
            .reps(10, kilograms: 60),
            .volume(kilograms: 65 * 8 + 600 + 650),
        ]
        #expect(result.records.map(\.value) == expected)
        #expect(result.count == 7)
        #expect(Set(result.records.map(\.id)).count == 7)
    }

    @Test func warmupsNeverCount() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        let second = H.session(day: 2, [H.entry(bench, [H.set(100, 5, warmup: true), H.set(50, 10)])])
        #expect(records(second, after: [first]).isEmpty)
    }

    @Test func unloggedSetsNeverCount() throws {
        let context = try makeInMemoryContext()
        let benchPress = Exercise(name: "Bench Press", equipment: .barbell)
        context.insert(benchPress)
        insertSession(startedAt: H.t0, entries: [(benchPress, [(60, 10, false)])], in: context)
        let today = insertSession(startedAt: H.t0.addingTimeInterval(2 * H.day), entries: [(benchPress, [(50, 10, false)])], in: context)
        // A planned set never logged, much heavier than anything before.
        let planned = SetLog(order: 1, weightKg: 200, reps: 5)
        context.insert(planned)
        planned.entry = today.sortedEntries.first
        try context.save()

        let result = try #require(try SessionRecords.load(sessionID: today.id, in: context))
        #expect(result.isEmpty)
    }

    @Test func importedEarlierSessionsCountAsHistory() {
        let imported = H.session(day: 0, source: .importHevy, [H.entry(bench, H.sets([(80, 5)]))])
        let today = H.session(day: 2, [H.entry(bench, H.sets([(85, 2)]))])
        let result = records(today, after: [imported])
        // 85 × 2 is heavier than 80 × 5; its estimate (90.7) and the volume (170) are not records.
        #expect(result.records.map(\.value) == [.weight(kilograms: 85, reps: 2)])
        // Without the import, today would be the first session: no records at all.
        #expect(records(today, after: []).isEmpty)
    }

    @Test func equalIsNotARecordAndTiesTakeTheEarliestSet() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        #expect(records(H.session(day: 2, [H.entry(bench, H.sets([(60, 10)]))]), after: [first]).isEmpty)

        let earliest = H.set(65, 6)
        let second = H.session(day: 2, [H.entry(bench, [H.set(65, 5), earliest, H.set(65, 6)])])
        let full = PersonalRecords.compute(from: [first, second])
        #expect(full.kinds(forSet: earliest.id) == [.weight])
        #expect(records(second, after: [first]).records.first?.value == .weight(kilograms: 65, reps: 6))
    }

    @Test func sessionsStartingTogetherResolveByID() {
        let a = H.session(day: 0, id: H.id(1), [H.entry(bench, H.sets([(60, 10)]))])
        let b = H.session(day: 0, id: H.id(2), [H.entry(bench, H.sets([(65, 10)]))])
        // b sorts after a, so a is its history; a has none.
        #expect(records(b, after: [a]).records.map(\.kind) == [.weight, .estimatedOneRepMax, .volume])
        #expect(records(a, after: [b]).isEmpty)
    }

    @Test func poundsAreADisplayConcernOnly() {
        let lb = WeightUnit.lb
        let first = H.session(day: 0, [H.entry(bench, H.sets([(lb.kilograms(fromValue: 135), 8)]))])
        // The same 135 lb read back a hair heavier: no record out of rounding noise.
        let noisy = H.session(day: 2, [H.entry(bench, H.sets([(61.234_995_001, 8)]))])
        #expect(records(noisy, after: [first]).isEmpty)
        // A real 5 lb jump: the value is the stored kilograms, untouched.
        let heavier = lb.kilograms(fromValue: 140)
        let second = H.session(day: 4, [H.entry(bench, H.sets([(heavier, 8)]))])
        #expect(records(second, after: [first]).records.first?.value == .weight(kilograms: heavier, reps: 8))
    }

    @Test func swappedBackExerciseIsOneGroup() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        let second = H.session(day: 2, [
            H.entry(bench, H.sets([(60, 10)])),
            H.entry(dips, name: "Dips", H.sets([(nil, 10)])),
            H.entry(bench, H.sets([(60, 10)])),
        ])
        let result = records(second, after: [first])
        #expect(result.records.map(\.value) == [.volume(kilograms: 1_200)])
    }

    @Test func relevantHistoryKeepsOnlyEarlierSessionsAndTheSessionsExercises() {
        let a = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)])), H.entry(dips, name: "Dips", H.sets([(nil, 10)]))])
        let unrelated = H.session(day: 1, [H.entry(dips, name: "Dips", H.sets([(nil, 12)]))])
        let today = H.session(day: 2, [H.entry(bench, H.sets([(62.5, 10)]))])
        let later = H.session(day: 3, [H.entry(bench, H.sets([(100, 10)]))])
        let relevant = SessionRecords.relevantHistory(for: today, in: [later, today, unrelated, a])
        #expect(relevant.map(\.id) == [a.id])
        #expect(relevant.first?.entries.map(\.exerciseID) == [bench])
    }

    /// The filtered history gives every session exactly what the full computation gives it.
    @Test func filteredHistoryMatchesFullPersonalRecords() {
        var generator = SeededGenerator(seed: 0x5EED)
        let exercises = (0..<8).map { _ in UUID() }
        var history: [HistorySession] = []
        for index in 0..<120 {
            let picked = exercises.shuffled(using: &generator).prefix(Int.random(in: 1...4, using: &generator))
            let entries = picked.map { exercise in
                let sets = (0..<Int.random(in: 1...4, using: &generator)).map { _ in
                    H.set(
                        Bool.random(using: &generator) && exercise == exercises[0] ? nil : Double(Int.random(in: 16...24, using: &generator)) * 2.5,
                        Int.random(in: 0...14, using: &generator),
                        warmup: Int.random(in: 0..<6, using: &generator) == 0
                    )
                }
                return H.entry(exercise, name: "E\(exercises.firstIndex(of: exercise) ?? 0)", sets)
            }
            // Several sessions share a start time, so ID ties are exercised too.
            history.append(H.session(day: Double(index / 3), source: index % 7 == 0 ? .importStrong : .watch, entries))
        }
        let full = PersonalRecords.compute(from: history)
        var withRecords = 0
        for session in history {
            let result = SessionRecords(session: session, history: history)
            #expect(result.count == full.count(forSession: session.id))
            #expect(result == SessionRecords(session: session, records: full))
            if !result.isEmpty { withRecords += 1 }
        }
        #expect(withRecords > 20)
    }
}

@Suite("Records set in one session, from the store")
struct SessionRecordsStoreTests {
    /// A store with `count` finished sessions rotating through Push, Pull and Legs days
    /// (six exercises each, a warm-up and three working sets, slowly getting heavier),
    /// plus one unfinished workout.
    private func makeHistory(sessions count: Int, in context: ModelContext) throws -> [Session] {
        let days = (0..<3).map { day in (0..<6).map { Exercise(name: "Day \(day) exercise \($0)", equipment: .barbell) } }
        days.joined().forEach(context.insert)
        var sessions: [Session] = []
        for index in 0..<count {
            let weight = 40 + Double(index / 3) * 0.5
            let entries = days[index % 3].map { exercise -> (Exercise, [LoggedSpec]) in
                (exercise, [(20, 10, true), (weight, 8, false), (weight, 8, false), (weight, 6 + index % 4, false)])
            }
            sessions.append(insertSession(startedAt: H.t0.addingTimeInterval(Double(index) * H.day), entries: entries, in: context))
        }
        insertSession(startedAt: H.t0.addingTimeInterval(Double(count) * H.day), ended: false, entries: [(days[0][0], [(300, 1, false)])], in: context)
        try context.save()
        return sessions
    }

    @Test func storeResultEqualsFullHistoryResult() throws {
        let context = try makeInMemoryContext()
        let sessions = try makeHistory(sessions: 60, in: context)
        let all = try HistorySnapshot.load(in: context)
        let full = PersonalRecords.compute(from: all)
        for stored in [sessions[0], sessions[3], sessions[31], sessions[58], sessions[59]] {
            let loaded = try #require(try SessionRecords.load(sessionID: stored.id, in: context))
            let session = try #require(all.first { $0.id == stored.id })
            #expect(loaded == SessionRecords(session: session, records: full))
            #expect(loaded.count == full.count(forSession: stored.id))
        }
        // Weights climb every third session of a day: later sessions do set records.
        #expect(try SessionRecords.load(sessionID: sessions[57].id, in: context)?.isEmpty == false)
    }

    @Test func storeReadsOnlyEarlierSessionsWithTheSameExercises() throws {
        let context = try makeInMemoryContext()
        let sessions = try makeHistory(sessions: 30, in: context)
        let today = try #require(HistorySnapshot.session(from: sessions[21]))
        let history = try SessionRecords.history(for: today, in: context)
        // Day 0 sessions are every third one; 7 come before session 21; the unfinished
        // workout and later sessions are left out.
        #expect(history.map(\.id) == stride(from: 0, to: 21, by: 3).map { sessions[$0].id })
        #expect(history.allSatisfy { $0.entries.count == 6 })
        #expect(history == SessionRecords.relevantHistory(for: today, in: try HistorySnapshot.load(in: context)))
    }

    @Test func storeKeepsOnlyTheSessionsExercisesOfMixedSessions() throws {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "Bench Press", equipment: .barbell)
        let row = Exercise(name: "Barbell Row", equipment: .barbell)
        context.insertAll(bench, row)
        let earlier = insertSession(startedAt: H.t0, entries: [(row, [(50, 10, false)]), (bench, [(60, 10, false)])], in: context)
        let today = insertSession(startedAt: H.t0.addingTimeInterval(H.day), entries: [(bench, [(65, 10, false)])], in: context)
        try context.save()
        let snapshot = try #require(HistorySnapshot.session(from: today))
        let history = try SessionRecords.history(for: snapshot, in: context)
        #expect(history.map(\.id) == [earlier.id])
        #expect(history.first?.entries.map(\.exerciseName) == ["Bench Press"])
        let result = try #require(try SessionRecords.load(sessionID: today.id, in: context))
        #expect(result.records.map(\.kind) == [.weight, .estimatedOneRepMax, .volume])
        #expect(result.records.allSatisfy { $0.exerciseName == "Bench Press" })
    }

    @Test func unfinishedOrMissingSessionLoadsNothing() throws {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "Bench Press", equipment: .barbell)
        context.insert(bench)
        let running = insertSession(startedAt: H.t0, ended: false, entries: [(bench, [(60, 10, false)])], in: context)
        try context.save()
        #expect(try SessionRecords.load(sessionID: running.id, in: context) == nil)
        #expect(try SessionRecords.load(sessionID: UUID(), in: context) == nil)
    }

    @Test func asyncLoadUsesItsOwnContext() async throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let bench = Exercise(name: "Bench Press", equipment: .barbell)
        context.insert(bench)
        insertSession(startedAt: H.t0, entries: [(bench, [(60, 10, false)])], in: context)
        let today = insertSession(startedAt: H.t0.addingTimeInterval(H.day), entries: [(bench, [(70, 3, false)])], in: context)
        try context.save()
        let result = try await SessionRecords.load(sessionID: today.id, from: container)
        #expect(result?.records.map(\.value) == [.weight(kilograms: 70, reps: 3)])
    }

    /// 300 sessions on disk, as a Watch might hold after a couple of years. Checks the
    /// result; the durations are printed for the report, never used to pass or fail.
    @Test func realisticHistoryOnDisk() throws {
        try withTemporaryStoreURL { url in
            let writer = ModelContext(try WholesetStore.makeContainer(url: url))
            let sessions = try makeHistory(sessions: 300, in: writer)
            let last = try #require(sessions.last)

            // As on the Watch at End: the container is open, the context is new.
            let container = try WholesetStore.makeContainer(url: url)
            _ = try ModelContext(container).fetchCount(FetchDescriptor<Session>())
            let clock = ContinuousClock()
            var filtered: SessionRecords?
            let filteredTime = try clock.measure {
                filtered = try SessionRecords.load(sessionID: last.id, in: ModelContext(container))
            }
            var full: PersonalRecords = .empty
            let fullTime = try clock.measure {
                full = PersonalRecords.compute(from: try HistorySnapshot.load(in: ModelContext(container)))
            }
            let result = try #require(filtered)
            #expect(result.count == full.count(forSession: last.id))
            let read = try SessionRecords.history(for: try #require(HistorySnapshot.session(from: last)), in: ModelContext(container))
            print("SessionRecords timing, 300 sessions: filtered load \(filteredTime) (\(read.count) earlier sessions read), full history \(fullTime)")
        }
    }
}

/// A deterministic random number generator (SplitMix64), so generated histories are the
/// same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
