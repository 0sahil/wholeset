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
    /// Whether the exercise was skipped for this workout.
    public let isSkipped: Bool

    /// Creates a progress value.
    public init(completed: Int, total: Int, isSkipped: Bool = false) {
        self.completed = completed
        self.total = total
        self.isSkipped = isSkipped
    }

    /// Whether no set is left to log: every set is logged, or the exercise was skipped.
    public var isDone: Bool { isSkipped || completed >= total }
}

/// The "last" line under the tiles: what the current set was last time.
public enum LastLine: Equatable, Sendable {
    /// The exercise has never been finished in a past workout.
    case firstTime
    /// The corresponding set of the last workout with this exercise.
    case previous(SetValues)
    /// There is history, but no corresponding set (a warm-up when last time had none).
    case none
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

/// Runs one live workout: creates the session (from a routine, or empty), tracks which
/// exercise and set is current, and writes every change to the store immediately.
///
/// The engine holds a `ModelContext` and model objects, so it must stay on the actor that
/// owns that context (the main actor in the apps). All persistent state lives in SwiftData;
/// the only in-memory state is which exercise is on screen, the progression settings and a
/// cache of each exercise's last performance.
///
/// Values for an unlogged set follow ``Prefill``: what was typed on the set, then a change
/// carried from an earlier set today, then the same set of the exercise's last finished
/// session, then any set logged today, then the rep floor with no weight.
@Observable
public final class WorkoutEngine {
    /// The session being recorded.
    public let session: Session
    /// The session's exercises in order.
    public private(set) var entries: [SessionExercise]
    /// Index into ``entries`` of the exercise on screen.
    public private(set) var currentIndex: Int
    /// The unit and per-equipment steps the progression hint uses. The Watch refreshes it
    /// when settings change.
    public var progressionSettings: ProgressionSettings

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let defaultRestSeconds: Int?
    /// Last performance per exercise `id`, read once per exercise. History cannot change
    /// during a workout: it only holds finished sessions, and this one is not finished.
    @ObservationIgnored private var historyCache: [UUID: LastPerformance?] = [:]

    /// Starts a new Watch session from `routine` and saves it.
    ///
    /// Snapshots the routine name and each slot's rep range, records the slot each entry
    /// comes from, and creates the slot's target number of planned sets (at least one).
    /// Slots without an exercise are skipped.
    ///
    /// - Parameters:
    ///   - routine: The routine to follow.
    ///   - context: The context to write to.
    ///   - defaultRestSeconds: The app-wide rest setting.
    ///   - progressionSettings: The progression settings.
    ///   - now: The clock; injected for tests.
    public static func start(
        routine: Routine,
        in context: ModelContext,
        defaultRestSeconds: Int?,
        progressionSettings: ProgressionSettings = ProgressionSettings(),
        now: @escaping () -> Date = Date.init
    ) throws -> WorkoutEngine {
        let startDate = now()
        let session = makeSession(named: routine.name, at: startDate, in: context)
        session.routine = routine

        var order = 0
        for item in routine.sortedItems {
            guard let exercise = item.exercise else { continue }
            let entry = SessionExercise(order: order, repLow: item.repLow, repHigh: item.repHigh)
            entry.routineItemID = item.id
            context.insert(entry)
            entry.session = session
            entry.exercise = exercise
            insertPlannedSets(max(1, item.targetSets), into: entry, in: context)
            order += 1
        }
        try context.save()
        return WorkoutEngine(
            resuming: session,
            in: context,
            defaultRestSeconds: defaultRestSeconds,
            progressionSettings: progressionSettings,
            now: now
        )
    }

    /// Starts a new Watch session without a routine or exercises, named "Workout", and saves it.
    ///
    /// - Parameters:
    ///   - context: The context to write to.
    ///   - defaultRestSeconds: The app-wide rest setting.
    ///   - progressionSettings: The progression settings.
    ///   - now: The clock; injected for tests.
    public static func startEmpty(
        in context: ModelContext,
        defaultRestSeconds: Int?,
        progressionSettings: ProgressionSettings = ProgressionSettings(),
        now: @escaping () -> Date = Date.init
    ) throws -> WorkoutEngine {
        let session = makeSession(named: emptyWorkoutName, at: now(), in: context)
        try context.save()
        return WorkoutEngine(
            resuming: session,
            in: context,
            defaultRestSeconds: defaultRestSeconds,
            progressionSettings: progressionSettings,
            now: now
        )
    }

    /// The name of a workout started without a routine.
    public static var emptyWorkoutName: String {
        String(localized: "Workout", bundle: .module)
    }

    private static func makeSession(named name: String, at date: Date, in context: ModelContext) -> Session {
        let session = Session(name: name, startedAt: date, source: .watch)
        session.createdAt = date
        session.updatedAt = date
        context.insert(session)
        return session
    }

    private static func insertPlannedSets(_ count: Int, into entry: SessionExercise, in context: ModelContext) {
        for setOrder in 0..<count {
            let set = SetLog(order: setOrder)
            context.insert(set)
            set.entry = entry
        }
    }

    /// Continues an existing session, for example after a relaunch.
    ///
    /// - Parameters:
    ///   - session: The in-progress session.
    ///   - context: The context `session` belongs to.
    ///   - defaultRestSeconds: The app-wide rest setting.
    ///   - progressionSettings: The progression settings.
    ///   - currentEntryID: The exercise to show; when `nil` or unknown, shows the exercise
    ///     of the most recently logged set, or the first exercise.
    ///   - now: The clock; injected for tests.
    public init(
        resuming session: Session,
        in context: ModelContext,
        defaultRestSeconds: Int?,
        progressionSettings: ProgressionSettings = ProgressionSettings(),
        currentEntryID: UUID? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.context = context
        self.defaultRestSeconds = defaultRestSeconds
        self.progressionSettings = progressionSettings
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

    /// The next set to log in `entry`: the first one not logged yet. `nil` when every set is
    /// logged or the exercise is skipped.
    public func currentSet(of entry: SessionExercise) -> SetLog? {
        guard !entry.isSkipped else { return nil }
        return entry.sortedSets.first { $0.completedAt == nil }
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
        guard let entry = set.entry else {
            return SetValues(weightKg: set.weightKg, reps: set.reps)
        }
        let sets = entry.sortedSets
        guard let index = sets.firstIndex(where: { $0 === set }) else {
            return SetValues(weightKg: set.weightKg, reps: set.reps ?? entry.repLow)
        }
        return Prefill.values(at: index, in: Self.states(of: sets), last: lastPerformance(of: entry), repFloor: entry.repLow)
    }

    /// The values to show for the current set, if there is one.
    public var currentValues: SetValues? {
        currentSet.map(values(for:))
    }

    private static func states(of sets: [SetLog]) -> [Prefill.SetState] {
        sets.map { Prefill.SetState(isWarmup: $0.isWarmup, weightKg: $0.weightKg, reps: $0.reps, isLogged: $0.completedAt != nil) }
    }

    /// The last finished performance of `entry`'s exercise, read once per exercise.
    public func lastPerformance(of entry: SessionExercise) -> LastPerformance? {
        entry.exercise.flatMap(lastPerformance(of:))
    }

    /// The last finished performance of `exercise`, read once per exercise. This workout
    /// never counts: it is not finished.
    public func lastPerformance(of exercise: Exercise) -> LastPerformance? {
        if let cached = historyCache[exercise.id] { return cached }
        let last = ExerciseHistory.lastPerformance(of: exercise, excluding: session.id)
        historyCache[exercise.id] = last
        return last
    }

    /// What `set` was in the exercise's last finished workout.
    public func lastLine(for set: SetLog) -> LastLine {
        guard let entry = set.entry, let last = lastPerformance(of: entry) else { return .firstTime }
        let sets = entry.sortedSets
        guard let index = sets.firstIndex(where: { $0 === set }) else { return .none }
        let kindIndex = Prefill.kindIndex(of: index, in: Self.states(of: sets))
        return last.matchingSet(isWarmup: set.isWarmup, index: kindIndex).map { .previous($0.values) } ?? .none
    }

    /// The "last" line for the current set, if there is one.
    public var currentLastLine: LastLine? {
        currentSet.map(lastLine(for:))
    }

    /// The progression suggestion for the current set: `nil` for warm-ups, when the rule
    /// does not fire (see ``Progression``), or when the set already shows the suggestion.
    public var currentProgressionHint: ProgressionHint? {
        guard let entry = currentEntry, let set = currentSet(of: entry), !set.isWarmup,
              let hint = progressionHint(for: entry) else { return nil }
        return Prefill.matches(values(for: set), hint.values) ? nil : hint
    }

    /// The progression suggestion for `entry`, whether or not it is already shown.
    public func progressionHint(for entry: SessionExercise) -> ProgressionHint? {
        guard let exercise = entry.exercise else { return nil }
        return Progression.hint(
            last: lastPerformance(of: exercise),
            repLow: entry.repLow,
            repHigh: entry.repHigh,
            equipment: exercise.equipment,
            stepKg: progressionSettings.step(for: exercise.equipment, exerciseStepKg: exercise.progressionStepKg)
        )
    }

    /// Logged and total sets of `entry`.
    public func progress(of entry: SessionExercise) -> ExerciseProgress {
        let sets = entry.sets ?? []
        return ExerciseProgress(completed: sets.count { $0.completedAt != nil }, total: sets.count, isSkipped: entry.isSkipped)
    }

    /// One status per set of `entry`, in order. A skipped exercise has no current set.
    public func statuses(of entry: SessionExercise) -> [SetStatus] {
        let sets = entry.sortedSets
        let currentID = currentSet(of: entry)?.id
        return sets.map { set in
            SetStatus(id: set.id, isCompleted: set.completedAt != nil, isCurrent: set.id == currentID, isWarmup: set.isWarmup)
        }
    }

    /// The 1-based position of the current set within its exercise, if there is one.
    public var currentSetNumber: Int? {
        guard let entry = currentEntry, let set = currentSet(of: entry) else { return nil }
        return entry.sortedSets.firstIndex { $0 === set }.map { $0 + 1 }
    }

    /// Whether `entry` has nothing left to do: every set is logged, or it was skipped.
    public func isDone(_ entry: SessionExercise) -> Bool {
        entry.isSkipped || !(entry.sets ?? []).contains { $0.completedAt == nil }
    }

    /// Whether every exercise of the workout is done.
    public var isComplete: Bool {
        entries.allSatisfy(isDone)
    }

    /// The next exercise with sets left after `entry`, wrapping round to earlier ones.
    /// Skipped exercises are passed over.
    public func nextUnfinishedEntry(after entry: SessionExercise) -> SessionExercise? {
        guard let index = entries.firstIndex(where: { $0 === entry }) else {
            return entries.first { !isDone($0) }
        }
        let later = entries[(index + 1)...].first { !isDone($0) }
        return later ?? entries[..<index].first { !isDone($0) }
    }

    /// Exercises with sets still to log, in order. Skipped exercises are not listed.
    public var unfinishedExercises: [UnfinishedExercise] {
        entries.compactMap { entry in
            guard !entry.isSkipped else { return nil }
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

    /// The routine slot `entry` was created from. Entries record it since schema version 3
    /// (and keep it through a swap); an entry without one in such a session was added during
    /// the workout. Sessions from before record none: they match by exercise, preferring the
    /// slot at the same position.
    private func routineItem(for entry: SessionExercise) -> RoutineItem? {
        guard let items = session.routine?.sortedItems else { return nil }
        if let itemID = entry.routineItemID {
            return items.first { $0.id == itemID }
        }
        guard !entries.contains(where: { $0.routineItemID != nil }), let exercise = entry.exercise else { return nil }
        let withExercise = items.filter { $0.exercise != nil }
        let matches = withExercise.indices.filter { withExercise[$0].exercise === exercise }
        let index = matches.first { $0 == entry.order } ?? matches.first
        return index.map { withExercise[$0] }
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

    // MARK: - Editing sets

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

    /// Writes the progression suggestion to every unlogged working set of the current
    /// exercise (so later sets keep it rather than falling back to history) and saves.
    ///
    /// - Returns: Whether a suggestion was applied.
    @discardableResult
    public func applyProgressionHint() throws -> Bool {
        guard let entry = currentEntry, let hint = currentProgressionHint else { return false }
        let date = now()
        for set in entry.sortedSets where set.completedAt == nil && !set.isWarmup {
            set.weightKg = hint.weightKg
            set.reps = hint.reps
            set.updatedAt = date
        }
        session.updatedAt = date
        try context.save()
        return true
    }

    /// Whether ``addSet()`` can add a set: there is a current exercise and it is not skipped.
    public var canAddSet: Bool {
        currentEntry.map { !$0.isSkipped } ?? false
    }

    /// Appends a planned set to the current exercise and saves. Does nothing while the
    /// exercise is skipped.
    public func addSet() throws {
        guard let entry = currentEntry, !entry.isSkipped else { return }
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
    /// Does nothing while the exercise is skipped.
    ///
    /// - Returns: `true` if a set was removed.
    @discardableResult
    public func removeLastUnloggedSet() throws -> Bool {
        guard let entry = currentEntry, !entry.isSkipped,
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

    // MARK: - Changing the workout

    /// Appends `exercise` at the end with the default sets and rep range of a new routine
    /// item, shows it, and saves. It belongs to no routine slot.
    @discardableResult
    public func addExercise(_ exercise: Exercise) throws -> SessionExercise {
        let date = now()
        renumber(entries, at: date)
        let entry = SessionExercise(order: entries.count, repLow: RoutineRules.defaultRepLow, repHigh: RoutineRules.defaultRepHigh)
        entry.createdAt = date
        entry.updatedAt = date
        context.insert(entry)
        entry.session = session
        entry.exercise = exercise
        Self.insertPlannedSets(RoutineRules.defaultSets, into: entry, in: context)
        session.updatedAt = date
        try context.save()
        entries = session.sortedEntries
        select(entry)
        return entry
    }

    /// Whether the current exercise can be swapped: it has no logged set (it is changed in
    /// place), or it still has sets to log (those move to the new exercise).
    public var canSwapCurrentExercise: Bool {
        guard let entry = currentEntry else { return false }
        return !entry.hasLoggedSet || (entry.sets ?? []).contains { $0.completedAt == nil }
    }

    /// Replaces the current exercise with `exercise` and saves.
    ///
    /// - With nothing logged, the entry's exercise changes in place.
    /// - With sets logged, those stay with the old exercise: the unlogged sets move to a new
    ///   entry for `exercise` right after it, with the same routine slot and rep range, and
    ///   that entry becomes current.
    ///
    /// Either way the unlogged sets lose their typed values, so they pre-fill from the new
    /// exercise's own history; warm-up flags stay. A skipped exercise is resumed.
    ///
    /// - Returns: Whether anything changed.
    @discardableResult
    public func swapCurrentExercise(to exercise: Exercise) throws -> Bool {
        guard let entry = currentEntry, entry.exercise !== exercise, canSwapCurrentExercise else { return false }
        let date = now()
        let unlogged = entry.sortedSets.filter { $0.completedAt == nil }
        let target: SessionExercise
        if !entry.hasLoggedSet {
            entry.exercise = exercise
            entry.isSkipped = false
            entry.updatedAt = date
            target = entry
        } else {
            let split = SessionExercise(order: entry.order + 1, repLow: entry.repLow, repHigh: entry.repHigh)
            split.routineItemID = entry.routineItemID
            split.createdAt = date
            split.updatedAt = date
            context.insert(split)
            split.session = session
            split.exercise = exercise
            for (order, set) in unlogged.enumerated() {
                set.entry = split
                set.order = order
            }
            entry.isSkipped = false
            entry.updatedAt = date
            var reordered = entries
            let index = reordered.firstIndex { $0 === entry } ?? reordered.count - 1
            reordered.insert(split, at: index + 1)
            renumber(reordered, at: date)
            target = split
        }
        for set in unlogged {
            set.weightKg = nil
            set.reps = nil
            set.updatedAt = date
        }
        session.updatedAt = date
        try context.save()
        entries = session.sortedEntries
        select(target)
        return true
    }

    /// Skips `entry` for this workout, or resumes it, and saves. A skipped exercise counts
    /// as done and keeps its logged sets. Skipping the exercise on screen moves on to the
    /// next unfinished one, if any.
    public func setSkipped(_ isSkipped: Bool, for entry: SessionExercise) throws {
        guard entries.contains(where: { $0 === entry }), entry.isSkipped != isSkipped else { return }
        let date = now()
        entry.isSkipped = isSkipped
        entry.updatedAt = date
        session.updatedAt = date
        try context.save()
        if isSkipped, entry === currentEntry, let next = nextUnfinishedEntry(after: entry) {
            select(next)
        }
    }

    /// Moves exercises (offsets into ``entries``, as SwiftUI's `onMove` describes them),
    /// keeps the exercise on screen selected, and saves.
    public func moveEntries(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        let current = currentEntry
        let reordered = Reorder.moving(entries, fromOffsets: source, toOffset: destination)
        let date = now()
        guard renumber(reordered, at: date) else { return }
        session.updatedAt = date
        try context.save()
        entries = session.sortedEntries
        if let current { select(current) }
    }

    /// Gives `ordered` the orders 0, 1, 2, …; returns whether any changed.
    @discardableResult
    private func renumber(_ ordered: [SessionExercise], at date: Date) -> Bool {
        var changed = false
        for (index, entry) in ordered.enumerated() where entry.order != index {
            entry.order = index
            entry.updatedAt = date
            changed = true
        }
        return changed
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

