// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import SwiftData

/// The weight and reps shown for a set before it is logged, or recorded once it is.
public struct SetValues: Equatable, Sendable {
    /// Weight in kilograms; `nil` means none entered (bodyweight or not set yet).
    public var weightKg: Double?
    /// Repetitions; `nil` means none entered.
    public var reps: Int?

    /// Creates set values.
    public init(weightKg: Double? = nil, reps: Int? = nil) {
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// The state of one set, for progress dots.
public struct SetStatus: Equatable, Sendable, Identifiable {
    /// The set's identifier.
    public let id: UUID
    /// Whether the set has been logged.
    public let isCompleted: Bool
    /// Whether this is the next set to log.
    public let isCurrent: Bool
    /// Whether the set is a warm-up.
    public let isWarmup: Bool
}

/// Logged and total sets of one exercise.
public struct ExerciseProgress: Equatable, Sendable {
    /// Sets logged.
    public let completed: Int
    /// All sets, logged or not.
    public let total: Int

    /// Whether no set is left to log.
    public var isDone: Bool { completed >= total }
}

/// An exercise that still has sets to log, for the End confirmation.
public struct UnfinishedExercise: Equatable, Sendable {
    /// The exercise name.
    public let name: String
    /// Sets not logged yet.
    public let remainingSets: Int
}

/// Totals over the logged sets of a session.
public struct WorkoutTotals: Equatable, Sendable {
    /// Every logged set, warm-ups included.
    public let completedSets: Int
    /// Logged sets that are not warm-ups.
    public let completedWorkingSets: Int
    /// Sum of weight × reps over logged working sets, in kilograms. Sets without a
    /// weight (bodyweight) add nothing.
    public let volumeKg: Double
}

/// The outcome of logging a set.
public struct LoggedSet {
    /// The set that was logged.
    public let set: SetLog
    /// The exercise it belongs to.
    public let entry: SessionExercise
    /// How long to rest now, or `nil` when every set of the workout is logged.
    public let restDuration: TimeInterval?
}

/// Runs one live workout: creates the session from a routine, tracks which exercise and set
/// is current, and writes each logged set to the store immediately.
///
/// The engine holds a `ModelContext` and model objects, so it must stay on the actor that
/// owns that context (the main actor in the apps). All persistent state lives in SwiftData;
/// the only in-memory state is which exercise is on screen.
///
/// Values for an unlogged set come from, in order: values edited on that set, the previous
/// logged set of the same exercise (preferring one of the same kind, warm-up or working),
/// and finally the routine's rep floor with no weight.
@Observable
public final class WorkoutEngine {
    /// The session being recorded.
    public let session: Session
    /// The session's exercises in order.
    public private(set) var entries: [SessionExercise]
    /// Index into ``entries`` of the exercise on screen.
    public private(set) var currentIndex: Int

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let defaultRestSeconds: Int?

    /// Starts a new Watch session from `routine` and saves it.
    ///
    /// Snapshots the routine name and each slot's rep range, and creates the slot's target
    /// number of planned sets (at least one). Slots without an exercise are skipped.
    ///
    /// - Parameters:
    ///   - routine: The routine to follow.
    ///   - context: The context to write to.
    ///   - defaultRestSeconds: The app-wide rest setting.
    ///   - now: The clock; injected for tests.
    public static func start(
        routine: Routine,
        in context: ModelContext,
        defaultRestSeconds: Int?,
        now: @escaping () -> Date = Date.init
    ) throws -> WorkoutEngine {
        let startDate = now()
        let session = Session(name: routine.name, startedAt: startDate, source: .watch)
        session.createdAt = startDate
        session.updatedAt = startDate
        context.insert(session)
        session.routine = routine

        var order = 0
        for item in routine.sortedItems {
            guard let exercise = item.exercise else { continue }
            let entry = SessionExercise(order: order, repLow: item.repLow, repHigh: item.repHigh)
            context.insert(entry)
            entry.session = session
            entry.exercise = exercise
            for setOrder in 0..<max(1, item.targetSets) {
                let set = SetLog(order: setOrder)
                context.insert(set)
                set.entry = entry
            }
            order += 1
        }
        try context.save()
        return WorkoutEngine(resuming: session, in: context, defaultRestSeconds: defaultRestSeconds, now: now)
    }

    /// Continues an existing session, for example after a relaunch.
    ///
    /// - Parameters:
    ///   - session: The in-progress session.
    ///   - context: The context `session` belongs to.
    ///   - defaultRestSeconds: The app-wide rest setting.
    ///   - currentEntryID: The exercise to show; when `nil` or unknown, shows the exercise
    ///     of the most recently logged set, or the first exercise.
    ///   - now: The clock; injected for tests.
    public init(
        resuming session: Session,
        in context: ModelContext,
        defaultRestSeconds: Int?,
        currentEntryID: UUID? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.context = context
        self.defaultRestSeconds = defaultRestSeconds
        self.now = now
        let entries = session.sortedEntries
        self.entries = entries
        self.currentIndex = Self.initialIndex(entries: entries, preferredID: currentEntryID)
    }

    private static func initialIndex(entries: [SessionExercise], preferredID: UUID?) -> Int {
        if let preferredID, let index = entries.firstIndex(where: { $0.id == preferredID }) {
            return index
        }
        var latest: (index: Int, date: Date)?
        for (index, entry) in entries.enumerated() {
            for set in entry.sets ?? [] {
                guard let completed = set.completedAt else { continue }
                if let current = latest, completed <= current.date { continue }
                latest = (index, completed)
            }
        }
        return latest?.index ?? 0
    }

    // MARK: - Reading

    /// The exercise on screen, or `nil` for a session without exercises.
    public var currentEntry: SessionExercise? {
        entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
    }

    /// The next set to log in `entry`: the first one not logged yet.
    public func currentSet(of entry: SessionExercise) -> SetLog? {
        entry.sortedSets.first { $0.completedAt == nil }
    }

    /// The next set to log in the current exercise.
    public var currentSet: SetLog? {
        currentEntry.flatMap(currentSet(of:))
    }

    /// The values to show for `set`. Logged sets return what was recorded.
    public func values(for set: SetLog) -> SetValues {
        if set.completedAt != nil {
            return SetValues(weightKg: set.weightKg, reps: set.reps)
        }
        let carried = carriedValues(for: set)
        return SetValues(
            weightKg: set.weightKg ?? carried?.weightKg,
            reps: set.reps ?? carried?.reps ?? set.entry?.repLow
        )
    }

    /// The values to show for the current set, if there is one.
    public var currentValues: SetValues? {
        currentSet.map(values(for:))
    }

    private func carriedValues(for set: SetLog) -> SetValues? {
        guard let entry = set.entry else { return nil }
        let sets = entry.sortedSets
        guard let index = sets.firstIndex(where: { $0 === set }) else { return nil }
        let logged = sets[..<index].filter { $0.completedAt != nil }
        guard let source = logged.last(where: { $0.isWarmup == set.isWarmup }) ?? logged.last else { return nil }
        return SetValues(weightKg: source.weightKg, reps: source.reps)
    }

    /// Logged and total sets of `entry`.
    public func progress(of entry: SessionExercise) -> ExerciseProgress {
        let sets = entry.sets ?? []
        return ExerciseProgress(completed: sets.count { $0.completedAt != nil }, total: sets.count)
    }

    /// One status per set of `entry`, in order.
    public func statuses(of entry: SessionExercise) -> [SetStatus] {
        let sets = entry.sortedSets
        let currentID = sets.first { $0.completedAt == nil }?.id
        return sets.map { set in
            SetStatus(id: set.id, isCompleted: set.completedAt != nil, isCurrent: set.id == currentID, isWarmup: set.isWarmup)
        }
    }

    /// The 1-based position of the current set within its exercise, if there is one.
    public var currentSetNumber: Int? {
        guard let entry = currentEntry, let set = currentSet(of: entry) else { return nil }
        return entry.sortedSets.firstIndex { $0 === set }.map { $0 + 1 }
    }

    /// Whether `entry` has no set left to log.
    public func isDone(_ entry: SessionExercise) -> Bool {
        !(entry.sets ?? []).contains { $0.completedAt == nil }
    }

    /// Whether every set of the workout is logged.
    public var isComplete: Bool {
        entries.allSatisfy(isDone)
    }

    /// The next exercise with sets left after `entry`, wrapping round to earlier ones.
    public func nextUnfinishedEntry(after entry: SessionExercise) -> SessionExercise? {
        guard let index = entries.firstIndex(where: { $0 === entry }) else {
            return entries.first { !isDone($0) }
        }
        let later = entries[(index + 1)...].first { !isDone($0) }
        return later ?? entries[..<index].first { !isDone($0) }
    }

    /// Exercises with sets still to log, in order.
    public var unfinishedExercises: [UnfinishedExercise] {
        entries.compactMap { entry in
            let remaining = (entry.sets ?? []).count { $0.completedAt == nil }
            guard remaining > 0 else { return nil }
            return UnfinishedExercise(name: entry.exercise?.name ?? "", remainingSets: remaining)
        }
    }

    /// Totals over every logged set.
    public var totals: WorkoutTotals {
        var completed = 0
        var working = 0
        var volume = 0.0
        for entry in entries {
            for set in entry.sets ?? [] where set.completedAt != nil {
                completed += 1
                guard !set.isWarmup else { continue }
                working += 1
                volume += (set.weightKg ?? 0) * Double(set.reps ?? 0)
            }
        }
        return WorkoutTotals(completedSets: completed, completedWorkingSets: working, volumeKg: volume)
    }

    /// How long to rest after a set of `entry`: the routine slot's rest, else the
    /// exercise's default, else the app setting.
    public func restDuration(for entry: SessionExercise) -> TimeInterval {
        RestTimer.duration(
            routineItemSeconds: routineItem(for: entry)?.restSeconds,
            exerciseSeconds: entry.exercise?.defaultRestSeconds,
            appDefaultSeconds: defaultRestSeconds
        )
    }

    /// The routine slot `entry` was created from: the slot with the same exercise,
    /// preferring the one at the same position.
    private func routineItem(for entry: SessionExercise) -> RoutineItem? {
        guard let items = session.routine?.sortedItems.filter({ $0.exercise != nil }),
              let exercise = entry.exercise else { return nil }
        let matches = items.indices.filter { items[$0].exercise === exercise }
        let index = matches.first { $0 == entry.order } ?? matches.first
        return index.map { items[$0] }
    }

    // MARK: - Navigation

    /// Shows the exercise at `index`, clamped to the valid range.
    public func select(entryAt index: Int) {
        guard !entries.isEmpty else { return }
        currentIndex = min(max(index, 0), entries.count - 1)
    }

    /// Shows `entry`, if it belongs to this session.
    public func select(_ entry: SessionExercise) {
        if let index = entries.firstIndex(where: { $0 === entry }) {
            currentIndex = index
        }
    }

    // MARK: - Editing

    /// Sets the weight of the current set without saving. Negative values are stored as 0.
    public func setCurrentWeight(_ kilograms: Double?) {
        guard let set = currentSet else { return }
        set.weightKg = kilograms.map { max(0, $0) }
        set.updatedAt = now()
    }

    /// Sets the reps of the current set without saving. Negative values are stored as 0.
    public func setCurrentReps(_ reps: Int?) {
        guard let set = currentSet else { return }
        set.reps = reps.map { max(0, $0) }
        set.updatedAt = now()
    }

    /// Saves pending edits, if any.
    public func saveEdits() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    /// Records the current set with its shown values and saves at once.
    ///
    /// - Returns: The logged set, or `nil` if the current exercise has no set left.
    @discardableResult
    public func logCurrentSet() throws -> LoggedSet? {
        guard let entry = currentEntry, let set = currentSet(of: entry) else { return nil }
        let values = values(for: set)
        let date = now()
        let previous = (set.weightKg, set.reps)
        set.weightKg = values.weightKg
        set.reps = values.reps
        set.completedAt = date
        set.updatedAt = date
        session.updatedAt = date
        do {
            try context.save()
        } catch {
            set.completedAt = nil
            (set.weightKg, set.reps) = previous
            throw error
        }
        return LoggedSet(set: set, entry: entry, restDuration: isComplete ? nil : restDuration(for: entry))
    }

    /// Appends a planned set to the current exercise and saves.
    public func addSet() throws {
        guard let entry = currentEntry else { return }
        let order = ((entry.sets ?? []).map(\.order).max() ?? -1) + 1
        let set = SetLog(order: order)
        context.insert(set)
        set.entry = entry
        session.updatedAt = now()
        try context.save()
    }

    /// Whether the current exercise has a set that ``removeLastUnloggedSet()`` can remove.
    public var canRemoveSet: Bool {
        currentEntry.map { !isDone($0) } ?? false
    }

    /// Deletes the last set of the current exercise that has not been logged, and saves.
    ///
    /// - Returns: `true` if a set was removed.
    @discardableResult
    public func removeLastUnloggedSet() throws -> Bool {
        guard let entry = currentEntry,
              let set = entry.sortedSets.last(where: { $0.completedAt == nil }) else { return false }
        entry.sets?.removeAll { $0 === set }
        context.delete(set)
        session.updatedAt = now()
        try context.save()
        return true
    }

    /// Flips the warm-up flag of the current set and saves.
    public func toggleWarmupOnCurrentSet() throws {
        guard let set = currentSet else { return }
        set.isWarmup.toggle()
        set.updatedAt = now()
        try context.save()
    }

    // MARK: - Ending

    /// Marks the session as ended now and saves. Sets never logged stay as planned sets
    /// (`completedAt == nil`).
    public func finish() throws {
        let date = now()
        session.endedAt = date
        session.updatedAt = date
        try context.save()
    }

    /// Deletes the session with all its exercises and sets, and saves.
    public func discard() throws {
        context.delete(session)
        try context.save()
    }
}
