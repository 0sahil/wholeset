// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The estimated one-rep max of a set.
public enum OneRepMax {
    /// The most reps an estimate is made from; beyond this the formula is too unreliable.
    public static let maximumReps = 12

    /// The Epley estimate `weight × (1 + reps / 30)` for 2 to ``maximumReps`` reps; for a
    /// single rep, the weight itself. `nil` without a positive weight, or for fewer than 1
    /// or more than ``maximumReps`` reps.
    public static func estimate(weightKg: Double?, reps: Int?) -> Double? {
        guard let weightKg, weightKg.isFinite, weightKg > 0,
              let reps, (1...maximumReps).contains(reps) else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }
}

extension HistorySet {
    /// The weight when it counts as weighted: positive (at least 0.01 kg once rounded) and
    /// finite. `nil` for sets without weight, which count as bodyweight or unweighted.
    public var effectiveWeightKg: Double? {
        guard let weightKg, weightKg.isFinite, WeightKey(weightKg).hundredths > 0 else { return nil }
        return weightKg
    }

    /// Weight × reps for a working set with weight and reps; 0 otherwise (warm-ups,
    /// unweighted sets and sets without reps add nothing).
    public var volumeKg: Double {
        guard !isWarmup, let weight = effectiveWeightKg, let reps, reps > 0 else { return 0 }
        return weight * Double(reps)
    }

    /// The set's estimated one-rep max (see ``OneRepMax``); `nil` for warm-ups.
    public var estimatedOneRepMaxKg: Double? {
        guard !isWarmup else { return nil }
        return OneRepMax.estimate(weightKg: effectiveWeightKg, reps: reps)
    }
}

/// A weight rounded to 0.01 kg, so values converted from pounds compare as equal.
public struct WeightKey: Hashable, Comparable, Sendable {
    /// The weight in hundredths of a kilogram.
    public let hundredths: Int

    /// The key of `kilograms`; non-finite values read as 0.
    public init(_ kilograms: Double) {
        guard kilograms.isFinite else {
            hundredths = 0
            return
        }
        let scaled = (kilograms * 100).rounded(.toNearestOrAwayFromZero)
        hundredths = Int(max(min(scaled, Double(Int32.max)), Double(Int32.min)))
    }

    public static func < (lhs: WeightKey, rhs: WeightKey) -> Bool { lhs.hundredths < rhs.hundredths }
}

/// Totals for one finished session. Only logged sets exist in history; warm-ups never count.
public enum SessionMetrics {
    /// Rest longer than this is not shown: the gap is more likely an edit or a pause.
    public static let maximumRest: TimeInterval = 30 * 60

    /// How long the session lasted (`endedAt − startedAt`); `nil` when that is not positive,
    /// as for imports that only know the start time.
    public static func duration(of session: HistorySession) -> TimeInterval? {
        let duration = session.endedAt.timeIntervalSince(session.startedAt)
        return duration > 0 ? duration : nil
    }

    /// Logged working sets (warm-ups excluded), over every exercise, skipped ones included.
    public static func workingSetCount(of session: HistorySession) -> Int {
        session.entries.reduce(0) { $0 + $1.sets.count { !$0.isWarmup } }
    }

    /// The summed weight × reps of the logged working sets with weight and reps, in kilograms.
    public static func volume(of session: HistorySession) -> Double {
        session.entries.reduce(0) { $0 + volume(of: $1.sets) }
    }

    /// The summed weight × reps of the working sets among `sets`, in kilograms.
    public static func volume(of sets: [HistorySet]) -> Double {
        sets.reduce(0) { $0 + $1.volumeKg }
    }

    /// The volume of each exercise in the session, in kilograms. An exercise that appears
    /// more than once (for example swapped out and back in) adds up all its entries.
    public static func volumeByExercise(of session: HistorySession) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for entry in session.entries {
            guard let id = entry.exerciseID else { continue }
            result[id, default: 0] += volume(of: entry.sets)
        }
        return result
    }

    /// The rest taken before each of `sets` (the logged sets of one entry, in order): the
    /// time since the previous set was logged.
    ///
    /// `nil` for the first set, and wherever the gap is not positive or is longer than
    /// ``maximumRest``: sets added by editing or imported from another app share
    /// timestamps, and those gaps say nothing about rest.
    public static func restBefore(_ sets: [HistorySet]) -> [TimeInterval?] {
        sets.indices.map { index in
            guard index > 0 else { return nil }
            let rest = sets[index].completedAt.timeIntervalSince(sets[index - 1].completedAt)
            return rest > 0 && rest <= maximumRest ? rest : nil
        }
    }
}

/// What can be told about an exercise of a session from its routine slot and position.
public enum EntryNote: Equatable, Sendable {
    /// Added during the workout: it came from no routine slot, while others did.
    case added
    /// Swapped in for the exercise before it in the same routine slot.
    case swappedIn
    /// Skipped for that session.
    case skipped
}

/// Everything the session screen shows, worked out once from a session and the records.
public struct SessionDetail: Equatable, Sendable {
    /// One logged set.
    public struct SetRow: Identifiable, Equatable, Sendable {
        /// The set's identifier.
        public let id: UUID
        /// The working set's 1-based number within its exercise; `nil` for a warm-up.
        public let number: Int?
        /// Whether the set was a warm-up.
        public let isWarmup: Bool
        /// Weight in kilograms; `nil` for a set without weight.
        public let weightKg: Double?
        /// Repetitions, if recorded.
        public let reps: Int?
        /// The records this set set, in ``PRKind`` order.
        public let records: [PRKind]
        /// The rest taken before it (see ``SessionMetrics/restBefore(_:)``).
        public let restBefore: TimeInterval?
    }

    /// One exercise.
    public struct Section: Identifiable, Equatable, Sendable {
        /// The entry's identifier.
        public let id: UUID
        /// The exercise's `id`, if it still exists.
        public let exerciseID: UUID?
        /// The exercise's name.
        public let exerciseName: String
        /// Added, swapped in or skipped, when that can be told.
        public let note: EntryNote?
        /// Whether this exercise's volume in the session was a record. Shown on the first
        /// section of the exercise only.
        public let isVolumeRecord: Bool
        /// The logged sets.
        public let rows: [SetRow]
    }

    /// The session.
    public let session: HistorySession
    /// See ``SessionMetrics/duration(of:)``.
    public let duration: TimeInterval?
    /// The session's volume in kilograms (see ``SessionMetrics``).
    public let volumeKg: Double
    /// See ``SessionMetrics/workingSetCount(of:)``.
    public let workingSets: Int
    /// The exercises with a logged set or skipped, in order. Exercises that were planned
    /// but never started are left out.
    public let sections: [Section]

    /// Works out the screen for `session`, with the badges from `records`.
    public init(session: HistorySession, records: PersonalRecords) {
        self.session = session
        duration = SessionMetrics.duration(of: session)
        volumeKg = SessionMetrics.volume(of: session)
        workingSets = SessionMetrics.workingSetCount(of: session)

        let notes = Self.notes(for: session.entries)
        var volumeShown: Set<UUID> = []
        var sections: [Section] = []
        for (index, entry) in session.entries.enumerated() where !entry.sets.isEmpty || entry.isSkipped {
            let rests = SessionMetrics.restBefore(entry.sets)
            var number = 0
            let rows = entry.sets.enumerated().map { offset, set in
                if !set.isWarmup { number += 1 }
                return SetRow(
                    id: set.id,
                    number: set.isWarmup ? nil : number,
                    isWarmup: set.isWarmup,
                    weightKg: set.weightKg,
                    reps: set.reps,
                    records: records.kinds(forSet: set.id).sorted(),
                    restBefore: rests[offset]
                )
            }
            var isVolumeRecord = false
            if let exerciseID = entry.exerciseID, volumeShown.insert(exerciseID).inserted {
                isVolumeRecord = records.hasVolumeRecord(session: session.id, exercise: exerciseID)
            }
            sections.append(Section(
                id: entry.id,
                exerciseID: entry.exerciseID,
                exerciseName: entry.exerciseName,
                note: notes[index],
                isVolumeRecord: isVolumeRecord,
                rows: rows
            ))
        }
        self.sections = sections
    }

    /// The note for each of `entries`, in order:
    /// - skipped entries are ``EntryNote/skipped``;
    /// - an entry sharing its routine slot with an earlier entry was ``EntryNote/swappedIn``;
    /// - an entry without a slot, in a session where other entries have one, was ``EntryNote/added``.
    ///
    /// Sessions where no entry has a slot (empty workouts, or sessions recorded before slots
    /// were) get no notes. A swap made before anything was logged changes the exercise in
    /// place and cannot be told apart from the plan.
    public static func notes(for entries: [HistoryEntry]) -> [EntryNote?] {
        let tracksSlots = entries.contains { $0.routineItemID != nil }
        var seenSlots: Set<UUID> = []
        return entries.map { entry in
            var note: EntryNote?
            if let slot = entry.routineItemID {
                if !seenSlots.insert(slot).inserted { note = .swappedIn }
            } else if tracksSlots {
                note = .added
            }
            return entry.isSkipped ? .skipped : note
        }
    }
}
