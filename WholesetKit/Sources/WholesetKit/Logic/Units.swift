// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension WeightUnit {
    /// Kilograms in one international avoirdupois pound. Exact by definition.
    public static let kilogramsPerPound = 0.45359237

    /// The default amount one Crown detent changes a weight by, in this unit.
    public var inputStep: Double {
        switch self {
        case .kg: 0.5
        case .lb: 1
        }
    }

    /// The unit's short label, for example "kg".
    public var symbol: String {
        switch self {
        case .kg: "kg"
        case .lb: "lb"
        }
    }

    /// Converts a weight stored in kilograms to this unit, without rounding.
    public func value(fromKilograms kilograms: Double) -> Double {
        switch self {
        case .kg: kilograms
        case .lb: kilograms / Self.kilogramsPerPound
        }
    }

    /// Converts a weight in this unit to kilograms for storage, without rounding.
    public func kilograms(fromValue value: Double) -> Double {
        switch self {
        case .kg: value
        case .lb: value * Self.kilogramsPerPound
        }
    }
}

/// Maps stored kilograms onto a grid of whole input steps in a display unit, and back.
///
/// The Crown edits a step *index*, never a converted floating-point value, so a weight
/// survives any number of edits and kg/lb round trips without drifting: reading a stored
/// value snaps it to the nearest step, and writing converts that exact step back to kilograms.
public struct WeightScale: Sendable, Equatable {
    /// The heaviest weight the Crown can reach, in kilograms.
    public static let maximumKilograms: Double = 500

    /// The display and input unit.
    public let unit: WeightUnit
    /// The size of one step in ``unit``.
    public let step: Double

    /// Creates a scale for `unit`. `step` defaults to the unit's ``WeightUnit/inputStep``;
    /// non-positive values fall back to that default.
    public init(unit: WeightUnit, step: Double? = nil) {
        self.unit = unit
        if let step, step > 0, step.isFinite {
            self.step = step
        } else {
            self.step = unit.inputStep
        }
    }

    /// The index of the step nearest to `kilograms`. Negative and non-finite input reads as 0.
    public func steps(forKilograms kilograms: Double) -> Int {
        guard kilograms.isFinite, kilograms > 0 else { return 0 }
        let value = unit.value(fromKilograms: kilograms) / step
        return Int(value.rounded(.toNearestOrAwayFromZero))
    }

    /// The weight in kilograms of step `steps` (clamped to `0...maximumSteps`).
    public func kilograms(forSteps steps: Int) -> Double {
        let clamped = min(max(steps, 0), maximumSteps)
        return unit.kilograms(fromValue: Double(clamped) * step)
    }

    /// `kilograms` expressed in ``unit`` and rounded to the nearest step.
    public func displayValue(forKilograms kilograms: Double) -> Double {
        Double(steps(forKilograms: kilograms)) * step
    }

    /// The step index of ``maximumKilograms``.
    public var maximumSteps: Int {
        Int((unit.value(fromKilograms: Self.maximumKilograms) / step).rounded(.down))
    }

    /// Fraction digits needed to show any multiple of ``step`` exactly (0 to 3).
    public var fractionDigits: Int {
        var digits = 0
        var scaled = step
        while digits < 3, abs(scaled - scaled.rounded()) > 1e-9 {
            scaled *= 10
            digits += 1
        }
        return digits
    }
}

/// Formats weights for display. Storage stays in kilograms.
public enum WeightFormat {
    /// A weight rounded to the scale's step, without a trailing ".0" (e.g. "60", "62.5").
    ///
    /// - Parameters:
    ///   - kilograms: The stored weight.
    ///   - scale: The display unit and step.
    ///   - locale: Controls the decimal separator.
    public static func string(kilograms: Double, scale: WeightScale, locale: Locale = .current) -> String {
        let value = scale.displayValue(forKilograms: kilograms)
        return value.formatted(
            .number
                .precision(.fractionLength(0...scale.fractionDigits))
                .grouping(.never)
                .locale(locale)
        )
    }

    /// A weight with its unit label, e.g. "62.5 kg".
    public static func stringWithUnit(kilograms: Double, scale: WeightScale, locale: Locale = .current) -> String {
        "\(string(kilograms: kilograms, scale: scale, locale: locale)) \(scale.unit.symbol)"
    }

    /// A total volume in the scale's unit, rounded to a whole number with grouping (e.g. "6,240").
    public static func volume(kilograms: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        let value = max(0, unit.value(fromKilograms: kilograms)).rounded()
        return value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
}

extension Equipment {
    /// Where the Crown starts when a set has no weight yet, in kilograms; `nil` means the
    /// exercise has no natural starting weight (bodyweight and other), so the Crown starts at 0.
    ///
    /// Values are round numbers in the display unit: an empty bar is 20 kg, or 45 lb for
    /// pound users, rather than a converted 44.1 lb.
    public func startingWeightKilograms(in unit: WeightUnit) -> Double? {
        let value: Double
        switch (self, unit) {
        case (.barbell, .kg), (.machine, .kg), (.cable, .kg): value = 20
        case (.dumbbell, .kg): value = 10
        case (.barbell, .lb), (.machine, .lb), (.cable, .lb): value = 45
        case (.dumbbell, .lb): value = 20
        case (.bodyweight, _), (.other, _): return nil
        }
        return unit.kilograms(fromValue: value)
    }
}
