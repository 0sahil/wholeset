// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// A small push/pull/legs split created on first launch, so the Watch has something
/// to start before any routine has been made on iPhone.
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
        public let name: String
        public let items: [Item]
    }

    /// The routines created by ``seedIfNeeded(in:)``, in list order.
    public static let templates: [Template] = [
        Template(name: "Push", items: [
            Item(exerciseName: "Bench Press", equipment: .barbell, muscle: .chest, sets: 3, repLow: 6, repHigh: 10, restSeconds: 150),
            Item(exerciseName: "Overhead Press", equipment: .barbell, muscle: .shoulders, sets: 3, repLow: 6, repHigh: 10, restSeconds: 120),
            Item(exerciseName: "Incline Dumbbell Press", equipment: .dumbbell, muscle: .chest, sets: 3, repLow: 8, repHigh: 12, restSeconds: 90),
            Item(exerciseName: "Lateral Raise", equipment: .dumbbell, muscle: .shoulders, sets: 3, repLow: 12, repHigh: 15, restSeconds: 60),
            Item(exerciseName: "Triceps Pushdown", equipment: .cable, muscle: .triceps, sets: 3, repLow: 10, repHigh: 15, restSeconds: 60),
        ]),
        Template(name: "Pull", items: [
            Item(exerciseName: "Pull-up", equipment: .bodyweight, muscle: .lats, sets: 3, repLow: 5, repHigh: 10, restSeconds: 120),
            Item(exerciseName: "Barbell Row", equipment: .barbell, muscle: .middleBack, sets: 3, repLow: 6, repHigh: 10, restSeconds: 120),
            Item(exerciseName: "Lat Pulldown", equipment: .cable, muscle: .lats, sets: 3, repLow: 8, repHigh: 12, restSeconds: 90),
            Item(exerciseName: "Face Pull", equipment: .cable, muscle: .shoulders, sets: 3, repLow: 12, repHigh: 15, restSeconds: 60),
            Item(exerciseName: "Dumbbell Curl", equipment: .dumbbell, muscle: .biceps, sets: 3, repLow: 8, repHigh: 12, restSeconds: 60),
        ]),
        Template(name: "Legs", items: [
            Item(exerciseName: "Squat", equipment: .barbell, muscle: .quadriceps, sets: 3, repLow: 5, repHigh: 8, restSeconds: 180),
            Item(exerciseName: "Romanian Deadlift", equipment: .barbell, muscle: .hamstrings, sets: 3, repLow: 8, repHigh: 10, restSeconds: 120),
            Item(exerciseName: "Leg Press", equipment: .machine, muscle: .quadriceps, sets: 3, repLow: 10, repHigh: 12, restSeconds: 120),
            Item(exerciseName: "Leg Curl", equipment: .machine, muscle: .hamstrings, sets: 3, repLow: 10, repHigh: 12, restSeconds: 90),
            Item(exerciseName: "Standing Calf Raise", equipment: .machine, muscle: .calves, sets: 4, repLow: 10, repHigh: 15, restSeconds: 60),
        ]),
    ]

    /// Creates the starter routines if the store has no routine at all, then saves.
    ///
    /// Idempotent: once any routine exists (seeded, user-made or synced), it does nothing.
    /// Exercises are matched by name, ignoring case and surrounding whitespace, and reused
    /// rather than duplicated; an active exercise is preferred over an archived one.
    ///
    /// - Returns: `true` if routines were created.
    @discardableResult
    public static func seedIfNeeded(in context: ModelContext) throws -> Bool {
        guard try context.fetchCount(FetchDescriptor<Routine>()) == 0 else { return false }

        var exercisesByName = try existingExercisesByName(in: context)
        for (index, template) in templates.enumerated() {
            let routine = Routine(name: template.name, sortIndex: index)
            context.insert(routine)
            for (order, spec) in template.items.enumerated() {
                let key = normalizedName(spec.exerciseName)
                let exercise: Exercise
                if let existing = exercisesByName[key] {
                    exercise = existing
                } else {
                    exercise = Exercise(name: spec.exerciseName, equipment: spec.equipment, primaryMuscle: spec.muscle)
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
                context.insert(item)
                item.routine = routine
                item.exercise = exercise
            }
        }
        try context.save()
        return true
    }

    /// Lower-cased name with surrounding whitespace removed, used to match exercises.
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func existingExercisesByName(in context: ModelContext) throws -> [String: Exercise] {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var byName: [String: Exercise] = [:]
        for exercise in exercises {
            let key = normalizedName(exercise.name)
            guard !key.isEmpty else { continue }
            if let current = byName[key], !isBetterMatch(exercise, than: current) { continue }
            byName[key] = exercise
        }
        return byName
    }

    /// Prefers active over archived, then the oldest, then the lowest `id`.
    private static func isBetterMatch(_ lhs: Exercise, than rhs: Exercise) -> Bool {
        if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
