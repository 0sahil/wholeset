// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One exercise of a finished session, as a line of the end-of-workout summary: the working
/// sets logged, the top set and the volume.
public struct ExerciseSummaryLine: Identifiable, Equatable, Sendable {
    /// The entry's identifier.
    public let id: UUID
    /// The exercise's `id`, if it still exists.
    public let exerciseID: UUID?
    /// The exercise's name.
    public let exerciseName: String
    /// Logged working sets (warm-ups left out).
    public let workingSets: Int
    /// The top set's weight in kilograms; `nil` when it had no weight.
    public let topSetWeightKg: Double?
    /// The top set's reps, if recorded.
    public let topSetReps: Int?
    /// The entry's working-set volume in kilograms, as ``SessionMetrics`` adds it up.
    public let volumeKg: Double

    /// Creates a line.
    public init(
        id: UUID,
        exerciseID: UUID?,
        exerciseName: String,
        workingSets: Int,
        topSetWeightKg: Double?,
        topSetReps: Int?,
        volumeKg: Double
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.workingSets = workingSets
        self.topSetWeightKg = topSetWeightKg
        self.topSetReps = topSetReps
        self.volumeKg = volumeKg
    }

    /// One line per entry of `session` with at least one logged working set, in workout
    /// order. Entries without one (skipped before any set, never started, or warm-ups only)
    /// are left out; a skipped entry that got working sets keeps its line. An exercise that
    /// appears twice (swapped out and back in) gets a line per entry.
    ///
    /// The top set is the heaviest working set, then the one with more reps; the earlier set
    /// wins a full tie. Weights are compared after rounding to 0.01 kg.
    public static func lines(for session: HistorySession) -> [ExerciseSummaryLine] {
        session.entries.compactMap { entry in
            let working = entry.workingSets
            guard let top = ExerciseTimeline.topSet(of: working) else { return nil }
            return ExerciseSummaryLine(
                id: entry.id,
                exerciseID: entry.exerciseID,
                exerciseName: entry.exerciseName,
                workingSets: working.count,
                topSetWeightKg: top.effectiveWeightKg,
                topSetReps: top.reps,
                volumeKg: SessionMetrics.volume(of: working)
            )
        }
    }
}
