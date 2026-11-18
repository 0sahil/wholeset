// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV1 {
    /// One day of the weekly plan: a routine to do, or a rest day when ``routine`` is `nil`.
    @Model
    public final class WeekPlanDay {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        /// `Calendar` weekday number: 1 = Sunday … 7 = Saturday.
        public var weekday: Int = 1
        /// The planned routine (inverse of ``Routine/weekPlanDays``); `nil` means rest.
        public var routine: Routine?

        /// Creates a plan day. Assign ``routine`` after insertion into a context.
        public init(weekday: Int = 1) {
            self.weekday = weekday
        }
    }
}
