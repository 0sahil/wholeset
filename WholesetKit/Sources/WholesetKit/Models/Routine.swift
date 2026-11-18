// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV2 {
    /// A reusable workout template: an ordered list of exercises with targets.
    ///
    /// Code that edits a routine or one of its items sets the routine's `updatedAt`:
    /// a routine whose `updatedAt` still equals its `createdAt` counts as never edited,
    /// which lets sync duplicates of an untouched starter routine be merged safely.
    @Model
    public final class Routine {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var name: String = ""
        public var notes: String = ""
        /// Position in the routines list (CloudKit has no ordered relationships).
        public var sortIndex: Int = 0
        /// The starter template this routine was seeded from (``StarterRoutines/Template/key``);
        /// `nil` for routines the user made.
        public var seedKey: String?

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

extension Routine {
    /// ``items`` in display order.
    public var sortedItems: [RoutineItem] {
        (items ?? []).sortedByOrder()
    }
}
