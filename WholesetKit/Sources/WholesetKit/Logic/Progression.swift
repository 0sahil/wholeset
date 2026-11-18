// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Progression steps: how much weight the progression hint adds.
public enum ProgressionStep {
    /// The built-in step for `equipment` in kilograms, chosen as a round number in `unit`
    /// (2.5 kg for a barbell, or 5 lb converted exactly for pound users). `nil` for
    /// bodyweight, which adds a rep instead of weight.
    public static func builtInDefault(for equipment: Equipment, unit: WeightUnit) -> Double? {
        let value: Double
        switch (equipment, unit) {
        case (.bodyweight, _): return nil
        case (.barbell, .kg), (.other, .kg): value = 2.5
        case (.dumbbell, .kg): value = 2
        case (.machine, .kg), (.cable, .kg): value = 5
        case (.barbell, .lb), (.dumbbell, .lb), (.other, .lb): value = 5
        case (.machine, .lb), (.cable, .lb): value = 10
        }
        return unit.kilograms(fromValue: value)
    }

    /// Whether `kilograms` can be stored as a step for `equipment`: positive, finite and not
    /// for bodyweight.
    public static func isValid(_ kilograms: Double, for equipment: Equipment) -> Bool {
        equipment != .bodyweight && kilograms.isFinite && kilograms > 0
    }

    /// Whether two steps are the same (they may have been converted from pounds).
    public static func isSame(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-6
    }
}

/// The settings the progression hint depends on, as a small value the Watch can hand to
/// the workout engine and refresh when settings change.
public struct ProgressionSettings: Equatable, Sendable {
    /// The display unit; the built-in steps follow it.
    public var unit: WeightUnit
    /// The user's own step per equipment, in kilograms.
    public var stepsKg: [Equipment: Double]

    /// Creates progression settings.
    public init(unit: WeightUnit = .kg, stepsKg: [Equipment: Double] = [:]) {
        self.unit = unit
        self.stepsKg = stepsKg
    }

    /// Reads the values from the settings row.
    public init(_ settings: AppSettings) {
        self.init(unit: settings.unit, stepsKg: settings.progressionSteps)
    }

    /// The step for `equipment` without an exercise override: the user's step, else the
    /// built-in default. `nil` for bodyweight.
    public func defaultStep(for equipment: Equipment) -> Double? {
        guard equipment != .bodyweight else { return nil }
        if let own = stepsKg[equipment], ProgressionStep.isValid(own, for: equipment) { return own }
        return ProgressionStep.builtInDefault(for: equipment, unit: unit)
    }

    /// The step for an exercise: its own step if it has a valid one, else
    /// ``defaultStep(for:)``. `nil` for bodyweight.
    public func step(for equipment: Equipment, exerciseStepKg: Double?) -> Double? {
        guard equipment != .bodyweight else { return nil }
        if let own = exerciseStepKg, ProgressionStep.isValid(own, for: equipment) { return own }
        return defaultStep(for: equipment)
    }
}

/// What the progression chip suggests for the remaining working sets.
public struct ProgressionHint: Equatable, Sendable {
    /// The suggested weight in kilograms; `nil` for a bodyweight exercise done without weight.
    public let weightKg: Double?
    /// The suggested reps.
    public let reps: Int

    /// Creates a hint.
    public init(weightKg: Double?, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }

    /// The hint as set values.
    public var values: SetValues { SetValues(weightKg: weightKg, reps: reps) }
}

/// Double progression: once every working set reached the top of the rep range at one
/// weight, suggest more weight and the bottom of the range.
public enum Progression {
    /// The hint for an exercise, or `nil` when the rule does not fire.
    ///
    /// Fires when the last performance has at least one working set (warm-ups never count),
    /// every working set has reps ≥ `repHigh`, and all working sets used one weight. Then:
    /// - with weight equipment, suggests that weight + `stepKg` at `repLow` reps (no hint
    ///   without a recorded weight or a step);
    /// - for bodyweight, suggests the same weight at the lowest reps of last time + 1.
    ///
    /// - Parameters:
    ///   - last: The exercise's last performance.
    ///   - repLow: Bottom of today's rep range; `repHigh` is used when it is missing.
    ///   - repHigh: Top of today's rep range; without it the rule never fires.
    ///   - equipment: The exercise's equipment.
    ///   - stepKg: The step to add (see ``ProgressionSettings/step(for:exerciseStepKg:)``).
    public static func hint(
        last: LastPerformance?,
        repLow: Int?,
        repHigh: Int?,
        equipment: Equipment,
        stepKg: Double?
    ) -> ProgressionHint? {
        guard let working = last?.workingSets, let first = working.first, let repHigh else { return nil }
        var lowestReps = Int.max
        for set in working {
            guard let reps = set.reps, reps >= repHigh else { return nil }
            lowestReps = min(lowestReps, reps)
            guard sameWeight(set.weightKg, first.weightKg) else { return nil }
        }
        if equipment == .bodyweight {
            return ProgressionHint(weightKg: first.weightKg, reps: lowestReps + 1)
        }
        guard let weight = first.weightKg, let stepKg, stepKg > 0, stepKg.isFinite else { return nil }
        return ProgressionHint(weightKg: weight + stepKg, reps: repLow ?? repHigh)
    }

    private static func sameWeight(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (l?, r?): abs(l - r) < Prefill.weightTolerance
        default: false
        }
    }
}

/// The steps the iPhone pickers offer, per display unit.
public enum ProgressionStepChoices {
    /// The choices in `unit` itself (for example 2.5 meaning 2.5 kg).
    public static func values(for unit: WeightUnit) -> [Double] {
        switch unit {
        case .kg: [0.5, 1, 1.25, 2, 2.5, 5, 7.5, 10]
        case .lb: [1, 2, 2.5, 5, 10, 15, 20]
        }
    }

    /// The choices converted to kilograms, in the same order.
    public static func kilograms(for unit: WeightUnit) -> [Double] {
        values(for: unit).map(unit.kilograms(fromValue:))
    }

    /// The choice (in kilograms) equal to `kilograms`, if there is one.
    public static func matching(_ kilograms: Double, unit: WeightUnit) -> Double? {
        Self.kilograms(for: unit).first { ProgressionStep.isSame($0, kilograms) }
    }

    /// The options for a picker in kilograms, ascending: the unit's choices, plus `current`
    /// when it is not one of them (for example a step chosen in the other unit), so the
    /// picker can always show the stored value.
    public static func options(for unit: WeightUnit, including current: Double?) -> [Double] {
        var options = kilograms(for: unit)
        if let current, current.isFinite, current > 0, matching(current, unit: unit) == nil {
            options.append(current)
            options.sort()
        }
        return options
    }

    /// `kilograms` as the picker tag to select: the matching choice, so floating-point noise
    /// from conversions never leaves a picker without a selection.
    public static func tag(for kilograms: Double, unit: WeightUnit) -> Double {
        matching(kilograms, unit: unit) ?? kilograms
    }
}
