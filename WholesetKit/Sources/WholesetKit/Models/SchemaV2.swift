// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

/// Version 2.0.0 of the persisted schema, as shipped with the iPhone app's planning release.
///
/// Frozen: these classes describe stores written by that release and exist only so
/// ``WholesetMigrationPlan`` can recognise and migrate them. Never change a stored
/// property, default, relationship or delete rule here. App code uses the current
/// schema through the module-level type aliases (``Exercise``, ``Routine`` …).
///
/// Added over version 1, all optional or defaulted (a lightweight step):
/// - `Exercise.libraryKey`: the built-in library entry an exercise is, so the library
///   seed can update it and sync duplicates can be merged even if renamed;
/// - `Routine.seedKey`: the starter template a routine was created from, so starter
///   routines seeded on two devices can be merged;
/// - `AppSettings.weightCrownSensitivityRaw` / `repsCrownSensitivityRaw`: the Watch's
///   Digital Crown speed for each tile;
/// - `AppSettings.starterRoutinesDecidedAt`: when the account first settled whether it
///   has starter routines, so a device never adds them on top of routines from iCloud.
public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            Routine.self,
            RoutineItem.self,
            WeekPlanDay.self,
            Session.self,
            SessionExercise.self,
            SetLog.self,
            AppSettings.self,
        ]
    }
}

extension SchemaV2 {
    /// Version 2 of an exercise.
    @Model
    public final class Exercise {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var name: String = ""
        public var equipmentRaw: String = Equipment.barbell.rawValue
        public var primaryMuscleRaw: String = Muscle.other.rawValue
        public var isCustom: Bool = false
        public var isArchived: Bool = false
        public var progressionStepKg: Double?
        public var defaultRestSeconds: Int?
        public var aliasesText: String = ""
        public var libraryKey: String?

        @Relationship(deleteRule: .nullify, inverse: \Exercise.alternativeOf)
        public var alternatives: [Exercise]? = []
        public var alternativeOf: [Exercise]? = []

        @Relationship(deleteRule: .nullify, inverse: \RoutineItem.exercise)
        public var routineItems: [RoutineItem]? = []

        @Relationship(deleteRule: .nullify, inverse: \SessionExercise.exercise)
        public var sessionEntries: [SessionExercise]? = []

        public init(
            name: String = "",
            equipment: Equipment = .barbell,
            primaryMuscle: Muscle = .other,
            isCustom: Bool = false
        ) {
            self.name = name
            self.equipmentRaw = equipment.rawValue
            self.primaryMuscleRaw = primaryMuscle.rawValue
            self.isCustom = isCustom
        }
    }

    /// Version 2 of a routine.
    @Model
    public final class Routine {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var name: String = ""
        public var notes: String = ""
        public var sortIndex: Int = 0
        public var seedKey: String?

        @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine)
        public var items: [RoutineItem]? = []

        @Relationship(deleteRule: .nullify, inverse: \Session.routine)
        public var sessions: [Session]? = []

        @Relationship(deleteRule: .nullify, inverse: \WeekPlanDay.routine)
        public var weekPlanDays: [WeekPlanDay]? = []

        public init(name: String = "", notes: String = "", sortIndex: Int = 0) {
            self.name = name
            self.notes = notes
            self.sortIndex = sortIndex
        }
    }

    /// Version 2 of a routine item.
    @Model
    public final class RoutineItem {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var routine: Routine?
        public var exercise: Exercise?
        public var order: Int = 0
        public var targetSets: Int = 3
        public var repLow: Int = 8
        public var repHigh: Int = 12
        public var restSeconds: Int?

        public init(order: Int = 0, targetSets: Int = 3, repLow: Int = 8, repHigh: Int = 12, restSeconds: Int? = nil) {
            self.order = order
            self.targetSets = targetSets
            self.repLow = repLow
            self.repHigh = repHigh
            self.restSeconds = restSeconds
        }
    }

    /// Version 2 of a weekly plan day.
    @Model
    public final class WeekPlanDay {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var weekday: Int = 1
        public var routine: Routine?

        public init(weekday: Int = 1) {
            self.weekday = weekday
        }
    }

    /// Version 2 of a session.
    @Model
    public final class Session {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var name: String = ""
        public var routine: Routine?
        public var startedAt: Date = Date.now
        public var endedAt: Date?
        public var notes: String = ""
        public var sourceRaw: String = Source.watch.rawValue
        public var externalKey: String?
        public var healthKitWorkoutID: UUID?
        public var avgHR: Double?
        public var maxHR: Double?
        public var activeKcal: Double?

        @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
        public var entries: [SessionExercise]? = []

        public init(name: String = "", startedAt: Date = .now, source: Source = .watch) {
            self.name = name
            self.startedAt = startedAt
            self.sourceRaw = source.rawValue
        }
    }

    /// Version 2 of a session exercise.
    @Model
    public final class SessionExercise {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var session: Session?
        public var exercise: Exercise?
        public var order: Int = 0
        public var repLow: Int?
        public var repHigh: Int?

        @Relationship(deleteRule: .cascade, inverse: \SetLog.entry)
        public var sets: [SetLog]? = []

        public init(order: Int = 0, repLow: Int? = nil, repHigh: Int? = nil) {
            self.order = order
            self.repLow = repLow
            self.repHigh = repHigh
        }
    }

    /// Version 2 of a set.
    @Model
    public final class SetLog {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var entry: SessionExercise?
        public var order: Int = 0
        public var weightKg: Double?
        public var reps: Int?
        public var durationSeconds: Int?
        public var isWarmup: Bool = false
        public var rpe: Double?
        public var note: String = ""
        public var completedAt: Date?

        public init(order: Int = 0, weightKg: Double? = nil, reps: Int? = nil, isWarmup: Bool = false) {
            self.order = order
            self.weightKg = weightKg
            self.reps = reps
            self.isWarmup = isWarmup
        }
    }

    /// Version 2 of the settings row.
    @Model
    public final class AppSettings {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var unitRaw: String = WeightUnit.kg.rawValue
        public var defaultRestSeconds: Int = 90
        public var weightCrownSensitivityRaw: String = CrownSensitivity.normal.rawValue
        public var repsCrownSensitivityRaw: String = CrownSensitivity.normal.rawValue
        public var starterRoutinesDecidedAt: Date?

        public init(unit: WeightUnit = .kg, defaultRestSeconds: Int = 90) {
            self.unitRaw = unit.rawValue
            self.defaultRestSeconds = defaultRestSeconds
            self.updatedAt = self.createdAt
        }
    }
}
