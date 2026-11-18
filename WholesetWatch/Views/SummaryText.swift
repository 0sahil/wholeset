// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import WholesetKit

/// Text for the end-of-workout summary. Records and lines arrive in kilograms; they are
/// converted to the display unit here. Weights read back as logged (like the iPhone's
/// history), estimates with up to one decimal, volumes as whole numbers.
enum SummaryText {
    /// "Bench Press 62.5 kg × 10", "Bench Press e1RM 83.3 kg", "Bench Press 11 reps at 60 kg",
    /// "Dips 15 reps", "Bench Press volume 1,563 kg".
    static func record(_ record: SessionRecord, unit: WeightUnit) -> String {
        let name = record.exerciseName
        switch record.value {
        case let .weight(kilograms, reps):
            return String(localized: "\(name) \(weight(kilograms, unit: unit)) × \(reps)", comment: "A heaviest-weight record: exercise, weight with unit, reps.")
        case let .estimatedOneRepMax(kilograms):
            return String(localized: "\(name) e1RM \(estimate(kilograms, unit: unit)) \(unit.symbol)", comment: "An estimated one-rep max record.")
        case let .reps(reps, kilograms?):
            let detail = inflectedString("^[\(reps) rep](inflect: true) at \(weight(kilograms, unit: unit))")
            return String(localized: "\(name) \(detail)", comment: "A most-reps record: exercise, then e.g. “11 reps at 60 kg”.")
        case let .reps(reps, nil):
            let detail = inflectedString("^[\(reps) rep](inflect: true)")
            return String(localized: "\(name) \(detail)", comment: "A most-reps record without weight: exercise, then e.g. “15 reps”.")
        case let .volume(kilograms):
            return String(localized: "\(name) volume \(WeightFormat.volume(kilograms: kilograms, unit: unit)) \(unit.symbol)", comment: "A session volume record.")
        }
    }

    /// The record for VoiceOver, e.g. "Bench Press, best estimated one-rep max, 83.3 kilograms".
    static func spokenRecord(_ record: SessionRecord, unit: WeightUnit) -> String {
        let name = record.exerciseName
        switch record.value {
        case let .weight(kilograms, reps):
            return String(localized: "\(name), heaviest weight, \(spokenWeight(kilograms, unit: unit)), \(spokenReps(reps))")
        case let .estimatedOneRepMax(kilograms):
            return String(localized: "\(name), best estimated one-rep max, \(spokenEstimate(kilograms, unit: unit))")
        case let .reps(reps, kilograms?):
            return String(localized: "\(name), most reps at \(spokenWeight(kilograms, unit: unit)), \(spokenReps(reps))")
        case let .reps(reps, nil):
            return String(localized: "\(name), most reps, \(spokenReps(reps))")
        case let .volume(kilograms):
            return String(localized: "\(name), best volume, \(spokenVolume(kilograms, unit: unit))")
        }
    }

    /// "3 sets · top 62.5×8 · 1,500 kg"; without weight "3 sets · top 12 reps".
    static func exerciseDetail(_ line: ExerciseSummaryLine, unit: WeightUnit) -> String {
        var parts = [inflectedString("^[\(line.workingSets) set](inflect: true)")]
        switch (line.topSetWeightKg, line.topSetReps) {
        case let (kilograms?, reps?):
            parts.append(String(localized: "top \(WeightFormat.preciseString(kilograms: kilograms, unit: unit))×\(reps)", comment: "The top set of an exercise, e.g. “top 62.5×8”."))
        case let (nil, reps?):
            parts.append(String(localized: "top \(inflectedString("^[\(reps) rep](inflect: true)"))", comment: "The top set of an exercise without weight, e.g. “top 12 reps”."))
        case let (kilograms?, nil):
            parts.append(String(localized: "top \(WeightFormat.preciseString(kilograms: kilograms, unit: unit))", comment: "The top set of an exercise without reps."))
        case (nil, nil):
            break
        }
        if line.volumeKg > 0 {
            parts.append("\(WeightFormat.volume(kilograms: line.volumeKg, unit: unit)) \(unit.symbol)")
        }
        return parts.joined(separator: " · ")
    }

    /// The line's detail for VoiceOver, e.g. "3 sets, top set 62.5 kilograms, 8 reps, volume 1,500 kilograms".
    static func spokenExerciseDetail(_ line: ExerciseSummaryLine, unit: WeightUnit) -> String {
        var parts = [inflectedString("^[\(line.workingSets) set](inflect: true)")]
        var top: [String] = []
        if let kilograms = line.topSetWeightKg { top.append(spokenWeight(kilograms, unit: unit)) }
        if let reps = line.topSetReps { top.append(spokenReps(reps)) }
        if !top.isEmpty {
            parts.append(String(localized: "top set \(top.joined(separator: ", "))"))
        }
        if line.volumeKg > 0 {
            parts.append(String(localized: "volume \(spokenVolume(line.volumeKg, unit: unit))"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Parts

    /// "62.5 kg", as logged.
    private static func weight(_ kilograms: Double, unit: WeightUnit) -> String {
        WeightFormat.preciseStringWithUnit(kilograms: kilograms, unit: unit)
    }

    /// "83.3", without the unit.
    private static func estimate(_ kilograms: Double, unit: WeightUnit) -> String {
        unit.value(fromKilograms: kilograms).formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func spokenWeight(_ kilograms: Double, unit: WeightUnit) -> String {
        spokenMass(unit.value(fromKilograms: kilograms), unit: unit, fractionDigits: 2)
    }

    private static func spokenEstimate(_ kilograms: Double, unit: WeightUnit) -> String {
        spokenMass(unit.value(fromKilograms: kilograms), unit: unit, fractionDigits: 1)
    }

    private static func spokenVolume(_ kilograms: Double, unit: WeightUnit) -> String {
        spokenMass(unit.value(fromKilograms: kilograms).rounded(), unit: unit, fractionDigits: 0)
    }

    private static func spokenMass(_ value: Double, unit: WeightUnit, fractionDigits: Int) -> String {
        Measurement(value: value, unit: unit == .kg ? UnitMass.kilograms : .pounds)
            .formatted(.measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0...fractionDigits))))
    }

    private static func spokenReps(_ reps: Int) -> String {
        inflectedString("^[\(reps) rep](inflect: true)")
    }
}
