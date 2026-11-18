// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import WholesetKit

extension ImportFormat {
    /// "Hevy export", or "CSV file" for other apps.
    var exportTitle: String {
        self == .generic ? String(localized: "CSV File") : String(localized: "\(appName) Export", comment: "Title of the import preview, e.g. “Hevy Export”.")
    }

    /// The name in the list of apps on the first import screen.
    var listName: String {
        self == .generic ? String(localized: "Other Apps") : appName
    }
}

extension SkipReason {
    /// Why rows were not read, as a short label.
    var label: String {
        switch self {
        case .timedOrDistanceOnly: String(localized: "Only time or distance")
        case .weightWithoutReps: String(localized: "Weight but no reps")
        case .noSetData: String(localized: "No weight, reps or time")
        case .unreadableDate: String(localized: "Date not readable")
        case .unreadableNumber: String(localized: "Number not readable")
        case .missingExercise: String(localized: "No exercise name")
        }
    }

    /// A sentence explaining the reason.
    var explanation: String {
        switch self {
        case .timedOrDistanceOnly:
            String(localized: "Cardio and timed exercises such as planks aren't imported yet: Wholeset logs sets of reps.")
        case .weightWithoutReps:
            String(localized: "A set with a weight but no reps, usually a set that was planned but not done.")
        case .noSetData:
            String(localized: "The row holds no weight, reps, time or distance.")
        case .unreadableDate:
            String(localized: "The date in this row couldn't be read.")
        case .unreadableNumber:
            String(localized: "A weight, reps or time in this row isn't a number Wholeset can use, or is negative.")
        case .missingExercise:
            String(localized: "The row has no exercise name.")
        }
    }
}

extension ColumnRole {
    /// The role's name in the column picker.
    var label: String {
        switch self {
        case .date: String(localized: "Date")
        case .exercise: String(localized: "Exercise")
        case .reps: String(localized: "Reps")
        case .weight: String(localized: "Weight")
        case .weightUnit: String(localized: "Weight Unit")
        case .workoutName: String(localized: "Workout Name")
        case .note: String(localized: "Note")
        case .setOrder: String(localized: "Set Number")
        case .workoutDuration: String(localized: "Workout Duration")
        case .ignore: String(localized: "Ignore")
        }
    }
}

extension DateOrder {
    /// The order's name, with an example.
    var label: String {
        switch self {
        case .dayMonthYear: String(localized: "Day First (31/12)")
        case .monthDayYear: String(localized: "Month First (12/31)")
        case .yearMonthDay: String(localized: "Year First (2026/12/31)")
        }
    }

    /// The order the user's region writes dates in.
    static var local: DateOrder {
        let pattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: .current) ?? ""
        let day = pattern.firstIndex(of: "d")
        let month = pattern.firstIndex(of: "M")
        let year = pattern.firstIndex(of: "y")
        if let year, let month, year < month { return .yearMonthDay }
        if let day, let month, month < day { return .monthDayYear }
        return .dayMonthYear
    }
}

extension ExerciseMatch {
    /// Why the row looks the way it does, after the exercise's name ("similar name",
    /// "machine?"), or `nil` for a plain match.
    func reason(importedName: String) -> String? {
        switch self {
        case .matched(let candidate, _):
            return candidate.isArchived ? String(localized: "archived") : nil
        case .check(_, .similarName):
            return String(localized: "similar name")
        case .check(_, .differentEquipment(let equipment)):
            if let (_, qualifier) = ExerciseMatcher.parenthetical(importedName) {
                return "\(qualifier.lowercased())?"
            }
            return equipment.map { "\($0.label.lowercased())?" } ?? String(localized: "similar name")
        case .newCustom:
            return nil
        }
    }
}
