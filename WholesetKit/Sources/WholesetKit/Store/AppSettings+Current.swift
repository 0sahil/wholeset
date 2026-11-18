// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV1.AppSettings {
    /// Returns the single settings row, creating it if none exists.
    ///
    /// CloudKit sync can produce duplicates, typically when a newly set-up device
    /// creates a default row before the existing one has synced down. These are
    /// collapsed deterministically so every device converges on the same result:
    /// - the survivor is the oldest row (by `createdAt`, then `id`);
    /// - it takes its values from the most recently *edited* row: rows never edited
    ///   (`updatedAt == createdAt`) rank below edited ones, then by `updatedAt`,
    ///   then `id`. A fresh default row therefore never overrides real choices;
    /// - all other rows are deleted.
    ///
    /// Saves the context when it creates or collapses rows.
    public static func current(in context: ModelContext) throws -> SchemaV1.AppSettings {
        let rows = try context.fetch(FetchDescriptor<SchemaV1.AppSettings>())

        guard let survivor = rows.min(by: isOlder) else {
            let created = SchemaV1.AppSettings()
            context.insert(created)
            try context.save()
            return created
        }
        guard rows.count > 1 else { return survivor }

        if let source = rows.max(by: hasOlderValues), source !== survivor {
            survivor.copyValues(from: source)
        }
        for row in rows where row !== survivor {
            context.delete(row)
        }
        try context.save()
        return survivor
    }

    /// Whether any setting was changed after the row was created.
    private var wasEdited: Bool { updatedAt > createdAt }

    /// Copies every user-facing value. New settings properties must be added here.
    private func copyValues(from other: SchemaV1.AppSettings) {
        unitRaw = other.unitRaw
        defaultRestSeconds = other.defaultRestSeconds
        updatedAt = other.updatedAt
    }

    private static func isOlder(_ lhs: SchemaV1.AppSettings, _ rhs: SchemaV1.AppSettings) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func hasOlderValues(_ lhs: SchemaV1.AppSettings, _ rhs: SchemaV1.AppSettings) -> Bool {
        if lhs.wasEdited != rhs.wasEdited { return !lhs.wasEdited }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
