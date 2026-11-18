// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Progression step settings")
struct ProgressionStepSettingsTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func accessorReadsValidEntriesAndIgnoresTheRest() {
        let settings = AppSettings()
        settings.progressionStepsRaw = "barbell=1.25; dumbbell = 2 ;machine=abc;kettlebell=4;bodyweight=1;cable=-5;other=0;=3;junk;cable=7.5"
        #expect(settings.progressionSteps == [.barbell: 1.25, .dumbbell: 2, .cable: 7.5])
        settings.progressionStepsRaw = ""
        #expect(settings.progressionSteps.isEmpty)
        settings.progressionStepsRaw = "barbell=nan;machine=inf"
        #expect(settings.progressionSteps.isEmpty)
    }

    @Test func accessorWritesInAFixedOrderAndRoundTripsExactly() {
        let settings = AppSettings()
        let fivePounds = 5 * WeightUnit.kilogramsPerPound
        settings.progressionSteps = [.cable: 7.5, .barbell: fivePounds, .bodyweight: 1, .other: -1]
        #expect(settings.progressionStepsRaw == "barbell=\(fivePounds.description);cable=7.5")
        #expect(settings.progressionSteps[.barbell] == fivePounds)
    }

    @Test func settingAStepMarksTheRowEdited() {
        let settings = AppSettings()
        settings.createdAt = t0
        settings.updatedAt = t0
        SettingsEditing.setProgressionStep(kilograms: 1.25, for: .barbell, on: settings, now: t0.addingTimeInterval(5))
        #expect(settings.progressionSteps == [.barbell: 1.25])
        #expect(settings.updatedAt == t0.addingTimeInterval(5))
        // Unchanged: no edit.
        SettingsEditing.setProgressionStep(kilograms: 1.25, for: .barbell, on: settings, now: t0.addingTimeInterval(9))
        #expect(settings.updatedAt == t0.addingTimeInterval(5))
    }

    @Test func theBuiltInDefaultClearsTheUsersStep() {
        let settings = AppSettings()
        SettingsEditing.setProgressionStep(kilograms: 1, for: .dumbbell, on: settings)
        SettingsEditing.setProgressionStep(kilograms: 2, for: .dumbbell, on: settings)
        #expect(settings.progressionStepsRaw.isEmpty)
        SettingsEditing.setProgressionStep(kilograms: 7.5, for: .machine, on: settings)
        SettingsEditing.setProgressionStep(kilograms: nil, for: .machine, on: settings)
        SettingsEditing.setProgressionStep(kilograms: -2, for: .cable, on: settings)
        #expect(settings.progressionSteps.isEmpty)
    }

    @Test func defaultsFollowTheUnit() {
        let settings = AppSettings(unit: .lb)
        // 2.5 kg is not the pound default (5 lb), so it is kept for a pound user…
        SettingsEditing.setProgressionStep(kilograms: 2.5, for: .barbell, on: settings)
        #expect(settings.progressionSteps == [.barbell: 2.5])
        // …while 5 lb is the default and clears it.
        SettingsEditing.setProgressionStep(kilograms: 5 * WeightUnit.kilogramsPerPound, for: .barbell, on: settings)
        #expect(settings.progressionSteps.isEmpty)
        #expect(ProgressionSettings(settings).defaultStep(for: .barbell) == 5 * WeightUnit.kilogramsPerPound)
    }

    @Test func bodyweightHasNoStep() {
        let settings = AppSettings()
        SettingsEditing.setProgressionStep(kilograms: 1, for: .bodyweight, on: settings)
        #expect(settings.progressionStepsRaw.isEmpty)
        #expect(settings.updatedAt == settings.createdAt)
    }

    @Test func stepsSurviveTheDuplicateMerge() throws {
        let context = try makeInMemoryContext()
        let fresh = AppSettings()
        fresh.createdAt = t0
        fresh.updatedAt = t0
        let edited = AppSettings()
        edited.createdAt = t0.addingTimeInterval(10)
        edited.updatedAt = t0.addingTimeInterval(10)
        SettingsEditing.setProgressionStep(kilograms: 1, for: .dumbbell, on: edited, now: t0.addingTimeInterval(20))
        context.insertAll(fresh, edited)
        try context.save()
        let merged = try AppSettings.current(in: context)
        #expect(merged === fresh)
        #expect(merged.progressionSteps == [.dumbbell: 1])
        #expect(try context.count(AppSettings.self) == 1)
    }
}

@Suite("Exercise settings and recent exercises")
struct ExerciseSettingsTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func editingSetsValuesAndUpdatedAtOnlyOnChange() {
        let exercise = Exercise(name: "Bench Press")
        exercise.updatedAt = t0
        ExerciseEditing.setEquipment(.barbell, on: exercise, now: t0.addingTimeInterval(1))
        ExerciseEditing.setProgressionStep(kilograms: nil, on: exercise, now: t0.addingTimeInterval(1))
        ExerciseEditing.setDefaultRest(nil, on: exercise, now: t0.addingTimeInterval(1))
        #expect(exercise.updatedAt == t0)

        ExerciseEditing.setEquipment(.machine, on: exercise, now: t0.addingTimeInterval(2))
        #expect(exercise.equipment == .machine)
        #expect(exercise.updatedAt == t0.addingTimeInterval(2))
        ExerciseEditing.setProgressionStep(kilograms: 1.25, on: exercise, now: t0.addingTimeInterval(3))
        #expect(exercise.progressionStepKg == 1.25)
        ExerciseEditing.setProgressionStep(kilograms: 0, on: exercise, now: t0.addingTimeInterval(4))
        #expect(exercise.progressionStepKg == nil)
        ExerciseEditing.setDefaultRest(100, on: exercise, now: t0.addingTimeInterval(5))
        #expect(exercise.defaultRestSeconds == 105)
        ExerciseEditing.setDefaultRest(5_000, on: exercise, now: t0.addingTimeInterval(6))
        #expect(exercise.defaultRestSeconds == 600)
        ExerciseEditing.setDefaultRest(nil, on: exercise, now: t0.addingTimeInterval(7))
        #expect(exercise.defaultRestSeconds == nil)
        #expect(exercise.updatedAt == t0.addingTimeInterval(7))
    }

    @Test func recentListsDistinctExercisesNewestFirst() throws {
        let context = try makeInMemoryContext()
        let names = ["Bench Press", "Squat", "Row", "Curl", "Fly", "Archived"]
        let exercises = names.map { Exercise(name: $0) }
        for exercise in exercises { context.insert(exercise) }
        exercises[5].isArchived = true
        let (bench, squat, row, curl, fly, archived) = (exercises[0], exercises[1], exercises[2], exercises[3], exercises[4], exercises[5])
        insertSession(startedAt: t0, entries: [(curl, [(10, 10, false)]), (bench, [(50, 10, false)])], in: context)
        // Newest finished: Row logged after Squat, so Row first; Fly has nothing logged.
        insertSession(startedAt: t0.addingTimeInterval(86_400), entries: [
            (squat, [(80, 5, false)]), (fly, []), (archived, [(1, 1, false)]), (row, [(60, 8, false)]),
        ], in: context)
        // Unfinished workouts never count.
        insertSession(startedAt: t0.addingTimeInterval(2 * 86_400), ended: false, entries: [(fly, [(15, 12, false)])], in: context)
        try context.save()

        let recent = try RecentExercises.recent(in: context)
        #expect(recent.map(\.name) == ["Row", "Squat", "Bench Press", "Curl"])
        #expect(try RecentExercises.recent(limit: 3, in: context).map(\.name) == ["Row", "Squat", "Bench Press"])
        #expect(try RecentExercises.recent(limit: 0, in: context).isEmpty)
    }

    @Test func recentReadsPastTheFirstBatch() throws {
        let context = try makeInMemoryContext()
        let old = Exercise(name: "Old Favourite")
        let new = Exercise(name: "Bench Press")
        context.insertAll(old, new)
        insertSession(startedAt: t0, entries: [(old, [(20, 10, false)])], in: context)
        for day in 1...(RecentExercises.batchSize + 5) {
            insertSession(startedAt: t0.addingTimeInterval(Double(day) * 86_400), entries: [(new, [(60, 10, false)])], in: context)
        }
        try context.save()
        #expect(try RecentExercises.recent(in: context).map(\.name) == ["Bench Press", "Old Favourite"])
    }
}
