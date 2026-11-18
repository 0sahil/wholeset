// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// Broad body areas used to filter and group exercises in lists.
public enum MuscleGroup: String, CaseIterable, Sendable, Identifiable {
    case chest
    case back
    case shoulders
    case arms
    case legs
    case core
    case other

    public var id: String { rawValue }

    /// The group `muscle` belongs to.
    public init(_ muscle: Muscle) {
        switch muscle {
        case .chest: self = .chest
        case .lats, .middleBack, .lowerBack, .traps: self = .back
        case .shoulders: self = .shoulders
        case .biceps, .triceps, .forearms: self = .arms
        case .quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors: self = .legs
        case .abdominals: self = .core
        case .neck, .other: self = .other
        }
    }

    /// The muscles in this group.
    public var muscles: [Muscle] {
        Muscle.allCases.filter { MuscleGroup($0) == self }
    }
}

/// Searching, filtering and adding exercises.
public enum ExerciseCatalog {
    /// What an exercise list shows.
    public struct Filter: Sendable, Equatable {
        /// Matched against names and aliases, ignoring case and diacritics; every word must match.
        public var searchText: String
        /// Only exercises in this group, or all when `nil`.
        public var group: MuscleGroup?
        /// Only exercises with this equipment, or all when `nil`.
        public var equipment: Equipment?
        /// Whether archived exercises are included.
        public var includesArchived: Bool

        /// Creates a filter; the default shows every active exercise.
        public init(searchText: String = "", group: MuscleGroup? = nil, equipment: Equipment? = nil, includesArchived: Bool = false) {
            self.searchText = searchText
            self.group = group
            self.equipment = equipment
            self.includesArchived = includesArchived
        }

        /// Whether `exercise` passes the filter.
        public func matches(_ exercise: Exercise) -> Bool {
            if !includesArchived, exercise.isArchived { return false }
            if let group, MuscleGroup(exercise.primaryMuscle) != group { return false }
            if let equipment, exercise.equipment != equipment { return false }
            let words = ExerciseName.normalized(searchText).split(separator: " ")
            guard !words.isEmpty else { return true }
            let haystacks = ([exercise.name] + exercise.aliases).map(ExerciseName.normalized)
            return haystacks.contains { haystack in
                words.allSatisfy { haystack.contains($0) }
            }
        }
    }

    /// `exercises` that pass `filter`, sorted by name.
    public static func filtered(_ exercises: [Exercise], by filter: Filter) -> [Exercise] {
        exercises
            .filter(filter.matches)
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// Why a name cannot be used for a new exercise.
    public enum NameProblem: Error, Equatable, Sendable {
        /// The name is empty after trimming.
        case empty
        /// An exercise with this name (ignoring case and spacing) exists; it may be archived.
        case duplicate(existingName: String, isArchived: Bool)
    }

    /// Checks `name` for a new custom exercise against `existing`.
    public static func validateNewName(_ name: String, existing: [Exercise]) -> Result<String, NameProblem> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        let wanted = ExerciseName.normalized(trimmed)
        if let match = existing.first(where: { ExerciseName.normalized($0.name) == wanted }) {
            return .failure(.duplicate(existingName: match.name, isArchived: match.isArchived))
        }
        return .success(trimmed)
    }

    /// Inserts a custom exercise after checking its name against every exercise in the
    /// store, archived ones included. Does not save.
    @discardableResult
    public static func createCustomExercise(
        named name: String,
        equipment: Equipment,
        muscle: Muscle,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Exercise {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let trimmed = try validateNewName(name, existing: existing).get()
        let exercise = Exercise(name: trimmed, equipment: equipment, primaryMuscle: muscle, isCustom: true)
        exercise.createdAt = now
        exercise.updatedAt = now
        context.insert(exercise)
        return exercise
    }

    /// Archives or unarchives `exercise`. Archived exercises keep their history and stay
    /// in routines that use them, but are hidden from lists by default.
    public static func setArchived(_ isArchived: Bool, _ exercise: Exercise, now: Date = .now) {
        guard exercise.isArchived != isArchived else { return }
        exercise.isArchived = isArchived
        exercise.updatedAt = now
    }
}
