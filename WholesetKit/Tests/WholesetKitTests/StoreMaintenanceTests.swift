// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

/// The launch/post-sync pass. Two devices are simulated by inserting both devices' rows
/// into one container, as CloudKit leaves them once both have synced.
@Suite("Store maintenance: library seed and sync dedupe")
struct StoreMaintenanceTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let library: ExerciseLibrary

    init() throws {
        library = try ExerciseLibrary.bundled()
    }

    // MARK: Helpers

    @discardableResult
    private func run(_ context: ModelContext, seed: Bool = false, at date: Date? = nil) throws -> MaintenanceReport {
        try StoreMaintenance.run(in: context, library: library, seedStarterRoutines: seed, now: date ?? t0)
    }

    /// Deletes this device's settings row, so a test can insert each device's own.
    private func removeSettings(_ context: ModelContext) throws {
        for settings in try context.all(AppSettings.self) {
            context.delete(settings)
        }
        try context.save()
    }

    /// One device's settings row, as it syncs to the other.
    @discardableResult
    private func insertSettings(
        in context: ModelContext,
        created: Date,
        edited: Date? = nil,
        unit: WeightUnit = .kg,
        decidedAt: Date?
    ) -> AppSettings {
        let settings = AppSettings(unit: unit)
        settings.createdAt = created
        settings.updatedAt = edited ?? created
        settings.starterRoutinesDecidedAt = decidedAt
        context.insert(settings)
        return settings
    }

    /// One device's automatic starter seed: routines with seed keys created at `date`,
    /// using that device's own copies of the library exercises when `exercises` is given.
    @discardableResult
    private func insertStarterRun(
        at date: Date,
        in context: ModelContext,
        exercises: [String: Exercise] = [:],
        skipping skipped: Set<String> = []
    ) throws -> [String: Routine] {
        var byName = exercises
        if byName.isEmpty {
            for exercise in try context.all(Exercise.self) {
                byName[exercise.name] = exercise
            }
        }
        var routines: [String: Routine] = [:]
        for (index, template) in StarterRoutines.templates.enumerated() where !skipped.contains(template.name) {
            let routine = Routine(name: template.name, sortIndex: index)
            routine.createdAt = date
            routine.updatedAt = date
            routine.seedKey = template.key
            context.insert(routine)
            for (order, spec) in template.items.enumerated() {
                let exercise = try #require(byName[spec.exerciseName])
                let item = RoutineItem(order: order, targetSets: spec.sets, repLow: spec.repLow, repHigh: spec.repHigh, restSeconds: spec.restSeconds)
                item.createdAt = date
                item.updatedAt = date
                context.insert(item)
                item.routine = routine
                item.exercise = exercise
            }
            routines[template.name] = routine
        }
        return routines
    }

    private func routineNames(_ context: ModelContext) throws -> [String] {
        TodayPlanResolver.sortedRoutines(try context.all(Routine.self)).map(\.name)
    }

    // MARK: Library seed

    @Test func insertsEveryLibraryExerciseOnce() throws {
        let context = try makeInMemoryContext()
        let first = try run(context)
        #expect(first.libraryInserted == library.entries.count)
        #expect(try context.count(Exercise.self) == library.entries.count)
        #expect(try context.all(Exercise.self).allSatisfy { $0.libraryKey != nil && !$0.isCustom })

        let second = try run(context)
        #expect(second == MaintenanceReport())
        #expect(try context.count(Exercise.self) == library.entries.count)
        #expect(!context.hasChanges)
    }

    @Test func theLibraryWaitsWhileTheDeviceWaitsForICloud() throws {
        let context = try makeInMemoryContext()
        let report = try StoreMaintenance.run(in: context, library: library, seedLibrary: false, seedStarterRoutines: false, now: t0)
        #expect(report.libraryInserted == 0)
        #expect(try context.count(Exercise.self) == 0)

        // Duplicates that arrived meanwhile are still merged.
        let key = try #require(library.entry(named: "Squat")).key
        for offset in [0.0, 30] {
            let copy = Exercise(name: "Squat")
            copy.libraryKey = key
            copy.createdAt = t0.addingTimeInterval(offset)
            context.insert(copy)
        }
        try context.save()
        let merged = try StoreMaintenance.run(in: context, library: library, seedLibrary: false, seedStarterRoutines: false, now: t0)
        #expect(merged.exercisesMerged == 1)
        #expect(try context.count(Exercise.self) == 1)
    }

    @Test func adoptsAnExistingExerciseWithTheSameNameInsteadOfDuplicating() throws {
        let context = try makeInMemoryContext()
        let mine = Exercise(name: "  bench PRESS", equipment: .machine, primaryMuscle: .chest, isCustom: true)
        mine.aliases = ["My Bench"]
        let older = Exercise(name: "Squat", equipment: .barbell, primaryMuscle: .quadriceps)
        context.insertAll(mine, older)
        try context.save()

        let report = try run(context)

        #expect(report.libraryAdopted == 2)
        #expect(try context.count(Exercise.self) == library.entries.count)
        let key = try #require(library.entry(named: "Bench Press")).key
        #expect(mine.libraryKey == key)
        #expect(!mine.isCustom)
        #expect(mine.equipment == .machine)
        #expect(mine.aliases.first == "My Bench")
        #expect(mine.aliases.contains("Bench Press (Barbell)"))
        #expect(older.libraryKey == library.entry(named: "Squat")?.key)
    }

    @Test func prefersAnActiveExerciseWhenAdopting() throws {
        let context = try makeInMemoryContext()
        let archived = Exercise(name: "Leg Press")
        archived.isArchived = true
        archived.createdAt = t0.addingTimeInterval(-100)
        let active = Exercise(name: "leg press")
        context.insertAll(archived, active)
        try context.save()

        try run(context)

        #expect(active.libraryKey != nil)
        #expect(archived.libraryKey == nil)
    }

    @Test func addsNewLibraryAliasesWithoutCountingAsAnEdit() throws {
        let context = try makeInMemoryContext()
        let entry = try #require(library.entry(named: "Deadlift"))
        let deadlift = Exercise(name: "Deadlift")
        deadlift.libraryKey = entry.key
        deadlift.aliases = ["Pulls"]
        deadlift.createdAt = t0
        deadlift.updatedAt = t0
        context.insert(deadlift)
        try context.save()

        let report = try run(context, at: t0.addingTimeInterval(500))

        #expect(report.libraryUpdated == 1)
        #expect(deadlift.aliases == ["Pulls"] + entry.aliases)
        #expect(deadlift.updatedAt == t0)
    }

    // MARK: Exercise duplicates

    @Test func duplicateLibraryExercisesMergeIntoTheOldestAndKeepEveryReference() throws {
        let context = try makeInMemoryContext()
        try run(context)
        let key = try #require(library.entry(named: "Bench Press")).key
        let survivor = try #require(try context.all(Exercise.self).first { $0.libraryKey == key })

        // The other device's copy, with things that point at it.
        let copy = Exercise(name: "Bench Press", equipment: .barbell, primaryMuscle: .chest)
        copy.libraryKey = key
        copy.createdAt = t0.addingTimeInterval(30)
        copy.updatedAt = t0.addingTimeInterval(30)
        context.insert(copy)
        let dumbbell = try #require(try context.all(Exercise.self).first { $0.name == "Dumbbell Bench Press" })
        let pushUp = try #require(try context.all(Exercise.self).first { $0.name == "Push-up" })
        copy.alternatives = [dumbbell]
        pushUp.alternatives = [copy]
        let routine = Routine(name: "Mine")
        context.insert(routine)
        let item = RoutineItem()
        context.insert(item)
        item.routine = routine
        item.exercise = copy
        let session = Session(name: "Mine")
        context.insert(session)
        let entry = SessionExercise()
        context.insert(entry)
        entry.session = session
        entry.exercise = copy
        try context.save()

        let report = try run(context)

        #expect(report.exercisesMerged == 1)
        #expect(try context.all(Exercise.self).filter { $0.libraryKey == key }.map(\.id) == [survivor.id])
        #expect(item.exercise === survivor)
        #expect(entry.exercise === survivor)
        #expect(survivor.alternatives?.contains { $0 === dumbbell } == true)
        #expect(pushUp.alternatives?.map(\.id) == [survivor.id])
        #expect(try context.count(Exercise.self) == library.entries.count)
    }

    @Test func mergedExerciseKeepsTheMostRecentEdits() throws {
        let context = try makeInMemoryContext()
        try run(context)
        let key = try #require(library.entry(named: "Lat Pulldown")).key
        let survivor = try #require(try context.all(Exercise.self).first { $0.libraryKey == key })
        let edited = Exercise(name: "Lat Pulldown", equipment: .machine, primaryMuscle: .lats)
        edited.libraryKey = key
        edited.createdAt = t0.addingTimeInterval(10)
        edited.updatedAt = t0.addingTimeInterval(900)
        edited.defaultRestSeconds = 75
        edited.isArchived = true
        context.insert(edited)
        try context.save()

        try run(context)

        #expect(survivor.equipment == .machine)
        #expect(survivor.defaultRestSeconds == 75)
        #expect(survivor.isArchived)
        #expect(survivor.updatedAt == t0.addingTimeInterval(900))
    }

    // MARK: Settings and plan

    @Test func settingsDuplicatesKeepTheEarliestStarterDecision() throws {
        let context = try makeInMemoryContext()
        insertSettings(in: context, created: t0, edited: t0.addingTimeInterval(5), unit: .lb, decidedAt: t0.addingTimeInterval(60))
        insertSettings(in: context, created: t0.addingTimeInterval(100), decidedAt: t0.addingTimeInterval(20))
        insertSettings(in: context, created: t0.addingTimeInterval(200), decidedAt: nil)
        try context.save()

        try run(context)

        let rows = try context.all(AppSettings.self)
        #expect(rows.count == 1)
        #expect(rows.first?.unit == .lb)
        #expect(rows.first?.starterRoutinesDecidedAt == t0.addingTimeInterval(20))
    }

    @Test func keepsOnePlanDayPerWeekdayTheNewest() throws {
        let context = try makeInMemoryContext()
        let push = Routine(name: "Push")
        let pull = Routine(name: "Pull")
        context.insertAll(push, pull)
        let older = WeekPlanDay(weekday: 2)
        older.updatedAt = t0
        let newer = WeekPlanDay(weekday: 2)
        newer.updatedAt = t0.addingTimeInterval(60)
        let other = WeekPlanDay(weekday: 4)
        context.insertAll(older, newer, other)
        older.routine = push
        newer.routine = pull
        try context.save()

        let report = try run(context)

        #expect(report.planDaysRemoved == 1)
        let days = try context.all(WeekPlanDay.self)
        #expect(days.count == 2)
        #expect(WeekPlan.routine(on: 2, planDays: days) === pull)
    }

    // MARK: (a) A new user with only a Watch

    @Test func newWatchOnlyUserGetsTheStarterRoutinesOnce() throws {
        let context = try makeInMemoryContext()
        let report = try run(context, seed: true)
        #expect(report.startersSeeded)
        #expect(try routineNames(context) == ["Push", "Pull", "Legs"])
        #expect(try AppSettings.current(in: context).starterRoutinesDecidedAt == t0)
        #expect(try context.count(Exercise.self) == library.entries.count)

        let again = try run(context, seed: true, at: t0.addingTimeInterval(3_600))
        #expect(!again.startersSeeded)
        #expect(again.routinesMerged == 0 && again.routinesRemoved == 0)
        #expect(try context.count(Routine.self) == 3)
    }

    @Test func nothingIsSeededWithoutPermission() throws {
        let context = try makeInMemoryContext()
        try run(context, seed: false)
        #expect(try context.count(Routine.self) == 0)
        #expect(try AppSettings.current(in: context).starterRoutinesDecidedAt == nil)
    }

    // MARK: (b) Routines built on the iPhone first

    @Test func routinesFromTheIPhoneStopTheWatchFromSeeding() throws {
        let context = try makeInMemoryContext()
        try run(context)
        try RoutineEditing.createRoutine(named: "My Split", in: context, now: t0)
        try context.save()

        let report = try run(context, seed: true, at: t0.addingTimeInterval(3_600))

        #expect(!report.startersSeeded)
        #expect(try routineNames(context) == ["My Split"])
    }

    @Test func anOfflineWatchSeedIsRemovedOnceTheEarlierIPhoneDecisionArrives() throws {
        let context = try makeInMemoryContext()
        try run(context)
        try removeSettings(context)
        // iPhone: units chosen, then a routine of the user's own.
        insertSettings(in: context, created: t0.addingTimeInterval(-60), edited: t0.addingTimeInterval(-30), unit: .lb, decidedAt: t0)
        let mine = Routine(name: "My Split", sortIndex: 0)
        mine.createdAt = t0
        mine.updatedAt = t0
        context.insert(mine)
        // Watch, an hour later and offline: its own settings row and an automatic seed.
        let watchSeed = t0.addingTimeInterval(3_600)
        insertSettings(in: context, created: watchSeed, decidedAt: watchSeed)
        try insertStarterRun(at: watchSeed, in: context)
        try context.save()

        let report = try run(context, seed: true, at: watchSeed.addingTimeInterval(60))

        #expect(report.routinesRemoved == 3)
        #expect(try routineNames(context) == ["My Split"])
        let settings = try AppSettings.current(in: context)
        #expect(settings.unit == .lb)
        #expect(settings.starterRoutinesDecidedAt == t0)
        #expect(try context.count(RoutineItem.self) == 0)
    }

    @Test func aLateStarterThatWasUsedIsKept() throws {
        let context = try makeInMemoryContext()
        try run(context)
        try removeSettings(context)
        insertSettings(in: context, created: t0, decidedAt: t0)
        let mine = Routine(name: "My Split")
        mine.createdAt = t0
        context.insert(mine)
        let watchSeed = t0.addingTimeInterval(3_600)
        let late = try insertStarterRun(at: watchSeed, in: context)
        let session = Session(name: "Push", startedAt: watchSeed.addingTimeInterval(600))
        context.insert(session)
        let latePush = try #require(late["Push"])
        session.routine = latePush
        try context.save()

        let report = try run(context, at: watchSeed.addingTimeInterval(7_200))

        #expect(report.routinesRemoved == 2)
        #expect(Set(try routineNames(context)) == ["My Split", "Push"])
        #expect(session.routine?.name == "Push")
    }

    // MARK: (c) Both devices seeded before they synced

    @Test func startersSeededOnBothDevicesEndUpOnce() throws {
        let context = try makeInMemoryContext()
        try run(context)
        try removeSettings(context)
        let phoneSeed = t0
        let watchSeed = t0.addingTimeInterval(45)
        insertSettings(in: context, created: phoneSeed, decidedAt: phoneSeed)
        insertSettings(in: context, created: watchSeed, decidedAt: watchSeed)
        let first = try insertStarterRun(at: phoneSeed, in: context)
        let second = try insertStarterRun(at: watchSeed, in: context)
        // The Watch already logged a workout from its copy, and the plan uses it.
        let session = Session(name: "Pull")
        context.insert(session)
        let latePull = try #require(second["Pull"])
        session.routine = latePull
        let tuesday = WeekPlanDay(weekday: 3)
        context.insert(tuesday)
        let lateLegs = try #require(second["Legs"])
        tuesday.routine = lateLegs
        try context.save()

        let report = try run(context, seed: true, at: watchSeed.addingTimeInterval(60))

        #expect(report.routinesMerged == 3)
        #expect(!report.startersSeeded)
        let routines = try context.all(Routine.self)
        #expect(Set(routines.map(\.id)) == Set(first.values.map(\.id)))
        #expect(session.routine === first["Pull"])
        #expect(tuesday.routine === first["Legs"])
        #expect(try context.count(RoutineItem.self) == 15)
    }

    @Test func simultaneousSeedsWithinASecondStillMerge() throws {
        let context = try makeInMemoryContext()
        try run(context)
        try removeSettings(context)
        insertSettings(in: context, created: t0, decidedAt: t0)
        insertSettings(in: context, created: t0.addingTimeInterval(0.4), decidedAt: t0.addingTimeInterval(0.4))
        try insertStarterRun(at: t0, in: context)
        try insertStarterRun(at: t0.addingTimeInterval(0.4), in: context)
        try context.save()

        try run(context)

        #expect(try routineNames(context) == ["Push", "Pull", "Legs"])
    }

    @Test func libraryCopiesFromBothDevicesMergeUnderTheirRoutines() throws {
        let context = try makeInMemoryContext()
        try run(context)
        // The other device inserted its own copy of the library and seeded with it.
        var otherCopies: [String: Exercise] = [:]
        for entry in library.entries {
            let copy = Exercise(name: entry.name, equipment: entry.equipment, primaryMuscle: entry.muscle)
            copy.libraryKey = entry.key
            copy.createdAt = t0.addingTimeInterval(120)
            copy.updatedAt = copy.createdAt
            context.insert(copy)
            otherCopies[entry.name] = copy
        }
        try removeSettings(context)
        insertSettings(in: context, created: t0.addingTimeInterval(120), decidedAt: t0.addingTimeInterval(120))
        try insertStarterRun(at: t0.addingTimeInterval(120), in: context, exercises: otherCopies)
        try context.save()

        let report = try run(context, seed: true)

        #expect(report.exercisesMerged == library.entries.count)
        #expect(try context.count(Exercise.self) == library.entries.count)
        let items = try context.all(RoutineItem.self)
        #expect(items.count == 15)
        #expect(items.allSatisfy { $0.exercise != nil && $0.exercise?.createdAt == t0 })
    }

    @Test func starterCopiesEditedOnBothDevicesAreBothKept() throws {
        let context = try makeInMemoryContext()
        try run(context)
        try removeSettings(context)
        insertSettings(in: context, created: t0, decidedAt: t0)
        let first = try insertStarterRun(at: t0, in: context)
        let second = try insertStarterRun(at: t0.addingTimeInterval(60), in: context)
        RoutineEditing.rename(try #require(first["Push"]), to: "Push A", now: t0.addingTimeInterval(300))
        RoutineEditing.rename(try #require(second["Push"]), to: "Push B", now: t0.addingTimeInterval(300))
        try context.save()

        let report = try run(context)

        #expect(report.routinesMerged == 2)
        #expect(Set(try routineNames(context)) == ["Push A", "Push B", "Pull", "Legs"])
    }

    // MARK: (d) Deleting a starter routine

    @Test func aDeletedStarterRoutineDoesNotComeBack() throws {
        let context = try makeInMemoryContext()
        try run(context, seed: true)
        let legs = try #require(try context.all(Routine.self).first { $0.name == "Legs" })
        RoutineEditing.delete(legs, in: context, now: t0.addingTimeInterval(60))
        try context.save()

        try run(context, seed: true, at: t0.addingTimeInterval(3_600))

        #expect(try routineNames(context) == ["Push", "Pull"])
    }

    @Test func aLateSeedOnAnotherDeviceDoesNotBringADeletedStarterBack() throws {
        let context = try makeInMemoryContext()
        try run(context)
        try removeSettings(context)
        insertSettings(in: context, created: t0, decidedAt: t0)
        try insertStarterRun(at: t0, in: context, skipping: ["Legs"])
        // A reinstalled Watch that gave up waiting for iCloud seeded again.
        let reinstall = t0.addingTimeInterval(86_400)
        insertSettings(in: context, created: reinstall, decidedAt: reinstall)
        try insertStarterRun(at: reinstall, in: context)
        try context.save()

        let report = try run(context, seed: true, at: reinstall.addingTimeInterval(60))

        #expect(report.routinesMerged == 2)
        #expect(report.routinesRemoved == 1)
        #expect(try routineNames(context) == ["Push", "Pull"])
    }

    // MARK: (e) The iPhone's own choice

    @Test func theIPhoneAddsStartersOnlyWhenAsked() throws {
        let context = try makeInMemoryContext()
        try run(context, seed: false)
        #expect(try context.count(Routine.self) == 0)

        try StarterRoutines.seed(in: context, library: library, now: t0)
        try run(context, seed: false)

        let routines = try context.all(Routine.self)
        #expect(routines.count == 3)
        #expect(routines.allSatisfy { $0.seedKey != nil })
    }

    @Test func startersAddedAfterTheDecisionAreOrdinaryRoutinesThatStay() throws {
        let context = try makeInMemoryContext()
        try run(context)
        try RoutineEditing.createRoutine(named: "Mine", in: context, now: t0)
        try context.save()

        let added = try StarterRoutines.seed(in: context, library: library, now: t0.addingTimeInterval(3_600))
        try run(context, at: t0.addingTimeInterval(7_200))

        #expect(added.allSatisfy { $0.seedKey == nil })
        #expect(try routineNames(context) == ["Mine", "Push", "Pull", "Legs"])
    }

    // MARK: Decisions from existing data

    @Test func routinesOfTheUsersOwnSettleTheDecision() throws {
        let context = try makeInMemoryContext()
        let mine = Routine(name: "Upper")
        mine.createdAt = t0.addingTimeInterval(-500)
        context.insert(mine)
        try context.save()

        let report = try run(context, seed: true)

        #expect(report.decisionInferred)
        #expect(!report.startersSeeded)
        #expect(try AppSettings.current(in: context).starterRoutinesDecidedAt == t0.addingTimeInterval(-500))
    }

    @Test func startersThatArriveBeforeTheirSettingsAreNeverRemoved() throws {
        let context = try makeInMemoryContext()
        try run(context)
        // This device made a routine an hour after the other device seeded, but has not
        // received the other device's settings row yet.
        let theirSeed = t0
        let mine = Routine(name: "Mine")
        mine.createdAt = t0.addingTimeInterval(3_600)
        context.insert(mine)
        try AppSettings.current(in: context).starterRoutinesDecidedAt = mine.createdAt
        try insertStarterRun(at: theirSeed, in: context)
        try context.save()

        let report = try run(context)

        #expect(report.routinesRemoved == 0)
        #expect(try context.count(Routine.self) == 4)
    }
}
