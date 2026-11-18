// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation
import SwiftData
import WholesetKit

/// Invented exports in each app's header layout, for the import demo states. Workouts are
/// dated in the weeks before today so they sit at the top of History after an import.
enum DemoImportFiles {
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func day(_ daysAgo: Int, hour: Int, minute: Int, now: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// "15 Oct 2026, 18:05", the way the Hevy app writes dates in English.
    private static func hevyDate(_ date: Date) -> String {
        date.formatted(Date.VerbatimFormatStyle(
            format: "\(day: .defaultDigits) \(month: .abbreviated) \(year: .defaultDigits), \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: posix,
            timeZone: .current,
            calendar: Calendar(identifier: .gregorian)
        ))
    }

    /// A Hevy export in kilograms: three repeated workouts over five weeks, with names that
    /// match, need a check or become custom exercises, and cardio rows that are not read.
    static func hevy(now: Date = .now) -> Data {
        typealias Set = (type: String, weight: String, reps: String, distance: String, seconds: String)
        func lift(_ weight: Double, _ reps: Int, warmup: Bool = false) -> Set {
            (warmup ? "warmup" : "normal", weight.formatted(.number.locale(posix).grouping(.never)), "\(reps)", "", "")
        }
        func cardio(_ distance: String, _ seconds: String) -> Set { ("normal", "", "", distance, seconds) }
        func bodyweight(_ reps: Int) -> Set { ("normal", "", "\(reps)", "", "") }

        var workouts: [(title: String, start: Date, minutes: Int, note: String, exercises: [(String, [Set])])] = []
        for (week, daysAgo) in [3, 10, 17, 24].enumerated() {
            let add = Double(3 - week) * 2.5
            workouts.append(("Upper A", day(daysAgo, hour: 18, minute: 5, now: now), 64, week == 0 ? "Long warm-up, shoulder felt fine" : "", [
                ("Bench Press (Barbell)", [lift(40, 10, warmup: true), lift(70 + add, 8), lift(70 + add, 8), lift(70 + add, 7)]),
                ("Cable Crossover", [lift(15, 12), lift(15, 12), lift(15, 11)]),
                ("Triceps Extension (Cable)", [lift(20, 12), lift(20, 12), lift(22.5, 10)]),
                ("Pull Up", [bodyweight(8), bodyweight(7), bodyweight(6)]),
            ]))
        }
        for (week, daysAgo) in [5, 12, 19].enumerated() {
            let add = Double(2 - week) * 5
            workouts.append(("Lower A", day(daysAgo, hour: 7, minute: 40, now: now), 58, "", [
                ("Squat (Barbell)", [lift(60, 5, warmup: true), lift(100 + add, 5), lift(100 + add, 5), lift(100 + add, 5)]),
                ("Hip Thrust (Machine)", [lift(80, 10), lift(80, 10), lift(80, 9)]),
                ("Zercher Squat", [lift(60, 8), lift(60, 8)]),
                ("Treadmill", [cardio("1.6", "600")]),
            ]))
        }
        for (week, daysAgo) in [7, 14, 21, 28].enumerated() {
            let add = Double(3 - week) * 5
            workouts.append(("Full Body", day(daysAgo, hour: 12, minute: 15, now: now), 71, "", [
                ("Deadlift (Barbell)", [lift(120 + add, 5), lift(120 + add, 5), lift(120 + add, 5)]),
                ("Overhead Press (Barbell)", [lift(40, 8), lift(40, 8), lift(40, 7)]),
                ("Lat Pulldown (Cable)", [lift(55, 10), lift(55, 10), lift(55, 9)]),
                ("Plank", [cardio("", "60")]),
            ]))
        }
        workouts.sort { $0.start > $1.start }

        var lines = ["\"title\",\"start_time\",\"end_time\",\"description\",\"exercise_title\",\"superset_id\",\"exercise_notes\",\"set_index\",\"set_type\",\"weight_kg\",\"reps\",\"distance_km\",\"duration_seconds\",\"rpe\""]
        for workout in workouts {
            let start = hevyDate(workout.start)
            let end = hevyDate(workout.start.addingTimeInterval(Double(workout.minutes) * 60))
            for (name, sets) in workout.exercises {
                for (index, set) in sets.enumerated() {
                    lines.append("\"\(workout.title)\",\"\(start)\",\"\(end)\",\"\(workout.note)\",\"\(name)\",,\"\",\(index),\"\(set.type)\",\(set.weight),\(set.reps),\(set.distance),\(set.seconds),")
                }
            }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// An old Strong export with no unit anywhere.
    static func strongNoUnit(now: Date = .now) -> Data {
        var lines = ["Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE"]
        for (index, daysAgo) in [2, 6, 9].enumerated() {
            let start = day(daysAgo, hour: 6, minute: 30, now: now).formatted(Date.VerbatimFormatStyle(
                format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
                locale: posix,
                timeZone: .current,
                calendar: Calendar(identifier: .gregorian)
            ))
            let squat = 185 + index * 5
            lines += [
                "\(start),\"Morning Session\",52m,\"Squat (Barbell)\",W,95.0,5,0,0,\"\",\"\",",
                "\(start),\"Morning Session\",52m,\"Squat (Barbell)\",1,\(squat).0,5,0,0,,,8",
                "\(start),\"Morning Session\",52m,\"Squat (Barbell)\",2,\(squat).0,5,0,0,,,8.5",
                "\(start),\"Morning Session\",52m,\"Bench Press (Barbell)\",1,135.0,8,0,0,,,",
                "\(start),\"Morning Session\",52m,\"Bench Press (Barbell)\",2,135.0,7,0,0,,,",
            ]
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// A Hevy export whose numeric dates could be day-first or month-first.
    static func hevyNumericDates() -> Data {
        let header = "title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe"
        let rows = [
            ("Push", "02/03/2026 18:00", "02/03/2026 19:02", "Incline Bench Press (Dumbbell)", "26", "10"),
            ("Pull", "05/03/2026 18:10", "05/03/2026 19:05", "Seated Cable Row - V Grip (Cable)", "60", "12"),
            ("Push", "09/03/2026 18:05", "09/03/2026 19:00", "Incline Bench Press (Dumbbell)", "28", "8"),
        ]
        let lines = [header] + rows.flatMap { row in
            (0..<3).map { "\(row.0),\(row.1),\(row.2),,\(row.3),,,\($0),normal,\(row.4),\(row.5),,," }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// Another app's CSV, with its own column names.
    static func generic() -> Data {
        let lines = [
            "Logged On,Lift,Load (lb),Reps,Program Day,Remarks,Set,Bar Speed",
            "2026-09-01 17:30,Front squat,155,5,Day 1,,1,0.61",
            "2026-09-01 17:30,Front squat,155,5,Day 1,,2,0.58",
            "2026-09-01 17:30,Pendlay row,135,6,Day 1,fast pulls,1,",
            "2026-09-03 17:45,Push press,115,5,Day 2,,1,0.74",
            "2026-09-03 17:45,Chin-up,0,8,Day 2,,1,",
        ]
        return Data(lines.joined(separator: "\n").utf8)
    }
}

/// Drives the import flow into the screen a demo state shows.
enum DemoImportDriver {
    /// Puts `flow` where `state` wants it, reading and importing the demo files.
    static func drive(_ flow: ImportFlowModel, to state: DemoState, container: ModelContainer, navigation: AppNavigation) async {
        switch state {
        case .importStart:
            break
        case .importHow:
            flow.path = [.howTo(.hevy)]
        case .importDetected:
            await flow.load(DemoImportFiles.hevy(), fileName: "workouts.csv")
        case .importUnit:
            await flow.load(DemoImportFiles.strongNoUnit(), fileName: "strong.csv")
        case .importDateOrder:
            await flow.load(DemoImportFiles.hevyNumericDates(), fileName: "workouts.csv")
        case .importColumns:
            await flow.load(DemoImportFiles.generic(), fileName: "training-log.csv")
        case .importMatch, .importMatchAll, .importProgress:
            await flow.load(DemoImportFiles.hevy(), fileName: "workouts.csv")
            flow.showsAllMatches = state == .importMatchAll
            flow.reviewExercises()
            if state == .importProgress {
                flow.showProgressForDemo(saved: 4, total: flow.plan?.insertCount ?? 9)
            }
        case .importDone, .importRowsNotRead, .historyImported:
            await importEarlierExport(into: container)
            await flow.load(DemoImportFiles.hevy(), fileName: "workouts.csv")
            flow.reviewExercises()
            flow.startImport()
            await flow.waitForWork()
            if state == .importRowsNotRead {
                flow.path = [.rowsNotRead]
            }
            if state == .historyImported {
                navigation.importFlow = nil
            }
        default:
            break
        }
    }

    /// Imports the two oldest demo workouts first, as an earlier export would have, so the
    /// summary shows workouts skipped as already in Wholeset.
    private static func importEarlierExport(into container: ModelContainer) async {
        guard case .parsed(let result)? = try? ImportFile(data: DemoImportFiles.hevy()).parse(ImportOptions()) else { return }
        let oldest = result.workouts.sorted { $0.startedAt < $1.startedAt }.prefix(2)
        guard let library = try? ExerciseLibrary.bundled() else { return }
        let context = ModelContext(container)
        let matcher = ExerciseMatcher(candidates: ExerciseCandidate.all(exercises: (try? context.fetch(FetchDescriptor<Exercise>())) ?? [], library: library))
        let resolutions = Dictionary(uniqueKeysWithValues: result.exerciseNames.map { ($0.name, ExerciseResolution(matcher.match($0.name))) })
        let request = ImportWriteRequest(workouts: Array(oldest), source: .importHevy, resolutions: resolutions, library: library)
        _ = try? await ImportWriter.write(request, to: container)
    }
}
#endif
