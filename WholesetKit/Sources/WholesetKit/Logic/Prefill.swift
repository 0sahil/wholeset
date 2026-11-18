// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One logged set of a past session, as pre-fill and the progression rule read it.
public struct PerformedSet: Equatable, Sendable {
    /// Weight in kilograms; `nil` for a set logged without weight.
    public var weightKg: Double?
    /// Repetitions; `nil` if none were recorded.
    public var reps: Int?
    /// Whether the set was a warm-up.
    public var isWarmup: Bool

    /// Creates a performed set.
    public init(weightKg: Double? = nil, reps: Int? = nil, isWarmup: Bool = false) {
        self.weightKg = weightKg
        self.reps = reps
        self.isWarmup = isWarmup
    }

    /// The weight and reps.
    public var values: SetValues {
        SetValues(weightKg: weightKg, reps: reps)
    }
}

/// What an exercise's most recent finished session holds for it: the logged sets of that
/// exercise in that session, in order.
public struct LastPerformance: Equatable, Sendable {
    /// The session the sets come from.
    public let sessionID: UUID
    /// When that session started.
    public let date: Date
    /// The logged sets, warm-ups included, in the order they were done. When the exercise
    /// appears more than once in the session (for example after a swap), the sets of all its
    /// entries are joined in entry order.
    public let sets: [PerformedSet]

    /// Creates a last performance.
    public init(sessionID: UUID, date: Date, sets: [PerformedSet]) {
        self.sessionID = sessionID
        self.date = date
        self.sets = sets
    }

    /// The logged sets that are not warm-ups.
    public var workingSets: [PerformedSet] { sets.filter { !$0.isWarmup } }

    /// The logged warm-up sets.
    public var warmupSets: [PerformedSet] { sets.filter(\.isWarmup) }

    /// The set of last time that corresponds to today's set number `index` (0-based) among
    /// sets of the same kind: working set N for working set N, warm-up N for warm-up N.
    /// Sets beyond what was done last time copy the last set of their kind. A warm-up never
    /// takes a working set's values (it would be too heavy), so this is `nil` for warm-ups
    /// when last time had none.
    public func matchingSet(isWarmup: Bool, index: Int) -> PerformedSet? {
        let candidates = isWarmup ? warmupSets : workingSets
        guard index >= 0 else { return nil }
        return candidates.indices.contains(index) ? candidates[index] : candidates.last
    }

    /// The best working set: the heaviest, then the one with the most reps. Falls back to
    /// all sets when every set was a warm-up.
    public var topSet: PerformedSet? {
        let pool = workingSets.isEmpty ? sets : workingSets
        return pool.max { lhs, rhs in
            let lw = lhs.weightKg ?? -1
            let rw = rhs.weightKg ?? -1
            if lw != rw { return lw < rw }
            return (lhs.reps ?? 0) < (rhs.reps ?? 0)
        }
    }
}

/// Reads an exercise's past performance from the store.
public enum ExerciseHistory {
    /// The exercise's most recent finished session (`endedAt` set) that has a logged set of
    /// exactly this exercise; alternatives never count. Sessions are ranked by start date,
    /// then `id`. Only logged sets are returned, so skipped and unfinished sets never appear.
    ///
    /// - Parameters:
    ///   - exercise: The exercise.
    ///   - excludedSessionID: A session to ignore, typically the one in progress.
    public static func lastPerformance(of exercise: Exercise, excluding excludedSessionID: UUID? = nil) -> LastPerformance? {
        var latest: Session?
        var entriesBySession: [UUID: [SessionExercise]] = [:]
        for entry in exercise.sessionEntries ?? [] {
            guard let session = entry.session, session.endedAt != nil, session.id != excludedSessionID,
                  entry.hasLoggedSet else { continue }
            entriesBySession[session.id, default: []].append(entry)
            if let current = latest, !isNewer(session, than: current) { continue }
            latest = session
        }
        guard let latest, let entries = entriesBySession[latest.id] else { return nil }
        let sets = entries.sortedByOrder()
            .flatMap(\.sortedSets)
            .filter { $0.completedAt != nil }
            .map { PerformedSet(weightKg: $0.weightKg, reps: $0.reps, isWarmup: $0.isWarmup) }
        return LastPerformance(sessionID: latest.id, date: latest.startedAt, sets: sets)
    }

    private static func isNewer(_ lhs: Session, than rhs: Session) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}

/// The values offered for sets that have not been logged yet.
///
/// For each set, in order, the first rule that applies gives its suggestion:
/// 1. **Carry**: the previous logged set of the same kind (warm-up or working) today, if the
///    user changed it from its own suggestion, or if it was itself carried and logged as
///    shown. A change made on one set therefore carries on to the later sets.
/// 2. **Last session**: the corresponding set of the exercise's last performance (see
///    ``LastPerformance/matchingSet(isWarmup:index:)``).
/// 3. **Today**: the most recent logged set today, preferring one of the same kind.
/// 4. **Plan**: no weight, reps at the bottom of the rep range.
///
/// Values typed on the set itself always win over its suggestion, field by field.
public enum Prefill {
    /// Weights closer than this count as equal (they come from the same Crown grid).
    static let weightTolerance = 1e-6

    /// One set of today's entry, as pre-fill reads it.
    public struct SetState: Equatable, Sendable {
        /// Whether the set is a warm-up.
        public var isWarmup: Bool
        /// For an unlogged set, the weight typed on it; for a logged set, what was recorded.
        public var weightKg: Double?
        /// For an unlogged set, the reps typed on it; for a logged set, what was recorded.
        public var reps: Int?
        /// Whether the set has been logged.
        public var isLogged: Bool

        /// Creates a set state.
        public init(isWarmup: Bool = false, weightKg: Double? = nil, reps: Int? = nil, isLogged: Bool = false) {
            self.isWarmup = isWarmup
            self.weightKg = weightKg
            self.reps = reps
            self.isLogged = isLogged
        }

        var values: SetValues { SetValues(weightKg: weightKg, reps: reps) }
    }

    /// Which rule produced a suggestion.
    public enum Source: Equatable, Sendable {
        /// Carried from an earlier set today that the user changed.
        case carried
        /// The corresponding set of the last session.
        case lastSession
        /// The most recent logged set today.
        case today
        /// The routine's rep floor, without weight.
        case plan
    }

    /// What a set would show if nothing were typed on it.
    public struct Suggestion: Equatable, Sendable {
        /// The suggested values. Reps fall back to the rep floor when the source has none.
        public let values: SetValues
        /// The rule that produced them.
        public let source: Source
    }

    /// The suggestion for every set, in order, ignoring what is typed on each set itself.
    ///
    /// - Parameters:
    ///   - sets: Every set of the entry in order, logged or not.
    ///   - last: The exercise's last performance, if any.
    ///   - repFloor: The bottom of the entry's rep range.
    public static func suggestions(for sets: [SetState], last: LastPerformance?, repFloor: Int?) -> [Suggestion] {
        var result: [Suggestion] = []
        result.reserveCapacity(sets.count)
        for index in sets.indices {
            result.append(suggestion(at: index, in: sets, earlier: result, last: last, repFloor: repFloor))
        }
        return result
    }

    /// The values to show for the set at `index`: what was recorded for a logged set;
    /// otherwise the typed values, falling back field by field to the suggestion.
    public static func values(at index: Int, in sets: [SetState], last: LastPerformance?, repFloor: Int?) -> SetValues {
        guard sets.indices.contains(index) else { return SetValues(reps: repFloor) }
        let set = sets[index]
        if set.isLogged { return set.values }
        let earlier = suggestions(for: Array(sets[..<index]), last: last, repFloor: repFloor)
        let suggested = suggestion(at: index, in: sets, earlier: earlier, last: last, repFloor: repFloor).values
        return SetValues(weightKg: set.weightKg ?? suggested.weightKg, reps: set.reps ?? suggested.reps)
    }

    /// The 0-based position of the set at `index` among the sets of its kind.
    public static func kindIndex(of index: Int, in sets: [SetState]) -> Int {
        guard sets.indices.contains(index) else { return 0 }
        let kind = sets[index].isWarmup
        return sets[..<index].count { $0.isWarmup == kind }
    }

    private static func suggestion(
        at index: Int,
        in sets: [SetState],
        earlier: [Suggestion],
        last: LastPerformance?,
        repFloor: Int?
    ) -> Suggestion {
        let set = sets[index]
        func make(_ values: SetValues, _ source: Source) -> Suggestion {
            Suggestion(values: SetValues(weightKg: values.weightKg, reps: values.reps ?? repFloor), source: source)
        }

        let loggedBefore = sets.indices.prefix(index).filter { sets[$0].isLogged }
        if let previous = loggedBefore.last(where: { sets[$0].isWarmup == set.isWarmup }) {
            let own = earlier[previous]
            if own.source == .carried || !matches(sets[previous].values, own.values) {
                return make(sets[previous].values, .carried)
            }
        }
        if let match = last?.matchingSet(isWarmup: set.isWarmup, index: kindIndex(of: index, in: sets)) {
            return make(match.values, .lastSession)
        }
        if let today = loggedBefore.last(where: { sets[$0].isWarmup == set.isWarmup }) ?? loggedBefore.last {
            return make(sets[today].values, .today)
        }
        return make(SetValues(), .plan)
    }

    /// Whether two set values are the same, weights compared with ``weightTolerance``.
    static func matches(_ lhs: SetValues, _ rhs: SetValues) -> Bool {
        guard lhs.reps == rhs.reps else { return false }
        switch (lhs.weightKg, rhs.weightKg) {
        case (nil, nil): return true
        case let (l?, r?): return abs(l - r) < weightTolerance
        default: return false
        }
    }
}
