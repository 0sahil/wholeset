// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Exercise catalog")
struct ExerciseCatalogTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeExercises(in context: ModelContext) -> [Exercise] {
        let specs: [(String, Equipment, Muscle, [String])] = [
            ("Bench Press", .barbell, .chest, ["Bench Press (Barbell)"]),
            ("Dumbbell Curl", .dumbbell, .biceps, ["Bicep Curl (Dumbbell)"]),
            ("Lat Pulldown", .cable, .lats, []),
            ("Leg Press", .machine, .quadriceps, []),
            ("Crunch", .bodyweight, .abdominals, []),
            ("Neck Curl", .other, .neck, []),
        ]
        return specs.map { name, equipment, muscle, aliases in
            let exercise = Exercise(name: name, equipment: equipment, primaryMuscle: muscle)
            exercise.aliases = aliases
            context.insert(exercise)
            return exercise
        }
    }

    @Test func everyMuscleBelongsToExactlyOneGroup() {
        for muscle in Muscle.allCases {
            let groups = MuscleGroup.allCases.filter { $0.muscles.contains(muscle) }
            #expect(groups == [MuscleGroup(muscle)])
        }
        #expect(MuscleGroup(.lats) == .back)
        #expect(MuscleGroup(.glutes) == .legs)
        #expect(MuscleGroup(.forearms) == .arms)
        #expect(MuscleGroup(.abdominals) == .core)
    }

    @Test func filtersBySearchGroupEquipmentAndArchive() throws {
        let context = try makeInMemoryContext()
        let all = makeExercises(in: context)
        all[3].isArchived = true

        func names(_ filter: ExerciseCatalog.Filter) -> [String] {
            ExerciseCatalog.filtered(all, by: filter).map(\.name)
        }

        #expect(names(.init()) == ["Bench Press", "Crunch", "Dumbbell Curl", "Lat Pulldown", "Neck Curl"])
        #expect(names(.init(includesArchived: true)).count == 6)
        #expect(names(.init(searchText: "curl")) == ["Dumbbell Curl", "Neck Curl"])
        #expect(names(.init(searchText: "bicep")) == ["Dumbbell Curl"])
        #expect(names(.init(searchText: "BARBELL bench")) == ["Bench Press"])
        #expect(names(.init(searchText: "  ")).count == 5)
        #expect(names(.init(group: .back)) == ["Lat Pulldown"])
        #expect(names(.init(group: .legs)) == [])
        #expect(names(.init(group: .legs, includesArchived: true)) == ["Leg Press"])
        #expect(names(.init(equipment: .dumbbell)) == ["Dumbbell Curl"])
        #expect(names(.init(searchText: "curl", group: .other)) == ["Neck Curl"])
    }

    @Test func newNamesMustBeUniqueIgnoringCaseAndSpacing() throws {
        let context = try makeInMemoryContext()
        let all = makeExercises(in: context)
        all[4].isArchived = true
        #expect(ExerciseCatalog.validateNewName("   ", existing: all) == .failure(.empty))
        #expect(ExerciseCatalog.validateNewName(" bench  press", existing: all) == .failure(.duplicate(existingName: "Bench Press", isArchived: false)))
        #expect(ExerciseCatalog.validateNewName("CRUNCH", existing: all) == .failure(.duplicate(existingName: "Crunch", isArchived: true)))
        #expect(ExerciseCatalog.validateNewName("  Zercher Squat ", existing: all) == .success("Zercher Squat"))
    }

    @Test func createsCustomExercisesAfterCheckingTheStore() throws {
        let context = try makeInMemoryContext()
        _ = makeExercises(in: context)
        let created = try ExerciseCatalog.createCustomExercise(named: " Zercher Squat ", equipment: .barbell, muscle: .quadriceps, in: context, now: t0)
        #expect(created.name == "Zercher Squat")
        #expect(created.isCustom)
        #expect(created.libraryKey == nil)
        #expect(created.equipment == .barbell && created.primaryMuscle == .quadriceps)
        #expect(created.createdAt == t0)
        #expect(throws: ExerciseCatalog.NameProblem.duplicate(existingName: "Zercher Squat", isArchived: false)) {
            try ExerciseCatalog.createCustomExercise(named: "zercher squat", equipment: .barbell, muscle: .quadriceps, in: context)
        }
    }

    @Test func archivingTouchesTheExerciseOnlyWhenItChanges() throws {
        let context = try makeInMemoryContext()
        let exercise = try ExerciseCatalog.createCustomExercise(named: "Zercher Squat", equipment: .barbell, muscle: .quadriceps, in: context, now: t0)
        let later = t0.addingTimeInterval(60)
        ExerciseCatalog.setArchived(false, exercise, now: later)
        #expect(exercise.updatedAt == t0)
        ExerciseCatalog.setArchived(true, exercise, now: later)
        #expect(exercise.isArchived)
        #expect(exercise.updatedAt == later)
    }
}
