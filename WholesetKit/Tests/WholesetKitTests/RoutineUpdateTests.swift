// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Routine update after a workout")
struct RoutineUpdateTests {
    private struct Fixture {
        let context: ModelContext
        let routine: Routine
        let clock: TestClock
        let engine: WorkoutEngine
        let dumbbellBench: Exercise
        let fly: Exercise
    }

    /// Push: Bench Press 3 × 8–12, Lateral Raise 2 × 12–15, Dips 1 × 6–10.
    private func makeFixture() throws -> Fixture {
        let context = try makeInMemoryContext()
        let routine = insertRoutine("Push", items: [
            ("Bench Press", .barbell, 3, 8, 12, 120),
            ("Lateral Raise", .dumbbell, 2, 12, 15, nil),
            ("Dips", .bodyweight, 1, 6, 10, nil),
        ], in: context)
        let dumbbellBench = Exercise(name: "Dumbbell Bench Press", equipment: .dumbbell)
        let fly = Exercise(name: "Cable Fly", equipment: .cable)
        context.insertAll(dumbbellBench, fly)
        try context.save()
        let clock = TestClock()
        let engine = try WorkoutEngine.start(routine: routine, in: context, defaultRestSeconds: 90, now: clock.now)
        return Fixture(context: context, routine: routine, clock: clock, engine: engine, dumbbellBench: dumbbellBench, fly: fly)
    }

    /// Logs every set left in every exercise that is not skipped.
    private func logEverything(_ engine: WorkoutEngine) throws {
        for index in engine.entries.indices {
            engine.select(entryAt: index)
            while try engine.logCurrentSet() != nil {}
        }
    }

    private func proposal(_ f: Fixture) throws -> RoutineUpdateProposal? {
        try f.engine.finish()
        return RoutineUpdate.proposal(for: f.engine.session)
    }

    private func itemNames(_ routine: Routine) -> [String] {
        routine.sortedItems.map { $0.exercise?.name ?? "" }
    }

    // MARK: What counts

    @Test func doingTheRoutineAsPlannedOffersNothing() throws {
        let f = try makeFixture()
        try logEverything(f.engine)
        #expect(try proposal(f) == nil)
    }

    @Test func endingEarlyIsNotAChange() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        #expect(try proposal(f) == nil)
    }

    @Test func nothingLoggedOffersNothing() throws {
        let f = try makeFixture()
        try f.engine.addSet()
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(try proposal(f) == nil)
    }

    @Test func skippingIsNeverAChange() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        try f.engine.setSkipped(true, for: f.engine.entries[0])
        try f.engine.setSkipped(true, for: f.engine.entries[1])
        f.engine.select(entryAt: 2)
        try f.engine.removeLastUnloggedSet()
        try f.engine.addSet()
        try f.engine.addSet()
        try f.engine.setSkipped(true, for: f.engine.entries[2])
        #expect(try proposal(f) == nil)
    }

    @Test func swapInPlaceIsReported() throws {
        let f = try makeFixture()
        try f.engine.swapCurrentExercise(to: f.dumbbellBench)
        try logEverything(f.engine)
        #expect(try proposal(f) == RoutineUpdateProposal(routineName: "Push", changes: [
            .swapped(from: "Bench Press", to: "Dumbbell Bench Press"),
        ]))
    }

    @Test func swapToAnExerciseNeverLoggedIsNotReported() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        try f.engine.swapCurrentExercise(to: f.dumbbellBench)
        f.engine.select(entryAt: 2)
        try f.engine.logCurrentSet()
        #expect(try proposal(f) == nil)
    }

    @Test func swapAfterLoggingCountsTheFinalExerciseAndAllItsSets() throws {
        let f = try makeFixture()
        try f.engine.logCurrentSet()
        try f.engine.swapCurrentExercise(to: f.dumbbellBench)
        try f.engine.addSet()
        try logEverything(f.engine)
        #expect(try proposal(f) == RoutineUpdateProposal(routineName: "Push", changes: [
            .swapped(from: "Bench Press", to: "Dumbbell Bench Press"),
            .setsChanged(exercise: "Dumbbell Bench Press", from: 3, to: 4),
        ]))
    }

    @Test func swappingBackIsNotASwap() throws {
        let f = try makeFixture()
        let bench = try #require(f.engine.entries[0].exercise)
        try f.engine.logCurrentSet()
        try f.engine.swapCurrentExercise(to: f.dumbbellBench)
        try f.engine.logCurrentSet()
        try f.engine.swapCurrentExercise(to: bench)
        try logEverything(f.engine)
        #expect(try proposal(f) == nil)
    }

    @Test func workingSetCountIgnoresWarmupsAndIsClamped() throws {
        let f = try makeFixture()
        try f.engine.toggleWarmupOnCurrentSet()
        try f.engine.logCurrentSet()
        f.engine.select(entryAt: 1)
        for _ in 0..<12 { try f.engine.addSet() }
        f.engine.select(entryAt: 2)
        try f.engine.removeLastUnloggedSet()
        try f.engine.addSet()
        try f.engine.logCurrentSet()
        #expect(try proposal(f) == RoutineUpdateProposal(routineName: "Push", changes: [
            .setsChanged(exercise: "Bench Press", from: 3, to: 2),
            .setsChanged(exercise: "Lateral Raise", from: 2, to: 10),
        ]))
    }

    @Test func addedExercisesNeedALoggedSet() throws {
        let f = try makeFixture()
        try f.engine.addExercise(f.dumbbellBench)
        try f.engine.addExercise(f.fly)
        try f.engine.logCurrentSet()
        try f.engine.addExercise(f.fly)
        // The second Cable Fly entry logged nothing, so only the first one counts.
        #expect(try proposal(f) == RoutineUpdateProposal(routineName: "Push", changes: [
            .added(exercise: "Cable Fly", sets: 3),
        ]))
    }

    @Test func reorderIsReportedOnce() throws {
        let f = try makeFixture()
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 2), toOffset: 1)
        try f.engine.logCurrentSet()
        #expect(try proposal(f) == RoutineUpdateProposal(routineName: "Push", changes: [.reordered]))
    }

    @Test func movingAnAddedExerciseIsNotAReorder() throws {
        let f = try makeFixture()
        try f.engine.addExercise(f.fly)
        try f.engine.logCurrentSet()
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(try proposal(f)?.changes == [.added(exercise: "Cable Fly", sets: 3)])
    }

    @Test func noRoutineOrAnUnfinishableComparisonOffersNothing() throws {
        let f = try makeFixture()
        try f.engine.discard()
        let empty = try WorkoutEngine.startEmpty(in: f.context, defaultRestSeconds: 90)
        try empty.addExercise(f.fly)
        try empty.logCurrentSet()
        try empty.finish()
        #expect(RoutineUpdate.proposal(for: empty.session) == nil)
        #expect(RoutineUpdate.apply(to: empty.session, in: f.context) == false)
    }

    // MARK: Applying

    @Test func applyRewritesTheRoutine() throws {
        let f = try makeFixture()
        let originalItemIDs = f.routine.sortedItems.map(\.id)
        try f.engine.logCurrentSet()
        try f.engine.swapCurrentExercise(to: f.dumbbellBench)
        try f.engine.addSet()
        try f.engine.addExercise(f.fly)
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 4), toOffset: 2)
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        try logEverything(f.engine)
        let changes = try #require(try proposal(f)).changes
        #expect(changes == [
            .swapped(from: "Bench Press", to: "Dumbbell Bench Press"),
            .setsChanged(exercise: "Dumbbell Bench Press", from: 3, to: 4),
            .added(exercise: "Cable Fly", sets: 3),
            .reordered,
        ])

        f.clock.advance(by: 600)
        #expect(RoutineUpdate.apply(to: f.engine.session, in: f.context, now: f.clock.date))
        try f.context.save()
        #expect(itemNames(f.routine) == ["Dips", "Dumbbell Bench Press", "Cable Fly", "Lateral Raise"])
        #expect(f.routine.sortedItems.map(\.order) == [0, 1, 2, 3])
        #expect(f.routine.sortedItems.map(\.targetSets) == [1, 4, 3, 2])
        let fly = try #require(f.routine.sortedItems.first { $0.exercise === f.fly })
        #expect(fly.repLow == RoutineRules.defaultRepLow && fly.repHigh == RoutineRules.defaultRepHigh)
        #expect(fly.restSeconds == nil)
        // The swapped slot is the same item, keeping its rest and rep range.
        let slot = try #require(f.routine.sortedItems.first { $0.id == originalItemIDs[0] })
        #expect(slot.exercise === f.dumbbellBench && slot.restSeconds == 120)
        #expect(f.routine.updatedAt == f.clock.date)
        #expect(f.routine.sortedItems.first { $0.id == originalItemIDs[2] }?.updatedAt == f.clock.date)
        // Afterwards the session matches the routine.
        #expect(RoutineUpdate.proposal(for: f.engine.session) == nil)
    }

    @Test func applyKeepsItemsTheSessionNeverHad() throws {
        let f = try makeFixture()
        // An item added on iPhone while the workout ran, between Bench Press and Lateral Raise.
        let extra = RoutineItem(order: 1)
        f.context.insert(extra)
        extra.routine = f.routine
        extra.exercise = f.fly
        let ordered = [f.routine.sortedItems[0], extra] + f.routine.sortedItems.dropFirst().filter { $0 !== extra }
        RoutineEditing.arrangeItems(ordered, in: f.routine)
        try f.engine.moveEntries(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        try logEverything(f.engine)
        #expect(try proposal(f)?.changes == [.reordered])
        RoutineUpdate.apply(to: f.engine.session, in: f.context)
        #expect(itemNames(f.routine) == ["Lateral Raise", "Dips", "Bench Press", "Cable Fly"])
    }

    @Test func applyLeavesSkippedSlotsAlone() throws {
        let f = try makeFixture()
        try f.engine.setSkipped(true, for: f.engine.entries[0])
        try f.engine.addExercise(f.fly)
        try logEverything(f.engine)
        RoutineUpdate.apply(to: f.engine.session, in: f.context)
        #expect(itemNames(f.routine) == ["Bench Press", "Lateral Raise", "Dips", "Cable Fly"])
        #expect(f.routine.sortedItems.map(\.targetSets) == [3, 2, 1, 3])
    }

    // MARK: Save as routine

    @Test func emptyWorkoutBecomesARoutine() throws {
        let f = try makeFixture()
        try f.engine.discard()
        let start = Date(timeIntervalSince1970: 1_795_000_000) // 18 Nov 2026, 11:06 UTC
        let engine = try WorkoutEngine.startEmpty(in: f.context, defaultRestSeconds: 90, now: { start })
        try engine.addExercise(f.fly)
        try engine.toggleWarmupOnCurrentSet()
        try engine.logCurrentSet()
        try engine.logCurrentSet()
        try engine.addExercise(f.dumbbellBench)
        try engine.addExercise(f.fly)
        try engine.logCurrentSet()
        try engine.finish()
        let session = engine.session

        #expect(RoutineUpdate.canSaveAsRoutine(session))
        let locale = Locale(identifier: "en_GB")
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        #expect(RoutineUpdate.suggestedRoutineName(for: session, locale: locale, timeZone: utc) == "Workout 18 Nov")
        let routine = try #require(try RoutineUpdate.saveAsRoutine(session, in: f.context, now: start, locale: locale, timeZone: utc))
        try f.context.save()

        #expect(routine.name == "Workout 18 Nov")
        #expect(session.routine === routine)
        #expect(itemNames(routine) == ["Cable Fly"])
        // Both Cable Fly entries: 2 + 3 working sets (the warm-up never counts).
        #expect(routine.sortedItems.map(\.targetSets) == [5])
        #expect(routine.sortedItems.map(\.repLow) == [RoutineRules.defaultRepLow])
        #expect(!RoutineUpdate.canSaveAsRoutine(session))
        #expect(RoutineUpdate.proposal(for: session) == nil)
        #expect(try RoutineUpdate.saveAsRoutine(session, in: f.context) == nil)
        #expect(try f.context.count(Routine.self) == 2)
    }

    @Test func nothingLoggedCannotBecomeARoutine() throws {
        let f = try makeFixture()
        try f.engine.discard()
        let engine = try WorkoutEngine.startEmpty(in: f.context, defaultRestSeconds: 90)
        try engine.addExercise(f.fly)
        try engine.finish()
        #expect(!RoutineUpdate.canSaveAsRoutine(engine.session))
        #expect(try RoutineUpdate.saveAsRoutine(engine.session, named: "Mine", in: f.context) == nil)
    }

    @Test func customNameIsUsed() throws {
        let f = try makeFixture()
        try f.engine.discard()
        let engine = try WorkoutEngine.startEmpty(in: f.context, defaultRestSeconds: 90)
        try engine.addExercise(f.fly)
        try engine.logCurrentSet()
        try engine.finish()
        #expect(try RoutineUpdate.saveAsRoutine(engine.session, named: "Chest Finisher", in: f.context)?.name == "Chest Finisher")
    }
}
