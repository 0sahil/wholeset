// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Import: reading each app's export")
struct ImportParserTests {
    private typealias F = ImportFixture
    private let pound = WeightUnit.kilogramsPerPound

    private func sets(_ exercise: ImportedExercise?) -> [String] {
        (exercise?.sets ?? []).map { set in
            let weight = set.weightKg.map { String(format: "%.4f", $0) } ?? "-"
            return "\(set.isWarmup ? "W" : "")\(weight)x\(set.reps ?? 0)\(set.kind == .normal ? "" : "/\(set.kind.rawValue)")"
        }
    }

    // MARK: Hevy

    @Test("Hevy: workouts by title and start, 0-based set index, set types, notes, RPE")
    func hevy() throws {
        let result = try F.parse("hevy-en-kg")
        #expect(result.layout == .hevy(weight: .kg))
        #expect(result.weightUnitSource == .header(.kg))
        #expect(result.workoutCount == 4)
        let upper = try #require(result.workouts.first)
        #expect(upper.name == "Upper Power")
        #expect(upper.startedAt == F.date(2026, 10, 7, 18, 5))
        #expect(upper.endedAt == F.date(2026, 10, 7, 19, 12))
        #expect(upper.notes == "Felt strong today")
        #expect(upper.externalKey == "2026-10-07T18:05:00|upper power")
        #expect(upper.firstLine == 2)
        #expect(upper.exercises.map(\.name) == ["Bench Press (Barbell)", "Lat Pulldown (Cable)", "Pull Up"])
        let bench = upper.exercises[0]
        #expect(bench.note == "Pause on chest")
        #expect(sets(bench) == ["W40.0000x8", "80.0000x5", "80.0000x5", "80.0000x4/failure"])
        #expect(bench.sets.map(\.rpe) == [nil, 8, 8.5, 10])
        #expect(bench.sets[3].storedNote == "Failure")
        #expect(sets(upper.exercises[1]) == ["55.0000x10", "55.0000x9", "40.0000x8/drop"])
        #expect(upper.exercises[1].sets[2].storedNote == "Drop set")
        #expect(sets(upper.exercises[2]) == ["-x8"])

        let lower = result.workouts[1]
        #expect(lower.startedAt == F.date(2026, 10, 3, 7, 40))
        #expect(lower.notes == "Knee a bit sore\nkept it light")
        #expect(lower.firstLine == 11)
        #expect(sets(lower.exercises[0]) == ["W60.0000x5", "100.0000x8", "100.0000x8", "100.0000x7"])

        #expect(result.skippedRows.map(\.line) == [10, 23])
        #expect(result.skippedRows.allSatisfy { $0.reason == .timedOrDistanceOnly })
        #expect(result.skippedRows.first?.text.contains("Treadmill") == true)
        #expect(result.dateRange == F.date(2026, 9, 23, 18, 2)...F.date(2026, 10, 7, 18, 5))
        #expect(result.exerciseNames.map(\.name) == ["Bench Press (Barbell)", "Lat Pulldown (Cable)", "Pull Up", "Squat (Barbell)", "Romanian Deadlift (Barbell)"])
    }

    @Test("Hevy in pounds: US dates, rows of two workouts interleaved, oldest first, extra column")
    func hevyPounds() throws {
        let result = try F.parse("hevy-us-lbs")
        #expect(result.layout == .hevy(weight: .lb))
        #expect(result.allWorkouts.map(\.name) == ["Garage Pull", "Garage Push", "Lunch Walk"])
        let pull = result.allWorkouts[0]
        #expect(pull.startedAt == F.date(2026, 9, 9, 18, 30))
        #expect(pull.exercises.map(\.name) == ["Deadlift (Barbell)", "Bent Over Row (Barbell)"])
        #expect(pull.exercises[0].sets.map(\.weightKg) == [225 * pound, 245 * pound])
        #expect(result.allWorkouts[1].exercises.first?.sets.map(\.reps) == [8, 7])
        #expect(result.allWorkouts[2].isEmpty)
        #expect(result.workoutCount == 2)
        #expect(result.skippedRows.map(\.reason) == [.timedOrDistanceOnly, .timedOrDistanceOnly])
    }

    @Test("Hevy: a CRLF copy of the file reads the same")
    func crlf() throws {
        let text = try #require(String(data: F.data("hevy-en-kg"), encoding: .utf8))
        let file = try ImportFile(data: Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8))
        let crlf = try F.parse(file)
        let lf = try F.parse("hevy-en-kg")
        #expect(crlf.allWorkouts == lf.allWorkouts)
        #expect(crlf.skippedRows.map(\.line) == lf.skippedRows.map(\.line))
    }

    // MARK: Strong

    @Test("Strong 1a: no unit (the chosen one is used), W/D/F, rest timers, notes, durations")
    func strongNoUnit() throws {
        let result = try F.parse("strong-1a", options: F.options(weightUnit: .lb))
        #expect(result.layout == .strongNoUnit)
        #expect(result.weightUnitSource == .chosen(.lb))
        #expect(result.allWorkouts.map(\.name) == ["Push A", "Legs B", "Push A", "Push A"])
        let push = result.allWorkouts[0]
        #expect(push.notes == "Short on time")
        #expect(push.endedAt == push.startedAt.addingTimeInterval(3_900))
        let incline = push.exercises[0]
        #expect(incline.note == "Elbows tucked\nslow negatives")
        #expect(incline.sets.map(\.isWarmup) == [true, false, false, false])
        #expect(incline.sets.map(\.kind) == [.normal, .normal, .normal, .drop])
        #expect(incline.sets.map(\.reps) == [10, 9, 8, 10])
        #expect(incline.sets[0].weightKg == 14 * pound)
        #expect(incline.sets[1].rpe == 8)
        #expect(push.exercises[1].sets.map(\.kind) == [.normal, .failure])
        // Rest-timer rows are not sets and not "rows not read".
        #expect(result.stats.ignoredRowCount == 1)
        #expect(result.skippedRows.map(\.line) == [9, 12])
        #expect(result.skippedRows.map(\.reason) == [.timedOrDistanceOnly, .weightWithoutReps])
        #expect(result.allWorkouts[1].endedAt == result.allWorkouts[1].startedAt.addingTimeInterval(48 * 60))
        #expect(result.allWorkouts[2].endedAt == result.allWorkouts[2].startedAt.addingTimeInterval(7_200))
        #expect(result.allWorkouts[3].endedAt == result.allWorkouts[3].startedAt.addingTimeInterval(38 * 60))
        // A weight of 0 is bodyweight.
        #expect(result.allWorkouts[2].exercises[1].sets.first?.weightKg == nil)
    }

    @Test("Strong 1b: semicolons, a unit per row, decimal commas; a missing unit follows the rows before")
    func strongUnitColumn() throws {
        let result = try F.parse("strong-1b", options: F.options(weightUnit: .kg))
        #expect(result.layout == .strongUnitColumn)
        #expect(result.weightUnitSource == .column)
        #expect(result.stats.unitsFound == [.kg, .lb])
        #expect(result.stats.rowsWithAssumedUnit == 1)
        let evening = result.allWorkouts[0]
        #expect(evening.exercises[0].sets.map(\.weightKg) == [62.5, 62.5])
        #expect(evening.exercises[1].sets.first?.weightKg == nil)
        #expect(evening.endedAt == evening.startedAt.addingTimeInterval(55 * 60))
        let hotel = result.allWorkouts[1]
        #expect(hotel.name == "Hotel Gym")
        #expect(hotel.exercises[0].sets.map(\.weightKg) == [50 * pound, 50 * pound])
        #expect(hotel.endedAt == hotel.startedAt.addingTimeInterval(3_840))
        #expect(result.skippedRows.map(\.line) == [5, 8])
    }

    @Test("Strong 1c: Workout # groups, kg header, note rows, repeated workout notes once")
    func strongNumbered() throws {
        let result = try F.parse("strong-1c")
        #expect(result.layout == .strongNumbered(weight: .kg))
        #expect(result.allWorkouts.count == 2)
        let sunday = result.allWorkouts[0]
        #expect(sunday.name == "Full Body 2")
        #expect(sunday.notes == "Sunday session")
        #expect(sunday.endedAt == sunday.startedAt.addingTimeInterval(3_600))
        #expect(sunday.exercises.map(\.name) == ["Front Squat (Barbell)", "Seated Row (Machine)"])
        #expect(sunday.exercises[0].sets.map(\.isWarmup) == [true, false, false])
        #expect(sunday.exercises[1].note == "Seat on 4")
        #expect(sunday.composedNotes() == "Sunday session\nSeated Row (Machine): Seat on 4")
        // The key is (start, name), never the Workout #.
        #expect(sunday.externalKey == "2026-05-10T09:15:00|full body 2")
        #expect(result.stats.ignoredRowCount == 1)
        #expect(result.skippedRows.map(\.reason) == [.timedOrDistanceOnly])
    }

    @Test("Strong 1d: unit in the header, rows a spreadsheet wrapped in quotes")
    func strongUnitHeader() throws {
        let result = try F.parse("strong-1d")
        #expect(result.layout == .strongUnitHeader(weight: .lb))
        #expect(result.workouts.first?.exercises.first?.sets.map(\.weightKg) == [135 * pound, 155 * pound])
        #expect(result.skippedRows.map(\.reason) == [.timedOrDistanceOnly])
    }

    // MARK: FitNotes

    @Test("FitNotes: one nameless workout per date at midnight, unit in the header")
    func fitNotesHeader() throws {
        let result = try F.parse("fitnotes-header-kgs")
        #expect(result.layout == .fitNotesUnitHeader(weight: .kg))
        #expect(result.allWorkouts.map(\.name) == ["", ""])
        #expect(result.allWorkouts.map(\.startedAt) == [F.date(2016, 4, 3), F.date(2016, 4, 5)])
        #expect(result.allWorkouts[0].endedAt == nil)
        #expect(result.allWorkouts[0].exercises.map(\.name) == ["Flat Dumbbell Bench Press", "Seated Cable Row"])
        #expect(result.allWorkouts[0].externalKey == "2016-04-03T00:00:00|")
        #expect(result.skippedRows.map(\.reason) == [.timedOrDistanceOnly])
    }

    @Test("FitNotes: kgs/lbs per row, comments become set notes")
    func fitNotesColumn() throws {
        let result = try F.parse("fitnotes-unit-column")
        #expect(result.layout == .fitNotesUnitColumn)
        let first = result.allWorkouts[0]
        #expect(first.exercises[0].sets.map(\.note) == ["", "grip a bit wider"])
        #expect(first.exercises[1].sets.first?.weightKg == nil)
        #expect(result.allWorkouts[1].exercises[0].sets.first?.weightKg == 135 * pound)
        #expect(result.stats.unitsFound == [.kg, .lb])
    }

    // MARK: Beta formats

    @Test("Fitbod: UTC timestamps, trimmed numbers, warm-up flags, repeated rows kept, pound noise snapped")
    func fitbod() throws {
        let result = try F.parse("fitbod")
        #expect(result.layout == .fitbod)
        #expect(result.workoutCount == 2)
        let first = result.allWorkouts[0]
        #expect(first.name.isEmpty)
        #expect(first.startedAt == F.date(2023, 6, 2, 17, 12, 40, zone: .gmt))
        #expect(first.exercises[0].sets.count == 3)
        #expect(first.exercises[0].sets.map(\.isWarmup) == [true, false, false])
        #expect(first.exercises[0].sets.map(\.weightKg) == [24, 24, 24])
        #expect(first.exercises[1].sets.first?.weightKg == 65 * pound)
        let second = result.allWorkouts[1]
        #expect(second.exercises[0].sets.first?.weightKg == nil)
        #expect(second.exercises[1].sets.map(\.isWarmup) == [true, false])
        #expect(second.exercises[1].sets.map(\.weightKg) == [187 * pound, 30.12])
        #expect(result.skippedRows.map(\.reason) == [.timedOrDistanceOnly])
    }

    @Test("StrongLifts: wide rows, 0-rep cells are not sets, a byte order mark, end after midnight")
    func strongLifts() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + (try F.data("stronglifts-lb"))
        let result = try F.parse(ImportFile(data: data))
        #expect(result.layout == .strongLifts(weight: .lb))
        #expect(result.allWorkouts.map(\.name) == ["Workout B", "Workout A"])
        let b = result.allWorkouts[0]
        #expect(b.startedAt == F.date(2026, 2, 3, 23, 40))
        #expect(b.endedAt == F.date(2026, 2, 4, 0, 43))
        #expect(b.exercises[0].sets.count == 5)
        #expect(b.exercises[0].sets.first?.weightKg == 185 * pound)
        #expect(b.exercises[1].sets.map(\.reps) == [5, 5, 4])
        #expect(b.exercises[1].note == "Last set grinder")
        #expect(result.skippedRows.map(\.reason) == [.timedOrDistanceOnly])
        #expect(result.allWorkouts[1].endedAt == F.date(2026, 2, 5, 7, 6))
    }

    @Test("Liftosaur 2024: ISO UTC with milliseconds, warm-up 0/1, unit per row, day name or program")
    func liftosaurLegacy() throws {
        let result = try F.parse("liftosaur-2024")
        #expect(result.layout == .liftosaur(isCurrent: false))
        #expect(result.allWorkouts.map(\.name) == ["Day 1", "My GZCLP"])
        let day = result.allWorkouts[0]
        #expect(day.externalKey == "2025-04-01T16:20:05Z|day 1")
        #expect(day.exercises[0].sets.map(\.isWarmup) == [true, false, false])
        #expect(day.exercises[0].sets.map(\.weightKg) == [95 * pound, 185 * pound, 185 * pound])
        #expect(result.allWorkouts[1].exercises[0].sets.first?.weightKg == 60)
        #expect(result.allWorkouts[1].exercises[0].sets.first?.rpe == 7.5)
        #expect(result.skippedRows.map(\.reason) == [.weightWithoutReps])
        #expect(result.stats.unitsFound == [.lb, .kg])
    }

    @Test("Liftosaur current header: completed weight and RPE")
    func liftosaurCurrent() throws {
        let result = try F.parse("liftosaur-current")
        #expect(result.layout == .liftosaur(isCurrent: true))
        let deadlift = try #require(result.workouts.first?.exercises.first)
        #expect(deadlift.sets.map(\.weightKg) == [142.5, 142.5])
        #expect(deadlift.sets.map(\.rpe) == [8, 9])
        #expect(deadlift.note == "Belt on")
    }

    // MARK: Generic

    @Test("Generic: needs a mapping, then groups by date-time and workout name")
    func generic() throws {
        let file = try F.file("generic")
        #expect(file.layout == .generic)
        guard case .needsColumnMapping = file.parse(F.options()) else {
            Issue.record("A generic file needs a mapping")
            return
        }
        let mapping = GenericMapping.suggested(header: file.table.header, sampleRows: file.table.rows)
        let result = try F.parse(file, options: F.options(mapping: mapping))
        #expect(result.weightUnitSource == .header(.lb))
        #expect(result.allWorkouts.map(\.name) == ["Upper A", "Lower A"])
        let upper = result.allWorkouts[0]
        #expect(upper.startedAt == F.date(2025, 3, 4, 18, 10))
        #expect(upper.exercises.map(\.name) == ["Bench press", "Bent row"])
        #expect(upper.exercises[0].sets.map(\.note) == ["felt easy", ""])
        #expect(upper.exercises[0].sets.first?.weightKg == 135 * pound)
        #expect(result.allWorkouts[1].exercises[0].sets.map(\.isWarmup) == [true, false])
    }

    @Test("Generic: date-only values without a name column make one workout per day")
    func genericPerDay() throws {
        let file = try ImportFile(data: F.csv("Day,Lift,Kg,Reps\n2025-05-01,Squat,100,5\n2025-05-01,Bench,70,5\n2025-05-02,Deadlift,140,3\n"))
        let mapping = GenericMapping.suggested(header: file.table.header, sampleRows: file.table.rows)
        #expect(mapping.roles == [.date, .exercise, .weight, .reps])
        let result = try F.parse(file, options: F.options(weightUnit: .lb, mapping: mapping))
        #expect(result.weightUnitSource == .header(.kg))
        #expect(result.allWorkouts.count == 2)
        #expect(result.allWorkouts[0].exercises.map(\.name) == ["Squat", "Bench"])
        #expect(result.allWorkouts[0].startedAt == F.date(2025, 5, 1))
    }

    @Test("Generic: a unit column, or the chosen unit when there is none")
    func genericUnits() throws {
        let withColumn = try ImportFile(data: F.csv("Date,Exercise,Weight,Unit,Reps\n2025-05-01,Squat,100,lbs,5\n2025-05-01,Squat,50,kg,5\n"))
        let columnMapping = GenericMapping.suggested(header: withColumn.table.header, sampleRows: withColumn.table.rows)
        #expect(columnMapping.column(for: .weightUnit) == 3)
        let first = try F.parse(withColumn, options: F.options(mapping: columnMapping))
        #expect(first.weightUnitSource == .column)
        #expect(first.workouts[0].exercises[0].sets.map(\.weightKg) == [100 * pound, 50])

        let without = try ImportFile(data: F.csv("Date,Exercise,Weight,Reps\n2025-05-01,Squat,100,5\n"))
        let mapping = GenericMapping.suggested(header: without.table.header, sampleRows: without.table.rows)
        let second = try F.parse(without, options: F.options(weightUnit: .lb, mapping: mapping))
        #expect(second.weightUnitSource == .chosen(.lb))
        #expect(second.workouts[0].exercises[0].sets.first?.weightKg == 100 * pound)
    }

    // MARK: Rows not read

    @Test("Unreadable rows are reported with their reason, never dropped")
    func unreadableRows() throws {
        let text = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2025-01-02 10:00:00,A,30m,Squat,1,100,5,0,0,,,
        not a date,A,30m,Squat,2,100,5,0,0,,,
        2025-01-02 10:00:00,A,30m,Squat,3,-100,5,0,0,,,
        2025-01-02 10:00:00,A,30m,Squat,4,lots,5,0,0,,,
        2025-01-02 10:00:00,A,30m,,5,100,5,0,0,,,
        2025-01-02 10:00:00,A,30m,Squat,6,,,0,0,,,
        2025-01-02 10:00:00,A,30m,Squat,7,100,7.5,0,0,,,
        """
        let result = try F.parse(ImportFile(data: F.csv(text)))
        #expect(result.skippedRows.map(\.line) == [3, 4, 5, 6, 7, 8])
        #expect(result.skippedRows.map(\.reason) == [.unreadableDate, .unreadableNumber, .unreadableNumber, .missingExercise, .noSetData, .unreadableNumber])
        #expect(result.skippedByReason.first?.reason == .unreadableNumber)
        #expect(result.skippedByReason.first?.rows.count == 3)
        #expect(result.setCount == 1)
    }

    @Test("A file whose dates the user must order asks, then reads with the chosen order")
    func dateOrderRoundTrip() throws {
        let text = """
        Date,Exercise,Reps
        03/04/2025,Squat,5
        05/04/2025,Bench,5
        """
        let file = try ImportFile(data: F.csv(text))
        let mapping = GenericMapping.suggested(header: file.table.header, sampleRows: file.table.rows)
        guard case .needsDateOrder(let sample) = file.parse(F.options(mapping: mapping)) else {
            Issue.record("Expected a date-order question")
            return
        }
        #expect(sample == "03/04/2025")
        let dayFirst = try F.parse(file, options: F.options(dateOrder: .dayMonthYear, mapping: mapping))
        #expect(dayFirst.allWorkouts.map(\.startedAt) == [F.date(2025, 4, 3), F.date(2025, 4, 5)])
        #expect(dayFirst.dateReading.wasChosen)
        let monthFirst = try F.parse(file, options: F.options(dateOrder: .monthDayYear, mapping: mapping))
        #expect(monthFirst.allWorkouts.map(\.startedAt) == [F.date(2025, 3, 4), F.date(2025, 5, 4)])
    }

    @Test("Results do not depend on the machine's time zone, only on the one given")
    func zoneIndependent() throws {
        var options = F.options()
        options.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        options.calendar = F.calendar(options.timeZone)
        let kolkata = try F.parse("strong-1c", options: options)
        // The start instant follows the zone, but the key is the wall-clock time the file
        // says, so importing the same file again in another zone finds the same workouts.
        let berlin = try F.parse("strong-1c")
        #expect(kolkata.allWorkouts[0].startedAt != berlin.allWorkouts[0].startedAt)
        #expect(kolkata.allWorkouts.map(\.externalKey) == berlin.allWorkouts.map(\.externalKey))
        #expect(kolkata.allWorkouts[0].externalKey == "2026-05-10T09:15:00|full body 2")
        let plan = ImportPlan(workouts: kolkata.allWorkouts, existingKeys: Set(berlin.allWorkouts.map(\.externalKey)))
        #expect(plan.insertCount == 0)
        // Zoned formats do not move.
        let fitbod = try F.parse("fitbod", options: options)
        #expect(fitbod.allWorkouts[0].startedAt == F.date(2023, 6, 2, 17, 12, 40, zone: .gmt))
        #expect(fitbod.allWorkouts[0].externalKey == "2023-06-02T17:12:40Z|")
    }
}
