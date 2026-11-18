// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// The exercises done most recently, for the Watch's "Add exercise" list.
public enum RecentExercises {
    /// How many sessions are read per fetch while collecting.
    static let batchSize = 25

    /// Distinct, non-archived exercises with a logged set in the newest finished sessions,
    /// most recent first: sessions newest first (by start date), and within a session the
    /// exercise whose last set was logged latest first.
    public static func recent(limit: Int = 20, in context: ModelContext) throws -> [Exercise] {
        guard limit > 0 else { return [] }
        var collector = Collector(limit: limit)
        var offset = 0
        while !collector.isFull {
            var descriptor = FetchDescriptor<Session>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let sessions = try context.fetch(descriptor)
            collector.add(sessions)
            guard sessions.count == batchSize else { break }
            offset += batchSize
        }
        return collector.exercises
    }

    /// The same selection over `sessions`, which must already be newest first.
    public static func recent(from sessions: [Session], limit: Int = 20) -> [Exercise] {
        var collector = Collector(limit: limit)
        collector.add(sessions)
        return collector.exercises
    }

    private struct Collector {
        let limit: Int
        var exercises: [Exercise] = []
        var seen: Set<PersistentIdentifier> = []

        var isFull: Bool { exercises.count >= limit }

        mutating func add(_ sessions: [Session]) {
            for session in sessions where session.endedAt != nil {
                let performed = (session.entries ?? []).compactMap { entry -> (Exercise, Date)? in
                    guard let exercise = entry.exercise, !exercise.isArchived,
                          let last = (entry.sets ?? []).compactMap(\.completedAt).max() else { return nil }
                    return (exercise, last)
                }
                for (exercise, _) in performed.sorted(by: { $0.1 > $1.1 }) {
                    guard !isFull else { return }
                    if seen.insert(exercise.persistentModelID).inserted {
                        exercises.append(exercise)
                    }
                }
            }
        }
    }
}
