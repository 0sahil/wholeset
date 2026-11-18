// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import os
import SwiftData
import WholesetKit

/// The history index (records, PRs, chart series, list rows) for the whole app.
///
/// The index is rebuilt off the main actor whenever the store changes: after every save in
/// the app (`ModelContext.didSave`) and after every CloudKit import (via the store's
/// maintenance pass). Changes that arrive while a rebuild runs are folded into one more
/// rebuild. Screens read the latest index and never recompute records themselves.
@Observable
final class HistoryModel {
    /// The latest index; empty until the first load finishes.
    private(set) var index: HistoryIndex = .empty
    /// Whether the first load has finished.
    private(set) var isLoaded = false

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var needsReload = false
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sectionsCache: SectionsCache?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset", category: "History")

    private struct SectionsCache {
        let generation: Int
        let query: String
        let calendar: Calendar
        let months: [HistoryMonth]
    }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Starts watching the store and loads the index. Call once.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
        reload()
    }

    /// Rebuilds the index from what is saved. A call during a rebuild schedules one more.
    ///
    /// The read starts at once, on a background context, even when called while the app is
    /// still launching (a plain `Task` would only start once the main actor is free, after the
    /// first frame). Only applying the finished index waits for the main actor.
    func reload() {
        guard loading == nil else {
            needsReload = true
            return
        }
        let container = container
        let requested = ContinuousClock.now
        loading = Task.immediate {
            do {
                let (index, buildTime) = try await Self.timedLoad(from: container)
                self.index = index
                generation += 1
                // How long the read took, and how long until it was on screen (main actor included).
                logger.info("History index: \(index.sessions.count, privacy: .public) sessions built in \(Self.milliseconds(buildTime), privacy: .public) ms, applied \(Self.milliseconds(requested.duration(to: .now)), privacy: .public) ms after the request")
            } catch {
                logger.error("Loading history failed: \(error, privacy: .public)")
            }
            isLoaded = true
            loading = nil
            if needsReload {
                needsReload = false
                reload()
            }
        }
    }

    /// Loads the index off the main actor and measures how long that took there.
    @concurrent
    private nonisolated static func timedLoad(from container: ModelContainer) async throws -> (HistoryIndex, Duration) {
        let start = ContinuousClock.now
        let index = try await HistoryIndex.load(from: container)
        return (index, start.duration(to: .now))
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    /// The finished sessions matching `query`, grouped by month in `calendar`. Computed once
    /// per index and query, however often a view asks.
    func sections(matching query: String, calendar: Calendar = .current) -> [HistoryMonth] {
        let rows = index.rows
        if let cache = sectionsCache, cache.generation == generation, cache.query == query, cache.calendar == calendar {
            return cache.months
        }
        let months = HistoryList.sections(rows, matching: query, calendar: calendar)
        sectionsCache = SectionsCache(generation: generation, query: query, calendar: calendar, months: months)
        return months
    }

    /// What the session screen shows for the session with `id`, if it exists and is finished.
    func detail(forSession id: UUID) -> SessionDetail? {
        index.detail(forSession: id)
    }

    /// The exercise's chart points, log and last top set, if it was ever done.
    func timeline(forExercise id: UUID) -> ExerciseTimeline? {
        index.progress[id]
    }

    /// The exercise's records, if it has a logged working set.
    func records(forExercise id: UUID) -> ExerciseRecords? {
        index.records.records(forExercise: id)
    }
}
