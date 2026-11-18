// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Changing a workout")
struct WorkoutChangesTests {
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let routine: Routine
        let clock: TestClock
        let engine: WorkoutEngine
        let dumbbellBench: Exercise
        let fly: Exercise
    }

    /// Push: Bench Press 3 × 8–12 (rest 120), Lateral Raise 2 × 12–15, Dips 1 × 6–10, plus two
    /// exercises outside the routine; Dumbbell Bench Press has history.
    private func makeFixture() throws -> Fixture {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let routine = insertRoutine("Push", items: [
            ("Bench Press", .barbell, 3, 8, 12, 120),
            ("Lateral Raise", .dumbbell, 2, 12, 15, nil),
            ("Dips", .bodyweight, 1, 6, 10, nil),
        ], in: context)
        let dumbbellBench = Exercise(name: "Dumbbell Bench Press", equipment: .dumbbell, primaryMuscle: .chest)
        let fly = Exercise(name: "Cable Fly", equipment: .cable, primaryMuscle: .chest)
        context.insertAll(dumbbellBench, fly)
        let clock = TestClock()
        insertSession(startedAt: clock.date.addingTimeInterval(-86_400), entries: [(dumbbellBench, [(26, 10, false), (26, 9, false)])], in: context)
        try context.save()
        let engine = try WorkoutEngine.start(routine: routine, in: context, defaultRestSeconds: 75, now: clock.now)
        return Fixture(container: container, context: context, routine: routine, clock: clock, engine: engine, dumbbellBench: dumbbellBench, fly: fly)
    }

    private func names(_ engine: WorkoutEngine) -> [String] {
        engine.entries.map { $0.exercise?.name ?? "" }
    }

    // MARK: Start

    @Test func entriesRecordTheirRoutineSlot() throws {
        let f = try makeFixture()
        #expect(f.engine.entries.map(\.routineItemID) == f.routine.sortedItems.map(\.id))
        #expect(f.engine.entries.allSatisfy { !$0.isSkipped })
    }

    @Test func emptyWorkoutStartsWithNoExercisesAndAddsAtTheEnd() throws {
        let f = try makeFixture()
        try f.engine.discard()
        let engine = try WorkoutEngine.startEmpty(in: f.context, defaultRestSeconds: 75, now: f.clock.now)
        #expect(engine.session.name == WorkoutEngine.emptyWorkoutName)
        #expect(engine.session.routine == nil)
        #expect(engine.session.startedAt == f.clock.date)
        #expect(engine.currentEntry == nil)
        #expect(!engine.canSwapCurrentExercise && !engine.canAddSet)
        #expect(try WorkoutRecovery.inProgressWatchSessions(in: ModelContext(f.container)).map(\.id) == [engine.session.id])

        let first = try engine.addExercise(f.fly)
        let second = try engine.addExercise(f.dumbbellBench)
        #expect(names(engine) == ["Cable Fly", "Dumbbell Bench Press"])
        #expect(engine.entries.map(\.order) == [0, 1])
        #expect(engine.currentEntry === second)
        #expect(first.routineItemID == nil && second.routineItemID == nil)
        #expect(second.repLow == RoutineRules.defaultRepLow && second.repHigh == RoutineRules.defaultRepHigh)
        #expect(second.sets?.count == RoutineRules.defaultSets)
        // The added exercise pre-fills from its own history; rest uses the app default.
        #expect(engine.currentValues == SetValues(weightKg: 26, reps: 10))
        #expect(engine.restDuration(for: second) == 75)
        #expect(!f.context.hasChanges)
    }

    @Test func addedExerciseGoesAfterTheRoutineAndGetsNoSlotRest() throws {
        let f = try makeFixture()
        f.engine.select(entryAt: 1)
        let added = try f.engine.addExercise(f.fly)
        #expect(names(f.engine) == ["Bench Press", "Lateral Raise", "Dips", "Cable Fly"])
        #expect(f.engine.currentIndex == 3)
        #expect(f.engine.restDuration(for: added) == 75)
        #expect(try ModelContext(f.container).count(SessionExercise.self) == 5)
    }

    // MARK: Swap

    @Test func swapWithNothingLoggedChangesTheExerciseInPlace() throws {
        let f = try makeFixture()
        f.engine.setCurrentWeight(80)
        try f.engine.toggleWarmupOnCurrentSet()
        #expect(try f.engine.swapCurrentExercise(to: f.dumbbellBench))
        #expect(names(f.engine) == ["Dumbbell Bench Press", "Lateral Raise", "Dips"])
        let entry = f.engine.entries[0]
        #expect(entry.routineItemID == f.routine.sortedItems[0].id)
        #expect(entry.sets?.count == 3)
        #expect(entry.sortedSets.allSatisfy { $0.weightKg == nil && $0.reps == nil })
        #expect(entry.sortedSets.map(\.isWarmup) == [true, false, false])
        // Typed values are gone, so the new exercise pre-fills from its own history.
        try f.engine.toggleWarmupOnCurrentSet()
        #expect(f.engine.currentValues == SetValues(weightKg: 26, reps: 10))
        #expect(f.engine.currentLastLine == .previous(SetValues(weightKg: 26, reps: 10)))
        // Rest still comes from the routine slot.
        #expect(f.engine.restDuration(for: entry) == 120)
        #expect(!f.context.hasChanges)
    }

    @Test func swapAfterLoggingSplitsTheEntry() throws {
        let f = try makeFixture()
        f.engine.setCurrentWeight(60)
        f.engine.setCurrentReps(10)
        try f.engine.logCurrentSet()
        f.engine.setCurrentWeight(65)
        #expect(f.engine.canSwapCurrentExercise)
        #expect(try f.engine.swapCurrentExercise(to: f.dumbbellBench))

        #expect(names(f.engine) == ["Bench Press", "Dumbbell Bench Press", "Lateral Raise", "Dips"])
        #expect(f.engine.entries.map(\.order) == [0, 1, 2, 3])
        let old = f.engine.entries[0]
        let split = f.engine.entries[1]
        #expect(f.engine.currentEntry === split)
        #expect(old.sortedSets.count == 1)
        #expect(old.sortedSets.allSatisfy { $0.completedAt != nil && $0.weightKg == 60 })
        #expect(f.engine.isDone(old))
        #expect(split.sortedSets.count == 2)
        #expect(split.sortedSets.map(\.order) == [0, 1])
        #expect(split.sortedSets.allSatisfy { $0.completedAt == nil && $0.weightKg == nil && $0.reps == nil })
        #expect(split.routineItemID == old.routineItemID)
        #expect(split.repLow == 8 && split.repHigh == 12)
        #expect(f.engine.currentSetNumber == 1)
        #expect(f.engine.currentValues == SetValues(weightKg: 26, reps: 10))
        #expect(f.engine.restDuration(for: split) == 120)
        #expect(f.engine.unfinishedExercises.first == UnfinishedExercise(name: "Dumbbell Bench Press", remainingSets: 2))

        // Persisted at once, visible to another context.
        let other = ModelContext(f.container)
        let session = try #require(try other.all(Session.self).first { $0.id == f.engine.session.id })
        #expect(session.sortedEntries.map { $0.exercise?.name } == ["Bench Press", "Dumbbell Bench Press", "Lateral Raise", "Dips"])
        #expect(session.sortedEntries.map { $0.sets?.count } == [1, 2, 2, 1])
    }

    @Test func swapIsUnavailableOnceEverySetIsLogged() throws {
        let f = try makeFixture()
        f.engine.select(entryAt: 2)
        try f.engine.logCurrentSet()
        #expect(!f.engine.canSwapCurrentExercise)
        #expect(try f.engine.swapCurrentExercise(to: f.fly) == false)
        #expect(try f.engine.swapCurrentExercise(to: try #require(f.engine.entries[0].exercise)) == false)
        #expect(names(f.engine) == ["Bench Press", "Lateral Raise", "Dips"])
    }

    @Test func swappingASkippedExerciseResumesIt() throws {
        let f = try makeFixture()
        try f.engine.setSkipped(true, for: f.engine.entries[0])
        f.engine.select(entryAt: 0)
        try f.engine.swapCurrentExercise(to: f.fly)
        #expect(!f.engine.entries[0].isSkipped)
        #expect(f.engine.currentSet != nil)
    }

    @Test func swapLeavesTheOldExerciseHistoryAlone() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        try f.engine.swapCurrentExercise(to: f.dumbbellBench)
        try f.engine.logCurrentSet()
        try f.engine.finish()
        let bench = try #require(f.engine.entries[0].exercise)
        #expect(ExerciseHistory.lastPerformance(of: bench)?.sets.count == 1)
        #expect(ExerciseHistory.lastPerformance(of: f.dumbbellBench)?.sets.map(\.weightKg) == [26])
    }

    // MARK: Skip

    @Test func skippedExerciseCountsAsDoneAndKeepsLoggedSets() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        let bench = f.engine.entries[0]
        try f.engine.setSkipped(true, for: bench)
        #expect(bench.isSkipped)
        #expect(f.engine.isDone(bench))
        #expect(f.engine.progress(of: bench) == ExerciseProgress(completed: 1, total: 3, isSkipped: true))
        #expect(f.engine.progress(of: bench).isDone)
        #expect(f.engine.currentSet(of: bench) == nil)
        #expect(f.engine.statuses(of: bench).map(\.isCurrent) == [false, false, false])
        #expect(f.engine.unfinishedExercises.map(\.name) == ["Lateral Raise", "Dips"])
        #expect(bench.sets?.count == 3)
        // Skipping the exercise on screen moves on to the next unfinished one.
        #expect(f.engine.currentEntry?.exercise?.name == "Lateral Raise")
        #expect(f.engine.nextUnfinishedEntry(after: f.engine.entries[2])?.exercise?.name == "Lateral Raise")
        #expect(!f.context.hasChanges)
    }

    @Test func skippedExerciseRejectsSetChangesUntilResumed() throws {
        let f = try makeFixture()
        try f.engine.setSkipped(true, for: f.engine.entries[0])
        f.engine.select(entryAt: 0)
        #expect(!f.engine.canAddSet && !f.engine.canRemoveSet)
        try f.engine.addSet()
        #expect(try f.engine.removeLastUnloggedSet() == false)
        #expect(try f.engine.logCurrentSet() == nil)
        #expect(f.engine.entries[0].sets?.count == 3)
        try f.engine.setSkipped(false, for: f.engine.entries[0])
        #expect(f.engine.currentIndex == 0)
        #expect(f.engine.currentSetNumber == 1)
    }

    @Test func skippingEverythingLeftCompletesTheWorkout() throws {
        let f = try makeFixture()
        for _ in 0..<3 { try f.engine.logCurrentSet() }
        try f.engine.setSkipped(true, for: f.engine.entries[1])
        try f.engine.setSkipped(true, for: f.engine.entries[2])
        #expect(f.engine.isComplete)
        #expect(f.engine.unfinishedExercises.isEmpty)
        // Skipping the last unfinished exercise on screen stays on it.
        let f2 = try makeFixture()
        f2.engine.select(entryAt: 2)
        try f2.engine.setSkipped(true, for: f2.engine.entries[0])
        try f2.engine.setSkipped(true, for: f2.engine.entries[1])
        try f2.engine.setSkipped(true, for: f2.engine.entries[2])
        #expect(f2.engine.currentIndex == 2)
    }

    @Test func lastSetBeforeOnlySkippedExercisesHasNoRest() throws {
        let f = try makeFixture()
        try f.engine.setSkipped(true, for: f.engine.entries[1])
        try f.engine.setSkipped(true, for: f.engine.entries[2])
        try f.engine.logCurrentSet()
        try f.engine.logCurrentSet()
        #expect(try f.engine.logCurrentSet()?.restDuration == nil)
    }

    // MARK: Reorder

    @Test func movingKeepsOrdersContiguousAndTheCurrentExercise() throws {
        let f = try makeFixture()
        f.engine.select(entryAt: 1)
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(names(f.engine) == ["Dips", "Bench Press", "Lateral Raise"])
        #expect(f.engine.entries.map(\.order) == [0, 1, 2])
        #expect(f.engine.currentEntry?.exercise?.name == "Lateral Raise")
        #expect(!f.context.hasChanges)
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(names(f.engine) == ["Bench Press", "Lateral Raise", "Dips"])
        // Rest still follows the slot, not the position.
        #expect(f.engine.restDuration(for: f.engine.entries[0]) == 120)
        let other = ModelContext(f.container)
        let stored = try other.all(Session.self).first { $0.id == f.engine.session.id }
        #expect(stored?.sortedEntries.map { $0.exercise?.name } == ["Bench Press", "Lateral Raise", "Dips"])
    }

    @Test func movingNowhereDoesNotSave() throws {
        let f = try makeFixture()
        let before = f.engine.session.updatedAt
        f.clock.advance(by: 60)
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 7), toOffset: 0)
        #expect(f.engine.session.updatedAt == before)
    }

    // MARK: Restore

    @Test func changedWorkoutRestoresAfterARelaunch() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        try f.engine.swapCurrentExercise(to: f.dumbbellBench)
        try f.engine.setSkipped(true, for: f.engine.entries[2])
        try f.engine.addExercise(f.fly)
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 4), toOffset: 1)

        let context = ModelContext(f.container)
        let session = try #require(try WorkoutRecovery.resolveInProgressSession(in: context))
        let resumed = WorkoutEngine(resuming: session, in: context, defaultRestSeconds: 75, currentEntryID: f.engine.currentEntry?.id)
        #expect(names(resumed) == ["Bench Press", "Cable Fly", "Dumbbell Bench Press", "Lateral Raise", "Dips"])
        #expect(resumed.entries.map(\.isSkipped) == [false, false, false, true, false])
        #expect(resumed.entries.map { $0.routineItemID != nil } == [true, false, true, true, true])
        #expect(resumed.currentEntry?.exercise?.name == "Cable Fly")
        #expect(resumed.restDuration(for: resumed.entries[2]) == 120)
    }
}
