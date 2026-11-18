// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One session of an exercise on its progress charts.
public struct ProgressPoint: Identifiable, Equatable, Sendable {
    /// The session's identifier.
    public let sessionID: UUID
    /// When the session started.
    public let date: Date
    /// The best estimated one-rep max of the session's working sets, in kilograms.
    public let estimatedOneRepMaxKg: Double?
    /// The heaviest working-set weight, in kilograms.
    public let topSetWeightKg: Double?
    /// The working-set volume, in kilograms.
    public let volumeKg: Double

    /// Creates a point.
    public init(sessionID: UUID, date: Date, estimatedOneRepMaxKg: Double?, topSetWeightKg: Double?, volumeKg: Double) {
        self.sessionID = sessionID
        self.date = date
        self.estimatedOneRepMaxKg = estimatedOneRepMaxKg
        self.topSetWeightKg = topSetWeightKg
        self.volumeKg = volumeKg
    }

    /// The session's identifier.
    public var id: UUID { sessionID }

    /// The point's value for `metric` in kilograms; `nil` when the session has none (for
    /// example no weighted set, or no set of 12 reps or fewer for the estimate).
    public func value(for metric: ProgressMetric) -> Double? {
        switch metric {
        case .estimatedOneRepMax: estimatedOneRepMaxKg
        case .topSet: topSetWeightKg
        case .volume: volumeKg > 0 ? volumeKg : nil
        }
    }
}

/// What a progress chart shows.
public enum ProgressMetric: String, CaseIterable, Sendable {
    /// The best estimated one-rep max per session.
    case estimatedOneRepMax
    /// The heaviest working set per session.
    case topSet
    /// The working-set volume per session.
    case volume
}

/// How far back a progress chart reaches.
public enum ProgressRange: String, CaseIterable, Sendable {
    /// The last three calendar months.
    case threeMonths
    /// The last calendar year.
    case oneYear
    /// Everything.
    case all

    /// The earliest date shown, or `nil` for ``all``: `now` moved back by three months or one
    /// year in `calendar`, so the range follows month lengths and leap years.
    public func startDate(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)
        case .oneYear: calendar.date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }
}

/// An exercise's best working set in a session: the heaviest, then the one with more reps.
public struct TopSet: Equatable, Sendable {
    /// The weight in kilograms; `nil` when the set had no weight.
    public let weightKg: Double?
    /// The reps, if recorded.
    public let reps: Int?
    /// The session.
    public let sessionID: UUID
    /// When that session started.
    public let date: Date
}

/// One session in an exercise's full log.
public struct ExerciseLogItem: Identifiable, Equatable, Sendable {
    /// The session's identifier.
    public let sessionID: UUID
    /// When the session started.
    public let date: Date
    /// The session's name (see ``HistorySession/displayName``).
    public let sessionName: String
    /// Whether the session was imported.
    public let isImported: Bool
    /// The exercise's logged sets in that session, warm-ups included, in order. If the
    /// exercise appears more than once in the session, the sets of all its entries are joined.
    public let sets: [HistorySet]

    /// The session's identifier.
    public var id: UUID { sessionID }
}

/// An exercise's history: chart points, full log and last top set.
public struct ExerciseTimeline: Equatable, Sendable {
    /// The exercise's `id`.
    public let exerciseID: UUID
    /// One point per finished session with a logged working set of the exercise, oldest first.
    public let points: [ProgressPoint]
    /// Every finished session with a logged set of the exercise, newest first.
    public let log: [ExerciseLogItem]
    /// The best working set of the newest session that has one.
    public let lastTopSet: TopSet?

    /// The number of finished sessions with a logged set of the exercise.
    public var sessionCount: Int { log.count }

    /// The points on or after `range`'s start (see ``ProgressRange/startDate(now:calendar:)``).
    public func points(in range: ProgressRange, now: Date, calendar: Calendar) -> [ProgressPoint] {
        guard let start = range.startDate(now: now, calendar: calendar) else { return points }
        guard let first = points.firstIndex(where: { $0.date >= start }) else { return [] }
        return Array(points[first...])
    }

    /// The newest point with a value for `metric`, with that value in kilograms.
    public func latest(_ metric: ProgressMetric) -> (point: ProgressPoint, valueKg: Double)? {
        for point in points.reversed() {
            if let value = point.value(for: metric) { return (point, value) }
        }
        return nil
    }

    /// Builds every exercise's progress from `sessions` (in any order) in one pass.
    public static func build(from sessions: [HistorySession]) -> [UUID: ExerciseTimeline] {
        var points: [UUID: [ProgressPoint]] = [:]
        var logs: [UUID: [ExerciseLogItem]] = [:]
        var topSets: [UUID: TopSet] = [:]

        for session in sessions.sorted(by: HistorySnapshot.isEarlier) {
            var order: [UUID] = []
            var setsByExercise: [UUID: [HistorySet]] = [:]
            for entry in session.entries where !entry.sets.isEmpty {
                guard let exerciseID = entry.exerciseID else { continue }
                if setsByExercise[exerciseID] == nil { order.append(exerciseID) }
                setsByExercise[exerciseID, default: []].append(contentsOf: entry.sets)
            }
            for exerciseID in order {
                let sets = setsByExercise[exerciseID] ?? []
                logs[exerciseID, default: []].append(ExerciseLogItem(
                    sessionID: session.id,
                    date: session.startedAt,
                    sessionName: session.displayName,
                    isImported: session.isImported,
                    sets: sets
                ))
                let working = sets.filter { !$0.isWarmup }
                guard let top = topSet(of: working) else { continue }
                topSets[exerciseID] = TopSet(weightKg: top.effectiveWeightKg, reps: top.reps, sessionID: session.id, date: session.startedAt)
                points[exerciseID, default: []].append(ProgressPoint(
                    sessionID: session.id,
                    date: session.startedAt,
                    estimatedOneRepMaxKg: working.compactMap(\.estimatedOneRepMaxKg).max(),
                    topSetWeightKg: working.compactMap(\.effectiveWeightKg).max(),
                    volumeKg: SessionMetrics.volume(of: working)
                ))
            }
        }

        var result: [UUID: ExerciseTimeline] = [:]
        for (exerciseID, log) in logs {
            result[exerciseID] = ExerciseTimeline(
                exerciseID: exerciseID,
                points: points[exerciseID] ?? [],
                log: log.reversed(),
                lastTopSet: topSets[exerciseID]
            )
        }
        return result
    }

    /// The heaviest of `sets`, then the one with more reps; the first wins a tie.
    static func topSet(of sets: [HistorySet]) -> HistorySet? {
        var best: HistorySet?
        for set in sets {
            guard let current = best else {
                best = set
                continue
            }
            let key = WeightKey(set.effectiveWeightKg ?? 0)
            let bestKey = WeightKey(current.effectiveWeightKg ?? 0)
            if key > bestKey || (key == bestKey && (set.reps ?? 0) > (current.reps ?? 0)) {
                best = set
            }
        }
        return best
    }
}

/// Consecutive working sets done at one weight, for a compact line such as
/// "62.5 kg × 10, 9, 8 · 65 kg × 5".
public struct SetGroup: Equatable, Sendable {
    /// The weight in kilograms; `nil` for sets without weight.
    public let weightKg: Double?
    /// The reps of each set, in order (`nil` where none were recorded).
    public let reps: [Int?]

    /// Creates a group.
    public init(weightKg: Double?, reps: [Int?]) {
        self.weightKg = weightKg
        self.reps = reps
    }

    /// The working sets among `sets` (warm-ups left out), with consecutive sets of the same
    /// weight (compared after rounding to 0.01 kg) grouped together.
    public static func groups(_ sets: [HistorySet]) -> [SetGroup] {
        var groups: [SetGroup] = []
        for set in sets where !set.isWarmup {
            let weight = set.effectiveWeightKg
            if let last = groups.last, sameWeight(last.weightKg, weight) {
                groups[groups.count - 1] = SetGroup(weightKg: last.weightKg, reps: last.reps + [set.reps])
            } else {
                groups.append(SetGroup(weightKg: weight, reps: [set.reps]))
            }
        }
        return groups
    }

    private static func sameWeight(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (l?, r?): WeightKey(l) == WeightKey(r)
        default: false
        }
    }
}
