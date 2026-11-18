// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os
import SwiftData
import WholesetKit

extension Equipment {
    /// The name shown in lists and pickers.
    var label: String {
        switch self {
        case .barbell: String(localized: "Barbell")
        case .dumbbell: String(localized: "Dumbbell")
        case .machine: String(localized: "Machine")
        case .cable: String(localized: "Cable")
        case .bodyweight: String(localized: "Bodyweight")
        case .other: String(localized: "Other")
        }
    }
}

extension Muscle {
    /// The name shown in lists and pickers.
    var label: String {
        switch self {
        case .abdominals: String(localized: "Abs")
        case .abductors: String(localized: "Abductors")
        case .adductors: String(localized: "Adductors")
        case .biceps: String(localized: "Biceps")
        case .calves: String(localized: "Calves")
        case .chest: String(localized: "Chest")
        case .forearms: String(localized: "Forearms")
        case .glutes: String(localized: "Glutes")
        case .hamstrings: String(localized: "Hamstrings")
        case .lats: String(localized: "Lats")
        case .lowerBack: String(localized: "Lower Back")
        case .middleBack: String(localized: "Middle Back")
        case .neck: String(localized: "Neck")
        case .quadriceps: String(localized: "Quads")
        case .shoulders: String(localized: "Shoulders")
        case .traps: String(localized: "Traps")
        case .triceps: String(localized: "Triceps")
        case .other: String(localized: "Other")
        }
    }
}

extension MuscleGroup {
    /// The name shown on filter chips and section headers.
    var label: String {
        switch self {
        case .chest: String(localized: "Chest")
        case .back: String(localized: "Back")
        case .shoulders: String(localized: "Shoulders")
        case .arms: String(localized: "Arms")
        case .legs: String(localized: "Legs")
        case .core: String(localized: "Core")
        case .other: String(localized: "Other")
        }
    }
}

extension CrownSensitivity {
    /// The name shown in Settings.
    var label: String {
        switch self {
        case .slow: String(localized: "Slow")
        case .normal: String(localized: "Normal")
        case .fast: String(localized: "Fast")
        }
    }
}

extension Exercise {
    /// "Barbell · Chest".
    var detailLine: String {
        "\(equipment.label) · \(primaryMuscle.label)"
    }
}

/// Text for rest times and plan targets.
enum Formatting {
    /// "1:30" for 90 seconds.
    static func rest(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    /// "1 minute, 30 seconds", for VoiceOver.
    static func spokenRest(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }

    /// A routine item's rest: its own value, or the exercise default.
    static func rest(_ seconds: Int?) -> String {
        seconds.map(rest) ?? String(localized: "Exercise default")
    }

    /// "3 × 8–12" (or "3 × 10" when both ends are equal).
    static func targets(sets: Int, repLow: Int, repHigh: Int) -> String {
        let reps = repLow == repHigh ? "\(repLow)" : "\(repLow)–\(repHigh)"
        return "\(sets) × \(reps)"
    }

    /// The full weekday name for a `Calendar` weekday number.
    static func weekdayName(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.weekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    /// The short weekday name ("Mon") for a `Calendar` weekday number.
    static func shortWeekdayName(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }
}

extension ModelContext {
    /// Saves, logging instead of throwing: SwiftData retries on the next save, and a
    /// failed save must not lose the screen the user is on.
    func saveLogged() {
        do {
            try save()
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset", category: "Store")
                .error("Save failed: \(error, privacy: .public)")
        }
    }
}
