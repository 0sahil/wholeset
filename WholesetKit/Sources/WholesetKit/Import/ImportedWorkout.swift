// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One set read from an export, in kilograms whatever the file's unit.
public struct ImportedSet: Sendable, Equatable {
    /// The kind of a working set, kept in the set's note: v1 logs drop and failure sets as
    /// normal sets.
    public enum Kind: String, Sendable, Equatable {
        case normal
        case drop
        case failure
    }

    /// Weight in kilograms; `nil` for bodyweight sets (no weight, or 0).
    public var weightKg: Double?
    /// Repetitions. Always at least 1: rows without reps are not sets (see ``SkipReason``).
    public var reps: Int?
    /// A duration recorded along with the reps, if any.
    public var durationSeconds: Int?
    /// A distance recorded along with the reps, if any, in metres.
    public var distanceMeters: Double?
    public var isWarmup: Bool
    public var kind: Kind
    /// Rating of perceived exertion, 0–10.
    public var rpe: Double?
    /// The set's own note from the file (for example a FitNotes comment).
    public var note: String
    /// The 1-based line of the file the set was read from.
    public var line: Int

    /// Creates a set.
    public init(
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        isWarmup: Bool = false,
        kind: Kind = .normal,
        rpe: Double? = nil,
        note: String = "",
        line: Int = 0
    ) {
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.isWarmup = isWarmup
        self.kind = kind
        self.rpe = rpe
        self.note = note
        self.line = line
    }

    /// The note to store on the set: "Drop set" or "Failure" for those kinds, then the
    /// file's own note.
    public var storedNote: String {
        let label: String? = switch kind {
        case .normal: nil
        case .drop: String(localized: "Drop set", bundle: .module, comment: "Set note for an imported drop set.")
        case .failure: String(localized: "Failure", bundle: .module, comment: "Set note for an imported set taken to failure.")
        }
        return [label, note.isEmpty ? nil : note].compactMap(\.self).joined(separator: " · ")
    }
}

/// One exercise of an imported workout, under the name the file gives it.
public struct ImportedExercise: Sendable, Equatable {
    /// The exercise name as written in the file (trimmed).
    public var name: String
    /// The exercise's note; repeated notes in the file appear once.
    public var note: String
    /// The sets in file order (Hevy: by `set_index`).
    public var sets: [ImportedSet]

    /// Creates an exercise.
    public init(name: String, note: String = "", sets: [ImportedSet] = []) {
        self.name = name
        self.note = note
        self.sets = sets
    }

    /// The sets that are not warm-ups.
    public var workingSets: [ImportedSet] { sets.filter { !$0.isWarmup } }
}

/// One workout read from an export.
public struct ImportedWorkout: Sendable, Equatable {
    /// The workout's name; empty when the file has none (FitNotes, Fitbod), which the app
    /// shows as "Workout".
    public var name: String
    /// When it started.
    public var startedAt: Date
    /// When it ended, if the file says (end time, or start plus duration); `nil` otherwise.
    public var endedAt: Date?
    /// The workout's own notes.
    public var notes: String
    /// The key that recognises this workout when it is imported again
    /// (see ``ImportKey/externalKey(start:name:)``).
    public var externalKey: String
    /// The exercises in file order. Exercises without sets are left out (their notes move to
    /// ``notes``).
    public var exercises: [ImportedExercise]
    /// The first line of the file that belongs to the workout.
    public var firstLine: Int

    /// Creates a workout; the key is derived from the start and name.
    ///
    /// - Parameter wallClockZone: The zone a start without one in the file was read in
    ///   (see ``ImportKey/externalKey(start:name:wallClockZone:)``); `nil` when the file gave a zone.
    public init(
        name: String,
        startedAt: Date,
        endedAt: Date? = nil,
        notes: String = "",
        exercises: [ImportedExercise],
        firstLine: Int = 0,
        wallClockZone: TimeZone? = nil
    ) {
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.externalKey = ImportKey.externalKey(start: startedAt, name: name, wallClockZone: wallClockZone)
        self.exercises = exercises
        self.firstLine = firstLine
    }

    /// Every set of every exercise.
    public var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// Whether no row of the workout could be read as a set.
    public var isEmpty: Bool { setCount == 0 }

    /// The text for the session's notes: the workout's notes, then one "Exercise: note" line
    /// per exercise note. `exerciseName` gives the name to show for an imported name (the
    /// Wholeset exercise it became).
    public func composedNotes(exerciseName: (String) -> String = { $0 }) -> String {
        var lines: [String] = []
        if !notes.isEmpty { lines.append(notes) }
        for exercise in exercises where !exercise.note.isEmpty {
            lines.append("\(exerciseName(exercise.name)): \(exercise.note)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Why a row of the file did not become a set. Rows that are not sets at all (Strong's
/// rest-timer rows, note rows) are not skipped rows: they never held a set.
public enum SkipReason: String, Sendable, CaseIterable, Comparable {
    /// Only a duration and/or a distance (cardio, planks): Wholeset has no timed exercises yet.
    case timedOrDistanceOnly
    /// A weight but no reps.
    case weightWithoutReps
    /// No weight, reps, duration or distance.
    case noSetData
    /// The date could not be read.
    case unreadableDate
    /// A number (weight, reps, RPE …) could not be read, or was negative.
    case unreadableNumber
    /// No exercise name.
    case missingExercise

    public static func < (lhs: SkipReason, rhs: SkipReason) -> Bool {
        let order = allCases
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

/// A row of the file that was not read, with its text so it can be shown.
public struct SkippedRow: Sendable, Equatable, Identifiable {
    /// The 1-based line the row starts on.
    public let line: Int
    public let reason: SkipReason
    /// The row as written in the file.
    public let text: String

    public var id: Int { line }

    /// Creates a skipped row.
    public init(line: Int, reason: SkipReason, text: String) {
        self.line = line
        self.reason = reason
        self.text = text
    }
}

/// Where the weights' unit came from.
public enum WeightUnitSource: Sendable, Equatable {
    /// The header names it for the whole file.
    case header(WeightUnit)
    /// Each row has a unit column.
    case column
    /// The file does not say; this unit was chosen (by the user, or their setting).
    case chosen(WeightUnit)

    /// Whether the user has to (or may) choose the unit.
    public var isChosen: Bool {
        if case .chosen = self { return true }
        return false
    }
}

/// How the file's dates were read.
public struct DateReading: Sendable, Equatable {
    /// The order used for all-numeric dates with the year last (`03/12/2023`); `nil` when the
    /// file has none.
    public let order: DateOrder?
    /// Whether that order could not be told from the file and was given by the caller.
    public let wasChosen: Bool
    /// A date as written in the file, for showing next to a date-order choice.
    public let sample: String

    /// Creates a reading.
    public init(order: DateOrder?, wasChosen: Bool, sample: String) {
        self.order = order
        self.wasChosen = wasChosen
        self.sample = sample
    }
}

/// Totals about a parsed file.
public struct ImportStats: Sendable, Equatable {
    /// Data rows in the file (blank lines excluded).
    public var rowCount = 0
    /// Rows ignored because they never hold a set (Strong rest-timer rows).
    public var ignoredRowCount = 0
    /// Rows whose field count differed from the header's.
    public var raggedRowCount = 0
    /// Rows with a weight but no unit in a file with a unit column; the chosen unit was used.
    public var rowsWithAssumedUnit = 0
    /// Units found in a unit column, most frequent first.
    public var unitsFound: [WeightUnit] = []

    /// Creates empty stats.
    public init() {}
}

/// Everything read from one export.
public struct ImportParseResult: Sendable {
    /// The recognised layout.
    public let layout: ImportLayout
    /// Every workout in file order, including empty ones (see ``ImportedWorkout/isEmpty``).
    public let allWorkouts: [ImportedWorkout]
    /// Rows that were not read, in file order.
    public let skippedRows: [SkippedRow]
    /// Where the weight unit came from.
    public let weightUnitSource: WeightUnitSource
    /// How dates were read.
    public let dateReading: DateReading
    /// How the file was decoded.
    public let encoding: CSVTextEncoding
    /// Totals.
    public let stats: ImportStats

    /// Creates a result.
    public init(
        layout: ImportLayout,
        allWorkouts: [ImportedWorkout],
        skippedRows: [SkippedRow],
        weightUnitSource: WeightUnitSource,
        dateReading: DateReading,
        encoding: CSVTextEncoding,
        stats: ImportStats
    ) {
        self.layout = layout
        self.allWorkouts = allWorkouts
        self.skippedRows = skippedRows
        self.weightUnitSource = weightUnitSource
        self.dateReading = dateReading
        self.encoding = encoding
        self.stats = stats
    }

    /// The app the file came from.
    public var format: ImportFormat { layout.format }

    /// Workouts with at least one set, in file order.
    public var workouts: [ImportedWorkout] { allWorkouts.filter { !$0.isEmpty } }

    /// The number of workouts with at least one set.
    public var workoutCount: Int { allWorkouts.count { !$0.isEmpty } }

    /// The number of sets read.
    public var setCount: Int { allWorkouts.reduce(0) { $0 + $1.setCount } }

    /// The earliest and latest start among workouts with sets.
    public var dateRange: ClosedRange<Date>? {
        let starts = workouts.map(\.startedAt)
        guard let first = starts.min(), let last = starts.max() else { return nil }
        return first...last
    }

    /// Every distinct exercise name (as written) in workouts with sets, in order of first
    /// appearance in the file, with how many sets use it.
    public var exerciseNames: [(name: String, sets: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for workout in allWorkouts {
            for exercise in workout.exercises {
                if counts[exercise.name] == nil { order.append(exercise.name) }
                counts[exercise.name, default: 0] += exercise.sets.count
            }
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    /// Skipped rows grouped by reason, largest group first.
    public var skippedByReason: [(reason: SkipReason, rows: [SkippedRow])] {
        Dictionary(grouping: skippedRows, by: \.reason)
            .map { (reason: $0.key, rows: $0.value) }
            .sorted { lhs, rhs in
                lhs.rows.count != rhs.rows.count ? lhs.rows.count > rhs.rows.count : lhs.reason < rhs.reason
            }
    }
}
