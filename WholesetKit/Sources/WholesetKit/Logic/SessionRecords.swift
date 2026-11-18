// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// One personal record set in a session, as one line of a summary.
public struct SessionRecord: Identifiable, Equatable, Sendable {
    /// What makes the record, with weights in kilograms.
    public enum Value: Equatable, Sendable {
        /// A heavier weight than ever before: the set's weight and reps.
        case weight(kilograms: Double, reps: Int)
        /// A better estimated one-rep max than ever before (see ``OneRepMax``).
        case estimatedOneRepMax(kilograms: Double)
        /// More reps at a weight done before; `kilograms` is `nil` for a set without weight,
        /// which beat every earlier set without weight.
        case reps(Int, kilograms: Double?)
        /// More volume for the exercise than in any earlier session.
        case volume(kilograms: Double)

        /// The kind of record.
        public var kind: PRKind {
            switch self {
            case .weight: .weight
            case .estimatedOneRepMax: .estimatedOneRepMax
            case .reps: .reps
            case .volume: .volume
            }
        }
    }

    /// Identifies a record within a session: one per exercise and kind.
    public struct ID: Hashable, Sendable {
        /// The exercise's `id`.
        public let exerciseID: UUID
        /// The kind of record.
        public let kind: PRKind
    }

    /// The exercise's `id`.
    public let exerciseID: UUID
    /// The exercise's name.
    public let exerciseName: String
    /// What makes it a record.
    public let value: Value

    /// Creates a record line.
    public init(exerciseID: UUID, exerciseName: String, value: Value) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.value = value
    }

    /// The kind of record.
    public var kind: PRKind { value.kind }

    /// The exercise and kind.
    public var id: ID { ID(exerciseID: exerciseID, kind: kind) }
}

/// The personal records one session set, exactly as ``PersonalRecords`` counts them, as
/// lines for the end-of-workout summary.
///
/// Every rule comes from ``PersonalRecords``: the same kinds, no records in the first session
/// of an exercise, only the best set of each kind within the session, the volume record per
/// exercise, warm-ups and unlogged sets never count, and ties resolve the same way.
///
/// Lines come in workout order (by each exercise's first entry in the session), and within
/// an exercise in ``PRKind`` order: weight, estimated one-rep max, reps, volume. There is one
/// line per record, so ``count`` is both the number of lines and the session's PR count in
/// the history list (``PersonalRecords/count(forSession:)``).
public struct SessionRecords: Equatable, Sendable {
    /// The session's identifier.
    public let sessionID: UUID
    /// One line per record, in display order.
    public let records: [SessionRecord]

    /// The number of records: distinct (exercise, kind) pairs.
    public var count: Int { records.count }

    /// Whether the session set no record.
    public var isEmpty: Bool { records.isEmpty }

    /// The records `session` set, measured against `history`.
    ///
    /// - Parameters:
    ///   - session: A finished session.
    ///   - history: Earlier finished sessions. It may be the whole history, the session
    ///     itself and later sessions included: only the parts that can matter are read
    ///     (see ``relevantHistory(for:in:)``).
    public init(session: HistorySession, history: [HistorySession]) {
        let relevant = Self.relevantHistory(for: session, in: history)
        self.init(session: session, records: PersonalRecords.compute(from: relevant + [session]))
    }

    /// The lines for `session`, read from `records` computed over a history containing it.
    public init(session: HistorySession, records: PersonalRecords) {
        sessionID = session.id

        var order: [UUID] = []
        var names: [UUID: String] = [:]
        var setsByKind: [UUID: [PRKind: HistorySet]] = [:]
        for entry in session.entries {
            guard let exerciseID = entry.exerciseID else { continue }
            if names[exerciseID] == nil {
                order.append(exerciseID)
                names[exerciseID] = entry.exerciseName
            }
            for set in entry.sets where !set.isWarmup {
                for kind in records.kinds(forSet: set.id) where setsByKind[exerciseID]?[kind] == nil {
                    setsByKind[exerciseID, default: [:]][kind] = set
                }
            }
        }

        let volumes = SessionMetrics.volumeByExercise(of: session)
        var lines: [SessionRecord] = []
        for exerciseID in order {
            let sets = setsByKind[exerciseID] ?? [:]
            var values: [SessionRecord.Value] = []
            if let set = sets[.weight], let weight = set.effectiveWeightKg, let reps = set.reps {
                values.append(.weight(kilograms: weight, reps: reps))
            }
            if let set = sets[.estimatedOneRepMax], let estimate = set.estimatedOneRepMaxKg {
                values.append(.estimatedOneRepMax(kilograms: estimate))
            }
            if let set = sets[.reps], let reps = set.reps {
                values.append(.reps(reps, kilograms: set.effectiveWeightKg))
            }
            if records.hasVolumeRecord(session: session.id, exercise: exerciseID) {
                values.append(.volume(kilograms: volumes[exerciseID] ?? 0))
            }
            let name = names[exerciseID] ?? ""
            lines += values.map { SessionRecord(exerciseID: exerciseID, exerciseName: name, value: $0) }
        }
        self.records = lines
    }

    /// The part of `history` that can change the records of `session`: the sessions before
    /// it (in ``HistorySnapshot/isEarlier(_:_:)`` order) that have an exercise of `session`,
    /// each cut down to the entries of those exercises.
    ///
    /// Records are kept per exercise, so this gives the same records for `session` as the
    /// whole history does, at a fraction of the work on a long history.
    public static func relevantHistory(for session: HistorySession, in history: [HistorySession]) -> [HistorySession] {
        let exerciseIDs = Set(session.entries.compactMap(\.exerciseID))
        guard !exerciseIDs.isEmpty else { return [] }
        return history.compactMap { candidate in
            guard candidate.id != session.id, HistorySnapshot.isEarlier(candidate, session) else { return nil }
            let entries = candidate.entries.filter { $0.exerciseID.map(exerciseIDs.contains) ?? false }
            guard !entries.isEmpty else { return nil }
            return candidate.keepingEntries(entries)
        }
        .sorted(by: HistorySnapshot.isEarlier)
    }

    /// Loads the finished session with `id` and the history that matters for it (see
    /// ``relevantHistory(for:in:)``) from `context`, and works out its records.
    ///
    /// Only the entries of the session's exercises are read, with their sessions and logged
    /// sets, rather than the whole history.
    ///
    /// - Returns: `nil` when the session does not exist or is not finished.
    public static func load(sessionID: UUID, in context: ModelContext) throws -> SessionRecords? {
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })
        guard let stored = try context.fetch(descriptor).first,
              let session = HistorySnapshot.session(from: stored) else { return nil }
        return SessionRecords(session: session, history: try history(for: session, in: context))
    }

    /// ``load(sessionID:in:)`` with a context of its own, off the caller's actor. A new
    /// context sees everything saved before the call.
    @concurrent
    public static func load(sessionID: UUID, from container: ModelContainer) async throws -> SessionRecords? {
        try load(sessionID: sessionID, in: ModelContext(container))
    }

    /// The finished sessions before `session` that have one of its exercises, holding only
    /// the entries of those exercises; the store's counterpart of ``relevantHistory(for:in:)``.
    static func history(for session: HistorySession, in context: ModelContext) throws -> [HistorySession] {
        let exerciseIDs = Array(Set(session.entries.compactMap(\.exerciseID)))
        guard !exerciseIDs.isEmpty else { return [] }

        // Exercises and routines are fetched so the names read below are already in memory.
        _ = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { exerciseIDs.contains($0.id) }))
        _ = try context.fetch(FetchDescriptor<Routine>())
        var descriptor = FetchDescriptor<SessionExercise>(predicate: #Predicate { entry in
            entry.exercise.flatMap { exerciseIDs.contains($0.id) } == true
        })
        descriptor.relationshipKeyPathsForPrefetching = [\.session, \.sets]
        let entries = try context.fetch(descriptor)

        var owners: [PersistentIdentifier: Session] = [:]
        var entriesBySession: [PersistentIdentifier: [SessionExercise]] = [:]
        for entry in entries {
            guard let owner = entry.session, owner.endedAt != nil, owner.id != session.id,
                  isEarlier(owner, than: session) else { continue }
            owners[owner.persistentModelID] = owner
            entriesBySession[owner.persistentModelID, default: []].append(entry)
        }
        return owners.compactMap { key, owner in
            HistorySnapshot.session(from: owner, entries: (entriesBySession[key] ?? []).sortedByOrder())
        }
        .sorted(by: HistorySnapshot.isEarlier)
    }

    /// ``HistorySnapshot/isEarlier(_:_:)`` for a stored session.
    private static func isEarlier(_ stored: Session, than session: HistorySession) -> Bool {
        if stored.startedAt != session.startedAt { return stored.startedAt < session.startedAt }
        return stored.id.uuidString < session.id.uuidString
    }
}

extension HistorySession {
    /// The same session with only `entries`.
    func keepingEntries(_ entries: [HistoryEntry]) -> HistorySession {
        HistorySession(
            id: id,
            name: name,
            routineName: routineName,
            startedAt: startedAt,
            endedAt: endedAt,
            source: source,
            notes: notes,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            activeKilocalories: activeKilocalories,
            entries: entries
        )
    }
}
