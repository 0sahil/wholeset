// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import WholesetKit

/// Builds history values tersely for tests.
enum H {
    /// A fixed reference date (14 Nov 2023 22:13:20 UTC).
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    static let day: TimeInterval = 86_400

    /// A logged set.
    static func set(_ weightKg: Double?, _ reps: Int?, warmup: Bool = false, id: UUID = UUID(), at date: Date = t0) -> HistorySet {
        HistorySet(id: id, isWarmup: warmup, weightKg: weightKg, reps: reps, completedAt: date)
    }

    /// Working sets of (weight, reps).
    static func sets(_ specs: [(Double?, Int?)]) -> [HistorySet] {
        specs.map { set($0.0, $0.1) }
    }

    /// An entry of `exercise`.
    static func entry(
        _ exercise: UUID?,
        name: String = "Bench Press",
        slot: UUID? = nil,
        skipped: Bool = false,
        id: UUID = UUID(),
        _ sets: [HistorySet]
    ) -> HistoryEntry {
        HistoryEntry(id: id, exerciseID: exercise, exerciseName: name, routineItemID: slot, isSkipped: skipped, sets: sets)
    }

    /// A finished session starting `day` days after ``t0`` (plus `offset` seconds), lasting an hour.
    static func session(
        day: Double,
        offset: TimeInterval = 0,
        id: UUID = UUID(),
        name: String = "Push",
        source: Source = .watch,
        _ entries: [HistoryEntry]
    ) -> HistorySession {
        let start = t0.addingTimeInterval(day * Self.day + offset)
        return HistorySession(id: id, name: name, startedAt: start, endedAt: start.addingTimeInterval(3_600), source: source, entries: entries)
    }

    /// A UUID whose string form sorts by `n` (for deterministic tie tests).
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
    }
}
