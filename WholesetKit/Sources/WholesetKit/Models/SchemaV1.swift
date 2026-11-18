// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData

/// Version 1.0.0 of the persisted schema.
///
/// The model classes are declared in extensions of this namespace so that a future `SchemaV2` can declare changed copies side by side
/// and a migration stage can map between them. Once a schema version has shipped
/// with the production CloudKit schema, its models must only change additively.
///
/// CloudKit rules every model follows:
/// - no unique attributes (uniqueness is enforced in code);
/// - every relationship optional, with an explicit inverse, never `.deny`;
/// - every attribute optional or defaulted;
/// - enums stored as raw `String` values with a typed computed accessor.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

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
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

/// The schema version the app currently reads and writes.
public typealias CurrentSchema = SchemaV1

/// An exercise in the library. See ``SchemaV1/Exercise``.
public typealias Exercise = CurrentSchema.Exercise
/// A reusable workout template. See ``SchemaV1/Routine``.
public typealias Routine = CurrentSchema.Routine
/// One exercise slot in a routine. See ``SchemaV1/RoutineItem``.
public typealias RoutineItem = CurrentSchema.RoutineItem
/// One day of the weekly plan. See ``SchemaV1/WeekPlanDay``.
public typealias WeekPlanDay = CurrentSchema.WeekPlanDay
/// A performed (or in-progress) workout. See ``SchemaV1/Session``.
public typealias Session = CurrentSchema.Session
/// One exercise within a session. See ``SchemaV1/SessionExercise``.
public typealias SessionExercise = CurrentSchema.SessionExercise
/// One set within a session exercise. See ``SchemaV1/SetLog``.
public typealias SetLog = CurrentSchema.SetLog
/// The single app-wide settings row. See ``SchemaV1/AppSettings``.
public typealias AppSettings = CurrentSchema.AppSettings
