// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// An editable copy of a routine, so the routine editor can be cancelled.
///
/// The editor changes this value only; nothing in the store changes until ``apply(in:now:)``
/// writes the differences through ``RoutineEditing``. Exercises are referred to by their
/// `id`, so a draft is plain data.
public struct RoutineDraft: Equatable, Sendable {
    /// One exercise slot.
    public struct Item: Identifiable, Equatable, Sendable {
        /// The `RoutineItem` id for existing items; a new id for items added in the draft.
        public let id: UUID
        /// The exercise's `id`.
        public var exerciseID: UUID
        /// The exercise's name when it was added, for display.
        public var exerciseName: String
        public var targetSets: Int
        public var repLow: Int
        public var repHigh: Int
        /// `nil` uses the exercise's default rest.
        public var restSeconds: Int?

        /// Creates an item with the default targets.
        public init(id: UUID = UUID(), exerciseID: UUID, exerciseName: String) {
            self.id = id
            self.exerciseID = exerciseID
            self.exerciseName = exerciseName
            self.targetSets = RoutineRules.defaultSets
            self.repLow = RoutineRules.defaultRepLow
            self.repHigh = RoutineRules.defaultRepHigh
            self.restSeconds = nil
        }
    }

    /// The routine being edited, or `nil` for a new routine.
    public let routineID: UUID?
    public var name: String
    public var notes: String
    public private(set) var items: [Item]
    /// Alternatives changed in this draft: exercise `id` → alternative `id`s. Exercises not
    /// listed keep their alternatives.
    public private(set) var alternatives: [UUID: [UUID]]

    /// A draft for a new routine.
    public init(name: String = "") {
        routineID = nil
        self.name = name
        notes = ""
        items = []
        alternatives = [:]
    }

    /// A draft of an existing routine.
    public init(routine: Routine) {
        routineID = routine.id
        name = routine.name
        notes = routine.notes
        items = routine.sortedItems.compactMap { item in
            guard let exercise = item.exercise else { return nil }
            var draft = Item(id: item.id, exerciseID: exercise.id, exerciseName: exercise.name)
            draft.targetSets = item.targetSets
            draft.repLow = item.repLow
            draft.repHigh = item.repHigh
            draft.restSeconds = item.restSeconds
            return draft
        }
        alternatives = [:]
    }

    /// Whether the draft can be saved: it needs a name.
    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Items

    /// Appends one item per exercise.
    public mutating func addExercises(_ exercises: [(id: UUID, name: String)]) {
        items += exercises.map { Item(exerciseID: $0.id, exerciseName: $0.name) }
    }

    /// Removes the items at `offsets`.
    public mutating func removeItems(atOffsets offsets: IndexSet) {
        items = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// Removes the item with `id`.
    public mutating func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Moves items like SwiftUI's `onMove`.
    public mutating func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        items = Reorder.moving(items, fromOffsets: source, toOffset: destination)
    }

    /// Sets the target sets of item `id` (limited to ``RoutineRules/setsRange``).
    public mutating func setTargetSets(_ sets: Int, forItem id: UUID) {
        update(id) { $0.targetSets = RoutineRules.clampedSets(sets) }
    }

    /// Sets the bottom of item `id`'s rep range, raising the top if needed.
    public mutating func setRepLow(_ low: Int, forItem id: UUID) {
        update(id) { item in
            let low = RoutineRules.clampedReps(low)
            item.repLow = low
            item.repHigh = max(item.repHigh, low)
        }
    }

    /// Sets the top of item `id`'s rep range, lowering the bottom if needed.
    public mutating func setRepHigh(_ high: Int, forItem id: UUID) {
        update(id) { item in
            let high = RoutineRules.clampedReps(high)
            item.repHigh = high
            item.repLow = min(item.repLow, high)
        }
    }

    /// Sets item `id`'s rest; `nil` uses the exercise's default.
    public mutating func setRest(_ seconds: Int?, forItem id: UUID) {
        update(id) { $0.restSeconds = RoutineRules.normalizedRest(seconds) }
    }

    /// The item with `id`, if any.
    public func item(id: UUID) -> Item? {
        items.first { $0.id == id }
    }

    private mutating func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    // MARK: Alternatives

    /// The alternatives of exercise `exerciseID` in this draft: the edited list, or `current`.
    public func alternatives(of exerciseID: UUID, current: [UUID]) -> [UUID] {
        alternatives[exerciseID] ?? current
    }

    /// Sets the alternatives of exercise `exerciseID`: without itself, without repeats, at
    /// most ``ExerciseRules/maxAlternatives``.
    public mutating func setAlternatives(_ ids: [UUID], of exerciseID: UUID) {
        var seen: Set<UUID> = [exerciseID]
        alternatives[exerciseID] = Array(ids.filter { seen.insert($0).inserted }.prefix(ExerciseRules.maxAlternatives))
    }

    // MARK: Saving

    /// Errors applying a draft.
    public enum ApplyError: Error, Equatable {
        /// The routine was deleted (for example on another device) while being edited.
        case routineMissing
    }

    /// Writes the draft to the store and returns the routine. Creates the routine for a
    /// new draft. Items whose exercise no longer exists are skipped. Does not save.
    @discardableResult
    public func apply(in context: ModelContext, now: Date = .now) throws -> Routine {
        let exercises = Dictionary(
            try context.fetch(FetchDescriptor<Exercise>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let routine: Routine
        if let routineID {
            let matches = try context.fetch(FetchDescriptor<Routine>(predicate: #Predicate { $0.id == routineID }))
            guard let existing = matches.first else { throw ApplyError.routineMissing }
            routine = existing
            RoutineEditing.rename(routine, to: name, now: now)
        } else {
            routine = try RoutineEditing.createRoutine(named: name, in: context, now: now)
        }
        RoutineEditing.setNotes(notes, on: routine, now: now)

        let existingItems = Dictionary(
            routine.sortedItems.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let kept = Set(items.map(\.id))
        for (id, item) in existingItems where !kept.contains(id) {
            RoutineEditing.removeItem(item, in: context, now: now)
        }

        var ordered: [RoutineItem] = []
        for draft in items {
            guard let exercise = exercises[draft.exerciseID] else { continue }
            let item: RoutineItem
            if let existing = existingItems[draft.id] {
                item = existing
                if item.exercise?.id != exercise.id {
                    item.exercise = exercise
                    item.updatedAt = now
                    routine.updatedAt = now
                }
            } else {
                guard let added = RoutineEditing.addItems(for: [exercise], to: routine, in: context, now: now).first else { continue }
                item = added
            }
            RoutineEditing.setTargetSets(draft.targetSets, on: item, now: now)
            RoutineEditing.setRepRange(low: draft.repLow, high: draft.repHigh, on: item, now: now)
            RoutineEditing.setRest(draft.restSeconds, on: item, now: now)
            ordered.append(item)
        }
        for (index, item) in ordered.enumerated() where item.order != index {
            item.order = index
            item.updatedAt = now
            routine.updatedAt = now
        }

        for (exerciseID, alternativeIDs) in alternatives {
            guard let exercise = exercises[exerciseID] else { continue }
            RoutineEditing.setAlternatives(alternativeIDs.compactMap { exercises[$0] }, for: exercise, now: now)
        }
        return routine
    }
}
