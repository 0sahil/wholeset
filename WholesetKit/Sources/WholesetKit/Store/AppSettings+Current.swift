// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension AppSettings {
    /// Returns the single settings row, creating it if none exists.
    ///
    /// CloudKit sync can produce duplicates, typically when a newly set-up device
    /// creates a default row before the existing one has synced down. These are
    /// collapsed deterministically so every device converges on the same result:
    /// - the survivor is the oldest row (by `createdAt`, then `id`);
    /// - it takes its values from the most recently *edited* row: rows never edited
    ///   (`updatedAt == createdAt`) rank below edited ones, then by `updatedAt`,
    ///   then `id`. A fresh default row therefore never overrides real choices;
    /// - ``starterRoutinesDecidedAt`` becomes the earliest date any row has, because the
    ///   first decision made on any device is the one that stands;
    /// - all other rows are deleted.
    ///
    /// Saves the context when it creates or collapses rows.
    public static func current(in context: ModelContext) throws -> AppSettings {
        let rows = try context.fetch(FetchDescriptor<AppSettings>())

        guard let survivor = rows.min(by: isOlder) else {
            let created = AppSettings()
            context.insert(created)
            try context.save()
            return created
        }
        guard rows.count > 1 else { return survivor }

        if let source = rows.max(by: hasOlderValues), source !== survivor {
            survivor.copyValues(from: source)
        }
        survivor.starterRoutinesDecidedAt = rows.compactMap(\.starterRoutinesDecidedAt).min()
        for row in rows where row !== survivor {
            context.delete(row)
        }
        try context.save()
        return survivor
    }

    /// Whether any setting was changed after the row was created (for example the unit
    /// chosen on another device and synced).
    public var wasEdited: Bool { updatedAt > createdAt }

    /// Copies every user-facing value. New settings properties must be added here.
    private func copyValues(from other: AppSettings) {
        unitRaw = other.unitRaw
        defaultRestSeconds = other.defaultRestSeconds
        weightCrownSensitivityRaw = other.weightCrownSensitivityRaw
        repsCrownSensitivityRaw = other.repsCrownSensitivityRaw
        progressionStepsRaw = other.progressionStepsRaw
        updatedAt = other.updatedAt
    }

    private static func isOlder(_ lhs: AppSettings, _ rhs: AppSettings) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func hasOlderValues(_ lhs: AppSettings, _ rhs: AppSettings) -> Bool {
        if lhs.wasEdited != rhs.wasEdited { return !lhs.wasEdited }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
