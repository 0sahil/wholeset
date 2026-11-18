// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV3 {
    /// One exercise performed within a session.
    @Model
    public final class SessionExercise {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        /// The owning session (inverse of ``Session/entries``).
        public var session: Session?
        /// The exercise performed (inverse of ``Exercise/sessionEntries``).
        public var exercise: Exercise?
        /// Position within the session.
        public var order: Int = 0
        /// Snapshot of the routine's rep range when the session started.
        public var repLow: Int?
        /// Snapshot of the routine's rep range when the session started.
        public var repHigh: Int?
        /// Whether the user skipped the exercise for this session. A skipped exercise counts
        /// as done; its logged sets stay, its unlogged sets are simply not done.
        public var isSkipped: Bool = false
        /// The `id` of the ``RoutineItem`` this entry was created from. Kept as a plain value
        /// rather than a relationship, so editing or deleting the routine never touches past
        /// sessions. Swapping the exercise keeps it; `nil` means the exercise was added during
        /// the workout (or the session predates schema version 3).
        public var routineItemID: UUID?

        /// The sets logged or planned. Deleted with the entry. Use ``sortedSets``.
        @Relationship(deleteRule: .cascade, inverse: \SetLog.entry)
        public var sets: [SetLog]? = []

        /// Creates a session entry. Attach it to a session and exercise after insertion.
        public init(order: Int = 0, repLow: Int? = nil, repHigh: Int? = nil) {
            self.order = order
            self.repLow = repLow
            self.repHigh = repHigh
        }
    }
}

extension SessionExercise: OrderedChild {}

extension SessionExercise {
    /// ``sets`` in display order.
    public var sortedSets: [SetLog] {
        (sets ?? []).sortedByOrder()
    }

    /// Whether at least one set has been logged.
    public var hasLoggedSet: Bool {
        (sets ?? []).contains { $0.completedAt != nil }
    }
}
