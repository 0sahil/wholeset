// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

/// Stores written by the planning release (schema version 2) must open, with every row,
/// relationship and version 2 value intact, in the current version.
@Suite("Migration from schema version 2")
struct MigrationV2Tests {
    private let t0 = Date(timeIntervalSince1970: 1_795_000_000)

    /// Identifiers of the rows written into the version 2 store.
    private struct Written {
        var bench: UUID
        var row: UUID
        var routine: UUID
        var items: [UUID]
        var finished: UUID
        var running: UUID
        var finishedEntries: [UUID]
        var finishedSets: [UUID]
        var settings: UUID
    }

    /// Writes a version 2 store with library exercises, a starter routine, a plan day, a
    /// finished workout and one still running (as a device could hold when updated mid-workout).
    private func writeVersionTwoStore(at url: URL) throws -> Written {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(WholesetStore.storeName, schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let bench = SchemaV2.Exercise(name: "Bench Press", equipment: .barbell, primaryMuscle: .chest)
        bench.libraryKey = "bench-press"
        bench.progressionStepKg = 1.25
        bench.defaultRestSeconds = 150
        bench.createdAt = t0
        bench.updatedAt = t0
        let row = SchemaV2.Exercise(name: "Barbell Row", equipment: .barbell, primaryMuscle: .middleBack)
        row.libraryKey = "barbell-row"
        context.insert(bench)
        context.insert(row)
        bench.alternatives = [row]

        let routine = SchemaV2.Routine(name: "Push", sortIndex: 0)
        routine.seedKey = "starter.push"
        routine.createdAt = t0
        routine.updatedAt = t0.addingTimeInterval(60)
        context.insert(routine)
        var itemIDs: [UUID] = []
        for (order, exercise) in [bench, row].enumerated() {
            let item = SchemaV2.RoutineItem(order: order, targetSets: 3, repLow: 6, repHigh: 10, restSeconds: 120)
            context.insert(item)
            item.routine = routine
            item.exercise = exercise
            itemIDs.append(item.id)
        }
        let monday = SchemaV2.WeekPlanDay(weekday: 2)
        context.insert(monday)
        monday.routine = routine

        func addSession(startedAt: Date, ended: Bool, logged: Int) -> (SchemaV2.Session, [UUID], [UUID]) {
            let session = SchemaV2.Session(name: "Push", startedAt: startedAt, source: .watch)
            if ended { session.endedAt = startedAt.addingTimeInterval(3_000) }
            context.insert(session)
            session.routine = routine
            var entryIDs: [UUID] = []
            var setIDs: [UUID] = []
            for (order, exercise) in [bench, row].enumerated() {
                let entry = SchemaV2.SessionExercise(order: order, repLow: 6, repHigh: 10)
                context.insert(entry)
                entry.session = session
                entry.exercise = exercise
                entryIDs.append(entry.id)
                for index in 0..<3 {
                    let set = SchemaV2.SetLog(order: index, weightKg: 60, reps: 10 - index, isWarmup: false)
                    if order * 3 + index < logged {
                        set.completedAt = startedAt.addingTimeInterval(Double(60 * (order * 3 + index + 1)))
                    } else {
                        set.weightKg = nil
                        set.reps = nil
                    }
                    context.insert(set)
                    set.entry = entry
                    setIDs.append(set.id)
                }
            }
            return (session, entryIDs, setIDs)
        }
        let (finished, finishedEntries, finishedSets) = addSession(startedAt: t0, ended: true, logged: 6)
        let (running, _, _) = addSession(startedAt: t0.addingTimeInterval(86_400), ended: false, logged: 2)

        let settings = SchemaV2.AppSettings(unit: .lb, defaultRestSeconds: 105)
        settings.weightCrownSensitivityRaw = CrownSensitivity.fast.rawValue
        settings.starterRoutinesDecidedAt = t0
        settings.createdAt = t0
        settings.updatedAt = t0.addingTimeInterval(5)
        context.insert(settings)
        try context.save()

        return Written(
            bench: bench.id, row: row.id, routine: routine.id, items: itemIDs,
            finished: finished.id, running: running.id,
            finishedEntries: finishedEntries, finishedSets: finishedSets, settings: settings.id
        )
    }

    @Test func everyRowAndVersionTwoValueSurvives() throws {
        try withTemporaryStoreURL { url in
            let written = try writeVersionTwoStore(at: url)
            let context = ModelContext(try WholesetStore.makeContainer(url: url))

            let exercises = try context.all(Exercise.self)
            #expect(exercises.count == 2)
            let bench = try #require(exercises.first { $0.id == written.bench })
            #expect(bench.libraryKey == "bench-press")
            #expect(bench.progressionStepKg == 1.25)
            #expect(bench.defaultRestSeconds == 150)
            #expect(bench.createdAt == t0)
            #expect(bench.alternatives?.map(\.id) == [written.row])

            let routine = try #require(try context.all(Routine.self).first)
            #expect(routine.id == written.routine)
            #expect(routine.seedKey == "starter.push")
            #expect(routine.updatedAt == t0.addingTimeInterval(60))
            #expect(routine.sortedItems.map(\.id) == written.items)
            #expect(routine.weekPlanDays?.map(\.weekday) == [2])

            let sessions = try context.all(Session.self)
            #expect(sessions.count == 2)
            let finished = try #require(sessions.first { $0.id == written.finished })
            #expect(finished.sortedEntries.map(\.id) == written.finishedEntries)
            #expect(finished.sortedEntries.flatMap(\.sortedSets).map(\.id) == written.finishedSets)
            #expect(finished.sortedEntries.flatMap(\.sortedSets).map(\.reps) == [10, 9, 8, 10, 9, 8])
            // New in version 3: defaults for everything that existed before.
            #expect(sessions.flatMap { $0.entries ?? [] }.allSatisfy { !$0.isSkipped && $0.routineItemID == nil })
            #expect(try context.count(SetLog.self) == 12)

            let settings = try AppSettings.current(in: context)
            #expect(settings.id == written.settings)
            #expect(settings.unit == .lb)
            #expect(settings.defaultRestSeconds == 105)
            #expect(settings.weightCrownSensitivity == .fast)
            #expect(settings.starterRoutinesDecidedAt == t0)
            #expect(settings.progressionStepsRaw.isEmpty)
            #expect(settings.progressionSteps.isEmpty)
            #expect(settings.wasEdited)
        }
    }

    @Test func migratedStoreAcceptsVersionThreeValues() throws {
        try withTemporaryStoreURL { url in
            let written = try writeVersionTwoStore(at: url)
            do {
                let context = ModelContext(try WholesetStore.makeContainer(url: url))
                let settings = try AppSettings.current(in: context)
                SettingsEditing.setProgressionStep(kilograms: 1, for: .dumbbell, on: settings)
                let entry = try #require(try context.all(Session.self).first { $0.id == written.finished }?.sortedEntries.first)
                entry.isSkipped = true
                entry.routineItemID = written.items[0]
                try context.save()
            }
            let context = try reopen(url)
            #expect(try AppSettings.current(in: context).progressionSteps == [.dumbbell: 1])
            let entry = try #require(try context.all(Session.self).first { $0.id == written.finished }?.sortedEntries.first)
            #expect(entry.isSkipped)
            #expect(entry.routineItemID == written.items[0])
        }
    }

    /// A workout running when the app was updated resumes in the new version: its sets are
    /// there, rest still comes from the routine slot (matched by exercise, as entries from
    /// version 2 record no slot), and no routine update is offered at the end because the
    /// session cannot be compared slot by slot.
    @Test func workoutRunningDuringTheUpdateResumes() throws {
        try withTemporaryStoreURL { url in
            let written = try writeVersionTwoStore(at: url)
            let context = ModelContext(try WholesetStore.makeContainer(url: url))
            let session = try #require(try WorkoutRecovery.resolveInProgressSession(in: context))
            #expect(session.id == written.running)
            let engine = WorkoutEngine(resuming: session, in: context, defaultRestSeconds: 90)
            #expect(engine.currentIndex == 0)
            #expect(engine.currentSetNumber == 3)
            #expect(engine.restDuration(for: engine.entries[1]) == 120)
            // The finished version 2 workout is this workout's history.
            #expect(engine.currentLastLine == .previous(SetValues(weightKg: 60, reps: 8)))
            try engine.setSkipped(true, for: engine.entries[1])
            try engine.logCurrentSet()
            try engine.finish()
            #expect(RoutineUpdate.proposal(for: session) == nil)
        }
    }
}
