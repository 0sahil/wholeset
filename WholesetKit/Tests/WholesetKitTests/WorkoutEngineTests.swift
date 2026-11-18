// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Workout engine")
struct WorkoutEngineTests {
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let routine: Routine
        let clock: TestClock
        let engine: WorkoutEngine
    }

    /// Push: Bench Press 3 × 8–12 (rest 120), Lateral Raise 2 × 12–15 (no rest), Dips 1 × 6–10 (bodyweight).
    private func makeFixture(defaultRest: Int? = 75) throws -> Fixture {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let routine = insertRoutine("Push", items: [
            ("Bench Press", .barbell, 3, 8, 12, 120),
            ("Lateral Raise", .dumbbell, 2, 12, 15, nil),
            ("Dips", .bodyweight, 1, 6, 10, nil),
        ], in: context)
        try context.save()
        let clock = TestClock()
        let engine = try WorkoutEngine.start(routine: routine, in: context, defaultRestSeconds: defaultRest, now: clock.now)
        return Fixture(container: container, context: context, routine: routine, clock: clock, engine: engine)
    }

    // MARK: Start

    @Test func startSnapshotsTheRoutine() throws {
        let f = try makeFixture()
        let session = f.engine.session
        #expect(session.name == "Push")
        #expect(session.routine === f.routine)
        #expect(session.source == .watch)
        #expect(session.startedAt == f.clock.date)
        #expect(session.endedAt == nil)
        #expect(f.engine.entries.map { $0.exercise?.name } == ["Bench Press", "Lateral Raise", "Dips"])
        #expect(f.engine.entries.map(\.order) == [0, 1, 2])
        #expect(f.engine.entries.map(\.repLow) == [8, 12, 6])
        #expect(f.engine.entries.map(\.repHigh) == [12, 15, 10])
        #expect(f.engine.entries.map { $0.sets?.count } == [3, 2, 1])
        let allSets = f.engine.entries.flatMap { $0.sortedSets }
        #expect(allSets.allSatisfy { $0.completedAt == nil && $0.weightKg == nil && $0.reps == nil && !$0.isWarmup })
        #expect(f.engine.currentIndex == 0)
        #expect(!f.context.hasChanges)
    }

    @Test func startIsVisibleToAnotherContext() throws {
        let f = try makeFixture()
        let other = ModelContext(f.container)
        let sessions = try other.all(Session.self)
        #expect(sessions.count == 1)
        #expect(try other.count(SetLog.self) == 6)
    }

    @Test func startSkipsItemsWithoutExerciseAndKeepsAtLeastOneSet() throws {
        let context = try makeInMemoryContext()
        let routine = insertRoutine("Odd", items: [("Curl", .dumbbell, 0, 8, 12, nil)], in: context)
        let orphan = RoutineItem(order: 5)
        context.insert(orphan)
        orphan.routine = routine
        try context.save()
        let engine = try WorkoutEngine.start(routine: routine, in: context, defaultRestSeconds: 90)
        #expect(engine.entries.count == 1)
        #expect(engine.entries.first?.sets?.count == 1)
    }

    // MARK: Values

    @Test func firstSetStartsAtRepFloorWithNoWeight() throws {
        let f = try makeFixture()
        #expect(f.engine.currentValues == SetValues(weightKg: nil, reps: 8))
        #expect(f.engine.currentSetNumber == 1)
    }

    @Test func loggingSavesImmediately() throws {
        let f = try makeFixture()
        f.engine.setCurrentWeight(60)
        f.clock.advance(by: 90)
        let logged = try f.engine.logCurrentSet()
        #expect(logged?.set.weightKg == 60)
        #expect(logged?.set.reps == 8)
        #expect(logged?.set.completedAt == f.clock.date)
        #expect(!f.context.hasChanges)

        let other = ModelContext(f.container)
        let completed = try other.all(SetLog.self).filter { $0.completedAt != nil }
        #expect(completed.count == 1)
        #expect(completed.first?.weightKg == 60)
        #expect(completed.first?.reps == 8)
    }

    @Test func nextSetCarriesForwardLoggedValues() throws {
        let f = try makeFixture()
        f.engine.setCurrentWeight(60)
        f.engine.setCurrentReps(10)
        try f.engine.logCurrentSet()
        #expect(f.engine.currentSetNumber == 2)
        #expect(f.engine.currentValues == SetValues(weightKg: 60, reps: 10))

        f.engine.setCurrentReps(9)
        try f.engine.logCurrentSet()
        #expect(f.engine.currentValues == SetValues(weightKg: 60, reps: 9))
    }

    @Test func untouchedFieldStillCarries() throws {
        let f = try makeFixture()
        f.engine.setCurrentWeight(60)
        f.engine.setCurrentReps(10)
        try f.engine.logCurrentSet()
        f.engine.setCurrentWeight(62.5)
        #expect(f.engine.currentValues == SetValues(weightKg: 62.5, reps: 10))
        try f.engine.logCurrentSet()
        #expect(f.engine.currentValues == SetValues(weightKg: 62.5, reps: 10))
    }

    @Test func loggingWithoutWeightRecordsNoWeight() throws {
        let f = try makeFixture()
        f.engine.select(entryAt: 2)
        #expect(f.engine.currentValues == SetValues(weightKg: nil, reps: 6))
        let logged = try f.engine.logCurrentSet()
        #expect(logged?.set.weightKg == nil)
        #expect(logged?.set.reps == 6)
    }

    @Test func warmupCarriesFromWarmupAndWorkingFromWorking() throws {
        let f = try makeFixture()
        try f.engine.toggleWarmupOnCurrentSet()
        f.engine.setCurrentWeight(40)
        f.engine.setCurrentReps(12)
        try f.engine.logCurrentSet()
        // Working set after only a warm-up: falls back to the warm-up's values.
        #expect(f.engine.currentValues == SetValues(weightKg: 40, reps: 12))
        f.engine.setCurrentWeight(60)
        f.engine.setCurrentReps(8)
        try f.engine.logCurrentSet()
        try f.engine.toggleWarmupOnCurrentSet()
        // A warm-up prefers the previous warm-up.
        #expect(f.engine.currentValues == SetValues(weightKg: 40, reps: 12))
        try f.engine.toggleWarmupOnCurrentSet()
        #expect(f.engine.currentValues == SetValues(weightKg: 60, reps: 8))
    }

    @Test func editsAreNotSavedUntilAsked() throws {
        let f = try makeFixture()
        f.engine.setCurrentWeight(50)
        #expect(f.context.hasChanges)
        try f.engine.saveEdits()
        #expect(!f.context.hasChanges)
        try f.engine.saveEdits()
    }

    @Test func negativeEditsClampToZero() throws {
        let f = try makeFixture()
        f.engine.setCurrentWeight(-5)
        f.engine.setCurrentReps(-2)
        #expect(f.engine.currentValues == SetValues(weightKg: 0, reps: 0))
    }

    // MARK: Rest

    @Test func restComesFromRoutineThenExerciseThenSettings() throws {
        let f = try makeFixture(defaultRest: 75)
        let entries = f.engine.entries
        #expect(f.engine.restDuration(for: entries[0]) == 120)
        #expect(f.engine.restDuration(for: entries[1]) == 75)
        entries[1].exercise?.defaultRestSeconds = 45
        #expect(f.engine.restDuration(for: entries[1]) == 45)

        let noSetting = try makeFixture(defaultRest: nil)
        #expect(noSetting.engine.restDuration(for: noSetting.engine.entries[2]) == 90)
    }

    @Test func logReturnsRestUntilTheLastSetOfTheWorkout() throws {
        let f = try makeFixture()
        #expect(try f.engine.logCurrentSet()?.restDuration == 120)
        try f.engine.logCurrentSet()
        // Last set of an exercise still rests: the next exercise comes after the rest.
        #expect(try f.engine.logCurrentSet()?.restDuration == 120)
        #expect(try f.engine.logCurrentSet() == nil)
        f.engine.select(entryAt: 1)
        try f.engine.logCurrentSet()
        try f.engine.logCurrentSet()
        f.engine.select(entryAt: 2)
        let last = try f.engine.logCurrentSet()
        #expect(last != nil)
        #expect(last?.restDuration == nil)
        #expect(f.engine.isComplete)
    }

    // MARK: Sets

    @Test func addSetAppendsAPlannedSet() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        try f.engine.addSet()
        let sets = f.engine.entries[0].sortedSets
        #expect(sets.count == 4)
        #expect(sets.map(\.order) == [0, 1, 2, 3])
        #expect(sets.last?.completedAt == nil)
        #expect(f.engine.progress(of: f.engine.entries[0]) == ExerciseProgress(completed: 1, total: 4))
        #expect(!f.context.hasChanges)
    }

    @Test func addSetToFinishedExerciseReopensIt() throws {
        let f = try makeFixture()
        f.engine.select(entryAt: 2)
        try f.engine.logCurrentSet()
        #expect(f.engine.isDone(f.engine.entries[2]))
        try f.engine.addSet()
        #expect(!f.engine.isDone(f.engine.entries[2]))
        #expect(f.engine.currentSetNumber == 2)
        #expect(f.engine.currentValues == SetValues(weightKg: nil, reps: 6))
    }

    @Test func removeDeletesTheLastUnloggedSetOnly() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        #expect(f.engine.canRemoveSet)
        #expect(try f.engine.removeLastUnloggedSet())
        #expect(try f.engine.removeLastUnloggedSet())
        #expect(!f.engine.canRemoveSet)
        #expect(try f.engine.removeLastUnloggedSet() == false)
        let sets = f.engine.entries[0].sortedSets
        #expect(sets.count == 1)
        #expect(sets.first?.completedAt != nil)
        #expect(try ModelContext(f.container).count(SetLog.self) == 4)
    }

    @Test func warmupToggleSavesAndShowsInStatuses() throws {
        let f = try makeFixture()
        try f.engine.toggleWarmupOnCurrentSet()
        #expect(!f.context.hasChanges)
        let statuses = f.engine.statuses(of: f.engine.entries[0])
        #expect(statuses.map(\.isWarmup) == [true, false, false])
        #expect(statuses.map(\.isCurrent) == [true, false, false])
        try f.engine.logCurrentSet()
        let after = f.engine.statuses(of: f.engine.entries[0])
        #expect(after.map(\.isCompleted) == [true, false, false])
        #expect(after.map(\.isCurrent) == [false, true, false])
        try f.engine.toggleWarmupOnCurrentSet()
        try f.engine.toggleWarmupOnCurrentSet()
        #expect(f.engine.statuses(of: f.engine.entries[0]).map(\.isWarmup) == [true, false, false])
    }

    // MARK: Navigation

    @Test func selectionClampsAndJumps() throws {
        let f = try makeFixture()
        f.engine.select(entryAt: 9)
        #expect(f.engine.currentIndex == 2)
        f.engine.select(entryAt: -1)
        #expect(f.engine.currentIndex == 0)
        f.engine.select(f.engine.entries[1])
        #expect(f.engine.currentEntry?.exercise?.name == "Lateral Raise")
    }

    @Test func doneExerciseNamesTheNextUnfinishedOne() throws {
        let f = try makeFixture()
        for _ in 0..<3 { try f.engine.logCurrentSet() }
        let bench = f.engine.entries[0]
        #expect(f.engine.isDone(bench))
        #expect(f.engine.currentSet == nil)
        #expect(f.engine.currentSetNumber == nil)
        #expect(f.engine.currentIndex == 0)
        #expect(f.engine.nextUnfinishedEntry(after: bench)?.exercise?.name == "Lateral Raise")

        f.engine.select(entryAt: 1)
        try f.engine.logCurrentSet()
        try f.engine.logCurrentSet()
        #expect(f.engine.nextUnfinishedEntry(after: f.engine.entries[1])?.exercise?.name == "Dips")
    }

    @Test func nextWrapsToEarlierUnfinishedExercises() throws {
        let f = try makeFixture()
        f.engine.select(entryAt: 2)
        try f.engine.logCurrentSet()
        #expect(f.engine.nextUnfinishedEntry(after: f.engine.entries[2])?.exercise?.name == "Bench Press")
    }

    // MARK: Summary and end

    @Test func totalsCountWorkingSetsAndVolume() throws {
        let f = try makeFixture()
        try f.engine.toggleWarmupOnCurrentSet()
        f.engine.setCurrentWeight(40)
        f.engine.setCurrentReps(10)
        try f.engine.logCurrentSet()
        f.engine.setCurrentWeight(60)
        f.engine.setCurrentReps(10)
        try f.engine.logCurrentSet()
        f.engine.setCurrentReps(8)
        try f.engine.logCurrentSet()
        f.engine.select(entryAt: 2)
        try f.engine.logCurrentSet()

        let totals = f.engine.totals
        #expect(totals.completedSets == 4)
        #expect(totals.completedWorkingSets == 3)
        #expect(totals.volumeKg == 60 * 10 + 60 * 8)
    }

    @Test func unfinishedListsRemainingSetsInOrder() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        #expect(f.engine.unfinishedExercises == [
            UnfinishedExercise(name: "Bench Press", remainingSets: 2),
            UnfinishedExercise(name: "Lateral Raise", remainingSets: 2),
            UnfinishedExercise(name: "Dips", remainingSets: 1),
        ])
    }

    @Test func finishSetsEndDateAndKeepsPlannedSets() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        f.clock.advance(by: 1800)
        try f.engine.finish()
        #expect(f.engine.session.endedAt == f.clock.date)
        #expect(!f.context.hasChanges)
        #expect(try WorkoutRecovery.inProgressWatchSessions(in: ModelContext(f.container)).isEmpty)
        #expect(try ModelContext(f.container).count(SetLog.self) == 6)
    }

    @Test func discardDeletesEverything() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        try f.engine.discard()
        let other = ModelContext(f.container)
        #expect(try other.count(Session.self) == 0)
        #expect(try other.count(SessionExercise.self) == 0)
        #expect(try other.count(SetLog.self) == 0)
        #expect(try other.count(Routine.self) == 1)
        #expect(try other.count(Exercise.self) == 3)
    }

    // MARK: Resume

    @Test func resumeShowsExerciseOfLastLoggedSet() throws {
        let f = try makeFixture()
        f.engine.select(entryAt: 1)
        f.clock.advance(by: 10)
        try f.engine.logCurrentSet()
        f.engine.select(entryAt: 0)
        f.clock.advance(by: 10)
        try f.engine.logCurrentSet()
        f.engine.select(entryAt: 2)

        let resumed = WorkoutEngine(resuming: f.engine.session, in: ModelContext(f.container), defaultRestSeconds: 90)
        #expect(resumed.currentIndex == 0)
        #expect(resumed.currentSetNumber == 2)
        #expect(resumed.totals.completedSets == 2)
    }

    @Test func resumePrefersTheStoredExercise() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        let dips = f.engine.entries[2]
        let resumed = WorkoutEngine(resuming: f.engine.session, in: f.context, defaultRestSeconds: 90, currentEntryID: dips.id)
        #expect(resumed.currentIndex == 2)
        let unknown = WorkoutEngine(resuming: f.engine.session, in: f.context, defaultRestSeconds: 90, currentEntryID: UUID())
        #expect(unknown.currentIndex == 0)
    }

    @Test func resumeWithNothingLoggedStartsAtTheFirstExercise() throws {
        let f = try makeFixture()
        let resumed = WorkoutEngine(resuming: f.engine.session, in: f.context, defaultRestSeconds: 90)
        #expect(resumed.currentIndex == 0)
        #expect(resumed.currentValues == SetValues(weightKg: nil, reps: 8))
    }

    @Test func emptySessionIsHarmless() throws {
        let context = try makeInMemoryContext()
        let routine = insertRoutine("Empty", items: [], in: context)
        let engine = try WorkoutEngine.start(routine: routine, in: context, defaultRestSeconds: 90)
        #expect(engine.currentEntry == nil)
        #expect(engine.currentValues == nil)
        #expect(try engine.logCurrentSet() == nil)
        try engine.addSet()
        #expect(try engine.removeLastUnloggedSet() == false)
        #expect(engine.isComplete)
        #expect(engine.unfinishedExercises.isEmpty)
    }
}
