// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData

/// Version 2.0.0 of the persisted schema: the current one.
///
/// The model classes are declared in extensions of this namespace (one file per model);
/// earlier versions keep frozen copies of theirs (``SchemaV1``) so the migration plan can
/// map between them. Everything added since version 1 is optional or defaulted, so the
/// step from version 1 is a lightweight migration:
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

/// The ordered list of schema versions and the stages that migrate between them.
public enum WholesetMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    public static var stages: [MigrationStage] { [migrateV1toV2] }

    /// Version 2 only adds optional or defaulted attributes, so no custom code is needed.
    static let migrateV1toV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
}

/// The schema version the app currently reads and writes.
public typealias CurrentSchema = SchemaV2

/// An exercise in the library. See ``SchemaV2/Exercise``.
public typealias Exercise = CurrentSchema.Exercise
/// A reusable workout template. See ``SchemaV2/Routine``.
public typealias Routine = CurrentSchema.Routine
/// One exercise slot in a routine. See ``SchemaV2/RoutineItem``.
public typealias RoutineItem = CurrentSchema.RoutineItem
/// One day of the weekly plan. See ``SchemaV2/WeekPlanDay``.
public typealias WeekPlanDay = CurrentSchema.WeekPlanDay
/// A performed (or in-progress) workout. See ``SchemaV2/Session``.
public typealias Session = CurrentSchema.Session
/// One exercise within a session. See ``SchemaV2/SessionExercise``.
public typealias SessionExercise = CurrentSchema.SessionExercise
/// One set within a session exercise. See ``SchemaV2/SetLog``.
public typealias SetLog = CurrentSchema.SetLog
/// The single app-wide settings row. See ``SchemaV2/AppSettings``.
public typealias AppSettings = CurrentSchema.AppSettings
