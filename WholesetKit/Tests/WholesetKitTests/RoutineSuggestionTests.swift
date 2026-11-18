// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Import: routine suggestions and the summary")
struct RoutineSuggestionTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func workout(_ name: String, day: Int, _ exercises: [(String, [(Int, Bool)])]) -> ImportedWorkout {
        ImportedWorkout(
            name: name,
            startedAt: t0.addingTimeInterval(Double(day) * 86_400),
            exercises: exercises.map { exercise in
                ImportedExercise(name: exercise.0, sets: exercise.1.map { ImportedSet(weightKg: 50, reps: $0.0, isWarmup: $0.1) })
            }
        )
    }

    private func repeated(_ name: String, times: Int, startDay: Int = 0) -> [ImportedWorkout] {
        (0..<times).map { workout(name, day: startDay + $0, [("Squat", [(5, false)])]) }
    }

    @Test("Built from the latest workout with the name: order, working sets, rep range")
    func fromFixture() throws {
        let result = try ImportFixture.parse("hevy-en-kg")
        let suggestions = RoutineSuggestion.suggestions(from: result.allWorkouts, existingRoutineNames: [])
        #expect(suggestions.count == 1)
        let upper = try #require(suggestions.first)
        #expect(upper.name == "Upper Power")
        #expect(upper.timesDone == 3)
        #expect(upper.latestStart == ImportFixture.date(2026, 10, 7, 18, 5))
        #expect(upper.items.map(\.importedName) == ["Bench Press (Barbell)", "Lat Pulldown (Cable)", "Pull Up"])
        #expect(upper.items.map(\.targetSets) == [3, 3, 1])
        #expect(upper.items.map { $0.repLow...$0.repHigh } == [4...5, 8...10, 6...10])
    }

    @Test("Nameless workouts, rare names and existing routines are not suggested")
    func exclusions() {
        let workouts = repeated("", times: 5) + repeated("Push Day", times: 4, startDay: 10) + repeated("Pull", times: 2, startDay: 20)
        #expect(RoutineSuggestion.suggestions(from: workouts, existingRoutineNames: [" push  DAY "]).isEmpty)
        #expect(RoutineSuggestion.suggestions(from: workouts, existingRoutineNames: []).map(\.name) == ["Push Day"])
    }

    @Test("Most frequent first, then most recent; at most five; names compared without case")
    func ordering() {
        var workouts: [ImportedWorkout] = []
        let counts = [("A", 3), ("B", 7), ("C", 4), ("D", 4), ("E", 5), ("F", 3), ("G", 6)]
        for (offset, (name, count)) in counts.enumerated() {
            workouts += repeated(name, times: count, startDay: offset * 10)
        }
        workouts += [workout("b", day: 200, [("Bench", [(8, false)])])]
        let suggestions = RoutineSuggestion.suggestions(from: workouts, existingRoutineNames: [])
        #expect(suggestions.map(\.name) == ["b", "G", "E", "D", "C"])
        #expect(suggestions.first?.timesDone == 8)
        #expect(suggestions.first?.items.map(\.importedName) == ["Bench"])
        #expect(RoutineSuggestion.enabledByDefault == 2)
    }

    @Test("Rep ranges from working reps", arguments: [
        ([Int](), 8...12), ([5, 5, 5], 3...7), ([10, 10], 8...12), ([1], 1...3), ([3, 5, 4], 3...5), ([60, 8], 8...12), ([12, 8], 8...12),
    ])
    func repRange(reps: [Int], expected: ClosedRange<Int>) {
        #expect(RoutineSuggestion.repRange(workingReps: reps) == expected)
    }

    @Test("Warm-ups do not count; an exercise done twice is merged into its first place; sets capped at 10")
    func items() {
        let latest = workout("Legs", day: 0, [
            ("Squat", [(10, true), (5, false), (5, false)]),
            ("Leg Curl", Array(repeating: (12, false), count: 12)),
            ("Squat", [(3, false)]),
        ])
        let items = RoutineSuggestion.items(for: latest)
        #expect(items.map(\.importedName) == ["Squat", "Leg Curl"])
        #expect(items.map(\.targetSets) == [3, 10])
        #expect(items[0].repLow == 3 && items[0].repHigh == 5)
    }

    @Test("Creating links only the latest session, like saving a workout as a routine")
    func create() throws {
        let context = try makeInMemoryContext()
        let library = ExerciseLibrary(entries: [])
        let workouts = [
            workout("Push", day: 0, [("Press", [(8, false)])]),
            workout("Push", day: 2, [("Press", [(8, false), (6, false)]), ("Dips", [(10, false)]), ("Press Again", [(5, false)])]),
            workout("Push", day: 4, [("Press", [(8, false), (8, false), (7, false)]), ("Dips", [(12, false)]), ("Press Again", [(5, false)])]),
        ]
        let press = Exercise(name: "Bench Press", equipment: .barbell)
        context.insert(press)
        try context.save()
        let resolutions: [String: ExerciseResolution] = [
            "Press": .exercise(.stored(press.id), remember: true),
            "Press Again": .exercise(.stored(press.id), remember: false),
            "Dips": .newCustom(name: "Dips", equipment: .bodyweight),
        ]
        let request = ImportWriteRequest(workouts: workouts, source: .importStrong, resolutions: resolutions, library: library)
        let report = try ImportWriter.write(request, in: context, isCancelled: { false }, progress: { _ in })
        let suggestion = try #require(RoutineSuggestion.suggestions(from: workouts, existingRoutineNames: []).first)
        let exercises = try context.all(Exercise.self)
        let routine = try #require(try suggestion.create(in: context, exercise: { name in
            report.exerciseIDs[name].flatMap { id in exercises.first { $0.id == id } }
        }, now: t0))
        try context.save()

        #expect(routine.name == "Push")
        let items = routine.sortedItems
        #expect(items.map { $0.exercise?.name } == ["Bench Press", "Dips"])
        #expect(items.map(\.targetSets) == [3, 1])
        #expect(items.map(\.repLow) == [7, 10])
        #expect(items.map(\.repHigh) == [8, 14])
        let sessions = try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(sessions.map { $0.routine != nil } == [false, false, true])
        let linked = try #require(sessions.last)
        #expect(linked.sortedEntries.map(\.routineItemID) == [items[0].id, items[1].id, items[0].id])
        let settings = try AppSettings.current(in: context)
        #expect(settings.starterRoutinesDecidedAt != nil)
    }

    @Test("Creating from resolutions finds the exercises the import created, even for earlier imports")
    func createFromResolutions() throws {
        let context = try makeInMemoryContext()
        let library = ExerciseLibrary(entries: [.init(key: "Leg_Press", name: "Leg Press", equipment: .machine, muscle: .quadriceps)])
        let workouts = (0..<3).map { workout("Legs", day: $0, [("Hack", [(10, false)]), ("Press", [(12, false), (12, false)])]) }
        let resolutions: [String: ExerciseResolution] = [
            "Hack": .newCustom(name: "Hack Squat Machine", equipment: .machine),
            "Press": .exercise(.library("Leg_Press"), remember: false),
        ]
        let request = ImportWriteRequest(workouts: workouts, source: .importCSV, resolutions: resolutions, library: library)
        _ = try ImportWriter.write(request, in: context, isCancelled: { false }, progress: { _ in })
        let before = try context.count(Exercise.self)
        let suggestion = try #require(RoutineSuggestion.suggestions(from: workouts, existingRoutineNames: []).first)
        let routine = try #require(try suggestion.create(in: context, resolutions: resolutions, library: library, now: t0))
        #expect(routine.sortedItems.map { $0.exercise?.name } == ["Hack Squat Machine", "Leg Press"])
        #expect(try context.count(Exercise.self) == before)
    }

    @Test("Nothing is created when none of the exercises can be found")
    func createNothing() throws {
        let context = try makeInMemoryContext()
        let suggestion = try #require(RoutineSuggestion.suggestions(from: repeated("Legs", times: 3), existingRoutineNames: []).first)
        #expect(try suggestion.create(in: context, exercise: { _ in nil }) == nil)
        #expect(try context.count(Routine.self) == 0)
    }

    @Test("The summary counts every workout and every row")
    func summary() throws {
        let result = try ImportFixture.parse("hevy-us-lbs")
        let plan = ImportPlan(workouts: result.allWorkouts + result.allWorkouts.prefix(1), existingKeys: [])
        var report = ImportWriteReport()
        report.inserted = 2
        report.alreadyImported = 1
        report.newExercises = ["Farmers Walk"]
        report.aliasesAdded = 1
        let summary = ImportSummary(result: result, plan: plan, report: report)
        #expect(summary.importedWorkouts == 2)
        #expect(summary.plannedWorkouts == 2)
        #expect(summary.alreadyImported == 1)
        #expect(summary.repeatedInFile == 1)
        #expect(summary.emptyWorkouts == 1)
        #expect(summary.rowsNotReadCount == 2)
        #expect(summary.rowsNotRead.map(\.reason) == [.timedOrDistanceOnly])
        #expect(summary.rowsNotRead.first?.rows.map(\.line) == [7, 8])
        #expect(summary.newExercises == ["Farmers Walk"])
        #expect(!summary.wasCancelled)
    }
}
