// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Exercise history")
struct ExerciseHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func newestFinishedSessionWithALoggedSetWins() throws {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "Bench Press")
        context.insert(bench)
        insertSession(startedAt: t0, entries: [(bench, [(50, 10, false)])], in: context)
        let newest = insertSession(startedAt: t0.addingTimeInterval(86_400), entries: [(bench, [(55, 10, false)])], in: context)
        // Newer but unfinished, and newer but with nothing logged: neither counts.
        insertSession(startedAt: t0.addingTimeInterval(2 * 86_400), ended: false, entries: [(bench, [(60, 10, false)])], in: context)
        let empty = insertSession(startedAt: t0.addingTimeInterval(3 * 86_400), entries: [(bench, [])], in: context)
        let plannedOnly = SetLog(order: 0, weightKg: 70, reps: 5)
        context.insert(plannedOnly)
        plannedOnly.entry = empty.sortedEntries.first
        try context.save()

        let last = try #require(ExerciseHistory.lastPerformance(of: bench))
        #expect(last.sessionID == newest.id)
        #expect(last.date == newest.startedAt)
        #expect(last.sets == [PerformedSet(weightKg: 55, reps: 10)])
        #expect(ExerciseHistory.lastPerformance(of: bench, excluding: newest.id)?.sets.first?.weightKg == 50)
    }

    @Test func alternativesNeverCount() throws {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "Bench Press")
        let dumbbell = Exercise(name: "Dumbbell Bench Press", equipment: .dumbbell)
        context.insertAll(bench, dumbbell)
        bench.alternatives = [dumbbell]
        insertSession(startedAt: t0, entries: [(dumbbell, [(26, 10, false)])], in: context)
        try context.save()
        #expect(ExerciseHistory.lastPerformance(of: bench) == nil)
    }

    @Test func anExerciseDoneTwiceInASessionJoinsItsSets() throws {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "Bench Press")
        let fly = Exercise(name: "Cable Fly", equipment: .cable)
        context.insertAll(bench, fly)
        insertSession(startedAt: t0, entries: [
            (bench, [(20, 10, true), (60, 10, false)]),
            (fly, [(15, 12, false)]),
            (bench, [(60, 8, false)]),
        ], in: context)
        try context.save()
        let last = try #require(ExerciseHistory.lastPerformance(of: bench))
        #expect(last.sets.map(\.reps) == [10, 10, 8])
        #expect(last.workingSets.count == 2)
        #expect(last.warmupSets.count == 1)
    }

    @Test func unloggedSetsOfASkippedEntryAreIgnored() throws {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "Bench Press")
        context.insert(bench)
        let session = insertSession(startedAt: t0, entries: [(bench, [(60, 10, false)])], in: context)
        let entry = try #require(session.sortedEntries.first)
        entry.isSkipped = true
        let planned = SetLog(order: 1, weightKg: 80, reps: 3)
        context.insert(planned)
        planned.entry = entry
        try context.save()
        #expect(ExerciseHistory.lastPerformance(of: bench)?.sets == [PerformedSet(weightKg: 60, reps: 10)])
    }
}

@Suite("Workout engine memory")
struct WorkoutMemoryTests {
    private struct Fixture {
        let context: ModelContext
        let routine: Routine
        let clock: TestClock
        let bench: Exercise
        let raise: Exercise
        let dips: Exercise
    }

    /// Push: Bench Press 3 × 8–12, Lateral Raise 2 × 12–15, Dips 2 × 6–10 (bodyweight), plus a
    /// finished workout the day before (for whatever `history` holds).
    private func makeFixture(history: [String: [LoggedSpec]] = [:]) throws -> Fixture {
        let context = try makeInMemoryContext()
        let routine = insertRoutine("Push", items: [
            ("Bench Press", .barbell, 3, 8, 12, 120),
            ("Lateral Raise", .dumbbell, 2, 12, 15, nil),
            ("Dips", .bodyweight, 2, 6, 10, nil),
        ], in: context)
        let bench = try exercise(named: "Bench Press", in: context)
        let raise = try exercise(named: "Lateral Raise", in: context)
        let dips = try exercise(named: "Dips", in: context)
        let clock = TestClock()
        let byName = ["Bench Press": bench, "Lateral Raise": raise, "Dips": dips]
        let entries = history.sorted { $0.key < $1.key }.compactMap { name, sets in byName[name].map { ($0, sets) } }
        if !entries.isEmpty {
            insertSession(startedAt: clock.date.addingTimeInterval(-86_400), entries: entries, in: context)
        }
        try context.save()
        return Fixture(context: context, routine: routine, clock: clock, bench: bench, raise: raise, dips: dips)
    }

    private func start(_ f: Fixture, settings: ProgressionSettings = ProgressionSettings()) throws -> WorkoutEngine {
        try WorkoutEngine.start(routine: f.routine, in: f.context, defaultRestSeconds: 90, progressionSettings: settings, now: f.clock.now)
    }

    // MARK: Pre-fill and last line

    @Test func setsPrefillFromLastSessionSetBySet() throws {
        let f = try makeFixture(history: ["Bench Press": [(60, 10, false), (60, 9, false), (57.5, 8, false)]])
        let engine = try start(f)
        #expect(engine.currentValues == SetValues(weightKg: 60, reps: 10))
        #expect(engine.currentLastLine == .previous(SetValues(weightKg: 60, reps: 10)))
        try engine.logCurrentSet()
        #expect(engine.currentValues == SetValues(weightKg: 60, reps: 9))
        try engine.logCurrentSet()
        #expect(engine.currentValues == SetValues(weightKg: 57.5, reps: 8))
        #expect(engine.currentLastLine == .previous(SetValues(weightKg: 57.5, reps: 8)))
    }

    @Test func firstTimeHasNoLastLineValues() throws {
        let f = try makeFixture()
        let engine = try start(f)
        #expect(engine.currentLastLine == .firstTime)
        #expect(engine.currentValues == SetValues(weightKg: nil, reps: 8))
    }

    @Test func warmupWithoutHistoricWarmupShowsNoLastValue() throws {
        let f = try makeFixture(history: ["Bench Press": [(60, 10, false)]])
        let engine = try start(f)
        try engine.toggleWarmupOnCurrentSet()
        #expect(engine.currentLastLine == LastLine.none)
        #expect(engine.currentValues == SetValues(weightKg: nil, reps: 8))
    }

    @Test func aChangeCarriesOverHistoryForTheRestOfTheExercise() throws {
        let f = try makeFixture(history: ["Bench Press": [(60, 10, false), (60, 10, false), (60, 10, false)]])
        let engine = try start(f)
        engine.setCurrentWeight(65)
        engine.setCurrentReps(8)
        try engine.logCurrentSet()
        #expect(engine.currentValues == SetValues(weightKg: 65, reps: 8))
        try engine.logCurrentSet()
        #expect(engine.currentValues == SetValues(weightKg: 65, reps: 8))
        // The "last" line still says what last time was.
        #expect(engine.currentLastLine == .previous(SetValues(weightKg: 60, reps: 10)))
    }

    @Test func historyIsReadOnceAndThisWorkoutNeverCounts() throws {
        let f = try makeFixture(history: ["Bench Press": [(60, 10, false)]])
        let engine = try start(f)
        try engine.logCurrentSet()
        // A finished session arriving mid-workout (say from sync) does not move the numbers.
        insertSession(startedAt: f.clock.date.addingTimeInterval(-60), entries: [(f.bench, [(100, 1, false)])], in: f.context)
        try f.context.save()
        #expect(engine.lastPerformance(of: f.bench)?.sets == [PerformedSet(weightKg: 60, reps: 10)])
        try engine.finish()
        #expect(ExerciseHistory.lastPerformance(of: f.bench)?.sessionID == engine.session.id)
    }

    // MARK: Progression hint

    @Test func hintFiresAppliesToEveryRemainingWorkingSetAndDisappears() throws {
        let f = try makeFixture(history: ["Bench Press": [(20, 10, true), (60, 12, false), (60, 12, false), (60, 12, false)]])
        let engine = try start(f)
        let hint = try #require(engine.currentProgressionHint)
        #expect(hint == ProgressionHint(weightKg: 62.5, reps: 8))
        #expect(!f.context.hasChanges)

        try engine.applyProgressionHint()
        #expect(!f.context.hasChanges)
        #expect(engine.currentProgressionHint == nil)
        #expect(engine.currentValues == SetValues(weightKg: 62.5, reps: 8))
        let sets = engine.entries[0].sortedSets
        #expect(sets.map(\.weightKg) == [62.5, 62.5, 62.5])
        #expect(sets.map(\.reps) == [8, 8, 8])
        try engine.logCurrentSet()
        try engine.logCurrentSet()
        #expect(engine.currentValues == SetValues(weightKg: 62.5, reps: 8))
        #expect(try engine.applyProgressionHint() == false)
    }

    @Test func hintSkipsWarmupsAndLeavesThemAlone() throws {
        let f = try makeFixture(history: ["Bench Press": [(60, 12, false), (60, 12, false)]])
        let engine = try start(f)
        try engine.toggleWarmupOnCurrentSet()
        #expect(engine.currentProgressionHint == nil)
        try engine.logCurrentSet()
        #expect(engine.currentProgressionHint == ProgressionHint(weightKg: 62.5, reps: 8))
        try engine.applyProgressionHint()
        let sets = engine.entries[0].sortedSets
        #expect(sets.map(\.isWarmup) == [true, false, false])
        #expect(sets.dropFirst().map(\.weightKg) == [62.5, 62.5])
    }

    @Test func ignoringTheHintChangesNothing() throws {
        let f = try makeFixture(history: ["Bench Press": [(60, 12, false), (60, 12, false), (60, 12, false)]])
        let engine = try start(f)
        #expect(engine.currentProgressionHint != nil)
        #expect(engine.currentValues == SetValues(weightKg: 60, reps: 12))
        try engine.logCurrentSet()
        #expect(engine.entries[0].sortedSets[1].weightKg == nil)
    }

    @Test func hintUsesExerciseThenUserThenUnitDefaultStep() throws {
        let f = try makeFixture(history: ["Bench Press": [(60, 12, false)], "Lateral Raise": [(10, 15, false)]])
        let engine = try start(f, settings: ProgressionSettings(unit: .kg, stepsKg: [.dumbbell: 1]))
        #expect(engine.currentProgressionHint?.weightKg == 62.5)
        f.bench.progressionStepKg = 5
        #expect(engine.currentProgressionHint?.weightKg == 65)
        engine.select(entryAt: 1)
        #expect(engine.currentProgressionHint == ProgressionHint(weightKg: 11, reps: 12))
        engine.progressionSettings = ProgressionSettings(unit: .lb)
        #expect(engine.currentProgressionHint?.weightKg == 10 + 5 * WeightUnit.kilogramsPerPound)
    }

    @Test func bodyweightHintAddsARep() throws {
        let f = try makeFixture(history: ["Dips": [(nil, 10, false), (nil, 11, false)]])
        let engine = try start(f)
        engine.select(entryAt: 2)
        #expect(engine.currentProgressionHint == ProgressionHint(weightKg: nil, reps: 11))
        try engine.applyProgressionHint()
        #expect(engine.currentValues == SetValues(weightKg: nil, reps: 11))
        #expect(engine.currentProgressionHint == nil)
    }
}
