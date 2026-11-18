// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV2 {
    /// One exercise slot in a routine, with its set and rep targets.
    @Model
    public final class RoutineItem {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        /// The owning routine (inverse of ``Routine/items``).
        public var routine: Routine?
        /// The exercise to perform (inverse of ``Exercise/routineItems``).
        public var exercise: Exercise?
        /// Position within the routine.
        public var order: Int = 0
        public var targetSets: Int = 3
        /// Bottom of the target rep range.
        public var repLow: Int = 8
        /// Top of the target rep range.
        public var repHigh: Int = 12
        /// Rest after each set; `nil` uses the exercise or app default.
        public var restSeconds: Int?

        /// Creates a routine item. Attach it to a routine and exercise after insertion.
        public init(order: Int = 0, targetSets: Int = 3, repLow: Int = 8, repHigh: Int = 12, restSeconds: Int? = nil) {
            self.order = order
            self.targetSets = targetSets
            self.repLow = repLow
            self.repHigh = repHigh
            self.restSeconds = restSeconds
        }
    }
}

extension RoutineItem: OrderedChild {}
