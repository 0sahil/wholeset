// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV2 {
    /// One set of an exercise: planned until ``completedAt`` is set.
    @Model
    public final class SetLog {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        /// The owning session entry (inverse of ``SessionExercise/sets``).
        public var entry: SessionExercise?
        /// Position within the entry.
        public var order: Int = 0
        /// Weight in kilograms; converted to the display unit only in the UI.
        public var weightKg: Double?
        public var reps: Int?
        /// For timed sets such as planks.
        public var durationSeconds: Int?
        public var isWarmup: Bool = false
        /// Rating of perceived exertion.
        public var rpe: Double?
        public var note: String = ""
        /// When the set was logged; `nil` means planned but not done.
        public var completedAt: Date?

        /// Creates a set. Attach it to an entry after insertion into a context.
        public init(order: Int = 0, weightKg: Double? = nil, reps: Int? = nil, isWarmup: Bool = false) {
            self.order = order
            self.weightKg = weightKg
            self.reps = reps
            self.isWarmup = isWarmup
        }
    }
}

extension SetLog: OrderedChild {}
