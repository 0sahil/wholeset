// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Starter routines")
struct StarterRoutinesTests {
    @Test func seedsPushPullLegsInOrder() throws {
        let context = try makeInMemoryContext()
        #expect(try StarterRoutines.seedIfNeeded(in: context))
        let routines = TodayPlanResolver.sortedRoutines(try context.all(Routine.self))
        #expect(routines.map(\.name) == ["Push", "Pull", "Legs"])
        #expect(routines.map(\.sortIndex) == [0, 1, 2])
        #expect(!context.hasChanges)
    }

    @Test func templatesHaveRealisticTargets() {
        #expect(StarterRoutines.templates.count == 3)
        for template in StarterRoutines.templates {
            #expect((4...6).contains(template.items.count))
            for item in template.items {
                #expect((2...5).contains(item.sets))
                #expect(item.repLow >= 1 && item.repLow <= item.repHigh && item.repHigh <= 20)
                #expect((30...300).contains(item.restSeconds))
            }
        }
        let names = StarterRoutines.templates.flatMap(\.items).map(\.exerciseName)
        #expect(names.contains("Bench Press"))
        #expect(names.contains("Lat Pulldown"))
        #expect(Set(names.map { $0.lowercased() }).count == names.count)
    }

    @Test func itemsCarryTemplateValuesAndExercises() throws {
        let context = try makeInMemoryContext()
        try StarterRoutines.seedIfNeeded(in: context)
        let routines = TodayPlanResolver.sortedRoutines(try context.all(Routine.self))
        for (routine, template) in zip(routines, StarterRoutines.templates) {
            let items = routine.sortedItems
            #expect(items.count == template.items.count)
            for (item, spec) in zip(items, template.items) {
                #expect(item.exercise?.name == spec.exerciseName)
                #expect(item.exercise?.equipment == spec.equipment)
                #expect(item.exercise?.primaryMuscle == spec.muscle)
                #expect(item.exercise?.isCustom == false)
                #expect(item.targetSets == spec.sets)
                #expect(item.repLow == spec.repLow)
                #expect(item.repHigh == spec.repHigh)
                #expect(item.restSeconds == spec.restSeconds)
            }
        }
        let itemCount = StarterRoutines.templates.reduce(0) { $0 + $1.items.count }
        #expect(try context.count(Exercise.self) == itemCount)
    }

    @Test func isIdempotent() throws {
        let context = try makeInMemoryContext()
        try StarterRoutines.seedIfNeeded(in: context)
        let exercises = try context.count(Exercise.self)
        #expect(try StarterRoutines.seedIfNeeded(in: context) == false)
        #expect(try context.count(Routine.self) == 3)
        #expect(try context.count(RoutineItem.self) == 15)
        #expect(try context.count(Exercise.self) == exercises)
    }

    @Test func doesNothingWhenAnyRoutineExists() throws {
        let context = try makeInMemoryContext()
        context.insert(Routine(name: "Mine"))
        try context.save()
        #expect(try StarterRoutines.seedIfNeeded(in: context) == false)
        #expect(try context.all(Routine.self).map(\.name) == ["Mine"])
        #expect(try context.count(Exercise.self) == 0)
    }

    @Test func reusesExistingExercisesIgnoringCase() throws {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "  bench press ", equipment: .barbell, primaryMuscle: .chest, isCustom: true)
        let pulldown = Exercise(name: "LAT PULLDOWN", equipment: .machine)
        context.insertAll(bench, pulldown)
        try context.save()

        try StarterRoutines.seedIfNeeded(in: context)

        let benches = try context.all(Exercise.self).filter { StarterRoutines.normalizedName($0.name) == "bench press" }
        #expect(benches.count == 1)
        #expect(benches.first === bench)
        #expect(bench.isCustom)
        #expect(pulldown.routineItems?.count == 1)
        let itemCount = StarterRoutines.templates.reduce(0) { $0 + $1.items.count }
        #expect(try context.count(Exercise.self) == itemCount)
    }

    @Test func prefersActiveOverArchivedMatch() throws {
        let context = try makeInMemoryContext()
        let archived = Exercise(name: "Squat")
        archived.isArchived = true
        archived.createdAt = Date(timeIntervalSince1970: 0)
        let active = Exercise(name: "squat")
        context.insertAll(archived, active)
        try context.save()

        try StarterRoutines.seedIfNeeded(in: context)

        #expect(active.routineItems?.count == 1)
        #expect(archived.routineItems?.isEmpty ?? true)
    }
}
