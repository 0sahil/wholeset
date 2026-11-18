// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One finished session in the History list.
public struct HistoryRow: Identifiable, Equatable, Sendable {
    /// The session's identifier.
    public let id: UUID
    /// The session's name (see ``HistorySession/displayName``); may be empty.
    public let name: String
    /// When the session started.
    public let startedAt: Date
    /// See ``SessionMetrics/duration(of:)``.
    public let duration: TimeInterval?
    /// Logged working sets.
    public let workingSets: Int
    /// Working-set volume in kilograms.
    public let volumeKg: Double
    /// PRs set in the session (see ``PersonalRecords/count(forSession:)``).
    public let prCount: Int
    /// Whether the session was imported from another app.
    public let isImported: Bool
    /// The names search looks in, folded for case- and diacritic-insensitive matching.
    let searchKey: String

    /// Creates a row. `searchTerms` are the names a search may match: the session's and
    /// routine's names and the names of its exercises.
    public init(
        id: UUID,
        name: String,
        startedAt: Date,
        duration: TimeInterval?,
        workingSets: Int,
        volumeKg: Double,
        prCount: Int,
        isImported: Bool,
        searchTerms: [String]
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.duration = duration
        self.workingSets = workingSets
        self.volumeKg = volumeKg
        self.prCount = prCount
        self.isImported = isImported
        self.searchKey = searchTerms.map(HistoryList.folded).joined(separator: "\n")
    }
}

/// The sessions of one calendar month in the History list.
public struct HistoryMonth: Identifiable, Equatable, Sendable {
    /// The year.
    public let year: Int
    /// The month, 1 to 12.
    public let month: Int
    /// The first moment of the month in the calendar the list was grouped with.
    public let start: Date
    /// The month's sessions, newest first.
    public let rows: [HistoryRow]

    /// Identifies the month: `year × 100 + month`.
    public var id: Int { year * 100 + month }
}

/// The History list: finished sessions newest first, grouped by month, with search.
public enum HistoryList {
    /// One row per session, newest first. In-progress sessions never reach history.
    ///
    /// - Parameters:
    ///   - sessions: Finished sessions, in any order.
    ///   - records: Supplies each session's PR count.
    public static func rows(from sessions: [HistorySession], records: PersonalRecords) -> [HistoryRow] {
        sessions.sorted { HistorySnapshot.isEarlier($1, $0) }.map { session in
            var terms = [session.name]
            if let routineName = session.routineName { terms.append(routineName) }
            terms += session.entries.map(\.exerciseName)
            return HistoryRow(
                id: session.id,
                name: session.displayName,
                startedAt: session.startedAt,
                duration: SessionMetrics.duration(of: session),
                workingSets: SessionMetrics.workingSetCount(of: session),
                volumeKg: SessionMetrics.volume(of: session),
                prCount: records.count(forSession: session.id),
                isImported: session.isImported,
                searchTerms: terms
            )
        }
    }

    /// The rows whose session name, routine name or any exercise name contains `query`,
    /// ignoring case, diacritics and surrounding whitespace. An empty query keeps every row.
    public static func filter(_ rows: [HistoryRow], matching query: String) -> [HistoryRow] {
        let needle = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return rows }
        return rows.filter { $0.searchKey.contains(needle) }
    }

    /// `rows` (newest first) grouped by the month they started in, in `calendar` and its
    /// time zone, newest month first.
    public static func months(_ rows: [HistoryRow], calendar: Calendar) -> [HistoryMonth] {
        var months: [HistoryMonth] = []
        var current: (year: Int, month: Int, rows: [HistoryRow])?
        func close() {
            guard let group = current else { return }
            let start = calendar.date(from: DateComponents(year: group.year, month: group.month, day: 1))
                ?? group.rows.first?.startedAt ?? .distantPast
            months.append(HistoryMonth(year: group.year, month: group.month, start: start, rows: group.rows))
        }
        for row in rows {
            let components = calendar.dateComponents([.year, .month], from: row.startedAt)
            let year = components.year ?? 0
            let month = components.month ?? 0
            if let group = current, group.year == year, group.month == month {
                current?.rows.append(row)
            } else {
                close()
                current = (year, month, [row])
            }
        }
        close()
        return months
    }

    /// The rows matching `query`, grouped by month (see ``filter(_:matching:)`` and
    /// ``months(_:calendar:)``).
    public static func sections(_ rows: [HistoryRow], matching query: String, calendar: Calendar) -> [HistoryMonth] {
        months(filter(rows, matching: query), calendar: calendar)
    }

    /// `text` without case, diacritic or width differences.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
