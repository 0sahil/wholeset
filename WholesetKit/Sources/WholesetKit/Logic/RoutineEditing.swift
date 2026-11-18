// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// Limits for routine targets.
public enum RoutineRules {
    /// Allowed target sets per exercise.
    public static let setsRange = 1...10
    /// Allowed reps at either end of a rep range.
    public static let repsRange = 1...50
    /// Allowed explicit rest, in seconds.
    public static let restRange = 15...600
    /// Rest is set in steps of this many seconds.
    public static let restStep = 15
    /// Targets of a newly added exercise.
    public static let defaultSets = 3
    /// Bottom of a newly added exercise's rep range.
    public static let defaultRepLow = 8
    /// Top of a newly added exercise's rep range.
    public static let defaultRepHigh = 12

    /// Every explicit rest value a picker offers: 15 s to 10 min in 15 s steps.
    public static var restChoices: [Int] {
        Array(stride(from: restRange.lowerBound, through: restRange.upperBound, by: restStep))
    }

    /// `sets` limited to ``setsRange``.
    public static func clampedSets(_ sets: Int) -> Int {
        min(max(sets, setsRange.lowerBound), setsRange.upperBound)
    }

    /// `reps` limited to ``repsRange``.
    public static func clampedReps(_ reps: Int) -> Int {
        min(max(reps, repsRange.lowerBound), repsRange.upperBound)
    }

    /// A valid rep range from `low` and `high`: both limited to ``repsRange``; if `low` ends
    /// up above `high`, `high` is raised to `low`.
    public static func repRange(low: Int, high: Int) -> ClosedRange<Int> {
        let low = clampedReps(low)
        let high = max(clampedReps(high), low)
        return low...high
    }

    /// A valid rest: `nil` (use the exercise's default) stays `nil`; anything else is rounded
    /// to the nearest ``restStep`` and limited to ``restRange``.
    public static func normalizedRest(_ seconds: Int?) -> Int? {
        guard let seconds else { return nil }
        let rounded = Int((Double(seconds) / Double(restStep)).rounded(.toNearestOrAwayFromZero)) * restStep
        return min(max(rounded, restRange.lowerBound), restRange.upperBound)
    }
}

/// Limits for exercises.
public enum ExerciseRules {
    /// The most alternatives an exercise can list.
    public static let maxAlternatives = 4

    /// `candidates` as a valid alternatives list for `exercise`: without `exercise` itself,
    /// without repeats (first occurrence kept), at most ``maxAlternatives``.
    public static func validAlternatives(_ candidates: [Exercise], for exercise: Exercise) -> [Exercise] {
        var seen: Set<PersistentIdentifier> = [exercise.persistentModelID]
        var result: [Exercise] = []
        for candidate in candidates where seen.insert(candidate.persistentModelID).inserted {
            result.append(candidate)
            if result.count == maxAlternatives { break }
        }
        return result
    }
}

/// The edits the routine screens make, as plain functions over the models.
///
/// Every function sets `updatedAt` on what it changes and on the routine it belongs to
/// (that is how a routine counts as edited; see ``StoreMaintenance``). None of them saves:
/// the caller saves once the user's action is complete.
public enum RoutineEditing {
    // MARK: Routines

    /// Inserts a routine named `name` (trimmed; "New Routine" if empty) at the end of the list.
    ///
    /// Creating a routine also settles the account's starter-routine decision if it is still
    /// open, so a Watch that has not synced yet will not add starter routines on top.
    @discardableResult
    public static func createRoutine(named name: String, in context: ModelContext, now: Date = .now) throws -> Routine {
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let routine = Routine(
            name: trimmed.isEmpty ? String(localized: "New Routine", bundle: .module) : trimmed,
            sortIndex: nextSortIndex(after: routines)
        )
        routine.createdAt = now
        routine.updatedAt = now
        context.insert(routine)
        try settleStarterDecision(in: context, now: now)
        return routine
    }

    /// Renames `routine`. Empty names (after trimming) are rejected.
    ///
    /// - Returns: Whether the name changed.
    @discardableResult
    public static func rename(_ routine: Routine, to name: String, now: Date = .now) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != routine.name else { return false }
        routine.name = trimmed
        routine.updatedAt = now
        return true
    }

    /// Sets the routine's notes.
    public static func setNotes(_ notes: String, on routine: Routine, now: Date = .now) {
        guard notes != routine.notes else { return }
        routine.notes = notes
        routine.updatedAt = now
    }

    /// Deletes `routine` and its items. Its sessions stay (they keep their own name), and
    /// weekly plan days that used it become rest days.
    public static func delete(_ routine: Routine, in context: ModelContext, now: Date = .now) {
        for day in routine.weekPlanDays ?? [] {
            day.routine = nil
            day.updatedAt = now
        }
        context.delete(routine)
    }

    /// Moves routines in the list. `routines` is the list as shown; afterwards their
    /// `sortIndex` values are 0, 1, 2, … in the new order.
    public static func moveRoutines(_ routines: [Routine], fromOffsets source: IndexSet, toOffset destination: Int, now: Date = .now) {
        let reordered = Reorder.moving(routines, fromOffsets: source, toOffset: destination)
        for (index, routine) in reordered.enumerated() where routine.sortIndex != index {
            routine.sortIndex = index
            routine.updatedAt = now
        }
    }

    /// Inserts a copy of `routine` (name, notes, items and their targets) at the end of
    /// the list, named "<name> Copy". The copy is a user routine, never a starter routine.
    @discardableResult
    public static func duplicate(_ routine: Routine, in context: ModelContext, now: Date = .now) throws -> Routine {
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let copy = Routine(
            name: String(localized: "\(routine.name) Copy", bundle: .module),
            notes: routine.notes,
            sortIndex: nextSortIndex(after: routines)
        )
        copy.createdAt = now
        copy.updatedAt = now
        context.insert(copy)
        for (order, item) in routine.sortedItems.enumerated() {
            let clone = RoutineItem(
                order: order,
                targetSets: item.targetSets,
                repLow: item.repLow,
                repHigh: item.repHigh,
                restSeconds: item.restSeconds
            )
            clone.createdAt = now
            clone.updatedAt = now
            context.insert(clone)
            clone.routine = copy
            clone.exercise = item.exercise
        }
        try settleStarterDecision(in: context, now: now)
        return copy
    }

    // MARK: Items

    /// Appends one item per exercise with the default targets.
    @discardableResult
    public static func addItems(for exercises: [Exercise], to routine: Routine, in context: ModelContext, now: Date = .now) -> [RoutineItem] {
        var order = routine.sortedItems.count
        var added: [RoutineItem] = []
        for exercise in exercises {
            let item = RoutineItem(
                order: order,
                targetSets: RoutineRules.defaultSets,
                repLow: RoutineRules.defaultRepLow,
                repHigh: RoutineRules.defaultRepHigh
            )
            item.createdAt = now
            item.updatedAt = now
            context.insert(item)
            item.routine = routine
            item.exercise = exercise
            added.append(item)
            order += 1
        }
        if !added.isEmpty {
            renumber(routine, now: now)
            routine.updatedAt = now
        }
        return added
    }

    /// Deletes `item` and closes the gap in the order.
    public static func removeItem(_ item: RoutineItem, in context: ModelContext, now: Date = .now) {
        let routine = item.routine
        item.routine = nil
        context.delete(item)
        if let routine {
            renumber(routine, now: now)
            routine.updatedAt = now
        }
    }

    /// Moves items within `routine` (offsets into ``Routine/sortedItems``).
    public static func moveItems(in routine: Routine, fromOffsets source: IndexSet, toOffset destination: Int, now: Date = .now) {
        let reordered = Reorder.moving(routine.sortedItems, fromOffsets: source, toOffset: destination)
        assignOrder(reordered, now: now)
        routine.updatedAt = now
    }

    /// Puts `ordered` (items of `routine`) in that order: their `order` becomes 0, 1, 2, ….
    /// Items of the routine missing from `ordered` keep their relative order after them.
    public static func arrangeItems(_ ordered: [RoutineItem], in routine: Routine, now: Date = .now) {
        var seen: Set<PersistentIdentifier> = []
        let listed = ordered.filter { $0.routine === routine && seen.insert($0.persistentModelID).inserted }
        let after = listed + routine.sortedItems.filter { !seen.contains($0.persistentModelID) }
        guard after.enumerated().contains(where: { $0.element.order != $0.offset }) else { return }
        assignOrder(after, now: now)
        routine.updatedAt = now
    }

    /// Sets the exercise `item` performs.
    public static func setExercise(_ exercise: Exercise, on item: RoutineItem, now: Date = .now) {
        guard item.exercise !== exercise else { return }
        item.exercise = exercise
        touch(item, now: now)
    }

    /// Sets the target sets, limited to ``RoutineRules/setsRange``.
    public static func setTargetSets(_ sets: Int, on item: RoutineItem, now: Date = .now) {
        let sets = RoutineRules.clampedSets(sets)
        guard sets != item.targetSets else { return }
        item.targetSets = sets
        touch(item, now: now)
    }

    /// Sets the rep range (see ``RoutineRules/repRange(low:high:)``).
    public static func setRepRange(low: Int, high: Int, on item: RoutineItem, now: Date = .now) {
        let range = RoutineRules.repRange(low: low, high: high)
        guard range.lowerBound != item.repLow || range.upperBound != item.repHigh else { return }
        item.repLow = range.lowerBound
        item.repHigh = range.upperBound
        touch(item, now: now)
    }

    /// Sets the rest after each set; `nil` uses the exercise's default
    /// (see ``RoutineRules/normalizedRest(_:)``).
    public static func setRest(_ seconds: Int?, on item: RoutineItem, now: Date = .now) {
        let rest = RoutineRules.normalizedRest(seconds)
        guard rest != item.restSeconds else { return }
        item.restSeconds = rest
        touch(item, now: now)
    }

    /// Sets the exercise's alternatives (see ``ExerciseRules/validAlternatives(_:for:)``).
    /// Alternatives belong to the exercise, so this changes them in every routine.
    public static func setAlternatives(_ alternatives: [Exercise], for exercise: Exercise, now: Date = .now) {
        let valid = ExerciseRules.validAlternatives(alternatives, for: exercise)
        let current = exercise.alternatives ?? []
        guard Set(valid.map(\.persistentModelID)) != Set(current.map(\.persistentModelID)) else { return }
        exercise.alternatives = valid
        exercise.updatedAt = now
    }

    // MARK: Helpers

    /// Records the account's starter-routine decision if none has been made.
    static func settleStarterDecision(in context: ModelContext, now: Date) throws {
        let settings = try AppSettings.current(in: context)
        if settings.starterRoutinesDecidedAt == nil {
            settings.starterRoutinesDecidedAt = now
        }
    }

    private static func nextSortIndex(after routines: [Routine]) -> Int {
        (routines.map(\.sortIndex).max() ?? -1) + 1
    }

    private static func touch(_ item: RoutineItem, now: Date) {
        item.updatedAt = now
        item.routine?.updatedAt = now
    }

    private static func renumber(_ routine: Routine, now: Date) {
        assignOrder(routine.sortedItems, now: now)
    }

    private static func assignOrder(_ items: [RoutineItem], now: Date) {
        for (index, item) in items.enumerated() where item.order != index {
            item.order = index
            item.updatedAt = now
        }
    }
}

/// Moving elements the way SwiftUI's `onMove` describes it, without depending on SwiftUI.
public enum Reorder {
    /// `elements` with the elements at `source` moved to before `destination` (an offset in
    /// the original array), keeping their relative order.
    public static func moving<Element>(_ elements: [Element], fromOffsets source: IndexSet, toOffset destination: Int) -> [Element] {
        let valid = source.filter { elements.indices.contains($0) }
        guard !valid.isEmpty else { return elements }
        let moving = valid.map { elements[$0] }
        var remaining: [Element] = []
        var insertion = 0
        for (index, element) in elements.enumerated() {
            if index == destination { insertion = remaining.count }
            if !valid.contains(index) { remaining.append(element) }
        }
        if destination >= elements.count { insertion = remaining.count }
        remaining.insert(contentsOf: moving, at: min(max(insertion, 0), remaining.count))
        return remaining
    }
}
