// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// What one ``StoreMaintenance/run(in:library:seedStarterRoutines:now:)`` pass changed.
public struct MaintenanceReport: Sendable, Equatable {
    /// Library exercises inserted.
    public var libraryInserted = 0
    /// Existing exercises that became library exercises (matched by name).
    public var libraryAdopted = 0
    /// Library exercises that gained aliases from a newer library.
    public var libraryUpdated = 0
    /// Duplicate library exercises merged into one.
    public var exercisesMerged = 0
    /// Routines from an earlier app version recognised as starter routines.
    public var legacyStartersAdopted = 0
    /// Duplicate starter routines merged into one.
    public var routinesMerged = 0
    /// Untouched starter routines removed because another device's decision came first.
    public var routinesRemoved = 0
    /// Extra weekly plan rows removed.
    public var planDaysRemoved = 0
    /// Whether the starter-routine decision was recorded from existing routines.
    public var decisionInferred = false
    /// Whether the starter routines were created.
    public var startersSeeded = false

    /// Creates an empty report.
    public init() {}
}

/// The launch and post-sync pass both apps run over the store.
///
/// Both apps seed the built-in library and both sync through the same CloudKit database,
/// so the same row can be created twice before the devices see each other's data.
/// CloudKit has no unique constraints; uniqueness is restored here, in a way that every
/// device computes the same result from the same rows:
///
/// 1. **Settings**: a single `AppSettings` row (``SchemaV3/AppSettings/current(in:)``).
/// 2. **Library exercises**: rows sharing a `libraryKey` are merged into the oldest; routine
///    items, session entries and alternatives are re-pointed to it first, user-editable
///    values come from the most recently edited copy, aliases are combined.
/// 3. **Library seed** (when `seedLibrary` is set): each library entry is matched by key,
///    else adopted from an existing exercise with the same name (ignoring case), else
///    inserted. Never a duplicate of what this device can see; devices hold this step until
///    they have seen iCloud's data (``StarterSeedGate``), so the library is normally
///    inserted once per account rather than once per device.
/// 4. **Starter decision**: routines from the first Watch release that exactly match a
///    starter template get its `seedKey`. If the account has not decided about starter
///    routines but has routines, the decision is recorded as when they appeared.
/// 5. **Starter routines** with the same `seedKey`: untouched copies (`updatedAt ==
///    createdAt`) are merged into one, re-pointing sessions and plan days. A starter routine
///    created more than a second after the account's decision lost a race to another
///    device's decision; if no copy of it remains and it is untouched and unused, it is
///    removed. Edited copies are never removed.
/// 6. **Weekly plan**: one row per weekday, the most recently updated one.
/// 7. **Seeding**: when `seedStarterRoutines` is set and ``StarterSeedGate`` agrees.
///
/// Maintenance writes never change `updatedAt`, which records user edits.
public enum StoreMaintenance {
    /// Starter routines created within this time of the account's decision belong to it.
    static let decisionTolerance: TimeInterval = 1

    /// Runs the pass and saves if anything changed.
    ///
    /// - Parameters:
    ///   - context: The context to repair, usually the main context.
    ///   - library: The built-in library.
    ///   - seedLibrary: Whether to add missing library exercises now.
    ///   - seedStarterRoutines: Whether this device may create the starter routines now
    ///     (see ``StarterSeedGate/shouldSeed(decidedAt:routineCount:readiness:)``); they are
    ///     only created if the account is undecided and has no routines.
    ///   - now: The current time.
    @discardableResult
    public static func run(
        in context: ModelContext,
        library: ExerciseLibrary,
        seedLibrary: Bool = true,
        seedStarterRoutines: Bool,
        now: Date = .now
    ) throws -> MaintenanceReport {
        var report = MaintenanceReport()
        let settings = try AppSettings.current(in: context)

        var exercises = try context.fetch(FetchDescriptor<Exercise>())
        exercises = mergeLibraryDuplicates(exercises, in: context, report: &report)
        if seedLibrary {
            Self.seedLibrary(library, existing: exercises, in: context, now: now, report: &report)
        }

        var routines = try context.fetch(FetchDescriptor<Routine>())
        settleDecision(settings: settings, routines: routines, report: &report)
        routines = reconcileStarters(routines, decidedAt: settings.starterRoutinesDecidedAt, in: context, report: &report)

        try dedupePlanDays(in: context, report: &report)

        if context.hasChanges {
            try context.save()
        }

        if seedStarterRoutines, settings.starterRoutinesDecidedAt == nil, routines.isEmpty {
            try StarterRoutines.seed(in: context, library: library, now: now)
            report.startersSeeded = true
        }
        return report
    }

    // MARK: - Exercises

    /// Merges exercises sharing a library key into the oldest; returns the survivors.
    private static func mergeLibraryDuplicates(
        _ exercises: [Exercise],
        in context: ModelContext,
        report: inout MaintenanceReport
    ) -> [Exercise] {
        let groups = Dictionary(grouping: exercises.filter { $0.libraryKey != nil }) { $0.libraryKey ?? "" }
        var removed: Set<PersistentIdentifier> = []
        for (_, group) in groups where group.count > 1 {
            let ordered = group.sorted(by: isOlder)
            guard let survivor = ordered.first else { continue }
            let newest = group.max { $0.updatedAt < $1.updatedAt }
            if let newest, newest !== survivor, newest.updatedAt > survivor.updatedAt {
                survivor.copyUserValues(from: newest)
            }
            for loser in ordered.dropFirst() {
                merge(loser, into: survivor)
                context.delete(loser)
                removed.insert(loser.persistentModelID)
                report.exercisesMerged += 1
            }
        }
        return exercises.filter { !removed.contains($0.persistentModelID) }
    }

    /// Moves everything that refers to `loser` over to `survivor`.
    static func merge(_ loser: Exercise, into survivor: Exercise) {
        for item in loser.routineItems ?? [] {
            item.exercise = survivor
        }
        for entry in loser.sessionEntries ?? [] {
            entry.exercise = survivor
        }
        var alternatives = survivor.alternatives ?? []
        for candidate in loser.alternatives ?? []
        where candidate !== survivor && !alternatives.contains(where: { $0 === candidate }) && alternatives.count < ExerciseRules.maxAlternatives {
            alternatives.append(candidate)
        }
        survivor.alternatives = alternatives
        for owner in loser.alternativeOf ?? [] where owner !== survivor {
            var list = (owner.alternatives ?? []).filter { $0 !== loser }
            if !list.contains(where: { $0 === survivor }) {
                list.append(survivor)
            }
            owner.alternatives = list
        }
        survivor.aliases = survivor.aliases + loser.aliases
    }

    private static func seedLibrary(
        _ library: ExerciseLibrary,
        existing: [Exercise],
        in context: ModelContext,
        now: Date,
        report: inout MaintenanceReport
    ) {
        var byKey: [String: Exercise] = [:]
        var unkeyedByName: [String: Exercise] = [:]
        for exercise in existing {
            if let key = exercise.libraryKey {
                byKey[key] = exercise
                continue
            }
            let name = ExerciseName.normalized(exercise.name)
            guard !name.isEmpty else { continue }
            if let current = unkeyedByName[name], !StarterRoutines.isBetterMatch(exercise, than: current) { continue }
            unkeyedByName[name] = exercise
        }

        for entry in library.entries {
            if let exercise = byKey[entry.key] {
                let merged = AliasList.encode(exercise.aliases + entry.aliases)
                if merged != exercise.aliasesText {
                    exercise.aliasesText = merged
                    report.libraryUpdated += 1
                }
            } else if let exercise = unkeyedByName.removeValue(forKey: ExerciseName.normalized(entry.name)) {
                exercise.libraryKey = entry.key
                exercise.isCustom = false
                exercise.aliases = exercise.aliases + entry.aliases
                byKey[entry.key] = exercise
                report.libraryAdopted += 1
            } else {
                let exercise = Exercise(name: entry.name, equipment: entry.equipment, primaryMuscle: entry.muscle)
                exercise.libraryKey = entry.key
                exercise.aliases = entry.aliases
                exercise.createdAt = now
                exercise.updatedAt = now
                context.insert(exercise)
                byKey[entry.key] = exercise
                report.libraryInserted += 1
            }
        }
    }

    // MARK: - Starter routines

    /// Adopts routines left by the first Watch release and records the account's decision
    /// when it has routines but none was recorded.
    private static func settleDecision(settings: AppSettings, routines: [Routine], report: inout MaintenanceReport) {
        guard settings.starterRoutinesDecidedAt == nil, !routines.isEmpty else { return }
        for template in StarterRoutines.templates {
            for routine in routines where StarterRoutines.isLegacyCopy(routine, of: template) {
                routine.seedKey = template.key
                report.legacyStartersAdopted += 1
            }
        }
        let starters = routines.filter { $0.seedKey != nil }
        let basis = starters.isEmpty ? routines : starters
        settings.starterRoutinesDecidedAt = basis.map(\.createdAt).min()
        report.decisionInferred = true
    }

    /// Merges duplicate starter routines and removes untouched ones that lost a race;
    /// returns the routines that remain.
    private static func reconcileStarters(
        _ routines: [Routine],
        decidedAt: Date?,
        in context: ModelContext,
        report: inout MaintenanceReport
    ) -> [Routine] {
        let groups = Dictionary(grouping: routines.filter { $0.seedKey != nil }) { $0.seedKey ?? "" }
        var removed: Set<PersistentIdentifier> = []

        for (_, group) in groups {
            func isLate(_ routine: Routine) -> Bool {
                guard let decidedAt else { return false }
                return routine.createdAt.timeIntervalSince(decidedAt) > decisionTolerance
            }
            let ordered = group.sorted { lhs, rhs in
                if lhs.isPristine != rhs.isPristine { return !lhs.isPristine }
                if isLate(lhs) != isLate(rhs) { return !isLate(lhs) }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            guard let keeper = ordered.first else { continue }
            for duplicate in ordered.dropFirst() where duplicate.isPristine {
                merge(duplicate, into: keeper)
                context.delete(duplicate)
                removed.insert(duplicate.persistentModelID)
                report.routinesMerged += 1
            }
            let hasTimelyCopy = group.contains { !isLate($0) }
            if !hasTimelyCopy, keeper.isPristine, (keeper.sessions ?? []).isEmpty, (keeper.weekPlanDays ?? []).isEmpty {
                context.delete(keeper)
                removed.insert(keeper.persistentModelID)
                report.routinesRemoved += 1
            }
        }
        return routines.filter { !removed.contains($0.persistentModelID) }
    }

    /// Moves sessions and plan days from `duplicate` to `keeper`.
    private static func merge(_ duplicate: Routine, into keeper: Routine) {
        for session in duplicate.sessions ?? [] {
            session.routine = keeper
        }
        for day in duplicate.weekPlanDays ?? [] {
            day.routine = keeper
        }
    }

    // MARK: - Weekly plan

    private static func dedupePlanDays(in context: ModelContext, report: inout MaintenanceReport) throws {
        let days = try context.fetch(FetchDescriptor<WeekPlanDay>())
        let groups = Dictionary(grouping: days.filter { (1...7).contains($0.weekday) }, by: \.weekday)
        for (_, group) in groups where group.count > 1 {
            guard let newest = WeekPlan.effectiveRow(in: group) else { continue }
            for day in group where day !== newest {
                context.delete(day)
                report.planDaysRemoved += 1
            }
        }
    }

    // MARK: - Ordering

    private static func isOlder(_ lhs: Exercise, _ rhs: Exercise) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

extension Routine {
    /// Whether the routine was never edited after it was created (within a second, so the
    /// millisecond precision CloudKit keeps for dates cannot make an untouched routine look edited).
    var isPristine: Bool {
        updatedAt.timeIntervalSince(createdAt) < StoreMaintenance.decisionTolerance
    }
}

extension Exercise {
    /// Copies the values a user can change (name, equipment, muscle, archive state and
    /// per-exercise settings) and `updatedAt`.
    func copyUserValues(from other: Exercise) {
        name = other.name
        equipmentRaw = other.equipmentRaw
        primaryMuscleRaw = other.primaryMuscleRaw
        isArchived = other.isArchived
        progressionStepKg = other.progressionStepKg
        defaultRestSeconds = other.defaultRestSeconds
        updatedAt = other.updatedAt
    }
}
