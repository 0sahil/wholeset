// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// Finds a Watch workout that was still running when the app last stopped.
public enum WorkoutRecovery {
    /// Watch sessions that have not ended, newest first (by start, then `id`).
    public static func inProgressWatchSessions(in context: ModelContext) throws -> [Session] {
        let watch = Source.watch.rawValue
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.endedAt == nil && $0.sourceRaw == watch }
        )
        return try context.fetch(descriptor).sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    /// Returns the newest in-progress Watch session and tidies up any older ones.
    ///
    /// Several can only exist if the app failed again while a recovered workout was being
    /// set up. Older ones are closed so nothing logged is lost: one with logged sets gets
    /// `endedAt` set to its last logged set (it then shows up as a normal past workout,
    /// without a Health workout); one with no logged set is deleted. Saves if anything changed.
    public static func resolveInProgressSession(in context: ModelContext) throws -> Session? {
        let sessions = try inProgressWatchSessions(in: context)
        guard let newest = sessions.first else { return nil }
        for stale in sessions.dropFirst() {
            if let lastLogged = lastLoggedDate(in: stale) {
                stale.endedAt = lastLogged
                stale.updatedAt = Date.now
            } else {
                context.delete(stale)
            }
        }
        if context.hasChanges {
            try context.save()
        }
        return newest
    }

    /// When the most recent set of `session` was logged, if any was.
    public static func lastLoggedDate(in session: Session) -> Date? {
        (session.entries ?? [])
            .flatMap { $0.sets ?? [] }
            .compactMap(\.completedAt)
            .max()
    }
}

/// Keys of the custom metadata stored on HealthKit workouts, linking them back to sessions.
public enum HealthKitMetadataKey {
    /// The routine name (a `String`).
    public static let routineName = "wholeset.routine"
    /// The session's `id` as a UUID string.
    public static let sessionID = "wholeset.sessionID"
}

/// What a finished HealthKit workout reports back to its session.
public struct HealthWorkoutSummary: Equatable, Sendable {
    /// The saved `HKWorkout`'s UUID.
    public var workoutID: UUID?
    /// Average heart rate in beats per minute.
    public var averageHeartRate: Double?
    /// Maximum heart rate in beats per minute.
    public var maxHeartRate: Double?
    /// Active energy in kilocalories.
    public var activeKilocalories: Double?

    /// Creates a summary.
    public init(workoutID: UUID? = nil, averageHeartRate: Double? = nil, maxHeartRate: Double? = nil, activeKilocalories: Double? = nil) {
        self.workoutID = workoutID
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeKilocalories = activeKilocalories
    }
}

extension Session {
    /// Copies the HealthKit results onto the session. Values that are `nil` in `summary`
    /// leave the stored ones untouched. Does not save.
    public func apply(_ summary: HealthWorkoutSummary, at date: Date = .now) {
        if let workoutID = summary.workoutID { healthKitWorkoutID = workoutID }
        if let average = summary.averageHeartRate { avgHR = average }
        if let max = summary.maxHeartRate { maxHR = max }
        if let kcal = summary.activeKilocalories { activeKcal = kcal }
        updatedAt = date
    }
}
