// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData

/// Version 3.0.0 of the persisted schema: the current one.
///
/// The model classes are declared in extensions of this namespace (one file per model);
/// earlier versions keep frozen copies of theirs (``SchemaV1``, ``SchemaV2``) so the
/// migration plan can map between them. Everything added since version 2 is optional or
/// defaulted, so the step from version 2 is a lightweight migration:
/// - `AppSettings.progressionStepsRaw`: the user's default progression step per equipment;
/// - `SessionExercise.isSkipped`: the exercise was skipped for that session;
/// - `SessionExercise.routineItemID`: the routine slot an entry came from, so swaps and
///   added exercises can be told apart when comparing a session with its routine.
public enum SchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

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
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self] }

    public static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3] }

    /// Version 2 only adds optional or defaulted attributes, so no custom code is needed.
    static let migrateV1toV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)

    /// Version 3 only adds optional or defaulted attributes, so no custom code is needed.
    static let migrateV2toV3 = MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
}

/// The schema version the app currently reads and writes.
public typealias CurrentSchema = SchemaV3

/// An exercise in the library. See ``SchemaV3/Exercise``.
public typealias Exercise = CurrentSchema.Exercise
/// A reusable workout template. See ``SchemaV3/Routine``.
public typealias Routine = CurrentSchema.Routine
/// One exercise slot in a routine. See ``SchemaV3/RoutineItem``.
public typealias RoutineItem = CurrentSchema.RoutineItem
/// One day of the weekly plan. See ``SchemaV3/WeekPlanDay``.
public typealias WeekPlanDay = CurrentSchema.WeekPlanDay
/// A performed (or in-progress) workout. See ``SchemaV3/Session``.
public typealias Session = CurrentSchema.Session
/// One exercise within a session. See ``SchemaV3/SessionExercise``.
public typealias SessionExercise = CurrentSchema.SessionExercise
/// One set within a session exercise. See ``SchemaV3/SetLog``.
public typealias SetLog = CurrentSchema.SetLog
/// The single app-wide settings row. See ``SchemaV3/AppSettings``.
public typealias AppSettings = CurrentSchema.AppSettings
