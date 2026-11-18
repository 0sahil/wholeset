// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// Everything the import's last screen reports. Nothing is skipped silently: every workout
/// and row of the file is either imported or counted here.
public struct ImportSummary: Sendable, Equatable {
    /// Sessions added.
    public var importedWorkouts: Int
    /// Workouts the import meant to add (equal to ``importedWorkouts`` unless it was stopped).
    public var plannedWorkouts: Int
    /// Workouts already in Wholeset (by key), when planned or when written.
    public var alreadyImported: Int
    /// Workouts appearing twice in the file (the first was imported).
    public var repeatedInFile: Int
    /// Workouts without a readable set, not created.
    public var emptyWorkouts: Int
    /// Rows not read, grouped by reason, largest group first; each with its rows.
    public var rowsNotRead: [RowGroup]
    /// Custom exercises created.
    public var newExercises: [String]
    /// Imported names remembered as aliases.
    public var aliasesAdded: Int
    /// Whether the import was stopped before the end.
    public var wasCancelled: Bool

    /// Rows not read for one reason.
    public struct RowGroup: Sendable, Equatable, Identifiable {
        public let reason: SkipReason
        public let rows: [SkippedRow]
        public var id: SkipReason { reason }
    }

    /// The summary of an import of `result` planned as `plan` and written as `report`.
    public init(result: ImportParseResult, plan: ImportPlan, report: ImportWriteReport) {
        importedWorkouts = report.inserted
        plannedWorkouts = plan.insertCount
        alreadyImported = plan.alreadyImported + report.alreadyImported
        repeatedInFile = plan.repeatedInFile
        emptyWorkouts = plan.emptyWorkouts
        rowsNotRead = result.skippedByReason.map { RowGroup(reason: $0.reason, rows: $0.rows) }
        newExercises = report.newExercises
        aliasesAdded = report.aliasesAdded
        wasCancelled = report.wasCancelled
    }

    /// The number of rows not read.
    public var rowsNotReadCount: Int { rowsNotRead.reduce(0) { $0 + $1.rows.count } }
}

/// A routine the import offers to create from a workout name the history repeats.
///
/// Suggested for workout names done at least ``minimumCount`` times in the file (workouts
/// with sets), except nameless workouts (shown as "Workout") and names equal to an existing
/// routine's, ignoring case and spacing. Most frequent first (then most recent), at most
/// ``limit``. The routine copies the **latest** workout with that name: its exercises in
/// order (an exercise done twice is merged into its first place), each with
/// - target sets = its working sets (warm-ups excluded), limited to 1...10;
/// - a rep range from its working reps (see ``repRange(workingReps:)``).
public struct RoutineSuggestion: Sendable, Equatable, Identifiable {
    /// Times a name must appear to be suggested.
    public static let minimumCount = 3
    /// The most suggestions offered.
    public static let limit = 5
    /// Suggestions switched on at first.
    public static let enabledByDefault = 2

    /// One exercise of the suggested routine.
    public struct Item: Sendable, Equatable {
        /// The exercise's name in the file (resolved when the routine is created).
        public let importedName: String
        public let targetSets: Int
        public let repLow: Int
        public let repHigh: Int
    }

    /// The routine's name: the latest workout's name as written.
    public let name: String
    /// How many workouts in the file have this name.
    public let timesDone: Int
    /// The latest workout's key, to link it to the routine.
    public let latestKey: String
    /// When the latest workout started.
    public let latestStart: Date
    public let items: [Item]

    public var id: String { ImportKey.normalizedName(name) }

    /// The suggestions for `workouts`.
    ///
    /// - Parameter existingRoutineNames: Names of the routines that exist.
    public static func suggestions(from workouts: [ImportedWorkout], existingRoutineNames: [String]) -> [RoutineSuggestion] {
        let taken = Set(existingRoutineNames.map(ImportKey.normalizedName))
        let groups = Dictionary(grouping: workouts.filter { !$0.isEmpty && !$0.name.trimmed.isEmpty }) {
            ImportKey.normalizedName($0.name)
        }
        let suggestions: [RoutineSuggestion] = groups.compactMap { key, group in
            guard group.count >= minimumCount, !taken.contains(key),
                  let latest = group.max(by: { $0.startedAt < $1.startedAt }) else { return nil }
            let items = items(for: latest)
            guard !items.isEmpty else { return nil }
            return RoutineSuggestion(
                name: latest.name.trimmed,
                timesDone: group.count,
                latestKey: latest.externalKey,
                latestStart: latest.startedAt,
                items: items
            )
        }
        return Array(suggestions.sorted { lhs, rhs in
            if lhs.timesDone != rhs.timesDone { return lhs.timesDone > rhs.timesDone }
            if lhs.latestStart != rhs.latestStart { return lhs.latestStart > rhs.latestStart }
            return lhs.name < rhs.name
        }.prefix(limit))
    }

    /// The routine items for `workout`: exercises in order, repeats merged into the first.
    static func items(for workout: ImportedWorkout) -> [Item] {
        var order: [String] = []
        var sets: [String: [ImportedSet]] = [:]
        for exercise in workout.exercises {
            if sets[exercise.name] == nil { order.append(exercise.name) }
            sets[exercise.name, default: []].append(contentsOf: exercise.sets)
        }
        return order.map { name in
            let working = (sets[name] ?? []).filter { !$0.isWarmup }
            let range = repRange(workingReps: working.compactMap(\.reps))
            return Item(
                importedName: name,
                targetSets: RoutineRules.clampedSets(working.count),
                repLow: range.lowerBound,
                repHigh: range.upperBound
            )
        }
    }

    /// The rep range for an exercise's working reps in the latest workout:
    /// - none, or any outside 1...50: the default 8–12;
    /// - several values: lowest to highest (5, 5, 3 → 3–5);
    /// - one value repeated (5 × 5): widened to the default range's width of four reps,
    ///   centred on it (5 → 3–7, 10 → 8–12, 1 → 1–3), so the progression hint has room.
    public static func repRange(workingReps: [Int]) -> ClosedRange<Int> {
        let defaults = RoutineRules.defaultRepLow...RoutineRules.defaultRepHigh
        guard let low = workingReps.min(), let high = workingReps.max(),
              RoutineRules.repsRange.contains(low), RoutineRules.repsRange.contains(high) else { return defaults }
        guard low == high else { return RoutineRules.repRange(low: low, high: high) }
        let half = (defaults.upperBound - defaults.lowerBound) / 2
        return RoutineRules.repRange(low: max(RoutineRules.repsRange.lowerBound, low - half), high: high + half)
    }

    /// Creates the routine with each imported name resolved the way the import resolved it
    /// (an exercise it created is found again by name, never created twice). See
    /// ``create(in:exercise:now:)``. Does not save.
    @discardableResult
    public func create(
        in context: ModelContext,
        resolutions: [String: ExerciseResolution],
        library: ExerciseLibrary,
        now: Date = .now
    ) throws -> Routine? {
        // The import already remembered the names; writing aliases again from this context
        // could overwrite what it saved.
        var resolver = try ImportExerciseResolver(context: context, library: library, now: now, addsAliases: false)
        return try create(in: context, exercise: { name in
            let resolution = resolutions[name] ?? .newCustom(name: name, equipment: ExerciseMatcher.guessedEquipment(for: name))
            return resolver.exercise(for: name, resolution: resolution)
        }, now: now)
    }

    /// Creates the routine, the way ``RoutineUpdate/saveAsRoutine(_:named:in:now:locale:timeZone:)``
    /// does: items through ``RoutineEditing``, and the latest workout's session (found by its
    /// key) linked to the routine with each entry pointing at its item. Other sessions with
    /// the name are not linked. Does not save.
    ///
    /// - Parameter exercise: The exercise an imported name became; names without one are left out.
    /// - Returns: The routine, or `nil` if none of its exercises could be found.
    @discardableResult
    public func create(in context: ModelContext, exercise: (String) -> Exercise?, now: Date = .now) throws -> Routine? {
        var seen: Set<PersistentIdentifier> = []
        var resolved: [(Item, Exercise)] = []
        for item in items {
            guard let found = exercise(item.importedName), seen.insert(found.persistentModelID).inserted else { continue }
            resolved.append((item, found))
        }
        guard !resolved.isEmpty else { return nil }
        let routine = try RoutineEditing.createRoutine(named: name, in: context, now: now)
        var itemIDs: [PersistentIdentifier: UUID] = [:]
        for (item, found) in resolved {
            guard let routineItem = RoutineEditing.addItems(for: [found], to: routine, in: context, now: now).first else { continue }
            RoutineEditing.setTargetSets(item.targetSets, on: routineItem, now: now)
            RoutineEditing.setRepRange(low: item.repLow, high: item.repHigh, on: routineItem, now: now)
            itemIDs[found.persistentModelID] = routineItem.id
        }
        let key = latestKey
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.externalKey == key })
        descriptor.fetchLimit = 1
        if let session = try context.fetch(descriptor).first, session.routine == nil {
            session.routine = routine
            session.updatedAt = now
            for entry in session.entries ?? [] {
                guard let found = entry.exercise, let itemID = itemIDs[found.persistentModelID] else { continue }
                entry.routineItemID = itemID
                entry.updatedAt = now
            }
        }
        return routine
    }
}
