// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// What the user decided an imported exercise name becomes.
public enum ExerciseResolution: Sendable, Hashable {
    /// An existing exercise (or library entry). With `remember`, the imported name is added
    /// to its aliases so later imports match it at once.
    case exercise(ExerciseCandidate.Reference, remember: Bool)
    /// A new custom exercise (or the existing exercise with that name, if one appeared).
    case newCustom(name: String, equipment: Equipment)

    /// The resolution of a match left as the matcher found it. A ``ExerciseMatch/check(_:_:)``
    /// the user keeps counts as confirmed, so its name is remembered.
    public init(_ match: ExerciseMatch) {
        switch match {
        case .matched(let candidate, _): self = .exercise(candidate.reference, remember: false)
        case .check(let candidate, _): self = .exercise(candidate.reference, remember: true)
        case let .newCustom(name, equipment): self = .newCustom(name: name, equipment: equipment)
        }
    }
}

/// Turns resolutions into exercises in a context, creating custom exercises and missing
/// library exercises the first time they are used, never twice.
///
/// Library exercises are created with their library key, so if another device adds the same
/// entry, ``StoreMaintenance`` merges the two like any library duplicate. Custom exercises
/// are looked up by name (ignoring case and spacing, archived ones included) before one is created.
struct ImportExerciseResolver {
    private let context: ModelContext
    private let library: ExerciseLibrary
    private let now: Date
    /// Whether imported names are added to aliases (only the import itself does that).
    private let addsAliases: Bool
    private var byID: [UUID: Exercise] = [:]
    private var byLibraryKey: [String: Exercise] = [:]
    private var byName: [String: Exercise] = [:]
    private var resolved: [String: Exercise] = [:]
    /// Names of the custom exercises created.
    private(set) var createdCustom: [String] = []
    /// Aliases added to exercises.
    private(set) var aliasesAdded = 0

    init(context: ModelContext, library: ExerciseLibrary, now: Date, addsAliases: Bool = true) throws {
        self.context = context
        self.library = library
        self.now = now
        self.addsAliases = addsAliases
        let exercises = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.createdAt)]))
        for exercise in exercises {
            if byID[exercise.id] == nil { byID[exercise.id] = exercise }
            if let key = exercise.libraryKey, byLibraryKey[key] == nil { byLibraryKey[key] = exercise }
            let name = ExerciseName.normalized(exercise.name)
            if let current = byName[name], !current.isArchived || exercise.isArchived { continue }
            byName[name] = exercise
        }
    }

    /// The exercise for `importedName`.
    mutating func exercise(for importedName: String, resolution: ExerciseResolution) -> Exercise {
        if let exercise = resolved[importedName] { return exercise }
        let exercise: Exercise
        switch resolution {
        case let .exercise(.stored(id), remember):
            if let found = byID[id] {
                exercise = found
                if remember { addAlias(importedName, to: found) }
            } else {
                // Deleted since the review: keep the name as a custom exercise.
                exercise = custom(named: importedName, equipment: ExerciseMatcher.guessedEquipment(for: importedName), importedName: importedName)
            }
        case let .exercise(.library(key), remember):
            if let found = byLibraryKey[key] {
                exercise = found
            } else if let entry = library.entry(forKey: key) {
                exercise = libraryExercise(entry)
            } else {
                exercise = custom(named: importedName, equipment: ExerciseMatcher.guessedEquipment(for: importedName), importedName: importedName)
            }
            if remember { addAlias(importedName, to: exercise) }
        case let .newCustom(name, equipment):
            exercise = custom(named: name, equipment: equipment, importedName: importedName)
        }
        resolved[importedName] = exercise
        return exercise
    }

    /// Adds aliases for `.exercise(…, remember: true)` resolutions without creating anything.
    mutating func rememberNames(_ resolutions: [String: ExerciseResolution]) {
        for (name, resolution) in resolutions.sorted(by: { $0.key < $1.key }) {
            if case .exercise(.stored(let id), true) = resolution, let exercise = byID[id] {
                addAlias(name, to: exercise)
            }
        }
    }

    private mutating func custom(named name: String, equipment: Equipment, importedName: String) -> Exercise {
        let trimmed = name.trimmed.isEmpty ? importedName.trimmed : name.trimmed
        let key = ExerciseName.normalized(trimmed)
        let exercise: Exercise
        if let existing = byName[key] {
            exercise = existing
        } else {
            exercise = Exercise(name: trimmed, equipment: equipment, primaryMuscle: .other, isCustom: true)
            exercise.createdAt = now
            exercise.updatedAt = now
            context.insert(exercise)
            byID[exercise.id] = exercise
            byName[key] = exercise
            createdCustom.append(trimmed)
        }
        addAlias(importedName, to: exercise)
        return exercise
    }

    private mutating func libraryExercise(_ entry: ExerciseLibrary.Entry) -> Exercise {
        let key = ExerciseName.normalized(entry.name)
        if let existing = byName[key], existing.libraryKey == nil {
            // An unkeyed exercise with the entry's name: the library seed adopts it later.
            byLibraryKey[entry.key] = existing
            return existing
        }
        let exercise = Exercise(name: entry.name, equipment: entry.equipment, primaryMuscle: entry.muscle)
        exercise.libraryKey = entry.key
        exercise.aliases = entry.aliases
        exercise.createdAt = now
        exercise.updatedAt = now
        context.insert(exercise)
        byID[exercise.id] = exercise
        byLibraryKey[entry.key] = exercise
        byName[key] = exercise
        return exercise
    }

    /// Adds `name` to the exercise's aliases unless it is its name or already an alias.
    private mutating func addAlias(_ name: String, to exercise: Exercise) {
        guard addsAliases else { return }
        let key = ExerciseMatcher.looseKey(name)
        guard !key.isEmpty, key != ExerciseMatcher.looseKey(exercise.name),
              !exercise.aliases.contains(where: { ExerciseMatcher.looseKey($0) == key }) else { return }
        exercise.aliases = exercise.aliases + [name.trimmed]
        exercise.updatedAt = now
        aliasesAdded += 1
    }
}

/// How far an import has got.
public struct ImportWriteProgress: Sendable, Equatable {
    /// Workouts saved so far.
    public let saved: Int
    /// Workouts to save in all.
    public let total: Int

    /// Creates a progress value.
    public init(saved: Int, total: Int) {
        self.saved = saved
        self.total = total
    }

    /// `saved / total`, 0...1.
    public var fraction: Double {
        total > 0 ? Double(saved) / Double(total) : 1
    }
}

/// What the import should write.
public struct ImportWriteRequest: Sendable {
    /// The workouts to add (usually ``ImportPlan/toInsert``); any whose key exists by the
    /// time they are written are skipped.
    public var workouts: [ImportedWorkout]
    /// The sessions' ``Source``.
    public var source: Source
    /// What each imported exercise name becomes, by the name as written. Names without a
    /// resolution become custom exercises.
    public var resolutions: [String: ExerciseResolution]
    /// The built-in library, for library exercises the store does not hold yet.
    public var library: ExerciseLibrary
    /// Sessions per save.
    public var batchSize: Int
    /// The time stamped on everything created.
    public var now: Date

    /// Creates a request.
    public init(
        workouts: [ImportedWorkout],
        source: Source,
        resolutions: [String: ExerciseResolution],
        library: ExerciseLibrary,
        batchSize: Int = 200,
        now: Date = .now
    ) {
        self.workouts = workouts
        self.source = source
        self.resolutions = resolutions
        self.library = library
        self.batchSize = max(1, batchSize)
        self.now = now
    }
}

/// What an import wrote.
public struct ImportWriteReport: Sendable, Equatable {
    /// Sessions added.
    public var inserted = 0
    /// Workouts skipped because their key existed when they were about to be written.
    public var alreadyImported = 0
    /// Workouts the request asked for.
    public var requested = 0
    /// Names of the custom exercises created.
    public var newExercises: [String] = []
    /// Imported names remembered as aliases.
    public var aliasesAdded = 0
    /// Whether the import stopped early; the batches saved before stay.
    public var wasCancelled = false
    /// The exercise each imported name became (only names that were written).
    public var exerciseIDs: [String: UUID] = [:]

    /// Creates an empty report.
    public init() {}
}

/// Writes imported workouts into the store.
///
/// Runs on a context of its own, away from the main actor. Sessions are inserted in file
/// order and saved every ``ImportWriteRequest/batchSize`` sessions; between batches the
/// write stops if its task is cancelled, keeping what was saved (importing the file again
/// adds the rest). Each session gets the format's ``Source``, its ``ImportedWorkout/externalKey``,
/// `endedAt` (the start when the file has no end, which history shows as no duration),
/// notes (the workout's, then one "Exercise: note" line per exercise note) and its sets in
/// order, each logged at the session's start so every history, record and pre-fill path
/// treats it as done. Nothing is written to HealthKit.
///
/// The store has no unique constraints (CloudKit); keys are looked up right before writing,
/// so workouts imported meanwhile are not duplicated.
public enum ImportWriter {
    /// Writes `request` into `container` off the caller's actor.
    ///
    /// - Parameter progress: Called after each saved batch, on the writing thread.
    @concurrent
    public static func write(
        _ request: ImportWriteRequest,
        to container: ModelContainer,
        progress: @escaping @Sendable (ImportWriteProgress) -> Void = { _ in }
    ) async throws -> ImportWriteReport {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try write(request, in: context, isCancelled: { Task.isCancelled }, progress: progress)
    }

    /// Writes `request` into `context`, saving each batch.
    static func write(
        _ request: ImportWriteRequest,
        in context: ModelContext,
        isCancelled: () -> Bool,
        progress: (ImportWriteProgress) -> Void
    ) throws -> ImportWriteReport {
        var report = ImportWriteReport()
        report.requested = request.workouts.count
        var resolver = try ImportExerciseResolver(context: context, library: request.library, now: request.now)
        resolver.rememberNames(request.resolutions)
        var keys = try existingKeys(in: context)
        let pending = request.workouts.filter { workout in
            guard !workout.isEmpty else { return false }
            guard keys.insert(workout.externalKey).inserted else {
                report.alreadyImported += 1
                return false
            }
            return true
        }
        progress(ImportWriteProgress(saved: 0, total: pending.count))

        var unsaved = 0
        for workout in pending {
            insert(workout, request: request, resolver: &resolver, report: &report, in: context)
            unsaved += 1
            if unsaved == request.batchSize {
                try context.save()
                unsaved = 0
                progress(ImportWriteProgress(saved: report.inserted, total: pending.count))
                if isCancelled(), report.inserted < pending.count {
                    report.wasCancelled = true
                    break
                }
            }
        }
        if context.hasChanges {
            try context.save()
        }
        if !report.wasCancelled {
            progress(ImportWriteProgress(saved: report.inserted, total: pending.count))
        }
        report.newExercises = resolver.createdCustom
        report.aliasesAdded = resolver.aliasesAdded
        return report
    }

    /// The keys of every imported session in the store.
    public static func existingKeys(in context: ModelContext) throws -> Set<String> {
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.externalKey != nil })
        descriptor.propertiesToFetch = [\.externalKey]
        return Set(try context.fetch(descriptor).compactMap(\.externalKey))
    }

    private static func insert(
        _ workout: ImportedWorkout,
        request: ImportWriteRequest,
        resolver: inout ImportExerciseResolver,
        report: inout ImportWriteReport,
        in context: ModelContext
    ) {
        let now = request.now
        var exercises: [Exercise] = []
        for imported in workout.exercises {
            let resolution = request.resolutions[imported.name]
                ?? .newCustom(name: imported.name, equipment: ExerciseMatcher.guessedEquipment(for: imported.name))
            let exercise = resolver.exercise(for: imported.name, resolution: resolution)
            report.exerciseIDs[imported.name] = exercise.id
            exercises.append(exercise)
        }
        let names = Dictionary(zip(workout.exercises.map(\.name), exercises.map(\.name)), uniquingKeysWith: { first, _ in first })

        let session = Session(name: workout.name, startedAt: workout.startedAt, source: request.source)
        session.endedAt = workout.endedAt ?? workout.startedAt
        session.externalKey = workout.externalKey
        session.notes = workout.composedNotes { names[$0] ?? $0 }
        session.createdAt = now
        session.updatedAt = now
        // The whole graph is built first and inserted with the session: inserting a model
        // inserts what it relates to, which is much faster than inserting and relating each set.
        var entries: [SessionExercise] = []
        for (order, imported) in workout.exercises.enumerated() {
            let entry = SessionExercise(order: order)
            entry.createdAt = now
            entry.updatedAt = now
            entry.sets = imported.sets.enumerated().map { index, imported in
                let set = SetLog(order: index, weightKg: imported.weightKg, reps: imported.reps, isWarmup: imported.isWarmup)
                set.durationSeconds = imported.durationSeconds
                set.rpe = imported.rpe
                set.note = imported.storedNote
                set.completedAt = workout.startedAt
                set.createdAt = now
                set.updatedAt = now
                return set
            }
            entries.append(entry)
        }
        session.entries = entries
        context.insert(session)
        for (entry, exercise) in zip(entries, exercises) {
            entry.exercise = exercise
        }
        report.inserted += 1
    }
}
