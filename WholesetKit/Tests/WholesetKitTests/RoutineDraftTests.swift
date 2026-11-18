// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Routine editor draft")
struct RoutineDraftTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var t1: Date { t0.addingTimeInterval(60) }

    private func seeded() throws -> (ModelContext, Routine) {
        let context = try makeInMemoryContext()
        try StoreMaintenance.run(in: context, library: try ExerciseLibrary.bundled(), seedStarterRoutines: true, now: t0)
        let push = try #require(try context.all(Routine.self).first { $0.name == "Push" })
        return (context, push)
    }

    private func exercise(named name: String, in context: ModelContext) throws -> Exercise {
        try #require(try context.all(Exercise.self).first { $0.name == name })
    }

    @Test func editingADraftChangesNothingUntilApplied() throws {
        let (_, push) = try seeded()
        var draft = RoutineDraft(routine: push)
        let original = draft
        draft.name = "Push Day"
        draft.setTargetSets(5, forItem: draft.items[0].id)
        draft.removeItems(atOffsets: IndexSet(integer: 4))
        #expect(draft != original)
        #expect(push.name == "Push")
        #expect(push.sortedItems.count == 5)
        #expect(push.sortedItems[0].targetSets == 3)
        #expect(push.updatedAt == t0)
    }

    @Test func applyingWritesEveryChange() throws {
        let (context, push) = try seeded()
        let squat = try exercise(named: "Squat", in: context)
        var draft = RoutineDraft(routine: push)
        draft.name = " Push Day "
        draft.notes = "Pause on the chest."
        let first = draft.items[0].id
        draft.setTargetSets(5, forItem: first)
        draft.setRepLow(14, forItem: first)
        draft.setRest(100, forItem: first)
        draft.removeItem(id: draft.items[3].id)
        draft.moveItems(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        draft.addExercises([(id: squat.id, name: squat.name)])

        let routine = try draft.apply(in: context, now: t1)
        try context.save()

        #expect(routine === push)
        #expect(push.name == "Push Day")
        #expect(push.notes == "Pause on the chest.")
        #expect(push.updatedAt == t1)
        #expect(push.sortedItems.map { $0.exercise?.name } == [
            "Overhead Press", "Incline Dumbbell Press", "Triceps Pushdown", "Bench Press", "Squat",
        ])
        #expect(push.sortedItems.map(\.order) == [0, 1, 2, 3, 4])
        let bench = push.sortedItems[3]
        #expect(bench.id == first)
        #expect(bench.targetSets == 5)
        #expect(bench.repLow == 14 && bench.repHigh == 14)
        #expect(bench.restSeconds == 105)
        #expect(try context.count(RoutineItem.self) == 15)
    }

    @Test func newDraftCreatesARoutine() throws {
        let (context, _) = try seeded()
        let bench = try exercise(named: "Bench Press", in: context)
        var draft = RoutineDraft()
        #expect(!draft.canSave)
        draft.name = "Upper"
        #expect(draft.canSave)
        draft.addExercises([(id: bench.id, name: bench.name)])
        draft.setRepHigh(6, forItem: draft.items[0].id)

        let routine = try draft.apply(in: context, now: t1)

        #expect(routine.name == "Upper")
        #expect(routine.sortIndex == 3)
        #expect(routine.seedKey == nil)
        #expect(routine.sortedItems.first?.repLow == 6)
        #expect(routine.sortedItems.first?.repHigh == 6)
    }

    @Test func alternativesAreValidatedAndAppliedToTheExercise() throws {
        let (context, push) = try seeded()
        let bench = try exercise(named: "Bench Press", in: context)
        let names = ["Dumbbell Bench Press", "Machine Chest Press", "Push-up", "Chest Dip", "Pec Deck"]
        let candidates = try names.map { try exercise(named: $0, in: context) }
        var draft = RoutineDraft(routine: push)
        #expect(draft.alternatives(of: bench.id, current: []) == [])
        draft.setAlternatives([bench.id] + candidates.map(\.id) + [candidates[0].id], of: bench.id)
        #expect(draft.alternatives(of: bench.id, current: []) == candidates.prefix(4).map(\.id))
        #expect(bench.alternatives?.isEmpty ?? true)

        try draft.apply(in: context, now: t1)

        #expect(Set(bench.alternatives?.map(\.id) ?? []) == Set(candidates.prefix(4).map(\.id)))
        #expect(bench.updatedAt == t1)
    }

    @Test func applyingFailsIfTheRoutineWasDeleted() throws {
        let (context, push) = try seeded()
        let draft = RoutineDraft(routine: push)
        context.delete(push)
        try context.save()
        #expect(throws: RoutineDraft.ApplyError.routineMissing) {
            try draft.apply(in: context, now: t1)
        }
    }

    @Test func unchangedDraftLeavesTheRoutineUntouched() throws {
        let (context, push) = try seeded()
        try RoutineDraft(routine: push).apply(in: context, now: t1)
        #expect(push.updatedAt == t0)
        #expect(push.sortedItems.allSatisfy { $0.updatedAt == t0 })
    }
}
