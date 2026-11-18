// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Import: writing into the store")
struct ImportWriterTests {
    private typealias F = ImportFixture
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let library = ExerciseLibrary(entries: [
        .init(key: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench Press", equipment: .barbell, muscle: .chest, aliases: ["Bench Press (Barbell)"]),
        .init(key: "Wide-Grip_Lat_Pulldown", name: "Lat Pulldown", equipment: .cable, muscle: .lats, aliases: ["Lat Pulldown (Cable)"]),
    ])

    private func request(_ workouts: [ImportedWorkout], source: Source = .importHevy, resolutions: [String: ExerciseResolution] = [:], batchSize: Int = 200) -> ImportWriteRequest {
        ImportWriteRequest(workouts: workouts, source: source, resolutions: resolutions, library: library, batchSize: batchSize, now: now)
    }

    private func write(_ request: ImportWriteRequest, in context: ModelContext, cancelAfter batches: Int? = nil) throws -> (ImportWriteReport, [ImportWriteProgress]) {
        var progress: [ImportWriteProgress] = []
        let report = try ImportWriter.write(request, in: context, isCancelled: {
            guard let batches else { return false }
            return progress.count - 1 >= batches
        }, progress: { progress.append($0) })
        return (report, progress)
    }

    /// Resolutions as the matcher finds them against what `context` holds.
    private func matched(_ result: ImportParseResult, in context: ModelContext) throws -> [String: ExerciseResolution] {
        let matcher = ExerciseMatcher(candidates: ExerciseCandidate.all(exercises: try context.all(Exercise.self), library: library))
        return Dictionary(uniqueKeysWithValues: result.exerciseNames.map { ($0.name, ExerciseResolution(matcher.match($0.name))) })
    }

    @Test("Sessions get the source, key, times, notes and every set, logged at the start")
    func writesSessions() throws {
        let context = try makeInMemoryContext()
        let result = try F.parse("hevy-en-kg")
        let plan = ImportPlan(workouts: result.allWorkouts, existingKeys: [])
        let (report, _) = try write(request(plan.toInsert, resolutions: try matched(result, in: context)), in: context)
        #expect(report.inserted == 4)
        #expect(report.requested == 4)

        let sessions = try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        #expect(sessions.count == 4)
        let upper = try #require(sessions.first)
        #expect(upper.source == .importHevy)
        #expect(upper.name == "Upper Power")
        #expect(upper.externalKey == "2026-10-07T18:05:00|upper power")
        #expect(upper.startedAt == F.date(2026, 10, 7, 18, 5))
        #expect(upper.endedAt == F.date(2026, 10, 7, 19, 12))
        #expect(upper.notes == "Felt strong today\nBench Press: Pause on chest")
        #expect(upper.healthKitWorkoutID == nil)
        #expect(upper.routine == nil)
        let entries = upper.sortedEntries
        #expect(entries.map { $0.exercise?.name } == ["Bench Press", "Lat Pulldown", "Pull Up"])
        let benchSets = entries[0].sortedSets
        #expect(benchSets.map(\.weightKg) == [40, 80, 80, 80])
        #expect(benchSets.map(\.isWarmup) == [true, false, false, false])
        #expect(benchSets.map(\.rpe) == [nil, 8, 8.5, 10])
        #expect(benchSets.map(\.note) == ["", "", "", "Failure"])
        #expect(benchSets.allSatisfy { $0.completedAt == upper.startedAt })
        #expect(entries[1].sortedSets.last?.note == "Drop set")
        #expect(entries[2].sortedSets.first?.weightKg == nil)
        // Names this test library does not know become custom exercises with those names.
        #expect(report.newExercises == ["Pull Up", "Squat (Barbell)", "Romanian Deadlift (Barbell)"])
        #expect(entries[2].exercise?.isCustom == true)
    }

    @Test("Imported sessions feed history, records and pre-fill; no end means no duration")
    func feedsHistory() throws {
        let context = try makeInMemoryContext()
        let result = try F.parse("fitnotes-header-kgs")
        _ = try write(request(result.workouts, source: .importFitNotes), in: context)
        let history = try HistorySnapshot.load(in: context)
        #expect(history.count == 2)
        #expect(history.allSatisfy { $0.isImported })
        #expect(history.allSatisfy { SessionMetrics.duration(of: $0) == nil })
        #expect(history.first?.displayName == "")
        let index = HistoryIndex(sessions: history)
        #expect(index.rows.allSatisfy { $0.isImported })
        let squat = try exercise(named: "Barbell Squat", in: context)
        #expect(index.records.records(forExercise: squat.id)?.heaviest?.weightKg == 80)
        let last = ExerciseHistory.lastPerformance(of: squat)
        #expect(last?.sets.first?.weightKg == 80)
        #expect(last?.sets.first?.reps == 5)
    }

    @Test("Importing the same file again adds nothing; a newer export adds only new workouts")
    func reimport() throws {
        let context = try makeInMemoryContext()
        let result = try F.parse("hevy-en-kg")
        let older = Array(result.workouts.dropFirst())
        _ = try write(request(older), in: context)
        #expect(try context.count(Session.self) == 3)

        let existing = try ImportWriter.existingKeys(in: context)
        let plan = ImportPlan(workouts: result.allWorkouts, existingKeys: existing)
        #expect(plan.insertCount == 1)
        #expect(plan.alreadyImported == 3)
        _ = try write(request(plan.toInsert), in: context)
        #expect(try context.count(Session.self) == 4)

        // Even a request that skips planning never duplicates: keys are checked when writing.
        let (again, _) = try write(request(result.workouts), in: context)
        #expect(again.inserted == 0)
        #expect(again.alreadyImported == 4)
        #expect(try context.count(Session.self) == 4)
        let exerciseNames = try context.all(Exercise.self).map(\.name)
        #expect(exerciseNames.count == Set(exerciseNames).count)
    }

    @Test("Custom exercises are created once and reuse an exercise that already has the name")
    func customOnce() throws {
        let context = try makeInMemoryContext()
        let existing = Exercise(name: "Zercher Squat", equipment: .barbell, isCustom: true)
        existing.isArchived = true
        context.insert(existing)
        try context.save()
        let workouts = [
            ImportedWorkout(name: "A", startedAt: now, exercises: [
                ImportedExercise(name: "Rope Push Down", sets: [ImportedSet(weightKg: 20, reps: 10)]),
                ImportedExercise(name: "rope push  down", sets: [ImportedSet(weightKg: 20, reps: 10)]),
                ImportedExercise(name: "Zercher Squat", sets: [ImportedSet(weightKg: 60, reps: 5)]),
            ]),
            ImportedWorkout(name: "A", startedAt: now.addingTimeInterval(86_400), exercises: [
                ImportedExercise(name: "Rope Push Down", sets: [ImportedSet(weightKg: 22, reps: 10)]),
            ]),
        ]
        let resolutions: [String: ExerciseResolution] = [
            "Rope Push Down": .newCustom(name: "Rope Push Down", equipment: .cable),
            "rope push  down": .newCustom(name: "Rope Push Down", equipment: .cable),
            "Zercher Squat": .newCustom(name: "Zercher Squat", equipment: .other),
        ]
        let (report, _) = try write(request(workouts, source: .importCSV, resolutions: resolutions), in: context)
        #expect(report.newExercises == ["Rope Push Down"])
        let exercises = try context.all(Exercise.self)
        #expect(exercises.count == 2)
        #expect(exercises.first { $0.name == "Rope Push Down" }?.equipment == .cable)
        #expect(exercises.first { $0.name == "Rope Push Down" }?.primaryMuscle == .other)
        #expect(report.exerciseIDs["Zercher Squat"] == existing.id)
    }

    @Test("Rematched and confirmed names are remembered as aliases; automatic matches are not")
    func aliases() throws {
        let context = try makeInMemoryContext()
        let fly = Exercise(name: "Cable Fly", equipment: .cable)
        let hipThrust = Exercise(name: "Hip Thrust", equipment: .barbell)
        let row = Exercise(name: "Seated Cable Row", equipment: .cable)
        context.insertAll(fly, hipThrust, row)
        try context.save()
        let workout = ImportedWorkout(name: "B", startedAt: now, exercises: [
            ImportedExercise(name: "Cable Crossover", sets: [ImportedSet(weightKg: 15, reps: 12)]),
            ImportedExercise(name: "Hip Thrust (Machine)", sets: [ImportedSet(weightKg: 80, reps: 10)]),
            ImportedExercise(name: "Seated Cable Row", sets: [ImportedSet(weightKg: 50, reps: 10)]),
            ImportedExercise(name: "Rows on the cable", sets: [ImportedSet(weightKg: 50, reps: 10)]),
        ])
        let resolutions: [String: ExerciseResolution] = [
            "Cable Crossover": .exercise(.stored(fly.id), remember: true),
            "Hip Thrust (Machine)": ExerciseResolution(.check(ExerciseCandidate(hipThrust), .differentEquipment(.machine))),
            "Seated Cable Row": ExerciseResolution(.matched(ExerciseCandidate(row), .exactName)),
            "Rows on the cable": .newCustom(name: "Cable Row Variation", equipment: .cable),
        ]
        let (report, _) = try write(request([workout], resolutions: resolutions), in: context)
        #expect(fly.aliases == ["Cable Crossover"])
        #expect(hipThrust.aliases == ["Hip Thrust (Machine)"])
        #expect(row.aliases.isEmpty)
        let custom = try exercise(named: "Cable Row Variation", in: context)
        #expect(custom.aliases == ["Rows on the cable"])
        #expect(report.aliasesAdded == 3)
        #expect(fly.updatedAt == now)

        // Next time the remembered names match by alias.
        let matcher = ExerciseMatcher(candidates: try context.all(Exercise.self).map(ExerciseCandidate.init))
        #expect(matcher.match("Cable Crossover") == .matched(ExerciseCandidate(fly), .alias))
    }

    @Test("A rematch is remembered even when every workout was imported before")
    func rememberWithoutNewWorkouts() throws {
        let context = try makeInMemoryContext()
        let fly = Exercise(name: "Cable Fly", equipment: .cable)
        context.insert(fly)
        try context.save()
        let (report, _) = try write(request([], resolutions: ["Pec Cable Cross": .exercise(.stored(fly.id), remember: true)]), in: context)
        #expect(report.inserted == 0)
        #expect(fly.aliases == ["Pec Cable Cross"])
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<Exercise>()).first?.aliases == ["Pec Cable Cross"])
    }

    @Test("A library exercise the store lacks is added with its key, so maintenance can merge it")
    func libraryExercise() throws {
        let context = try makeInMemoryContext()
        let workout = ImportedWorkout(name: "C", startedAt: now, exercises: [
            ImportedExercise(name: "Bench Press (Barbell)", sets: [ImportedSet(weightKg: 60, reps: 8)]),
        ])
        let (report, _) = try write(request([workout], resolutions: ["Bench Press (Barbell)": .exercise(.library("Barbell_Bench_Press_-_Medium_Grip"), remember: false)]), in: context)
        #expect(report.newExercises.isEmpty)
        let bench = try exercise(named: "Bench Press", in: context)
        #expect(bench.libraryKey == "Barbell_Bench_Press_-_Medium_Grip")
        #expect(!bench.isCustom)
        #expect(bench.aliases == ["Bench Press (Barbell)"])

        // Another device seeded the same entry: the usual merge keeps one, with the session.
        let other = Exercise(name: "Bench Press", equipment: .barbell, primaryMuscle: .chest)
        other.libraryKey = "Barbell_Bench_Press_-_Medium_Grip"
        other.createdAt = now.addingTimeInterval(-60)
        context.insert(other)
        try context.save()
        let maintenance = try StoreMaintenance.run(in: context, library: library, seedStarterRoutines: false, now: now)
        #expect(maintenance.exercisesMerged == 1)
        let survivors = try context.all(Exercise.self).filter { $0.libraryKey == "Barbell_Bench_Press_-_Medium_Grip" }
        #expect(survivors.count == 1)
        #expect(survivors.first?.sessionEntries?.count == 1)
    }

    @Test("A stored exercise deleted since the review becomes a custom exercise")
    func deletedSinceReview() throws {
        let context = try makeInMemoryContext()
        let workout = ImportedWorkout(name: "D", startedAt: now, exercises: [ImportedExercise(name: "Ghost Lift", sets: [ImportedSet(reps: 5)])])
        let (report, _) = try write(request([workout], resolutions: ["Ghost Lift": .exercise(.stored(UUID()), remember: true)]), in: context)
        #expect(report.newExercises == ["Ghost Lift"])
    }

    @Test("Batches are saved with progress; stopping keeps what was saved")
    func cancellation() throws {
        let context = try makeInMemoryContext()
        let workouts = (0..<7).map { day in
            ImportedWorkout(name: "Day", startedAt: now.addingTimeInterval(Double(day) * 86_400), exercises: [
                ImportedExercise(name: "Squat", sets: [ImportedSet(weightKg: 100, reps: 5)]),
            ])
        }
        let (stopped, progress) = try write(request(workouts, batchSize: 2), in: context, cancelAfter: 2)
        #expect(stopped.wasCancelled)
        #expect(stopped.inserted == 4)
        #expect(progress.map(\.saved) == [0, 2, 4])
        #expect(progress.allSatisfy { $0.total == 7 })
        // Saved: a fresh context on the same container sees them.
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Session>()) == 4)

        // Importing again adds the rest.
        let (rest, restProgress) = try write(request(workouts, batchSize: 2), in: context)
        #expect(rest.inserted == 3)
        #expect(rest.alreadyImported == 4)
        #expect(!rest.wasCancelled)
        #expect(restProgress.last == ImportWriteProgress(saved: 3, total: 3))
        #expect(try context.count(Session.self) == 7)
        #expect(try context.count(Exercise.self) == 1)
    }

    @Test("Writes through a container off the caller's actor")
    func concurrentWrite() async throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let result = try F.parse("strong-1c")
        let report = try await ImportWriter.write(request(result.workouts, source: .importStrong), to: container)
        #expect(report.inserted == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Session>()) == 2)
    }

    @Test("2,000 workouts are written in batches to an on-disk store (time is printed, not asserted)")
    func largeImport() throws {
        try withTemporaryStoreURL { url in
            try largeImport(into: ModelContext(WholesetStore.makeContainer(url: url)))
        }
    }

    private func largeImport(into context: ModelContext) throws {
        let names = ["Squat", "Bench Press (Barbell)", "Barbell Row", "Overhead Press", "Romanian Deadlift", "Lat Pulldown (Cable)"]
        let workouts = (0..<2_000).map { index in
            ImportedWorkout(
                name: ["Upper", "Lower", "Full"][index % 3],
                startedAt: now.addingTimeInterval(-Double(index) * 86_400),
                endedAt: now.addingTimeInterval(-Double(index) * 86_400 + 3_600),
                exercises: names.map { name in
                    ImportedExercise(name: name, sets: (0..<4).map { set in ImportedSet(weightKg: 40 + Double(set) * 5, reps: 8, isWarmup: set == 0) })
                }
            )
        }
        let started = ContinuousClock.now
        let (report, progress) = try write(request(workouts), in: context)
        let elapsed = started.duration(to: .now)
        print("ImportWriter: 2,000 sessions, 12,000 entries, 48,000 sets in \(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000) ms (\(progress.count - 1) saves)")
        #expect(report.inserted == 2_000)
        #expect(progress.count == 12)
        #expect(try context.count(SetLog.self) == 48_000)
        #expect(try context.count(Exercise.self) == names.count)
    }
}
