// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// Reads the weight and reps of a set typed when fixing a past session.
///
/// Weights are typed in the display unit with up to ``fractionDigits`` decimals (point or
/// comma, see ``DecimalInput``) and stored in kilograms; ``weightText(kilograms:unit:locale:)``
/// shows a stored weight the same way, so a weight typed in pounds reads back exactly as typed.
public enum SetInput {
    /// The heaviest weight accepted, in kilograms.
    public static let maximumWeightKilograms: Double = 1000
    /// The reps accepted.
    public static let repsRange = 1...999
    /// Decimals kept in the display unit.
    public static let fractionDigits = 2

    /// Why a typed weight is not valid.
    public enum WeightProblem: Error, Equatable, Sendable {
        /// Not a plain decimal number.
        case notANumber
        /// Below zero.
        case negative
        /// More than ``SetInput/maximumWeight(in:)``.
        case tooHeavy
    }

    /// Why typed reps are not valid.
    public enum RepsProblem: Error, Equatable, Sendable {
        /// Nothing typed; every logged set needs reps.
        case empty
        /// Not a whole number.
        case notANumber
        /// Outside ``SetInput/repsRange``.
        case outOfRange
    }

    /// The heaviest weight accepted in `unit`, rounded down to ``fractionDigits`` decimals
    /// (1000 kg, or 2204.62 lb).
    public static func maximumWeight(in unit: WeightUnit) -> Double {
        let scale = pow(10, Double(fractionDigits))
        return (unit.value(fromKilograms: maximumWeightKilograms) * scale).rounded(.down) / scale
    }

    /// The weight in kilograms that `text` (in `unit`) describes, after rounding to
    /// ``fractionDigits`` decimals in `unit`; `nil` when nothing is typed (a set without weight).
    public static func weightKilograms(from text: String, unit: WeightUnit, locale: Locale = .current) -> Result<Double?, WeightProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }
        guard let parsed = DecimalInput.parse(trimmed, locale: locale), parsed.isFinite else { return .failure(.notANumber) }
        let value = DecimalInput.rounded(parsed, fractionDigits: fractionDigits)
        guard value >= 0 else { return .failure(.negative) }
        guard value <= maximumWeight(in: unit) else { return .failure(.tooHeavy) }
        // "-0" rounds to negative zero, which is stored as plain zero.
        return .success(unit.kilograms(fromValue: value == 0 ? 0 : value))
    }

    /// The reps `text` describes.
    public static func reps(from text: String) -> Result<Int, RepsProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let reps = DecimalInput.parseWholeNumber(trimmed) else { return .failure(.notANumber) }
        guard repsRange.contains(reps) else { return .failure(.outOfRange) }
        return .success(reps)
    }

    /// A stored weight as editable text in `unit`: up to ``fractionDigits`` decimals, no
    /// grouping, the locale's separator. Empty for a set without weight.
    public static func weightText(kilograms: Double?, unit: WeightUnit, locale: Locale = .current) -> String {
        guard let kilograms, kilograms.isFinite else { return "" }
        let value = DecimalInput.rounded(unit.value(fromKilograms: kilograms), fractionDigits: fractionDigits)
        return DecimalInput.text(value, maximumFractionDigits: fractionDigits, locale: locale)
    }

    /// Stored reps as editable text; empty when none were recorded.
    public static func repsText(_ reps: Int?) -> String {
        reps.map(String.init) ?? ""
    }
}

/// An editable copy of a finished session's logged sets and notes, so the editor can be
/// cancelled.
///
/// The editor changes this value only; nothing in the store changes until
/// ``apply(in:now:)`` writes the differences in one go. Only exercises with at least one
/// logged set are listed; planned sets that were never logged are not edited.
public struct SessionDraft: Equatable, Sendable {
    /// One logged set, or a set added in the draft.
    public struct SetDraft: Identifiable, Equatable, Sendable {
        /// The `SetLog`'s id, or a new id for a set added in the draft.
        public let id: UUID
        /// Whether the set was added in the draft.
        public let isNew: Bool
        /// Whether the set is a warm-up.
        public var isWarmup: Bool
        /// The weight as typed, in the display unit; empty for no weight.
        public var weightText: String
        /// The reps as typed.
        public var repsText: String
    }

    /// One exercise and its sets.
    public struct EntryDraft: Identifiable, Equatable, Sendable {
        /// The `SessionExercise`'s id.
        public let id: UUID
        /// The exercise's name.
        public let exerciseName: String
        /// The sets in order. When empty, applying removes the exercise from the session.
        public internal(set) var sets: [SetDraft]

        /// The 1-based number of the working set with `id` among this exercise's working
        /// sets; `nil` for warm-ups and unknown ids.
        public func number(ofSet id: UUID) -> Int? {
            var number = 0
            for set in sets {
                if !set.isWarmup { number += 1 }
                if set.id == id { return set.isWarmup ? nil : number }
            }
            return nil
        }
    }

    /// The session being edited.
    public let sessionID: UUID
    /// The unit weights are typed in.
    public let unit: WeightUnit
    /// The locale typed numbers are read in.
    public let locale: Locale
    /// The session's notes.
    public var notes: String
    /// The exercises with logged sets, in order.
    public private(set) var entries: [EntryDraft]

    private let originalNotes: String
    private let originalEntries: [EntryDraft]
    private let originalSets: [UUID: SetDraft]

    /// A draft of `session`, with weights shown in `unit`.
    public init(session: Session, unit: WeightUnit, locale: Locale = .current) {
        sessionID = session.id
        self.unit = unit
        self.locale = locale
        notes = session.notes
        entries = session.sortedEntries.compactMap { entry in
            let logged = entry.sortedSets.filter { $0.completedAt != nil }
            guard !logged.isEmpty else { return nil }
            return EntryDraft(
                id: entry.id,
                exerciseName: entry.exercise?.name ?? "",
                sets: logged.map { set in
                    SetDraft(
                        id: set.id,
                        isNew: false,
                        isWarmup: set.isWarmup,
                        weightText: SetInput.weightText(kilograms: set.weightKg, unit: unit, locale: locale),
                        repsText: SetInput.repsText(set.reps)
                    )
                }
            )
        }
        originalNotes = notes
        originalEntries = entries
        originalSets = Dictionary(entries.flatMap(\.sets).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: State

    /// Whether anything differs from the session as it was opened.
    public var hasChanges: Bool {
        notes != originalNotes || entries != originalEntries
    }

    /// Whether Done is allowed: every set has valid reps and a valid (or no) weight.
    public var canSave: Bool {
        entries.allSatisfy { entry in
            entry.sets.allSatisfy { weightProblem(for: $0) == nil && repsProblem(for: $0) == nil }
        }
    }

    /// The set with `id`, if any.
    public func set(id: UUID) -> SetDraft? {
        for entry in entries {
            if let set = entry.sets.first(where: { $0.id == id }) { return set }
        }
        return nil
    }

    /// What is wrong with the weight typed on the set with `id`, if anything.
    public func weightProblem(forSet id: UUID) -> SetInput.WeightProblem? {
        set(id: id).flatMap(weightProblem(for:))
    }

    /// What is wrong with the reps typed on the set with `id`, if anything.
    public func repsProblem(forSet id: UUID) -> SetInput.RepsProblem? {
        set(id: id).flatMap(repsProblem(for:))
    }

    private func weightProblem(for set: SetDraft) -> SetInput.WeightProblem? {
        if case .failure(let problem) = SetInput.weightKilograms(from: set.weightText, unit: unit, locale: locale) { return problem }
        return nil
    }

    private func repsProblem(for set: SetDraft) -> SetInput.RepsProblem? {
        if case .failure(let problem) = SetInput.reps(from: set.repsText) { return problem }
        return nil
    }

    // MARK: Editing

    /// Sets the weight text of the set with `id`.
    public mutating func setWeightText(_ text: String, forSet id: UUID) {
        update(id) { $0.weightText = text }
    }

    /// Sets the reps text of the set with `id`.
    public mutating func setRepsText(_ text: String, forSet id: UUID) {
        update(id) { $0.repsText = text }
    }

    /// Marks the set with `id` as a warm-up or a working set.
    public mutating func setWarmup(_ isWarmup: Bool, forSet id: UUID) {
        update(id) { $0.isWarmup = isWarmup }
    }

    /// Removes the set with `id`. An exercise left without sets is removed from the session
    /// when the draft is applied.
    public mutating func deleteSet(id: UUID) {
        for index in entries.indices {
            entries[index].sets.removeAll { $0.id == id }
        }
    }

    /// Removes the sets at `offsets` of the exercise with `entryID`, like SwiftUI's `onDelete`.
    public mutating func deleteSets(atOffsets offsets: IndexSet, inEntry entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].sets = entries[index].sets.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// Appends a working set to the exercise with `entryID`, starting from the values of its
    /// last set. Returns the new set's id.
    @discardableResult
    public mutating func addSet(toEntry entryID: UUID) -> UUID? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        let last = entries[index].sets.last
        let set = SetDraft(
            id: UUID(),
            isNew: true,
            isWarmup: false,
            weightText: last?.weightText ?? "",
            repsText: last?.repsText ?? ""
        )
        entries[index].sets.append(set)
        return set.id
    }

    private mutating func update(_ id: UUID, _ change: (inout SetDraft) -> Void) {
        for entryIndex in entries.indices {
            if let setIndex = entries[entryIndex].sets.firstIndex(where: { $0.id == id }) {
                change(&entries[entryIndex].sets[setIndex])
                return
            }
        }
    }

    // MARK: Saving

    /// Errors applying a draft.
    public enum ApplyError: Error, Equatable {
        /// The session was deleted (for example on another device) while being edited.
        case sessionMissing
        /// A field is not valid (see ``canSave``).
        case invalid
    }

    /// Writes the draft to the session in one go. Does not save.
    ///
    /// - Changed weight, reps and warm-up flags are written; a field whose text was not
    ///   touched keeps its stored value exactly (no unit round trip).
    /// - Deleted sets are deleted. An exercise whose logged sets were all deleted is removed
    ///   with its unlogged sets.
    /// - Added sets are logged at the time of the set before them (or when the session
    ///   ended), and placed after the last logged set; the order of each exercise's sets
    ///   stays 0, 1, 2 … with unlogged sets after the logged ones.
    /// - `updatedAt` is set on each set, exercise and the session only when it changed.
    ///   Applying an unchanged draft changes nothing.
    ///
    /// - Returns: Whether anything changed.
    @discardableResult
    public func apply(in context: ModelContext, now: Date = .now) throws -> Bool {
        guard canSave else { throw ApplyError.invalid }
        let sessionID = sessionID
        guard let session = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first else {
            throw ApplyError.sessionMissing
        }
        var changed = false
        if notes != session.notes {
            session.notes = notes
            changed = true
        }
        let entriesByID = Dictionary((session.entries ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for draft in entries {
            guard let entry = entriesByID[draft.id] else { continue }
            if apply(draft, to: entry, session: session, in: context, now: now) {
                changed = true
            }
        }
        if changed { session.updatedAt = now }
        return changed
    }

    /// Applies one exercise; returns whether anything changed.
    private func apply(_ draft: EntryDraft, to entry: SessionExercise, session: Session, in context: ModelContext, now: Date) -> Bool {
        let allSets = entry.sortedSets
        let logged = allSets.filter { $0.completedAt != nil }
        guard !draft.sets.isEmpty else {
            context.delete(entry)
            return true
        }
        let loggedByID = Dictionary(logged.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        var membershipChanged = false

        let kept = Set(draft.sets.lazy.filter { !$0.isNew }.map(\.id))
        for set in logged where !kept.contains(set.id) {
            context.delete(set)
            membershipChanged = true
        }

        var ordered: [SetLog] = []
        var previousCompletedAt: Date?
        for setDraft in draft.sets {
            let weight = (try? SetInput.weightKilograms(from: setDraft.weightText, unit: unit, locale: locale).get()) ?? nil
            let reps = try? SetInput.reps(from: setDraft.repsText).get()
            if setDraft.isNew {
                let set = SetLog(order: ordered.count, weightKg: weight, reps: reps, isWarmup: setDraft.isWarmup)
                set.completedAt = previousCompletedAt ?? session.endedAt ?? session.startedAt
                set.createdAt = now
                set.updatedAt = now
                context.insert(set)
                set.entry = entry
                ordered.append(set)
                previousCompletedAt = set.completedAt
                membershipChanged = true
            } else if let set = loggedByID[setDraft.id] {
                if update(set, from: setDraft, weight: weight, reps: reps) {
                    set.updatedAt = now
                    changed = true
                }
                ordered.append(set)
                previousCompletedAt = set.completedAt
            }
        }

        let unlogged = allSets.filter { $0.completedAt == nil }
        for (index, set) in (ordered + unlogged).enumerated() where set.order != index {
            set.order = index
            set.updatedAt = now
            changed = true
        }
        if membershipChanged {
            entry.updatedAt = now
            changed = true
        }
        return changed
    }

    /// Writes the fields of `draft` that were edited to `set`; returns whether any changed.
    private func update(_ set: SetLog, from draft: SetDraft, weight: Double?, reps: Int?) -> Bool {
        let original = originalSets[draft.id]
        var changed = false
        if draft.weightText != original?.weightText, !Self.sameWeight(weight, set.weightKg) {
            set.weightKg = weight
            changed = true
        }
        if draft.repsText != original?.repsText, reps != set.reps {
            set.reps = reps
            changed = true
        }
        if draft.isWarmup != original?.isWarmup, draft.isWarmup != set.isWarmup {
            set.isWarmup = draft.isWarmup
            changed = true
        }
        return changed
    }

    private static func sameWeight(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (l?, r?): abs(l - r) < 1e-9
        default: false
        }
    }
}

/// Deleting past sessions.
public enum SessionEditing {
    /// Deletes `session` with its exercises and sets. Nothing in Apple Health is touched:
    /// the workout saved there stays until the user deletes it in the Fitness or Health app.
    /// Does not save.
    public static func delete(_ session: Session, in context: ModelContext) {
        context.delete(session)
    }

    /// Deletes the session with `id`, if it exists (see ``delete(_:in:)``). Does not save.
    ///
    /// - Returns: Whether a session was deleted.
    @discardableResult
    public static func deleteSession(id: UUID, in context: ModelContext) throws -> Bool {
        guard let session = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first else {
            return false
        }
        delete(session, in: context)
        return true
    }
}
