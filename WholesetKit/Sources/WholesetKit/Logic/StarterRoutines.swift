// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// A small push/pull/legs split, so the Watch has something to start before any routine
/// has been made on iPhone.
///
/// Which device creates them, and when, is decided by ``StarterSeedGate`` and
/// ``StoreMaintenance``; this type only knows how to create them.
public enum StarterRoutines {
    /// One exercise slot of a starter routine.
    public struct Item: Sendable, Equatable {
        public let exerciseName: String
        public let equipment: Equipment
        public let muscle: Muscle
        public let sets: Int
        public let repLow: Int
        public let repHigh: Int
        public let restSeconds: Int
    }

    /// A starter routine definition.
    public struct Template: Sendable, Equatable {
        /// Stable identifier stored in `Routine.seedKey`, so copies seeded on two devices
        /// can be recognised as the same routine.
        public let key: String
        public let name: String
        public let items: [Item]
    }

    /// The starter routines, in list order. Every exercise name is a library exercise name.
    public static let templates: [Template] = [
        Template(key: "starter.push", name: "Push", items: [
            Item(exerciseName: "Bench Press", equipment: .barbell, muscle: .chest, sets: 3, repLow: 6, repHigh: 10, restSeconds: 150),
            Item(exerciseName: "Overhead Press", equipment: .barbell, muscle: .shoulders, sets: 3, repLow: 6, repHigh: 10, restSeconds: 120),
            Item(exerciseName: "Incline Dumbbell Press", equipment: .dumbbell, muscle: .chest, sets: 3, repLow: 8, repHigh: 12, restSeconds: 90),
            Item(exerciseName: "Lateral Raise", equipment: .dumbbell, muscle: .shoulders, sets: 3, repLow: 12, repHigh: 15, restSeconds: 60),
            Item(exerciseName: "Triceps Pushdown", equipment: .cable, muscle: .triceps, sets: 3, repLow: 10, repHigh: 15, restSeconds: 60),
        ]),
        Template(key: "starter.pull", name: "Pull", items: [
            Item(exerciseName: "Pull-up", equipment: .bodyweight, muscle: .lats, sets: 3, repLow: 5, repHigh: 10, restSeconds: 120),
            Item(exerciseName: "Barbell Row", equipment: .barbell, muscle: .middleBack, sets: 3, repLow: 6, repHigh: 10, restSeconds: 120),
            Item(exerciseName: "Lat Pulldown", equipment: .cable, muscle: .lats, sets: 3, repLow: 8, repHigh: 12, restSeconds: 90),
            Item(exerciseName: "Face Pull", equipment: .cable, muscle: .shoulders, sets: 3, repLow: 12, repHigh: 15, restSeconds: 60),
            Item(exerciseName: "Dumbbell Curl", equipment: .dumbbell, muscle: .biceps, sets: 3, repLow: 8, repHigh: 12, restSeconds: 60),
        ]),
        Template(key: "starter.legs", name: "Legs", items: [
            Item(exerciseName: "Squat", equipment: .barbell, muscle: .quadriceps, sets: 3, repLow: 5, repHigh: 8, restSeconds: 180),
            Item(exerciseName: "Romanian Deadlift", equipment: .barbell, muscle: .hamstrings, sets: 3, repLow: 8, repHigh: 10, restSeconds: 120),
            Item(exerciseName: "Leg Press", equipment: .machine, muscle: .quadriceps, sets: 3, repLow: 10, repHigh: 12, restSeconds: 120),
            Item(exerciseName: "Leg Curl", equipment: .machine, muscle: .hamstrings, sets: 3, repLow: 10, repHigh: 12, restSeconds: 90),
            Item(exerciseName: "Standing Calf Raise", equipment: .machine, muscle: .calves, sets: 4, repLow: 10, repHigh: 15, restSeconds: 60),
        ]),
    ]

    /// The template with `key`, if any.
    public static func template(forKey key: String) -> Template? {
        templates.first { $0.key == key }
    }

    /// Creates the three starter routines after any existing routines, then saves.
    ///
    /// If the account has not yet decided about starter routines
    /// (`AppSettings.starterRoutinesDecidedAt` is `nil`), this *is* the decision: the
    /// routines get their template's `seedKey` and the decision is recorded at `now`, so
    /// copies seeded on another device before sync are merged later. Once the account has
    /// decided, the routines are plain user routines (no `seedKey`) that sync never merges
    /// or removes: that is the iPhone's explicit "add them again" action.
    ///
    /// Exercises are looked up by name (ignoring case and spacing), preferring library
    /// exercises and active over archived ones; a missing one is created, from `library`
    /// when it has that name.
    ///
    /// - Returns: The created routines, in list order.
    @discardableResult
    public static func seed(in context: ModelContext, library: ExerciseLibrary? = nil, now: Date = .now) throws -> [Routine] {
        let settings = try AppSettings.current(in: context)
        let isDecision = settings.starterRoutinesDecidedAt == nil
        let library = library ?? (try? ExerciseLibrary.bundled())
        let existingRoutines = try context.fetch(FetchDescriptor<Routine>())
        let firstIndex = (existingRoutines.map(\.sortIndex).max() ?? -1) + 1

        var exercisesByName = try existingExercisesByName(in: context)
        var created: [Routine] = []
        for (index, template) in templates.enumerated() {
            let routine = Routine(name: template.name, sortIndex: firstIndex + index)
            routine.createdAt = now
            routine.updatedAt = now
            routine.seedKey = isDecision ? template.key : nil
            context.insert(routine)
            for (order, spec) in template.items.enumerated() {
                let key = ExerciseName.normalized(spec.exerciseName)
                let exercise: Exercise
                if let existing = exercisesByName[key] {
                    exercise = existing
                } else {
                    exercise = makeExercise(for: spec, library: library, now: now)
                    context.insert(exercise)
                    exercisesByName[key] = exercise
                }
                let item = RoutineItem(
                    order: order,
                    targetSets: spec.sets,
                    repLow: spec.repLow,
                    repHigh: spec.repHigh,
                    restSeconds: spec.restSeconds
                )
                item.createdAt = now
                item.updatedAt = now
                context.insert(item)
                item.routine = routine
                item.exercise = exercise
            }
            created.append(routine)
        }
        if isDecision {
            settings.starterRoutinesDecidedAt = now
        }
        try context.save()
        return created
    }

    private static func makeExercise(for spec: Item, library: ExerciseLibrary?, now: Date) -> Exercise {
        let entry = library?.entry(named: spec.exerciseName)
        let exercise = Exercise(
            name: entry?.name ?? spec.exerciseName,
            equipment: entry?.equipment ?? spec.equipment,
            primaryMuscle: entry?.muscle ?? spec.muscle
        )
        exercise.libraryKey = entry?.key
        exercise.aliases = entry?.aliases ?? []
        exercise.createdAt = now
        exercise.updatedAt = now
        return exercise
    }

    private static func existingExercisesByName(in context: ModelContext) throws -> [String: Exercise] {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var byName: [String: Exercise] = [:]
        for exercise in exercises {
            let key = ExerciseName.normalized(exercise.name)
            guard !key.isEmpty else { continue }
            if let current = byName[key], !isBetterMatch(exercise, than: current) { continue }
            byName[key] = exercise
        }
        return byName
    }

    /// Prefers active over archived, then library over custom, then the oldest, then the lowest `id`.
    static func isBetterMatch(_ lhs: Exercise, than rhs: Exercise) -> Bool {
        if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
        if (lhs.libraryKey != nil) != (rhs.libraryKey != nil) { return lhs.libraryKey != nil }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Whether `routine` is exactly what an earlier app version seeded for `template`:
    /// same name and the same exercises in the same order, with no seed key yet.
    static func isLegacyCopy(_ routine: Routine, of template: Template) -> Bool {
        guard routine.seedKey == nil,
              ExerciseName.normalized(routine.name) == ExerciseName.normalized(template.name) else { return false }
        let names = routine.sortedItems.map { ExerciseName.normalized($0.exercise?.name ?? "") }
        return names == template.items.map { ExerciseName.normalized($0.exerciseName) }
    }
}
