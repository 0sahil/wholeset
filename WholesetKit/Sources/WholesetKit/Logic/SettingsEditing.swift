// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension WeightUnit {
    /// The unit to suggest for someone in `locale`'s region: pounds where the US
    /// customary system is used, kilograms everywhere else, including the UK (whose
    /// gyms mostly label plates and dumbbells in kilograms).
    public static func preferred(for locale: Locale) -> WeightUnit {
        locale.measurementSystem == .us ? .lb : .kg
    }
}

/// Changes to the settings row. Each one sets `updatedAt`, which is what makes a change
/// win over a never-edited row when sync merges duplicates.
///
/// None of them saves: the caller saves.
public enum SettingsEditing {
    /// Allowed default rest, in seconds.
    public static let defaultRestRange = RoutineRules.restRange

    /// Sets the weight unit.
    ///
    /// - Parameter isExplicitChoice: Mark the row edited even if the unit is unchanged. First
    ///   launch uses it: picking the default unit is still a choice that must win over
    ///   another device's untouched default row.
    public static func setUnit(_ unit: WeightUnit, on settings: AppSettings, now: Date = .now, isExplicitChoice: Bool = false) {
        guard isExplicitChoice || settings.unitRaw != unit.rawValue else { return }
        settings.unit = unit
        settings.updatedAt = now
    }

    /// Sets the default rest, rounded to 15 s steps within 15 s…10 min.
    public static func setDefaultRest(_ seconds: Int, on settings: AppSettings, now: Date = .now) {
        let rest = RoutineRules.normalizedRest(seconds) ?? RestTimer.fallbackSeconds
        guard rest != settings.defaultRestSeconds else { return }
        settings.defaultRestSeconds = rest
        settings.updatedAt = now
    }

    /// Sets how fast the Watch's Crown changes the weight tile.
    public static func setWeightCrownSensitivity(_ sensitivity: CrownSensitivity, on settings: AppSettings, now: Date = .now) {
        guard settings.weightCrownSensitivityRaw != sensitivity.rawValue else { return }
        settings.weightCrownSensitivity = sensitivity
        settings.updatedAt = now
    }

    /// Sets how fast the Watch's Crown changes the reps tile.
    public static func setRepsCrownSensitivity(_ sensitivity: CrownSensitivity, on settings: AppSettings, now: Date = .now) {
        guard settings.repsCrownSensitivityRaw != sensitivity.rawValue else { return }
        settings.repsCrownSensitivity = sensitivity
        settings.updatedAt = now
    }

    /// Sets the user's default progression step for `equipment`.
    ///
    /// `nil`, an invalid value, or the built-in default for the current unit removes the
    /// user's step, so the equipment follows the built-in default (which changes with the
    /// unit). Bodyweight has no step and is ignored.
    public static func setProgressionStep(kilograms: Double?, for equipment: Equipment, on settings: AppSettings, now: Date = .now) {
        guard equipment != .bodyweight else { return }
        var steps = settings.progressionSteps
        let builtIn = ProgressionStep.builtInDefault(for: equipment, unit: settings.unit)
        if let kilograms, ProgressionStep.isValid(kilograms, for: equipment),
           !(builtIn.map { ProgressionStep.isSame($0, kilograms) } ?? false) {
            steps[equipment] = kilograms
        } else {
            steps[equipment] = nil
        }
        let raw = ProgressionStepList.encode(steps)
        guard raw != settings.progressionStepsRaw else { return }
        settings.progressionStepsRaw = raw
        settings.updatedAt = now
    }
}
