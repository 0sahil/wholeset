// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// One logged set of a finished session, as plain data.
///
/// Only sets with a `completedAt` date become history: planned sets that were never logged
/// do not exist here, so nothing computed from history can count them by mistake.
public struct HistorySet: Identifiable, Equatable, Sendable {
    /// The `SetLog`'s identifier.
    public let id: UUID
    /// Whether the set was a warm-up. Warm-ups never count towards volume, set counts or records.
    public let isWarmup: Bool
    /// Weight in kilograms; `nil` for a set logged without weight.
    public let weightKg: Double?
    /// Repetitions; `nil` if none were recorded (for example a timed set).
    public let reps: Int?
    /// When the set was logged.
    public let completedAt: Date

    /// Creates a history set.
    public init(id: UUID = UUID(), isWarmup: Bool = false, weightKg: Double? = nil, reps: Int? = nil, completedAt: Date) {
        self.id = id
        self.isWarmup = isWarmup
        self.weightKg = weightKg
        self.reps = reps
        self.completedAt = completedAt
    }
}

/// One exercise of a finished session, as plain data.
public struct HistoryEntry: Identifiable, Equatable, Sendable {
    /// The `SessionExercise`'s identifier.
    public let id: UUID
    /// The exercise's `id`; `nil` if the exercise no longer exists.
    public let exerciseID: UUID?
    /// The exercise's name, or an empty string if it no longer exists.
    public let exerciseName: String
    /// The routine slot the entry came from (see ``SessionExercise/routineItemID``).
    public let routineItemID: UUID?
    /// Whether the exercise was skipped.
    public let isSkipped: Bool
    /// The logged sets in display order, warm-ups included.
    public let sets: [HistorySet]

    /// Creates a history entry.
    public init(
        id: UUID = UUID(),
        exerciseID: UUID?,
        exerciseName: String,
        routineItemID: UUID? = nil,
        isSkipped: Bool = false,
        sets: [HistorySet]
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.routineItemID = routineItemID
        self.isSkipped = isSkipped
        self.sets = sets
    }

    /// The logged sets that are not warm-ups.
    public var workingSets: [HistorySet] { sets.filter { !$0.isWarmup } }
}

/// A finished session, as plain data that can be computed with on any thread.
public struct HistorySession: Identifiable, Equatable, Sendable {
    /// The `Session`'s identifier.
    public let id: UUID
    /// The name the session was saved with (a snapshot of the routine's name).
    public let name: String
    /// The current name of the routine it was started from, if that routine still exists.
    public let routineName: String?
    /// When the session started.
    public let startedAt: Date
    /// When the session ended.
    public let endedAt: Date
    /// Where the session came from.
    public let source: Source
    /// The session's notes.
    public let notes: String
    /// Average heart rate in beats per minute, if known.
    public let averageHeartRate: Double?
    /// Maximum heart rate in beats per minute, if known.
    public let maximumHeartRate: Double?
    /// Active energy in kilocalories, if known.
    public let activeKilocalories: Double?
    /// The exercises in display order, including those without a logged set.
    public let entries: [HistoryEntry]

    /// Creates a history session.
    public init(
        id: UUID = UUID(),
        name: String,
        routineName: String? = nil,
        startedAt: Date,
        endedAt: Date,
        source: Source = .watch,
        notes: String = "",
        averageHeartRate: Double? = nil,
        maximumHeartRate: Double? = nil,
        activeKilocalories: Double? = nil,
        entries: [HistoryEntry]
    ) {
        self.id = id
        self.name = name
        self.routineName = routineName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.source = source
        self.notes = notes
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.activeKilocalories = activeKilocalories
        self.entries = entries
    }

    /// Whether the session was imported from another app.
    public var isImported: Bool { source.isImported }

    /// The name to show: the saved name, else the routine's current name, else empty.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return routineName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// Turns stored sessions into ``HistorySession`` values.
public enum HistorySnapshot {
    /// The order of history: by start date, then by `id`, so sessions that started at the
    /// same moment still sort the same way on every device.
    public static func isEarlier(_ lhs: HistorySession, _ rhs: HistorySession) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// The value of `session`, or `nil` while it is still in progress (`endedAt` is `nil`).
    public static func session(from session: Session) -> HistorySession? {
        make(session, entries: session.sortedEntries) { $0.sortedSets }
    }

    /// The finished sessions among `sessions`, oldest first (see ``isEarlier(_:_:)``).
    public static func sessions(from sessions: some Sequence<Session>) -> [HistorySession] {
        sessions.compactMap { session(from: $0) }.sorted(by: isEarlier)
    }

    /// Every finished session in `context`, oldest first.
    ///
    /// Reads sessions, their exercises and their logged sets with one fetch per model type
    /// and groups them in memory, rather than following each session's relationships (which
    /// would cost a fetch per session and per exercise on a large history).
    public static func load(in context: ModelContext) throws -> [HistorySession] {
        let sessions = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.endedAt != nil }))
        guard !sessions.isEmpty else { return [] }
        // Exercises and routines are fetched so the names read below are already in memory.
        _ = try context.fetch(FetchDescriptor<Exercise>())
        _ = try context.fetch(FetchDescriptor<Routine>())
        let entries = try context.fetch(FetchDescriptor<SessionExercise>())
        let sets = try context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.completedAt != nil }))

        var entriesBySession: [PersistentIdentifier: [SessionExercise]] = [:]
        for entry in entries {
            guard let session = entry.session else { continue }
            entriesBySession[session.persistentModelID, default: []].append(entry)
        }
        var setsByEntry: [PersistentIdentifier: [SetLog]] = [:]
        for set in sets {
            guard let entry = set.entry else { continue }
            setsByEntry[entry.persistentModelID, default: []].append(set)
        }
        return sessions.compactMap { session in
            make(session, entries: (entriesBySession[session.persistentModelID] ?? []).sortedByOrder()) { entry in
                (setsByEntry[entry.persistentModelID] ?? []).sortedByOrder()
            }
        }
        .sorted(by: isEarlier)
    }

    private static func make(
        _ session: Session,
        entries: [SessionExercise],
        sets: (SessionExercise) -> [SetLog]
    ) -> HistorySession? {
        guard let endedAt = session.endedAt else { return nil }
        return HistorySession(
            id: session.id,
            name: session.name,
            routineName: session.routine?.name,
            startedAt: session.startedAt,
            endedAt: endedAt,
            source: session.source,
            notes: session.notes,
            averageHeartRate: session.avgHR,
            maximumHeartRate: session.maxHR,
            activeKilocalories: session.activeKcal,
            entries: entries.map { entry in
                HistoryEntry(
                    id: entry.id,
                    exerciseID: entry.exercise?.id,
                    exerciseName: entry.exercise?.name ?? "",
                    routineItemID: entry.routineItemID,
                    isSkipped: entry.isSkipped,
                    sets: sets(entry).compactMap { set in
                        guard let completedAt = set.completedAt else { return nil }
                        return HistorySet(
                            id: set.id,
                            isWarmup: set.isWarmup,
                            weightKg: set.weightKg,
                            reps: set.reps,
                            completedAt: completedAt
                        )
                    }
                )
            }
        )
    }
}
