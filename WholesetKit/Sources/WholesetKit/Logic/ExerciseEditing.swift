// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Changes to an exercise's per-exercise settings. Each one sets `updatedAt` when it
/// changes something (sync merges duplicates by it). None of them saves: the caller saves.
public enum ExerciseEditing {
    /// Sets the equipment type, which decides the default progression step.
    public static func setEquipment(_ equipment: Equipment, on exercise: Exercise, now: Date = .now) {
        guard exercise.equipmentRaw != equipment.rawValue else { return }
        exercise.equipment = equipment
        exercise.updatedAt = now
    }

    /// Sets the exercise's own progression step in kilograms; `nil` (or a value that is not
    /// positive and finite) uses the default for its equipment.
    public static func setProgressionStep(kilograms: Double?, on exercise: Exercise, now: Date = .now) {
        let step = kilograms.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        guard step != exercise.progressionStepKg else { return }
        exercise.progressionStepKg = step
        exercise.updatedAt = now
    }

    /// Sets the exercise's default rest; `nil` uses the app setting. Other values are
    /// rounded and limited like routine rest (see ``RoutineRules/normalizedRest(_:)``).
    public static func setDefaultRest(_ seconds: Int?, on exercise: Exercise, now: Date = .now) {
        let rest = RoutineRules.normalizedRest(seconds)
        guard rest != exercise.defaultRestSeconds else { return }
        exercise.defaultRestSeconds = rest
        exercise.updatedAt = now
    }
}
