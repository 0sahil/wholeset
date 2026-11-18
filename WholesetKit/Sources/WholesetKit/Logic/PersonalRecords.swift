// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A kind of personal record (PR).
public enum PRKind: Int, CaseIterable, Comparable, Sendable {
    /// The heaviest weight lifted for at least one rep.
    case weight
    /// The best estimated one-rep max (see ``OneRepMax``).
    case estimatedOneRepMax
    /// The most reps at a weight done before (or, without weight, the most reps).
    case reps
    /// The most volume in one session.
    case volume

    public static func < (lhs: PRKind, rhs: PRKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The set a record was set with.
public struct RecordSet: Equatable, Sendable {
    /// The set's identifier.
    public let setID: UUID
    /// The session it was logged in.
    public let sessionID: UUID
    /// When that session started.
    public let date: Date
    /// The weight in kilograms; `nil` for a set without weight.
    public let weightKg: Double?
    /// The reps.
    public let reps: Int

    /// Creates a record set.
    public init(setID: UUID, sessionID: UUID, date: Date, weightKg: Double?, reps: Int) {
        self.setID = setID
        self.sessionID = sessionID
        self.date = date
        self.weightKg = weightKg
        self.reps = reps
    }

    /// The weight's key; 0 for a set without weight.
    var weightKey: WeightKey { WeightKey(weightKg ?? 0) }
}

/// The best estimated one-rep max of an exercise.
public struct OneRepMaxRecord: Equatable, Sendable {
    /// The estimate in kilograms.
    public let estimateKg: Double
    /// The set it was estimated from.
    public let set: RecordSet
}

/// The most volume an exercise had in one session.
public struct VolumeRecord: Equatable, Sendable {
    /// The volume in kilograms.
    public let volumeKg: Double
    /// The session.
    public let sessionID: UUID
    /// When that session started.
    public let date: Date
}

/// The most reps done at one weight.
public struct RepsAtWeight: Identifiable, Equatable, Sendable {
    /// The set with the most reps at this weight (the first one, if several tie).
    public let record: RecordSet

    /// The weight, rounded to 0.01 kg.
    public var id: WeightKey { record.weightKey }
    /// The weight in kilograms, as logged.
    public var weightKg: Double { record.weightKg ?? 0 }
    /// The most reps at this weight.
    public var reps: Int { record.reps }
}

/// An exercise's records over its whole history.
public struct ExerciseRecords: Equatable, Sendable {
    /// The exercise's `id`.
    public let exerciseID: UUID
    /// The heaviest weight, with the most reps done at it.
    public let heaviest: RecordSet?
    /// The best estimated one-rep max.
    public let bestOneRepMax: OneRepMaxRecord?
    /// The most volume in one session.
    public let bestSessionVolume: VolumeRecord?
    /// The most reps at each weight, heaviest first. Weights are compared after rounding
    /// to 0.01 kg.
    public let repsByWeight: [RepsAtWeight]
    /// The most reps in one set without weight (bodyweight or unweighted sets).
    public let mostReps: RecordSet?
}

/// Personal records and the PRs each session set, computed from the whole history.
///
/// Rules:
/// - Only logged working sets of finished sessions count: warm-ups never do. Imported
///   sessions count like any other. A set needs at least 1 rep; weighted records need a
///   weight of at least 0.01 kg (lighter sets count as unweighted).
/// - Sessions are taken oldest first, by start date and then `id`, so ties always resolve
///   the same way. Within a session, sets are taken in order.
/// - A **PR** is a set (or, for volume, the session's total for the exercise) that strictly
///   beats the best of all *earlier* sessions for that exercise:
///   - ``PRKind/weight``: a heavier weight than ever before;
///   - ``PRKind/estimatedOneRepMax``: a better estimate than ever before;
///   - ``PRKind/reps``: more reps at a weight that was done before (or, for a set without
///     weight, more reps than any earlier set without weight);
///   - ``PRKind/volume``: more volume than any earlier session.
///
///   Weights, estimates and volumes are compared after rounding to 0.01 kg, so pounds
///   converted to kilograms never make a PR out of rounding noise.
/// - A kind with no earlier best sets a baseline and earns no PR: the first session of an
///   exercise never shows PRs.
/// - Within one session, only the best set of each kind earns it: the heaviest for weight
///   (then the most reps), the highest estimate, and for reps the heaviest weight (then the
///   most reps); the earliest set wins a tie.
/// - Records themselves (the best ever) take ties in favour of the earlier set.
///
/// Everything is computed in one pass over the history, visiting each logged working set
/// once, so the cost grows linearly with the number of sets.
public struct PersonalRecords: Equatable, Sendable {
    /// No history.
    public static let empty = PersonalRecords(exercises: [:], setKinds: [:], volumeRecords: [:], countBySession: [:])

    /// Each exercise's records, by exercise `id`.
    public let exercises: [UUID: ExerciseRecords]
    let setKinds: [UUID: Set<PRKind>]
    let volumeRecords: [UUID: Set<UUID>]
    let countBySession: [UUID: Int]

    /// The PRs set by the set with `id`: weight, estimated one-rep max and reps only.
    public func kinds(forSet id: UUID) -> Set<PRKind> {
        setKinds[id] ?? []
    }

    /// Whether the exercise's volume in the session was a volume PR.
    public func hasVolumeRecord(session sessionID: UUID, exercise exerciseID: UUID) -> Bool {
        volumeRecords[sessionID]?.contains(exerciseID) ?? false
    }

    /// The number of PRs set in a session: distinct (exercise, kind) pairs.
    public func count(forSession id: UUID) -> Int {
        countBySession[id] ?? 0
    }

    /// The records of the exercise with `id`, if it has any logged working set.
    public func records(forExercise id: UUID) -> ExerciseRecords? {
        exercises[id]
    }

    /// Computes the records and PRs of `sessions` (in any order).
    public static func compute(from sessions: [HistorySession]) -> PersonalRecords {
        var statistics = Statistics()
        return compute(from: sessions, statistics: &statistics)
    }

    /// What a computation did, for tests of its cost.
    struct Statistics: Equatable {
        /// Sessions read.
        var sessions = 0
        /// Logged working sets read.
        var setVisits = 0
    }

    static func compute(from sessions: [HistorySession], statistics: inout Statistics) -> PersonalRecords {
        var running: [UUID: Running] = [:]
        var setKinds: [UUID: Set<PRKind>] = [:]
        var volumeRecords: [UUID: Set<UUID>] = [:]
        var countBySession: [UUID: Int] = [:]

        for session in sessions.sorted(by: HistorySnapshot.isEarlier) {
            statistics.sessions += 1
            var order: [UUID] = []
            var bests: [UUID: SessionBest] = [:]
            for entry in session.entries {
                guard let exerciseID = entry.exerciseID else { continue }
                for set in entry.sets where !set.isWarmup {
                    statistics.setVisits += 1
                    if bests[exerciseID] == nil { order.append(exerciseID) }
                    bests[exerciseID, default: SessionBest()].add(set, session: session, before: running[exerciseID])
                }
            }

            var count = 0
            for exerciseID in order {
                guard let best = bests[exerciseID] else { continue }
                let before = running[exerciseID]
                if let set = best.weightPR {
                    setKinds[set.setID, default: []].insert(.weight)
                    count += 1
                }
                if let candidate = best.oneRepMaxPR {
                    setKinds[candidate.set.setID, default: []].insert(.estimatedOneRepMax)
                    count += 1
                }
                if let set = best.repsPR {
                    setKinds[set.setID, default: []].insert(.reps)
                    count += 1
                }
                if best.volume > 0, let previous = before?.volume, WeightKey(best.volume) > previous.key {
                    volumeRecords[session.id, default: []].insert(exerciseID)
                    count += 1
                }
                running[exerciseID, default: Running()].merge(best, session: session)
            }
            if count > 0 { countBySession[session.id] = count }
        }

        let exercises = Dictionary(uniqueKeysWithValues: running.map { exerciseID, state in
            (exerciseID, state.records(for: exerciseID))
        })
        return PersonalRecords(
            exercises: exercises,
            setKinds: setKinds,
            volumeRecords: volumeRecords,
            countBySession: countBySession
        )
    }
}

// MARK: - The pass

/// An estimate with its rounded key.
private struct Estimate {
    let key: WeightKey
    let valueKg: Double
    let set: RecordSet
}

/// Whether (`key`, `reps`) beats `current` strictly: heavier, or as heavy with more reps.
private func ranks(_ key: WeightKey, _ reps: Int, above current: RecordSet?) -> Bool {
    guard let current else { return true }
    if key != current.weightKey { return key > current.weightKey }
    return reps > current.reps
}

/// An exercise's bests over every session read so far.
private struct Running {
    var heaviest: RecordSet?
    var oneRepMax: Estimate?
    var volume: (key: WeightKey, valueKg: Double, sessionID: UUID, date: Date)?
    var repsByWeight: [WeightKey: RecordSet] = [:]
    var mostReps: RecordSet?

    /// Takes in a session's bests; the earlier record keeps a tie.
    mutating func merge(_ best: SessionBest, session: HistorySession) {
        if let set = best.heaviest, ranks(set.weightKey, set.reps, above: heaviest) {
            heaviest = set
        }
        if let estimate = best.oneRepMax, estimate.key > (oneRepMax?.key ?? WeightKey(0)) {
            oneRepMax = estimate
        }
        if best.volume > 0 {
            let key = WeightKey(best.volume)
            if key > (volume?.key ?? WeightKey(0)) {
                volume = (key, best.volume, session.id, session.startedAt)
            }
        }
        for (key, set) in best.repsByWeight where set.reps > (repsByWeight[key]?.reps ?? 0) {
            repsByWeight[key] = set
        }
        if let set = best.mostReps, set.reps > (mostReps?.reps ?? 0) {
            mostReps = set
        }
    }

    func records(for exerciseID: UUID) -> ExerciseRecords {
        ExerciseRecords(
            exerciseID: exerciseID,
            heaviest: heaviest,
            bestOneRepMax: oneRepMax.map { OneRepMaxRecord(estimateKg: $0.valueKg, set: $0.set) },
            bestSessionVolume: volume.map { VolumeRecord(volumeKg: $0.valueKg, sessionID: $0.sessionID, date: $0.date) },
            repsByWeight: repsByWeight.sorted { $0.key > $1.key }.map { RepsAtWeight(record: $0.value) },
            mostReps: mostReps
        )
    }
}

/// An exercise's bests within one session, and the sets that beat every earlier session.
private struct SessionBest {
    var heaviest: RecordSet?
    var oneRepMax: Estimate?
    var repsByWeight: [WeightKey: RecordSet] = [:]
    var mostReps: RecordSet?
    var volume: Double = 0

    var weightPR: RecordSet?
    var oneRepMaxPR: Estimate?
    var repsPR: RecordSet?

    /// Reads one logged working set, comparing it with `before` (earlier sessions only).
    mutating func add(_ set: HistorySet, session: HistorySession, before: Running?) {
        guard let reps = set.reps, reps >= 1 else { return }
        let weight = set.effectiveWeightKg
        let record = RecordSet(setID: set.id, sessionID: session.id, date: session.startedAt, weightKg: weight, reps: reps)
        let key = record.weightKey

        guard let weight else {
            if reps > (mostReps?.reps ?? 0) { mostReps = record }
            if let previous = before?.mostReps, reps > previous.reps, ranks(key, reps, above: repsPR) {
                repsPR = record
            }
            return
        }

        volume += weight * Double(reps)
        if ranks(key, reps, above: heaviest) { heaviest = record }
        if let previous = before?.heaviest, key > previous.weightKey, ranks(key, reps, above: weightPR) {
            weightPR = record
        }

        if let value = OneRepMax.estimate(weightKg: weight, reps: reps) {
            let estimate = Estimate(key: WeightKey(value), valueKg: value, set: record)
            if estimate.key > (oneRepMax?.key ?? WeightKey(0)) { oneRepMax = estimate }
            if let previous = before?.oneRepMax, estimate.key > previous.key,
               estimate.key > (oneRepMaxPR?.key ?? WeightKey(0)) {
                oneRepMaxPR = estimate
            }
        }

        if reps > (repsByWeight[key]?.reps ?? 0) { repsByWeight[key] = record }
        if let previous = before?.repsByWeight[key], reps > previous.reps, ranks(key, reps, above: repsPR) {
            repsPR = record
        }
    }
}
