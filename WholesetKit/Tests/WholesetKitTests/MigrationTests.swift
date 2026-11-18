// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

/// Stores written by the first Watch release (schema version 1) must open, with every row
/// and relationship intact, in the current version.
@Suite("Migration from schema version 1")
struct MigrationTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// Identifiers of the rows written into the version 1 store.
    private struct Written {
        var bench: UUID
        var row: UUID
        var custom: UUID
        var routine: UUID
        var items: [UUID]
        var monday: UUID
        var sunday: UUID
        var session: UUID
        var entries: [UUID]
        var sets: [UUID]
        var settings: UUID
    }

    /// Writes a version 1 store with one of everything, then closes it.
    private func writeVersionOneStore(at url: URL) throws -> Written {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(WholesetStore.storeName, schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let bench = SchemaV1.Exercise(name: "Bench Press", equipment: .barbell, primaryMuscle: .chest)
        bench.createdAt = t0
        bench.updatedAt = t0
        bench.defaultRestSeconds = 150
        bench.progressionStepKg = 2.5
        bench.aliasesText = "Bench Press (Barbell)"
        let row = SchemaV1.Exercise(name: "Barbell Row", equipment: .barbell, primaryMuscle: .middleBack)
        let custom = SchemaV1.Exercise(name: "Landmine Press", equipment: .other, primaryMuscle: .shoulders, isCustom: true)
        custom.isArchived = true
        context.insert(bench)
        context.insert(row)
        context.insert(custom)
        bench.alternatives = [custom]

        let routine = SchemaV1.Routine(name: "Upper", notes: "Pause on the chest.", sortIndex: 4)
        routine.createdAt = t0
        context.insert(routine)
        var itemIDs: [UUID] = []
        for (order, exercise) in [bench, row].enumerated() {
            let item = SchemaV1.RoutineItem(order: order, targetSets: 4, repLow: 6, repHigh: 10, restSeconds: order == 0 ? 180 : nil)
            context.insert(item)
            item.routine = routine
            item.exercise = exercise
            itemIDs.append(item.id)
        }

        let monday = SchemaV1.WeekPlanDay(weekday: 2)
        let sunday = SchemaV1.WeekPlanDay(weekday: 1)
        context.insert(monday)
        context.insert(sunday)
        monday.routine = routine

        let session = SchemaV1.Session(name: "Upper", startedAt: t0, source: .watch)
        session.endedAt = t0.addingTimeInterval(3_600)
        session.healthKitWorkoutID = UUID()
        session.avgHR = 121
        session.maxHR = 160
        session.activeKcal = 380
        context.insert(session)
        session.routine = routine
        var entryIDs: [UUID] = []
        var setIDs: [UUID] = []
        for (order, exercise) in [bench, row].enumerated() {
            let entry = SchemaV1.SessionExercise(order: order, repLow: 6, repHigh: 10)
            context.insert(entry)
            entry.session = session
            entry.exercise = exercise
            entryIDs.append(entry.id)
            for index in 0..<2 {
                let set = SchemaV1.SetLog(order: index, weightKg: 60 + Double(index) * 2.5, reps: 8 - index, isWarmup: index == 0 && order == 0)
                set.completedAt = t0.addingTimeInterval(Double(60 * (order * 2 + index)))
                context.insert(set)
                set.entry = entry
                setIDs.append(set.id)
            }
        }

        let settings = SchemaV1.AppSettings(unit: .lb, defaultRestSeconds: 120)
        settings.createdAt = t0
        settings.updatedAt = t0.addingTimeInterval(10)
        context.insert(settings)
        try context.save()

        return Written(
            bench: bench.id, row: row.id, custom: custom.id, routine: routine.id, items: itemIDs,
            monday: monday.id, sunday: sunday.id, session: session.id, entries: entryIDs, sets: setIDs,
            settings: settings.id
        )
    }

    @Test func everyRowAndRelationshipSurvives() throws {
        try withTemporaryStoreURL { url in
            let written = try writeVersionOneStore(at: url)
            let context = ModelContext(try WholesetStore.makeContainer(url: url))

            let exercises = try context.all(Exercise.self)
            #expect(exercises.count == 3)
            let bench = try #require(exercises.first { $0.id == written.bench })
            #expect(bench.name == "Bench Press")
            #expect(bench.equipment == .barbell)
            #expect(bench.primaryMuscle == .chest)
            #expect(bench.defaultRestSeconds == 150)
            #expect(bench.progressionStepKg == 2.5)
            #expect(bench.aliases == ["Bench Press (Barbell)"])
            #expect(bench.createdAt == t0)
            #expect(bench.libraryKey == nil)
            #expect(bench.alternatives?.map(\.id) == [written.custom])
            let custom = try #require(exercises.first { $0.id == written.custom })
            #expect(custom.isCustom && custom.isArchived)
            #expect(custom.alternativeOf?.map(\.id) == [written.bench])

            let routine = try #require(try context.all(Routine.self).first)
            #expect(routine.id == written.routine)
            #expect(routine.name == "Upper")
            #expect(routine.notes == "Pause on the chest.")
            #expect(routine.sortIndex == 4)
            #expect(routine.seedKey == nil)
            #expect(routine.sortedItems.map(\.id) == written.items)
            #expect(routine.sortedItems.map { $0.exercise?.id } == [written.bench, written.row])
            #expect(routine.sortedItems.map(\.targetSets) == [4, 4])
            #expect(routine.sortedItems.map(\.restSeconds) == [180, nil])

            let days = try context.all(WeekPlanDay.self)
            #expect(days.count == 2)
            #expect(days.first { $0.id == written.monday }?.routine?.id == written.routine)
            #expect(days.first { $0.id == written.sunday }?.routine == nil)
            #expect(Set(routine.weekPlanDays?.map(\.id) ?? []) == [written.monday])

            let session = try #require(try context.all(Session.self).first)
            #expect(session.id == written.session)
            #expect(session.routine?.id == written.routine)
            #expect(session.startedAt == t0)
            #expect(session.endedAt == t0.addingTimeInterval(3_600))
            #expect(session.source == .watch)
            #expect(session.healthKitWorkoutID != nil)
            #expect(session.avgHR == 121 && session.maxHR == 160 && session.activeKcal == 380)
            #expect(session.sortedEntries.map(\.id) == written.entries)
            #expect(session.sortedEntries.map { $0.exercise?.id } == [written.bench, written.row])
            let sets = session.sortedEntries.flatMap(\.sortedSets)
            #expect(sets.map(\.id) == written.sets)
            #expect(sets.map(\.weightKg) == [60, 62.5, 60, 62.5])
            #expect(sets.map(\.reps) == [8, 7, 8, 7])
            #expect(sets.map(\.isWarmup) == [true, false, false, false])
            #expect(sets.allSatisfy { $0.completedAt != nil })
            #expect(try context.count(SetLog.self) == 4)

            let settings = try AppSettings.current(in: context)
            #expect(settings.id == written.settings)
            #expect(settings.unit == .lb)
            #expect(settings.defaultRestSeconds == 120)
            #expect(settings.weightCrownSensitivity == .normal)
            #expect(settings.repsCrownSensitivity == .normal)
            #expect(settings.starterRoutinesDecidedAt == nil)
            #expect(settings.wasEdited)
        }
    }

    @Test func migratedStoreStillOpensAndAcceptsVersionTwoValues() throws {
        try withTemporaryStoreURL { url in
            _ = try writeVersionOneStore(at: url)
            do {
                let context = ModelContext(try WholesetStore.makeContainer(url: url))
                let settings = try AppSettings.current(in: context)
                SettingsEditing.setWeightCrownSensitivity(.slow, on: settings)
                try #require(try context.all(Routine.self).first).seedKey = "custom"
                try context.save()
            }
            let context = try reopen(url)
            #expect(try AppSettings.current(in: context).weightCrownSensitivity == .slow)
            #expect(try context.all(Routine.self).first?.seedKey == "custom")
        }
    }

    /// The real devices hold what the first Watch release seeded (push/pull/legs without
    /// seed keys) plus logged workouts. After migration and the launch maintenance pass, the
    /// routines are recognised as starters, no starter is added again and no library
    /// exercise is duplicated.
    @Test func firstReleaseStarterDataIsAdoptedNotDuplicated() throws {
        try withTemporaryStoreURL { url in
            let schema = Schema(versionedSchema: SchemaV1.self)
            let configuration = ModelConfiguration(WholesetStore.storeName, schema: schema, url: url, cloudKitDatabase: .none)
            var benchID: UUID?
            do {
                let container = try ModelContainer(for: schema, configurations: [configuration])
                let context = ModelContext(container)
                var exercises: [String: SchemaV1.Exercise] = [:]
                for (index, template) in StarterRoutines.templates.enumerated() {
                    let routine = SchemaV1.Routine(name: template.name, sortIndex: index)
                    routine.createdAt = t0
                    routine.updatedAt = t0
                    context.insert(routine)
                    for (order, spec) in template.items.enumerated() {
                        let exercise = exercises[spec.exerciseName] ?? {
                            let created = SchemaV1.Exercise(name: spec.exerciseName, equipment: spec.equipment, primaryMuscle: spec.muscle)
                            context.insert(created)
                            exercises[spec.exerciseName] = created
                            return created
                        }()
                        let item = SchemaV1.RoutineItem(order: order, targetSets: spec.sets, repLow: spec.repLow, repHigh: spec.repHigh, restSeconds: spec.restSeconds)
                        context.insert(item)
                        item.routine = routine
                        item.exercise = exercise
                    }
                }
                let bench = try #require(exercises["Bench Press"])
                benchID = bench.id
                let session = SchemaV1.Session(name: "Push", startedAt: t0.addingTimeInterval(86_400))
                session.endedAt = session.startedAt.addingTimeInterval(3_000)
                context.insert(session)
                let entry = SchemaV1.SessionExercise(order: 0, repLow: 6, repHigh: 10)
                context.insert(entry)
                entry.session = session
                entry.exercise = bench
                try context.save()
            }

            let context = ModelContext(try WholesetStore.makeContainer(url: url))
            let library = try ExerciseLibrary.bundled()
            let report = try StoreMaintenance.run(in: context, library: library, seedStarterRoutines: true)

            #expect(report.legacyStartersAdopted == 3)
            #expect(report.libraryAdopted == 15)
            #expect(!report.startersSeeded)
            let routines = TodayPlanResolver.sortedRoutines(try context.all(Routine.self))
            #expect(routines.map(\.name) == ["Push", "Pull", "Legs"])
            #expect(routines.map(\.seedKey) == ["starter.push", "starter.pull", "starter.legs"])
            #expect(try AppSettings.current(in: context).starterRoutinesDecidedAt == t0)
            #expect(try context.count(Exercise.self) == library.entries.count)
            let entry = try #require(try context.all(SessionExercise.self).first)
            #expect(entry.exercise?.id == benchID)
            #expect(entry.exercise?.libraryKey == library.entry(named: "Bench Press")?.key)
        }
    }
}
