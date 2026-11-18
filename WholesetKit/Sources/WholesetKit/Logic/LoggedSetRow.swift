// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One row of the table of logged sets of an exercise.
public struct LoggedSetRow: Identifiable, Equatable, Sendable {
    /// The set's identifier.
    public let id: UUID
    /// The set's 1-based position among all sets of its exercise, warm-ups included, so it
    /// matches the "Set N of M" count shown while logging.
    public let number: Int
    /// Whether the set is a warm-up.
    public let isWarmup: Bool
    /// The recorded weight in kilograms; `nil` for a set without weight.
    public let weightKg: Double?
    /// The recorded repetitions.
    public let reps: Int?

    /// Creates a row.
    public init(id: UUID, number: Int, isWarmup: Bool, weightKg: Double?, reps: Int?) {
        self.id = id
        self.number = number
        self.isWarmup = isWarmup
        self.weightKg = weightKg
        self.reps = reps
    }

    /// The rows for the logged sets among `sets`.
    ///
    /// - Parameter sets: Every set of one exercise in order, logged or not (for example
    ///   `SessionExercise.sortedSets`). Unlogged sets get no row but still count towards
    ///   the numbers of the sets after them.
    public static func rows(for sets: [SetLog]) -> [LoggedSetRow] {
        sets.enumerated().compactMap { index, set in
            guard set.completedAt != nil else { return nil }
            return LoggedSetRow(id: set.id, number: index + 1, isWarmup: set.isWarmup, weightKg: set.weightKg, reps: set.reps)
        }
    }

    /// The weight with its unit, e.g. "60 kg"; `nil` when the set has no weight.
    public func weightText(scale: WeightScale, locale: Locale = .current) -> String? {
        weightKg.map { WeightFormat.stringWithUnit(kilograms: $0, scale: scale, locale: locale) }
    }

    /// The reps, e.g. "10", or "–" when none were recorded.
    public var repsText: String {
        reps.map { "\($0)" } ?? "–"
    }

    /// "60 kg × 10", or "× 10" for a set without weight.
    public func valueText(scale: WeightScale, locale: Locale = .current) -> String {
        guard let weight = weightText(scale: scale, locale: locale) else { return "× \(repsText)" }
        return "\(weight) × \(repsText)"
    }
}
