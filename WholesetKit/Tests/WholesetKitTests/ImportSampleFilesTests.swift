// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

/// Reads a local folder of real exports, when one is given. Nothing from those files is part
/// of the repository: set `WHOLESET_IMPORT_SAMPLES_DIR` to run it.
@Suite("Import: real export samples (local only)")
struct ImportSampleFilesTests {
    static let directory = ProcessInfo.processInfo.environment["WHOLESET_IMPORT_SAMPLES_DIR"]

    @Test("Every sample is detected and parsed", .enabled(if: directory != nil))
    func parsesEverySample() throws {
        let root = URL(filePath: try #require(Self.directory), directoryHint: .isDirectory)
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "csv" }
            .sorted { $0.path < $1.path }
        #expect(!files.isEmpty)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let formatter = Date.FormatStyle(date: .numeric, time: .omitted, locale: Locale(identifier: "en_GB"), calendar: calendar, timeZone: .gmt)
        let matcher = ExerciseMatcher(candidates: ExerciseCandidate.all(exercises: [], library: try ExerciseLibrary.bundled()))
        print("file | layout | encoding | workouts | sets | empty | rows not read | dates | unit | names matched/check/new | ms")
        for url in files {
            let name = url.pathComponents.suffix(2).joined(separator: "/")
            let started = ContinuousClock.now
            let file = try ImportFile(data: Data(contentsOf: url))
            var options = ImportOptions(weightUnit: .kg, timeZone: .gmt, calendar: calendar)
            if file.layout == .generic {
                options.mapping = GenericMapping.suggested(header: file.table.header, sampleRows: file.table.rows.prefix(50))
            }
            var outcome = file.parse(options)
            var dateNote = ""
            if case .needsDateOrder(let sample) = outcome {
                dateNote = "asked (\(sample)), dmy "
                options.dateOrder = .dayMonthYear
                outcome = file.parse(options)
            }
            let elapsed = started.duration(to: .now)
            switch outcome {
            case .parsed(let result):
                let reasons = result.skippedByReason.map { "\($0.reason.rawValue) \($0.rows.count)" }.joined(separator: ", ")
                let range = result.dateRange.map { "\($0.lowerBound.formatted(formatter))–\($0.upperBound.formatted(formatter))" } ?? "–"
                let unit = switch result.weightUnitSource {
                case .header(let unit): "header \(unit.rawValue)"
                case .column: "column \(result.stats.unitsFound.map(\.rawValue).joined(separator: "+"))" + (result.stats.rowsWithAssumedUnit > 0 ? " (\(result.stats.rowsWithAssumedUnit) assumed)" : "")
                case .chosen(let unit): "chosen \(unit.rawValue)"
                }
                let order = result.dateReading.order.map { " \($0.rawValue)" } ?? ""
                var matches = (matched: 0, check: 0, new: 0)
                for (exerciseName, _) in result.exerciseNames {
                    switch matcher.match(exerciseName) {
                    case .matched: matches.matched += 1
                    case .check: matches.check += 1
                    case .newCustom: matches.new += 1
                    }
                }
                print("\(name) | \(result.layout.identifier) | \(result.encoding.rawValue) | \(result.workoutCount) | \(result.setCount) | \(ImportPlan(workouts: result.allWorkouts, existingKeys: []).emptyWorkouts) | \(reasons.isEmpty ? "0" : reasons) | \(dateNote)\(range)\(order) | \(unit) | \(matches.matched)/\(matches.check)/\(matches.new) | \(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)")
                if [.strong, .hevy, .fitNotes].contains(result.format) {
                    #expect(result.workoutCount > 0, "\(name) parsed to no workouts")
                }
            case .needsColumnMapping:
                print("\(name) | \(file.layout.identifier) | generic, no usable column guess")
            case .needsDateOrder(let sample), .unreadableDates(let sample):
                print("\(name) | \(file.layout.identifier) | dates unreadable: \(sample)")
                #expect(file.layout.format == .generic, "\(name): dates unreadable")
            }
        }
    }
}
