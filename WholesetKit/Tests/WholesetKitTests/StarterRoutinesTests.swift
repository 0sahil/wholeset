// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Starter routines")
struct StarterRoutinesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func seedsPushPullLegsInOrderAndRecordsTheDecision() throws {
        let context = try makeInMemoryContext()
        let created = try StarterRoutines.seed(in: context, now: now)
        #expect(created.count == 3)
        let routines = TodayPlanResolver.sortedRoutines(try context.all(Routine.self))
        #expect(routines.map(\.name) == ["Push", "Pull", "Legs"])
        #expect(routines.map(\.sortIndex) == [0, 1, 2])
        #expect(routines.map(\.seedKey) == ["starter.push", "starter.pull", "starter.legs"])
        #expect(routines.allSatisfy { $0.createdAt == now && $0.updatedAt == now })
        #expect(try AppSettings.current(in: context).starterRoutinesDecidedAt == now)
        #expect(!context.hasChanges)
    }

    @Test func templatesHaveRealisticTargetsAndUniqueKeys() {
        #expect(StarterRoutines.templates.count == 3)
        #expect(Set(StarterRoutines.templates.map(\.key)).count == 3)
        for template in StarterRoutines.templates {
            #expect(StarterRoutines.template(forKey: template.key) == template)
            #expect((4...6).contains(template.items.count))
            for item in template.items {
                #expect((2...5).contains(item.sets))
                #expect(item.repLow >= 1 && item.repLow <= item.repHigh && item.repHigh <= 20)
                #expect((30...300).contains(item.restSeconds))
                #expect(RoutineRules.normalizedRest(item.restSeconds) == item.restSeconds)
            }
        }
        let names = StarterRoutines.templates.flatMap(\.items).map(\.exerciseName)
        #expect(names.contains("Bench Press"))
        #expect(names.contains("Lat Pulldown"))
        #expect(Set(names.map { $0.lowercased() }).count == names.count)
    }

    @Test func itemsCarryTemplateValuesAndLibraryExercises() throws {
        let context = try makeInMemoryContext()
        try StarterRoutines.seed(in: context, now: now)
        let routines = TodayPlanResolver.sortedRoutines(try context.all(Routine.self))
        for (routine, template) in zip(routines, StarterRoutines.templates) {
            let items = routine.sortedItems
            #expect(items.count == template.items.count)
            for (item, spec) in zip(items, template.items) {
                #expect(item.exercise?.name == spec.exerciseName)
                #expect(item.exercise?.equipment == spec.equipment)
                #expect(item.exercise?.primaryMuscle == spec.muscle)
                #expect(item.exercise?.isCustom == false)
                #expect(item.exercise?.libraryKey != nil)
                #expect(item.targetSets == spec.sets)
                #expect(item.repLow == spec.repLow)
                #expect(item.repHigh == spec.repHigh)
                #expect(item.restSeconds == spec.restSeconds)
            }
        }
        let itemCount = StarterRoutines.templates.reduce(0) { $0 + $1.items.count }
        #expect(try context.count(Exercise.self) == itemCount)
    }

    @Test func seedingAgainAfterTheDecisionAddsPlainRoutines() throws {
        let context = try makeInMemoryContext()
        try StarterRoutines.seed(in: context, now: now)
        let exercises = try context.count(Exercise.self)
        let again = try StarterRoutines.seed(in: context, now: now.addingTimeInterval(60))
        #expect(again.allSatisfy { $0.seedKey == nil })
        #expect(again.map(\.sortIndex) == [3, 4, 5])
        #expect(try context.count(Routine.self) == 6)
        #expect(try context.count(Exercise.self) == exercises)
        #expect(try AppSettings.current(in: context).starterRoutinesDecidedAt == now)
    }

    @Test func reusesExistingExercisesIgnoringCase() throws {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "  bench press ", equipment: .barbell, primaryMuscle: .chest, isCustom: true)
        let pulldown = Exercise(name: "LAT PULLDOWN", equipment: .machine)
        context.insertAll(bench, pulldown)
        try context.save()

        try StarterRoutines.seed(in: context, now: now)

        let benches = try context.all(Exercise.self).filter { ExerciseName.normalized($0.name) == "bench press" }
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

        try StarterRoutines.seed(in: context, now: now)

        #expect(active.routineItems?.count == 1)
        #expect(archived.routineItems?.isEmpty ?? true)
    }

    @Test func recognisesRoutinesSeededByTheFirstRelease() throws {
        let context = try makeInMemoryContext()
        try StarterRoutines.seed(in: context, now: now)
        let push = try #require(try context.all(Routine.self).first { $0.name == "Push" })
        let template = try #require(StarterRoutines.template(forKey: "starter.push"))
        #expect(!StarterRoutines.isLegacyCopy(push, of: template))
        push.seedKey = nil
        #expect(StarterRoutines.isLegacyCopy(push, of: template))
        let other = Exercise(name: "Something Else")
        context.insert(other)
        push.sortedItems.last?.exercise = other
        #expect(!StarterRoutines.isLegacyCopy(push, of: template))
    }
}
