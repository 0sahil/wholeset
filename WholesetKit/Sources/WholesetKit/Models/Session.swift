// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV1 {
    /// A workout: logged live on a device or imported from another app.
    @Model
    public final class Session {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        /// Snapshot of the routine name when the session started.
        public var name: String = ""
        /// The routine it was started from (inverse of ``Routine/sessions``).
        /// Becomes `nil` if that routine is deleted.
        public var routine: Routine?
        public var startedAt: Date = Date.now
        /// `nil` while the session is still in progress.
        public var endedAt: Date?
        public var notes: String = ""
        /// Raw storage for ``source``.
        public var sourceRaw: String = Source.watch.rawValue
        /// Key used to skip sessions that were already imported.
        public var externalKey: String?
        /// The matching HealthKit workout, once it has been saved.
        public var healthKitWorkoutID: UUID?
        /// Average heart rate in beats per minute.
        public var avgHR: Double?
        /// Maximum heart rate in beats per minute.
        public var maxHR: Double?
        /// Active energy in kilocalories.
        public var activeKcal: Double?

        /// The exercises performed. Deleted with the session. Use ``sortedEntries``.
        @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
        public var entries: [SessionExercise]? = []

        /// Creates a session. Entries are added after insertion into a context.
        public init(name: String = "", startedAt: Date = .now, source: Source = .watch) {
            self.name = name
            self.startedAt = startedAt
            self.sourceRaw = source.rawValue
        }
    }
}

extension SchemaV1.Session {
    /// Where the session came from. Unknown stored values read as ``Source/watch``.
    public var source: Source {
        get { Source(persisted: sourceRaw) }
        set { sourceRaw = newValue.rawValue }
    }

    /// ``entries`` in display order.
    public var sortedEntries: [SchemaV1.SessionExercise] {
        (entries ?? []).sortedByOrder()
    }
}
