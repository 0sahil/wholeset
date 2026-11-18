// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import WholesetKit

extension EnvironmentValues {
    /// The unit weights are shown and typed in, from the settings row.
    @Entry var weightUnit: WeightUnit = .kg
}

/// Text for history screens. Weights are stored in kilograms and converted here, at the edge.
enum HistoryFormat {
    /// "62.5 kg".
    static func weight(_ kilograms: Double, unit: WeightUnit) -> String {
        WeightFormat.preciseStringWithUnit(kilograms: kilograms, unit: unit)
    }

    /// "62.5 kilograms", for VoiceOver.
    static func spokenWeight(_ kilograms: Double, unit: WeightUnit) -> String {
        Measurement(value: unit.value(fromKilograms: kilograms), unit: unit == .kg ? UnitMass.kilograms : .pounds)
            .formatted(.measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }

    /// "62.5 kg × 10", "12 reps" without weight, "62.5 kg" without reps.
    static func set(weightKg: Double?, reps: Int?, unit: WeightUnit) -> String {
        switch (weightKg, reps) {
        case let (kilograms?, reps?): "\(weight(kilograms, unit: unit)) × \(reps)"
        case let (nil, reps?): repsText(reps)
        case let (kilograms?, nil): weight(kilograms, unit: unit)
        case (nil, nil): "—"
        }
    }

    /// "62.5 × 10" (no unit, for compact columns), "12 reps" without weight.
    static func compactSet(weightKg: Double?, reps: Int?, unit: WeightUnit) -> String {
        switch (weightKg, reps) {
        case let (kilograms?, reps?): "\(WeightFormat.preciseString(kilograms: kilograms, unit: unit)) × \(reps)"
        case let (nil, reps?): repsText(reps)
        case let (kilograms?, nil): WeightFormat.preciseString(kilograms: kilograms, unit: unit)
        case (nil, nil): "—"
        }
    }

    /// "62.5 kilograms, 10 reps", for VoiceOver.
    static func spokenSet(weightKg: Double?, reps: Int?, unit: WeightUnit) -> String {
        var parts: [String] = []
        if let weightKg { parts.append(spokenWeight(weightKg, unit: unit)) }
        if let reps { parts.append(repsText(reps)) }
        return parts.isEmpty ? String(localized: "Not recorded") : parts.joined(separator: ", ")
    }

    /// "10 reps".
    static func repsText(_ reps: Int) -> String {
        inflectedString("^[\(reps) rep](inflect: true)")
    }

    /// "15 sets".
    static func setCount(_ count: Int) -> String {
        inflectedString("^[\(count) set](inflect: true)")
    }

    /// "1 PR", "2 PRs".
    ///
    /// Automatic inflection does not know the abbreviation (it returns "2 PR"), so the plural
    /// forms come from the string catalog.
    static func prCount(_ count: Int) -> String {
        String(localized: "\(count) PRs", comment: "Number of personal records set in a workout.")
    }

    /// "6,240 kg".
    static func volume(_ kilograms: Double, unit: WeightUnit) -> String {
        "\(WeightFormat.volume(kilograms: kilograms, unit: unit)) \(unit.symbol)"
    }

    /// "6,240 kilograms", for VoiceOver.
    static func spokenVolume(_ kilograms: Double, unit: WeightUnit) -> String {
        Measurement(value: unit.value(fromKilograms: kilograms).rounded(), unit: unit == .kg ? UnitMass.kilograms : .pounds)
            .formatted(.measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// "61 min".
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.minutes], width: .abbreviated, zeroValueUnits: .show(length: 1)))
    }

    /// "61 minutes", for VoiceOver.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// "2:04 rest".
    static func rest(_ seconds: TimeInterval) -> String {
        String(localized: "\(Formatting.rest(Int(seconds.rounded()))) rest")
    }

    /// "Rested 2 minutes, 4 seconds", for VoiceOver.
    static func spokenRest(_ seconds: TimeInterval) -> String {
        String(localized: "Rested \(Formatting.spokenRest(Int(seconds.rounded())))")
    }

    /// "e1RM PR", "Weight PR", "Rep PR", or several joined ("Weight PR · e1RM PR").
    static func recordLabel(_ kinds: [PRKind]) -> String {
        kinds.map(recordName).joined(separator: " · ")
    }

    /// The badge for one kind of record.
    static func recordName(_ kind: PRKind) -> String {
        switch kind {
        case .weight: String(localized: "Weight PR")
        case .estimatedOneRepMax: String(localized: "e1RM PR")
        case .reps: String(localized: "Rep PR")
        case .volume: String(localized: "Volume PR")
        }
    }

    /// "Thu 12".
    static func dayOfMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    /// "Mon, 9 Nov 2026".
    static func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// "9 Nov 2026".
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "November 2026".
    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    /// "18:04 – 19:02", or just the start time when the end is not after it.
    static func timeRange(from start: Date, to end: Date) -> String {
        guard end > start else { return start.formatted(date: .omitted, time: .shortened) }
        return (start..<end).formatted(.interval.hour().minute())
    }

    /// The name of a session, or "Workout" when it has none.
    static func sessionName(_ name: String) -> String {
        name.isEmpty ? String(localized: "Workout") : name
    }

    /// The name of an exercise, or a placeholder when it no longer exists.
    static func exerciseName(_ name: String) -> String {
        name.isEmpty ? String(localized: "Unknown Exercise") : name
    }
}
