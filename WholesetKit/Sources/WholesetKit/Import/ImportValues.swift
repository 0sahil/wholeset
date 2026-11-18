// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A field read as a value: empty, a value, or text that is not a valid value.
enum FieldValue<Value: Equatable>: Equatable {
    case empty
    case value(Value)
    case invalid

    /// The value, or `nil` when empty or invalid.
    var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }

    var isInvalid: Bool { self == .invalid }
}

/// Reads numbers, durations and units from export fields.
public enum ImportValues {
    /// A non-negative finite number below ``largestNumber``. Surrounding spaces are ignored and
    /// a decimal comma is accepted when the field holds no other separator (`"34,5"`);
    /// thousands separators, `NaN`, infinities, negative and absurdly large values are invalid.
    public static func number(_ text: String) -> Double? {
        decimal(text).value
    }

    /// Larger values are never weights, reps or durations (and could not become an `Int`).
    public static let largestNumber: Double = 1_000_000_000

    static func decimal(_ text: String) -> FieldValue<Double> {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        let commas = trimmed.count { $0 == "," }
        if commas > 0 {
            guard commas == 1, !trimmed.contains(".") else { return .invalid }
            trimmed = trimmed.replacingOccurrences(of: ",", with: ".")
        }
        guard trimmed.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == "+" || $0 == "e" || $0 == "E" || $0 == "-") }),
              let value = Double(trimmed), value.isFinite, value >= 0, value < largestNumber else { return .invalid }
        return .value(value)
    }

    /// A whole, non-negative count: `"8"`, `" 8"` and `"8.0"` are 8; `"7.5"` is invalid.
    static func count(_ text: String) -> FieldValue<Int> {
        switch decimal(text) {
        case .empty: return .empty
        case .invalid: return .invalid
        case .value(let value):
            guard value == value.rounded(), value < 100_000 else { return .invalid }
            return .value(Int(value))
        }
    }

    /// A rating of perceived exertion in 0...10; anything else reads as absent.
    static func rpe(_ text: String) -> FieldValue<Double> {
        switch decimal(text) {
        case .value(let value) where value > 0 && value <= 10: .value(value)
        case .value: .empty
        case .empty: .empty
        case .invalid: .invalid
        }
    }

    /// A duration in seconds: plain seconds (`"4419"`, `"60.0"`), Strong's `"1h 5m"`, `"35m"`,
    /// `"2h"`, `"38min"`, `"45s"`, or a clock `"H:MM:SS"` / `"MM:SS"`.
    public static func durationSeconds(_ text: String) -> Int? {
        duration(text).value
    }

    static func duration(_ text: String, bareNumberUnit: TimeInterval = 1) -> FieldValue<Int> {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return .empty }
        if case .value(let seconds) = decimal(trimmed) {
            return .value(Int((seconds * bareNumberUnit).rounded()))
        }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            let values = parts.compactMap { $0.count <= 6 ? Int($0) : nil }
            guard (2...3).contains(parts.count), values.count == parts.count, values.allSatisfy({ $0 >= 0 }) else { return .invalid }
            return .value(values.reduce(0) { $0 * 60 + $1 })
        }
        var total = 0
        var digits = ""
        var unit = ""
        var foundAny = false
        func flush() -> Bool {
            guard !digits.isEmpty else { return unit.isEmpty }
            guard digits.count <= 6, let value = Int(digits) else { return false }
            let factor: Int
            switch unit {
            case "h", "hr", "hrs", "hour", "hours": factor = 3_600
            case "m", "min", "mins", "minute", "minutes": factor = 60
            case "s", "sec", "secs", "second", "seconds": factor = 1
            default: return false
            }
            total += value * factor
            foundAny = true
            digits = ""
            unit = ""
            return true
        }
        for character in trimmed {
            if character.isASCII, character.isNumber {
                if !unit.isEmpty { guard flush() else { return .invalid } }
                digits.append(character)
            } else if character.isLetter {
                guard !digits.isEmpty || !unit.isEmpty else { return .invalid }
                unit.append(character)
            } else if character.isWhitespace {
                continue
            } else {
                return .invalid
            }
        }
        guard flush(), foundAny else { return .invalid }
        return .value(total)
    }

    /// A weight unit written in a file: `kg`, `kgs`, `kilograms`, `lb`, `lbs`, `pounds` …
    public static func weightUnit(_ text: String) -> WeightUnit? {
        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "kg", "kgs", "kg.", "kilo", "kilos", "kilogram", "kilograms": .kg
        case "lb", "lbs", "lb.", "lbs.", "pound", "pounds", "#": .lb
        default: nil
        }
    }

    /// Metres in one of a distance unit; `nil` for units not recognised.
    static func metres(per unit: String) -> Double? {
        switch unit.trimmingCharacters(in: .whitespaces).lowercased() {
        case "m", "meter", "meters", "metre", "metres": 1
        case "km", "kms", "kilometer", "kilometers", "kilometre", "kilometres": 1_000
        case "mi", "mi.", "mile", "miles": 1_609.344
        case "yd", "yds", "yard", "yards": 0.9144
        case "ft", "feet", "foot": 0.3048
        case "cm": 0.01
        case "in", "inch", "inches": 0.0254
        default: nil
        }
    }

    /// Fitbod writes every weight in kilograms, converted from the pounds a pound user
    /// entered with float noise (`61.235042773811365` is 135 lb). A value that is already a
    /// whole multiple of 0.25 kg is a kilogram user's and stays; otherwise a value within
    /// 0.02 lb of a multiple of 0.5 lb becomes the exact kilograms of that pound value; any
    /// other value is rounded to 0.01 kg.
    public static func fitbodKilograms(_ value: Double) -> Double {
        let quarters = value / 0.25
        if abs(quarters - quarters.rounded()) < 1e-6 { return quarters.rounded() * 0.25 }
        let pounds = WeightUnit.lb.value(fromKilograms: value)
        let halfPounds = (pounds * 2).rounded() / 2
        if abs(pounds - halfPounds) <= 0.02 {
            return WeightUnit.lb.kilograms(fromValue: halfPounds)
        }
        return (value * 100).rounded() / 100
    }

    /// Classifies a row's measurements: a set when it has reps; otherwise why it is not one.
    static func classify(weightKg: Double?, reps: Int?, durationSeconds: Int?, distanceMeters: Double?) -> SkipReason? {
        if let reps, reps > 0 { return nil }
        if (durationSeconds ?? 0) > 0 || (distanceMeters ?? 0) > 0 { return .timedOrDistanceOnly }
        if (weightKg ?? 0) > 0 { return .weightWithoutReps }
        return .noSetData
    }

    /// A weight in kilograms from `value` in `unit`, or `nil` for 0 (bodyweight).
    static func kilograms(_ value: Double?, unit: WeightUnit) -> Double? {
        guard let value, value > 0 else { return nil }
        return unit.kilograms(fromValue: value)
    }
}

/// Strong's `Set Order` column: a set number, a set-type letter, or a row that is not a set.
enum StrongSetOrder: Equatable {
    case working(Int)
    case warmup
    case drop
    case failure
    /// A rest-timer row: the rest length, not a set.
    case restTimer
    /// A note row: its text belongs to the exercise.
    case note
    /// Empty or unrecognised (for example another language's words).
    case other

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch trimmed.lowercased() {
        case "w": self = .warmup
        case "d": self = .drop
        case "f": self = .failure
        case "rest timer": self = .restTimer
        case "note": self = .note
        default:
            if case .value(let number) = ImportValues.count(trimmed) {
                self = .working(number)
            } else {
                self = .other
            }
        }
    }
}

extension String {
    /// Strong writes line breaks in notes as a literal backslash-n.
    var unescapingNewlines: String {
        replacingOccurrences(of: "\\n", with: "\n")
    }

    /// Trimmed of whitespace and line breaks.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
