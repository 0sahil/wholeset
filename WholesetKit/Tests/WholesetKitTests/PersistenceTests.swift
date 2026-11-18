// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

/// Saves models to an on-disk SQLite store and reads them back through a newly
/// opened container.
@Suite("Persistence round trips")
struct PersistenceTests {
    @Test func routineWithItemsRoundTrips() throws {
        try withTemporaryStoreURL { url in
            do {
                let context = try reopen(url)
                let bench = Exercise(name: "Bench Press", equipment: .barbell, primaryMuscle: .chest)
                let fly = Exercise(name: "Cable Fly", equipment: .cable, primaryMuscle: .chest)
                let dip = Exercise(name: "Dip", equipment: .bodyweight, primaryMuscle: .triceps)
                let routine = Routine(name: "Push", notes: "Heavy week", sortIndex: 2)
                context.insert(routine)
                // Inserted out of order on purpose.
                for (exercise, order) in [(dip, 2), (bench, 0), (fly, 1)] {
                    context.insert(exercise)
                    let item = RoutineItem(order: order, targetSets: 4, repLow: 6, repHigh: 10, restSeconds: 120)
                    context.insert(item)
                    item.routine = routine
                    item.exercise = exercise
                }
                try context.save()
            }

            let context = try reopen(url)
            let routine = try #require(try context.all(Routine.self).first)
            #expect(routine.name == "Push")
            #expect(routine.notes == "Heavy week")
            #expect(routine.sortIndex == 2)
            #expect(routine.sortedItems.map { $0.exercise?.name } == ["Bench Press", "Cable Fly", "Dip"])
            #expect(routine.sortedItems.map(\.order) == [0, 1, 2])
            let first = try #require(routine.sortedItems.first)
            #expect(first.targetSets == 4)
            #expect(first.repLow == 6)
            #expect(first.repHigh == 10)
            #expect(first.restSeconds == 120)
            #expect(first.exercise?.equipment == .barbell)
            #expect(first.exercise?.primaryMuscle == .chest)
            #expect(first.exercise?.routineItems?.count == 1)
        }
    }

    @Test func sessionWithEntriesAndSetsRoundTrips() throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let workoutID = UUID()
        try withTemporaryStoreURL { url in
            do {
                let context = try reopen(url)
                let squat = Exercise(name: "Squat", equipment: .barbell, primaryMuscle: .quadriceps)
                let row = Exercise(name: "Row", equipment: .cable, primaryMuscle: .middleBack)
                let session = Session(name: "Legs", startedAt: started, source: .importHevy)
                session.endedAt = started.addingTimeInterval(3_600)
                session.externalKey = "import-key"
                session.healthKitWorkoutID = workoutID
                session.avgHR = 121.5
                session.maxHR = 168
                session.activeKcal = 402.25
                context.insertAll(squat, row, session)

                for (exercise, order) in [(row, 1), (squat, 0)] {
                    let entry = SessionExercise(order: order, repLow: 5, repHigh: 8)
                    context.insert(entry)
                    entry.session = session
                    entry.exercise = exercise
                    for (index, setOrder) in [2, 0, 1].enumerated() {
                        let set = SetLog(order: setOrder, weightKg: 60 + Double(setOrder) * 2.5, reps: 8, isWarmup: setOrder == 0)
                        set.completedAt = started.addingTimeInterval(Double(index) * 120)
                        set.rpe = 8.5
                        set.note = "set \(setOrder)"
                        context.insert(set)
                        set.entry = entry
                    }
                }
                try context.save()
            }

            let context = try reopen(url)
            let session = try #require(try context.all(Session.self).first)
            #expect(session.name == "Legs")
            #expect(session.startedAt == started)
            #expect(session.endedAt == started.addingTimeInterval(3_600))
            #expect(session.source == .importHevy)
            #expect(session.externalKey == "import-key")
            #expect(session.healthKitWorkoutID == workoutID)
            #expect(session.avgHR == 121.5)
            #expect(session.maxHR == 168)
            #expect(session.activeKcal == 402.25)
            #expect(session.routine == nil)

            #expect(session.sortedEntries.map { $0.exercise?.name } == ["Squat", "Row"])
            let squat = try #require(session.sortedEntries.first)
            #expect(squat.repLow == 5)
            #expect(squat.repHigh == 8)
            #expect(squat.sortedSets.map(\.order) == [0, 1, 2])
            #expect(squat.sortedSets.map(\.weightKg) == [60, 62.5, 65])
            #expect(squat.sortedSets.map(\.isWarmup) == [true, false, false])
            #expect(squat.sortedSets.map(\.note) == ["set 0", "set 1", "set 2"])
            #expect(squat.sortedSets.allSatisfy { $0.reps == 8 && $0.rpe == 8.5 && $0.completedAt != nil })
            #expect(try context.count(SetLog.self) == 6)
        }
    }

    @Test func deletingSessionCascadesToEntriesAndSets() throws {
        try withTemporaryStoreURL { url in
            do {
                let context = try reopen(url)
                let exercise = Exercise(name: "Deadlift")
                let session = Session(name: "Pull")
                context.insert(exercise)
                context.insert(session)
                let entry = SessionExercise(order: 0)
                context.insert(entry)
                entry.session = session
                entry.exercise = exercise
                for order in 0..<3 {
                    let set = SetLog(order: order, weightKg: 100, reps: 5)
                    context.insert(set)
                    set.entry = entry
                }
                try context.save()
            }
            do {
                let context = try reopen(url)
                let session = try #require(try context.all(Session.self).first)
                context.delete(session)
                try context.save()
            }

            let context = try reopen(url)
            #expect(try context.count(Session.self) == 0)
            #expect(try context.count(SessionExercise.self) == 0)
            #expect(try context.count(SetLog.self) == 0)
            let exercise = try #require(try context.all(Exercise.self).first)
            #expect(exercise.sessionEntries?.isEmpty == true)
        }
    }

    @Test func deletingRoutineKeepsSessionsAndClearsPlanDays() throws {
        try withTemporaryStoreURL { url in
            do {
                let context = try reopen(url)
                let exercise = Exercise(name: "Overhead Press")
                let routine = Routine(name: "Push")
                let session = Session(name: "Push")
                let monday = WeekPlanDay(weekday: 2)
                context.insertAll(exercise, routine, session, monday)
                let item = RoutineItem(order: 0)
                context.insert(item)
                item.routine = routine
                item.exercise = exercise
                session.routine = routine
                monday.routine = routine
                try context.save()
            }
            do {
                let context = try reopen(url)
                let routine = try #require(try context.all(Routine.self).first)
                #expect(routine.sessions?.count == 1)
                #expect(routine.weekPlanDays?.count == 1)
                context.delete(routine)
                try context.save()
            }

            let context = try reopen(url)
            #expect(try context.count(Routine.self) == 0)
            #expect(try context.count(RoutineItem.self) == 0)
            #expect(try context.count(Exercise.self) == 1)
            let session = try #require(try context.all(Session.self).first)
            #expect(session.routine == nil)
            #expect(session.name == "Push")
            let monday = try #require(try context.all(WeekPlanDay.self).first)
            #expect(monday.weekday == 2)
            #expect(monday.routine == nil)
        }
    }

    @Test func alternativesAreDirectedAndRoundTrip() throws {
        try withTemporaryStoreURL { url in
            do {
                let context = try reopen(url)
                let bench = Exercise(name: "Bench Press")
                let dumbbell = Exercise(name: "Dumbbell Press", equipment: .dumbbell)
                let machine = Exercise(name: "Machine Press", equipment: .machine)
                context.insertAll(bench, dumbbell, machine)
                bench.alternatives = [dumbbell, machine]
                machine.alternatives = [bench]
                try context.save()
            }

            let context = try reopen(url)
            let byName = Dictionary(uniqueKeysWithValues: try context.all(Exercise.self).map { ($0.name, $0) })
            let bench = try #require(byName["Bench Press"])
            let dumbbell = try #require(byName["Dumbbell Press"])
            let machine = try #require(byName["Machine Press"])

            #expect(Set((bench.alternatives ?? []).map(\.name)) == ["Dumbbell Press", "Machine Press"])
            #expect(Set((bench.alternativeOf ?? []).map(\.name)) == ["Machine Press"])
            #expect(dumbbell.alternatives?.isEmpty == true)
            #expect((dumbbell.alternativeOf ?? []).map(\.name) == ["Bench Press"])
            #expect((machine.alternatives ?? []).map(\.name) == ["Bench Press"])

            // Deleting an exercise only removes the links, never the other exercises.
            context.delete(dumbbell)
            try context.save()
            let reloaded = try reopen(url)
            #expect(try reloaded.count(Exercise.self) == 2)
            let reloadedBench = try #require(try reloaded.all(Exercise.self).first { $0.name == "Bench Press" })
            #expect((reloadedBench.alternatives ?? []).map(\.name) == ["Machine Press"])
        }
    }

    @Test func aliasesRoundTripThroughSQLite() throws {
        let aliases = [
            "Bench Press (Barbell)",
            "Press, bench",
            "Développé couché",
            "ベンチプレス",
            "Flat | Bench; \"BB\" 'press'",
        ]
        try withTemporaryStoreURL { url in
            do {
                let context = try reopen(url)
                let exercise = Exercise(name: "Bench Press")
                exercise.aliases = aliases
                context.insert(exercise)
                context.insert(Exercise(name: "Squat"))
                try context.save()
            }

            let context = try reopen(url)
            let bench = try #require(try context.all(Exercise.self).first { $0.name == "Bench Press" })
            #expect(bench.aliases == aliases)

            // The joined text stays searchable in a store-level predicate.
            let descriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.aliasesText.localizedStandardContains("couché") }
            )
            #expect(try context.fetch(descriptor).map(\.name) == ["Bench Press"])
        }
    }

    @Test func unknownEnumValuesReadAsFallbackWithoutRewriting() throws {
        try withTemporaryStoreURL { url in
            do {
                let context = try reopen(url)
                let exercise = Exercise(name: "Sled Push")
                exercise.equipmentRaw = "sled"
                exercise.primaryMuscleRaw = "fullBody"
                let session = Session(name: "Conditioning")
                session.sourceRaw = "importSomethingNew"
                let settings = AppSettings()
                settings.unitRaw = "stone"
                context.insertAll(exercise, session, settings)
                try context.save()
            }

            let context = try reopen(url)
            let exercise = try #require(try context.all(Exercise.self).first)
            #expect(exercise.equipment == .other)
            #expect(exercise.primaryMuscle == .other)
            #expect(exercise.equipmentRaw == "sled")
            let session = try #require(try context.all(Session.self).first)
            #expect(session.source == .watch)
            #expect(session.sourceRaw == "importSomethingNew")
            let settings = try #require(try context.all(AppSettings.self).first)
            #expect(settings.unit == .kg)
            #expect(settings.unitRaw == "stone")
        }
    }
}
