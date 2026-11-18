// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV1 {
    /// A reusable workout template: an ordered list of exercises with targets.
    @Model
    public final class Routine {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var name: String = ""
        public var notes: String = ""
        /// Position in the routines list (CloudKit has no ordered relationships).
        public var sortIndex: Int = 0

        /// The routine's exercise slots. Deleted with the routine. Use ``sortedItems``.
        @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine)
        public var items: [RoutineItem]? = []

        /// Sessions started from this routine. Deleting the routine keeps them.
        @Relationship(deleteRule: .nullify, inverse: \Session.routine)
        public var sessions: [Session]? = []

        /// Weekly plan days that point at this routine. Deleting it turns them into rest days.
        @Relationship(deleteRule: .nullify, inverse: \WeekPlanDay.routine)
        public var weekPlanDays: [WeekPlanDay]? = []

        /// Creates a routine. Items are added after insertion into a context.
        public init(name: String = "", notes: String = "", sortIndex: Int = 0) {
            self.name = name
            self.notes = notes
            self.sortIndex = sortIndex
        }
    }
}

extension SchemaV1.Routine {
    /// ``items`` in display order.
    public var sortedItems: [SchemaV1.RoutineItem] {
        (items ?? []).sortedByOrder()
    }
}
