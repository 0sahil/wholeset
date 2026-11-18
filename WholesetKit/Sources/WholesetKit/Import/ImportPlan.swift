// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The key that recognises an imported workout when the same export (or a newer one) is
/// imported again, stored as ``SchemaV3/Session/externalKey``.
public enum ImportKey {
    /// `"<start>|<name>"`: the start to the second, then the workout name lower-cased,
    /// trimmed and with inner whitespace collapsed. A file's own grouping key (Strong's
    /// `Workout #`) is never used, so the key is the same whichever export generation the
    /// workout came from.
    ///
    /// - Parameter wallClockZone: For files whose dates carry no zone (Strong, Hevy, FitNotes,
    ///   StrongLifts), the zone they were read in: the start is then written as the wall-clock
    ///   time the file says, without a zone (`2025-09-15T07:48:00`), so importing the same file
    ///   in another time zone recognises the same workouts. `nil` for dates with a zone
    ///   (Fitbod, Liftosaur): the instant in UTC (`2022-01-05T22:06:49Z`).
    public static func externalKey(start: Date, name: String, wallClockZone: TimeZone? = nil) -> String {
        "\(timestamp(start, wallClockZone: wallClockZone))|\(normalizedName(name))"
    }

    /// The name part of the key.
    static func normalizedName(_ name: String) -> String {
        name.lowercased(with: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// `yyyy-MM-ddTHH:mm:ssZ` in UTC, or `yyyy-MM-ddTHH:mm:ss` wall-clock in `wallClockZone`;
    /// truncated to the second.
    static func timestamp(_ date: Date, wallClockZone: TimeZone? = nil) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = wallClockZone ?? .gmt
        let seconds = date.timeIntervalSince1970.rounded(.down)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: seconds))
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        ) + (wallClockZone == nil ? "Z" : "")
    }
}

/// Which parsed workouts an import will add.
///
/// Uniqueness is enforced here rather than by the store (CloudKit allows no unique
/// constraints): a workout whose ``ImportedWorkout/externalKey`` is already a session's key
/// is skipped, so importing the same file twice adds nothing and a newer export adds only
/// the new workouts.
public struct ImportPlan: Sendable, Equatable {
    /// The workouts to insert, in file order.
    public let toInsert: [ImportedWorkout]
    /// Workouts skipped because a session with their key exists.
    public let alreadyImported: Int
    /// Workouts skipped because an earlier workout in the same file has their key.
    public let repeatedInFile: Int
    /// Workouts without a readable set; they are not created.
    public let emptyWorkouts: Int

    /// Plans the import of `workouts` into a store whose sessions have `existingKeys`.
    public init(workouts: [ImportedWorkout], existingKeys: Set<String>) {
        var seen: Set<String> = []
        var toInsert: [ImportedWorkout] = []
        var alreadyImported = 0
        var repeated = 0
        var empty = 0
        for workout in workouts {
            if workout.isEmpty {
                empty += 1
            } else if existingKeys.contains(workout.externalKey) {
                alreadyImported += 1
            } else if !seen.insert(workout.externalKey).inserted {
                repeated += 1
            } else {
                toInsert.append(workout)
            }
        }
        self.toInsert = toInsert
        self.alreadyImported = alreadyImported
        self.repeatedInFile = repeated
        self.emptyWorkouts = empty
    }

    /// The number of workouts the import will add.
    public var insertCount: Int { toInsert.count }
}
