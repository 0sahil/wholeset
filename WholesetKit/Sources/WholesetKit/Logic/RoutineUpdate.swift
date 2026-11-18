// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// One way a finished session differed from the routine it was started from.
public enum RoutineChange: Equatable, Sendable {
    /// A routine slot was done with another exercise.
    case swapped(from: String, to: String)
    /// An exercise outside the routine was added and logged, with its working-set count.
    case added(exercise: String, sets: Int)
    /// A slot ended up with a different number of working sets.
    case setsChanged(exercise: String, from: Int, to: Int)
    /// The routine's exercises were done in a different order.
    case reordered
}

/// The offer, after a workout, to update its routine with what was done.
public struct RoutineUpdateProposal: Equatable, Sendable {
    /// The routine's name.
    public let routineName: String
    /// What changed, slot by slot in routine order, then added exercises, then the order.
    public let changes: [RoutineChange]

    /// Creates a proposal.
    public init(routineName: String, changes: [RoutineChange]) {
        self.routineName = routineName
        self.changes = changes
    }
}

/// Compares a finished session with its routine, and writes the differences back.
///
/// The session's entries are grouped by the routine slot they came from
/// (``SessionExercise/routineItemID``, kept through swaps); entries without one were added
/// during the workout. A slot's changes:
/// - **swapped**: the exercise of the slot's last entry with a logged set differs from the
///   slot's exercise. A replacement nobody logged a set of is not a swap.
/// - **sets**: the working sets (not warm-ups) over all the slot's entries, logged and still
///   planned, clamped to ``RoutineRules/setsRange``, differ from the slot's target.
/// - A slot whose entries were all skipped never changes: skipping means "not today".
///
/// Added exercises count when they have at least one logged set. The order changed when the
/// slots appear in the session in a different relative order than in the routine.
///
/// Nothing is offered for a session without a logged set, or for one started before
/// entries recorded their slot.
public enum RoutineUpdate {
    /// The changes worth offering for `session`, or `nil` when it has no routine, nothing
    /// was logged, or nothing changed.
    public static func proposal(for session: Session) -> RoutineUpdateProposal? {
        guard let routine = session.routine, let analysis = Analysis(session: session, routine: routine) else { return nil }
        let changes = analysis.changes
        guard !changes.isEmpty else { return nil }
        return RoutineUpdateProposal(routineName: routine.name, changes: changes)
    }

    /// Rewrites `session`'s routine to match the session: slot exercises and target sets,
    /// new items for added exercises (with the entry's rep range), and the order. Sets
    /// `updatedAt` the way ``RoutineEditing`` does. Does not save.
    ///
    /// - Returns: Whether the routine changed.
    @discardableResult
    public static func apply(to session: Session, in context: ModelContext, now: Date = .now) -> Bool {
        guard let routine = session.routine, let analysis = Analysis(session: session, routine: routine),
              !analysis.changes.isEmpty else { return false }
        for slot in analysis.slots where !slot.isSkipped {
            if let final = slot.finalExercise, final !== slot.item.exercise {
                RoutineEditing.setExercise(final, on: slot.item, now: now)
            }
            RoutineEditing.setTargetSets(slot.workingSets, on: slot.item, now: now)
        }
        var addedItems: [PersistentIdentifier: RoutineItem] = [:]
        for group in analysis.added {
            guard let item = RoutineEditing.addItems(for: [group.exercise], to: routine, in: context, now: now).first else { continue }
            RoutineEditing.setTargetSets(group.workingSets, on: item, now: now)
            RoutineEditing.setRepRange(low: group.repLow, high: group.repHigh, on: item, now: now)
            addedItems[group.exercise.persistentModelID] = item
            // The session now matches the routine: its added entries belong to the new item.
            for entry in group.entries {
                entry.routineItemID = item.id
                entry.updatedAt = now
            }
        }
        let ordered: [RoutineItem] = analysis.sequence.compactMap { element in
            switch element {
            case .slot(let item): item
            case .added(let exercise): addedItems[exercise.persistentModelID]
            }
        }
        RoutineEditing.arrangeItems(analysis.anchoring(ordered), in: routine, now: now)
        routine.updatedAt = now
        return true
    }

    // MARK: Save as routine

    /// Whether `session` can become a new routine: it has no routine and at least one
    /// logged set.
    public static func canSaveAsRoutine(_ session: Session) -> Bool {
        session.routine == nil && (session.entries ?? []).contains(where: \.hasLoggedSet)
    }

    /// "Workout 18 Nov": the default name for a routine made from `session`, with the
    /// session's start day in `locale`'s short day-and-month format.
    public static func suggestedRoutineName(for session: Session, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let day = session.startedAt.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).day().month(.abbreviated))
        return String(localized: "Workout \(day)", bundle: .module)
    }

    /// Creates a routine from `session` and links the session to it: one item per exercise
    /// with a logged set, in session order, targeting the working sets done or still planned
    /// (see ``RoutineRules/setsRange``) with the entry's rep range. Does not save.
    ///
    /// - Parameter name: The routine's name; `nil` uses ``suggestedRoutineName(for:locale:timeZone:)``.
    /// - Returns: The routine, or `nil` if ``canSaveAsRoutine(_:)`` is `false`.
    @discardableResult
    public static func saveAsRoutine(
        _ session: Session,
        named name: String? = nil,
        in context: ModelContext,
        now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) throws -> Routine? {
        guard canSaveAsRoutine(session) else { return nil }
        let routine = try RoutineEditing.createRoutine(
            named: name ?? suggestedRoutineName(for: session, locale: locale, timeZone: timeZone),
            in: context,
            now: now
        )
        for group in exerciseGroups(session.sortedEntries.filter(\.hasLoggedSet)) {
            guard let item = RoutineEditing.addItems(for: [group.exercise], to: routine, in: context, now: now).first else { continue }
            RoutineEditing.setTargetSets(group.workingSets, on: item, now: now)
            RoutineEditing.setRepRange(low: group.repLow, high: group.repHigh, on: item, now: now)
            for entry in group.entries {
                entry.routineItemID = item.id
                entry.updatedAt = now
            }
        }
        session.routine = routine
        session.updatedAt = now
        return routine
    }

    // MARK: Analysis

    /// Working sets over `entries`, logged or still planned, within ``RoutineRules/setsRange``.
    static func workingSetCount(_ entries: [SessionExercise]) -> Int {
        RoutineRules.clampedSets(entries.reduce(0) { $0 + ($1.sets ?? []).count { !$0.isWarmup } })
    }

    /// Entries of one exercise, with what a routine item for them needs.
    struct ExerciseGroup {
        let exercise: Exercise
        var entries: [SessionExercise]

        var workingSets: Int { RoutineUpdate.workingSetCount(entries) }
        var repLow: Int { entries.first?.repLow ?? RoutineRules.defaultRepLow }
        var repHigh: Int { entries.first?.repHigh ?? RoutineRules.defaultRepHigh }
    }

    /// `entries` (in session order) grouped by exercise, in order of first appearance.
    static func exerciseGroups(_ entries: [SessionExercise]) -> [ExerciseGroup] {
        var groups: [ExerciseGroup] = []
        var index: [PersistentIdentifier: Int] = [:]
        for entry in entries {
            guard let exercise = entry.exercise else { continue }
            if let position = index[exercise.persistentModelID] {
                groups[position].entries.append(entry)
            } else {
                index[exercise.persistentModelID] = groups.count
                groups.append(ExerciseGroup(exercise: exercise, entries: [entry]))
            }
        }
        return groups
    }

    /// A session laid against its routine.
    struct Analysis {
        /// A routine slot with the entries that came from it.
        struct Slot {
            let item: RoutineItem
            var entries: [SessionExercise]

            /// Every entry was skipped: the slot is left as it is.
            var isSkipped: Bool { entries.allSatisfy(\.isSkipped) }
            /// The exercise of the last entry with a logged set.
            var finalExercise: Exercise? { entries.last(where: \.hasLoggedSet)?.exercise }
            var workingSets: Int { RoutineUpdate.workingSetCount(entries) }
        }

        /// A slot or an added exercise, in session order.
        enum Element {
            case slot(RoutineItem)
            case added(Exercise)
        }

        let routineItems: [RoutineItem]
        /// Slots with entries, in routine order.
        let slots: [Slot]
        /// Added exercises with a logged set, in session order.
        let added: [ExerciseGroup]
        /// Slots and added exercises in the order they appear in the session.
        let sequence: [Element]

        init?(session: Session, routine: Routine) {
            let entries = session.sortedEntries
            guard entries.contains(where: \.hasLoggedSet) else { return nil }
            let items = routine.sortedItems
            // Sessions from before schema version 3 record no slots: nothing can be compared.
            if items.contains(where: { $0.exercise != nil }), !entries.contains(where: { $0.routineItemID != nil }) {
                return nil
            }
            let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var slotEntries: [UUID: [SessionExercise]] = [:]
            var addedEntries: [SessionExercise] = []
            var sequence: [Element] = []
            var seenSlots: Set<UUID> = []
            var seenAdded: Set<PersistentIdentifier> = []
            for entry in entries {
                if let itemID = entry.routineItemID {
                    // A slot deleted from the routine since the workout started is not compared.
                    guard let item = itemsByID[itemID] else { continue }
                    slotEntries[itemID, default: []].append(entry)
                    if seenSlots.insert(itemID).inserted { sequence.append(.slot(item)) }
                } else if entry.hasLoggedSet, let exercise = entry.exercise {
                    addedEntries.append(entry)
                    if seenAdded.insert(exercise.persistentModelID).inserted { sequence.append(.added(exercise)) }
                }
            }
            self.routineItems = items
            self.slots = items.compactMap { item in slotEntries[item.id].map { Slot(item: item, entries: $0) } }
            self.added = RoutineUpdate.exerciseGroups(addedEntries)
            self.sequence = sequence
        }

        var changes: [RoutineChange] {
            var changes: [RoutineChange] = []
            for slot in slots where !slot.isSkipped {
                let finalName = slot.finalExercise?.name ?? slot.item.exercise?.name ?? ""
                if let original = slot.item.exercise, let final = slot.finalExercise, final !== original {
                    changes.append(.swapped(from: original.name, to: final.name))
                }
                if slot.workingSets != slot.item.targetSets {
                    changes.append(.setsChanged(exercise: finalName, from: slot.item.targetSets, to: slot.workingSets))
                }
            }
            for group in added {
                changes.append(.added(exercise: group.exercise.name, sets: group.workingSets))
            }
            let sessionOrder = sequence.compactMap { element -> UUID? in
                if case .slot(let item) = element { return item.id }
                return nil
            }
            let present = Set(sessionOrder)
            let routineOrder = routineItems.map(\.id).filter(present.contains)
            if sessionOrder != routineOrder {
                changes.append(.reordered)
            }
            return changes
        }

        /// `ordered` (the session's slots and new items) with the routine's other items
        /// (no entry in the session) put back after the item they followed in the routine.
        func anchoring(_ ordered: [RoutineItem]) -> [RoutineItem] {
            let present = Set(slots.map(\.item.id))
            var leading: [RoutineItem] = []
            var following: [UUID: [RoutineItem]] = [:]
            var anchor: UUID?
            for item in routineItems {
                if present.contains(item.id) {
                    anchor = item.id
                } else if let anchor {
                    following[anchor, default: []].append(item)
                } else {
                    leading.append(item)
                }
            }
            var result = leading
            for item in ordered {
                result.append(item)
                result += following[item.id] ?? []
            }
            return result
        }
    }
}
