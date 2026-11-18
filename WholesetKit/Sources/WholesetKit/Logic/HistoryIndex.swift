// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// Everything the history screens show, computed once from all finished sessions.
///
/// Records, PRs, chart series and list rows each come from one pass over the history. The
/// index is plain data, so it can be built away from the main actor (see
/// ``load(from:)``) and replaced as a whole whenever the store changes.
public struct HistoryIndex: Equatable, Sendable {
    /// No history.
    public static let empty = HistoryIndex(sessions: [])

    /// Finished sessions by `id`.
    public let sessions: [UUID: HistorySession]
    /// One row per finished session, newest first.
    public let rows: [HistoryRow]
    /// Records and PRs.
    public let records: PersonalRecords
    /// Each exercise's progress, by exercise `id`.
    public let progress: [UUID: ExerciseTimeline]

    /// Builds the index of `sessions`; in-progress sessions must already be left out (they
    /// cannot be represented as ``HistorySession``).
    public init(sessions: [HistorySession]) {
        let ordered = sessions.sorted(by: HistorySnapshot.isEarlier)
        let records = PersonalRecords.compute(from: ordered)
        self.sessions = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.records = records
        self.rows = HistoryList.rows(from: ordered, records: records)
        self.progress = ExerciseTimeline.build(from: ordered)
    }

    /// The finished session with `id`, if any.
    public func session(id: UUID) -> HistorySession? {
        sessions[id]
    }

    /// What the session screen shows for the session with `id`, if it exists and is finished.
    public func detail(forSession id: UUID) -> SessionDetail? {
        sessions[id].map { SessionDetail(session: $0, records: records) }
    }

    /// Reads every finished session from `container` with a context of its own, off the
    /// caller's actor, and builds the index. A new context always sees what was last saved.
    @concurrent
    public static func load(from container: ModelContainer) async throws -> HistoryIndex {
        let context = ModelContext(container)
        return HistoryIndex(sessions: try HistorySnapshot.load(in: context))
    }
}
