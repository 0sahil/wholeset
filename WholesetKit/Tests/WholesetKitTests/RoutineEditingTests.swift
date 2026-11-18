// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Routine editing")
struct RoutineEditingTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var t1: Date { t0.addingTimeInterval(60) }

    private func exercises(_ names: [String], in context: ModelContext) -> [Exercise] {
        names.map { name in
            let exercise = Exercise(name: name)
            exercise.createdAt = t0
            exercise.updatedAt = t0
            context.insert(exercise)
            return exercise
        }
    }

    // MARK: Rules

    @Test func clampsSetsAndReps() {
        #expect(RoutineRules.clampedSets(0) == 1)
        #expect(RoutineRules.clampedSets(11) == 10)
        #expect(RoutineRules.clampedSets(4) == 4)
        #expect(RoutineRules.repRange(low: 0, high: 60) == 1...50)
        #expect(RoutineRules.repRange(low: 12, high: 8) == 12...12)
        #expect(RoutineRules.repRange(low: 8, high: 12) == 8...12)
    }

    @Test func restIsDefaultOrFifteenSecondSteps() {
        #expect(RoutineRules.normalizedRest(nil) == nil)
        #expect(RoutineRules.normalizedRest(0) == 15)
        #expect(RoutineRules.normalizedRest(10) == 15)
        #expect(RoutineRules.normalizedRest(97) == 90)
        #expect(RoutineRules.normalizedRest(98) == 105)
        #expect(RoutineRules.normalizedRest(601) == 600)
        #expect(RoutineRules.normalizedRest(10_000) == 600)
        let choices = RoutineRules.restChoices
        #expect(choices.first == 15 && choices.last == 600 && choices.count == 40)
    }

    @Test func alternativesExcludeSelfAndRepeatsAndStopAtFour() throws {
        let context = try makeInMemoryContext()
        let all = exercises(["A", "B", "C", "D", "E", "F"], in: context)
        let valid = ExerciseRules.validAlternatives([all[0], all[1], all[1], all[2], all[3], all[4], all[5]], for: all[0])
        #expect(valid.map(\.name) == ["B", "C", "D", "E"])
    }

    // MARK: Routines

    @Test func createsRoutinesAtTheEndOfTheList() throws {
        let context = try makeInMemoryContext()
        let first = try RoutineEditing.createRoutine(named: "  Upper ", in: context, now: t0)
        let second = try RoutineEditing.createRoutine(named: "   ", in: context, now: t1)
        #expect(first.name == "Upper")
        #expect(first.sortIndex == 0)
        #expect(second.sortIndex == 1)
        #expect(second.name == "New Routine")
        #expect(first.createdAt == t0 && first.updatedAt == t0)
        #expect(try AppSettings.current(in: context).starterRoutinesDecidedAt == t0)
    }

    @Test func renamesAndRejectsEmptyNames() throws {
        let context = try makeInMemoryContext()
        let routine = try RoutineEditing.createRoutine(named: "Upper", in: context, now: t0)
        #expect(!RoutineEditing.rename(routine, to: "  ", now: t1))
        #expect(!RoutineEditing.rename(routine, to: "Upper", now: t1))
        #expect(routine.updatedAt == t0)
        #expect(RoutineEditing.rename(routine, to: " Upper A ", now: t1))
        #expect(routine.name == "Upper A")
        #expect(routine.updatedAt == t1)
    }

    @Test func deletingKeepsSessionsAndTurnsPlanDaysIntoRest() throws {
        let context = try makeInMemoryContext()
        let routine = try RoutineEditing.createRoutine(named: "Push", in: context, now: t0)
        RoutineEditing.addItems(for: exercises(["Bench"], in: context), to: routine, in: context, now: t0)
        let session = Session(name: "Push")
        context.insert(session)
        session.routine = routine
        try WeekPlan.set(routine, on: 2, in: context, now: t0)
        try context.save()

        RoutineEditing.delete(routine, in: context, now: t1)
        try context.save()

        #expect(try context.count(Routine.self) == 0)
        #expect(try context.count(RoutineItem.self) == 0)
        #expect(try context.count(Exercise.self) == 1)
        #expect(session.routine == nil)
        #expect(session.name == "Push")
        let day = try #require(try context.all(WeekPlanDay.self).first)
        #expect(day.routine == nil)
        #expect(day.updatedAt == t1)
        #expect(WeekPlan.days(planDays: [day], calendar: utcCalendar).first { $0.weekday == 2 }?.isRest == true)
    }

    @Test func reordersRoutinesContiguously() throws {
        let context = try makeInMemoryContext()
        let names = ["A", "B", "C", "D"]
        for name in names {
            try RoutineEditing.createRoutine(named: name, in: context, now: t0)
        }
        let shown = TodayPlanResolver.sortedRoutines(try context.all(Routine.self))
        RoutineEditing.moveRoutines(shown, fromOffsets: IndexSet(integer: 3), toOffset: 1, now: t1)
        let reordered = TodayPlanResolver.sortedRoutines(try context.all(Routine.self))
        #expect(reordered.map(\.name) == ["A", "D", "B", "C"])
        #expect(reordered.map(\.sortIndex) == [0, 1, 2, 3])
        #expect(reordered[0].updatedAt == t0)
        #expect(reordered[1].updatedAt == t1)
    }

    @Test func duplicatesARoutineAsAnOrdinaryRoutine() throws {
        let context = try makeInMemoryContext()
        try StarterRoutines.seed(in: context, now: t0)
        let push = try #require(try context.all(Routine.self).first { $0.name == "Push" })
        push.notes = "Pause reps."
        let copy = try RoutineEditing.duplicate(push, in: context, now: t1)
        #expect(copy.name == "Push Copy")
        #expect(copy.notes == "Pause reps.")
        #expect(copy.seedKey == nil)
        #expect(copy.sortIndex == 3)
        #expect(copy.sortedItems.map { $0.exercise?.name } == push.sortedItems.map { $0.exercise?.name })
        #expect(copy.sortedItems.map(\.targetSets) == push.sortedItems.map(\.targetSets))
        #expect(copy.sortedItems.map(\.order) == Array(0..<push.sortedItems.count))
        #expect(Set(copy.sortedItems.map(\.id)).isDisjoint(with: push.sortedItems.map(\.id)))
    }

    // MARK: Items

    @Test func addsRemovesAndMovesItemsKeepingOrderContiguous() throws {
        let context = try makeInMemoryContext()
        let routine = try RoutineEditing.createRoutine(named: "Full", in: context, now: t0)
        let added = RoutineEditing.addItems(for: exercises(["A", "B", "C", "D"], in: context), to: routine, in: context, now: t0)
        #expect(added.map(\.order) == [0, 1, 2, 3])
        #expect(added.allSatisfy { $0.targetSets == 3 && $0.repLow == 8 && $0.repHigh == 12 && $0.restSeconds == nil })

        RoutineEditing.removeItem(added[1], in: context, now: t1)
        #expect(routine.sortedItems.map { $0.exercise?.name } == ["A", "C", "D"])
        #expect(routine.sortedItems.map(\.order) == [0, 1, 2])
        #expect(routine.updatedAt == t1)

        RoutineEditing.moveItems(in: routine, fromOffsets: IndexSet(integer: 0), toOffset: 3, now: t1)
        #expect(routine.sortedItems.map { $0.exercise?.name } == ["C", "D", "A"])
        #expect(routine.sortedItems.map(\.order) == [0, 1, 2])
    }

    @Test func targetChangesAreValidatedAndTouchTheRoutine() throws {
        let context = try makeInMemoryContext()
        let routine = try RoutineEditing.createRoutine(named: "Full", in: context, now: t0)
        let item = try #require(RoutineEditing.addItems(for: exercises(["A"], in: context), to: routine, in: context, now: t0).first)

        RoutineEditing.setTargetSets(3, on: item, now: t1)
        #expect(item.updatedAt == t0)
        RoutineEditing.setTargetSets(25, on: item, now: t1)
        #expect(item.targetSets == 10)
        #expect(item.updatedAt == t1 && routine.updatedAt == t1)

        RoutineEditing.setRepRange(low: 15, high: 10, on: item, now: t1)
        #expect(item.repLow == 15 && item.repHigh == 15)
        RoutineEditing.setRepRange(low: 0, high: 99, on: item, now: t1)
        #expect(item.repLow == 1 && item.repHigh == 50)

        RoutineEditing.setRest(100, on: item, now: t1)
        #expect(item.restSeconds == 105)
        RoutineEditing.setRest(nil, on: item, now: t1)
        #expect(item.restSeconds == nil)
    }

    @Test func alternativesAreSetOnTheExercise() throws {
        let context = try makeInMemoryContext()
        let all = exercises(["Bench", "DB Bench", "Machine Press", "Push-up", "Dip", "Floor Press"], in: context)
        RoutineEditing.setAlternatives(Array(all.dropFirst()) + [all[0]], for: all[0], now: t1)
        #expect(all[0].alternatives?.count == 4)
        #expect(all[0].alternatives?.contains { $0 === all[0] } == false)
        #expect(all[0].updatedAt == t1)
        #expect(all[1].alternativeOf?.contains { $0 === all[0] } == true)

        let later = t1.addingTimeInterval(60)
        RoutineEditing.setAlternatives(all[0].alternatives ?? [], for: all[0], now: later)
        #expect(all[0].updatedAt == t1)
    }

    @Test func reorderMatchesSwiftUIMoveSemantics() {
        let letters = ["a", "b", "c", "d", "e"]
        #expect(Reorder.moving(letters, fromOffsets: IndexSet(integer: 0), toOffset: 2) == ["b", "a", "c", "d", "e"])
        #expect(Reorder.moving(letters, fromOffsets: IndexSet(integer: 4), toOffset: 0) == ["e", "a", "b", "c", "d"])
        #expect(Reorder.moving(letters, fromOffsets: IndexSet([1, 3]), toOffset: 5) == ["a", "c", "e", "b", "d"])
        #expect(Reorder.moving(letters, fromOffsets: IndexSet([0, 1]), toOffset: 4) == ["c", "d", "a", "b", "e"])
        #expect(Reorder.moving(letters, fromOffsets: IndexSet(integer: 2), toOffset: 2) == letters)
        #expect(Reorder.moving(letters, fromOffsets: IndexSet(integer: 9), toOffset: 0) == letters)
    }
}
