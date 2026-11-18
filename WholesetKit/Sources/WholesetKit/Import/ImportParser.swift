// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Choices that shape how a file is read.
public struct ImportOptions: Sendable, Equatable {
    /// The unit of weights in files that do not say (Strong's oldest layout, generic files
    /// without a unit). Usually the user's display unit.
    public var weightUnit: WeightUnit
    /// The order of ambiguous all-numeric dates, once the user has chosen it.
    public var dateOrder: DateOrder?
    /// The zone of wall-clock dates.
    public var timeZone: TimeZone
    /// A Gregorian calendar used to build dates.
    public var calendar: Calendar
    /// The columns of a generic file.
    public var mapping: GenericMapping?

    /// Creates options.
    public init(
        weightUnit: WeightUnit = .kg,
        dateOrder: DateOrder? = nil,
        timeZone: TimeZone = .current,
        calendar: Calendar = Calendar(identifier: .gregorian),
        mapping: GenericMapping? = nil
    ) {
        self.weightUnit = weightUnit
        self.dateOrder = dateOrder
        self.timeZone = timeZone
        self.calendar = calendar
        self.mapping = mapping
    }
}

/// What reading a file's rows gave.
public enum ImportParseOutcome: Sendable {
    /// The workouts and everything that was not read.
    case parsed(ImportParseResult)
    /// All-numeric dates whose order the file cannot tell; parse again with
    /// ``ImportOptions/dateOrder`` set. `sample` is a date as written.
    case needsDateOrder(sample: String)
    /// A generic file without a complete ``GenericMapping``.
    case needsColumnMapping
    /// No date in the file could be read, even with the chosen order.
    case unreadableDates(sample: String)
}

/// A CSV file with its recognised layout: what the import screens work from.
public struct ImportFile: Sendable {
    /// The file's rows.
    public let table: CSVTable
    /// Its layout.
    public let layout: ImportLayout

    /// Creates a file from a table, detecting its layout.
    public init(table: CSVTable) {
        self.table = table
        self.layout = ImportFormatDetector.detect(table.header)
    }

    /// Reads and recognises `data`.
    public init(data: Data) throws(CSVReader.ReadError) {
        self.init(table: try CSVReader.read(data))
    }

    /// Reads `data` off the caller's actor.
    @concurrent
    public static func load(_ data: Data) async throws(CSVReader.ReadError) -> ImportFile {
        try ImportFile(data: data)
    }

    /// Reads the workouts.
    public func parse(_ options: ImportOptions) -> ImportParseOutcome {
        ImportParser.parse(table, layout: layout, options: options)
    }

    /// Reads the workouts off the caller's actor.
    @concurrent
    public func parseInBackground(_ options: ImportOptions) async -> ImportParseOutcome {
        parse(options)
    }

    /// Where weights' unit comes from with `options`.
    public func weightUnitSource(_ options: ImportOptions) -> WeightUnitSource {
        ImportParser.weightUnitSource(layout: layout, header: table.header, options: options)
    }
}

/// Turns a table's rows into workouts, for every layout.
public enum ImportParser {
    /// Reads `table` as `layout`.
    ///
    /// Dates are decided once for the whole file (see ``ImportDateParser/detect(_:order:)``),
    /// then every row is read; rows that do not hold a set are listed in
    /// ``ImportParseResult/skippedRows`` with their reason.
    public static func parse(_ table: CSVTable, layout: ImportLayout, options: ImportOptions) -> ImportParseOutcome {
        guard let reader = makeReader(layout: layout, header: table.header, options: options) else {
            return .needsColumnMapping
        }
        let dates = ImportDateParser(timeZone: options.timeZone, calendar: options.calendar)
        var texts: [String] = []
        texts.reserveCapacity(table.rows.count)
        for row in table.rows {
            if let start = reader.startText(of: row) { texts.append(start) }
            if let end = reader.endText(of: row) { texts.append(end) }
        }
        let reading: DateReading
        switch dates.detect(texts, order: options.dateOrder) {
        case .readable(let found): reading = found
        case .needsDateOrder(let sample): return .needsDateOrder(sample: sample)
        case .unreadable(let sample): return .unreadableDates(sample: sample)
        }

        var cache: [String: Date?] = [:]
        func date(_ text: String) -> Date? {
            if let cached = cache[text] { return cached }
            let parsed = dates.date(from: text, order: reading.order)
            cache[text] = parsed
            return parsed
        }

        // Whether a start carries its own zone decides how its workout's key is written.
        var zoned: [String: Bool] = [:]
        func hasZone(_ text: String) -> Bool {
            if let known = zoned[text] { return known }
            let found = ImportDateParser.analyze(text)?.zone != nil
            zoned[text] = found
            return found
        }

        var assembler = WorkoutAssembler(ordersBySetIndex: reader.ordersBySetIndex)
        var units = UnitTally()
        for row in table.rows {
            guard let startText = reader.startText(of: row), let start = date(startText) else {
                assembler.skip(line: row.line, reason: .unreadableDate, text: table.rawText(of: row))
                continue
            }
            let end = reader.endText(of: row).flatMap(date)
            let record = reader.record(for: row, start: start, end: end, units: &units)
            let wallClockZone = hasZone(startText) ? nil : options.timeZone
            assembler.add(record, start: start, wallClockZone: wallClockZone, line: row.line) { table.rawText(of: row) }
        }

        var stats = ImportStats()
        stats.rowCount = table.rows.count
        stats.ignoredRowCount = assembler.ignoredCount
        stats.raggedRowCount = table.raggedLines.count
        stats.rowsWithAssumedUnit = units.assumed
        stats.unitsFound = units.counts.sorted { $0.value > $1.value }.map(\.key)

        return .parsed(ImportParseResult(
            layout: layout,
            allWorkouts: assembler.workouts(),
            skippedRows: assembler.skipped,
            weightUnitSource: weightUnitSource(layout: layout, header: table.header, options: options),
            dateReading: reading,
            encoding: table.encoding,
            stats: stats
        ))
    }

    /// Where weights' unit comes from for `layout`.
    static func weightUnitSource(layout: ImportLayout, header: CSVHeader, options: ImportOptions) -> WeightUnitSource {
        if let unit = layout.headerWeightUnit { return .header(unit) }
        if layout.hasUnitColumn { return .column }
        if case .generic = layout, let mapping = options.mapping {
            return mapping.weightUnitSource(in: header, chosen: options.weightUnit)
        }
        return .chosen(options.weightUnit)
    }

    private static func makeReader(layout: ImportLayout, header: CSVHeader, options: ImportOptions) -> (any ImportRowReader)? {
        switch layout {
        case .hevy(let unit):
            return HevyRows(header: header, unit: unit)
        case .strongNoUnit, .strongUnitColumn, .strongNumbered, .strongUnitHeader:
            return StrongRows(header: header, layout: layout, fallbackUnit: options.weightUnit)
        case .fitNotesUnitHeader, .fitNotesUnitColumn:
            return FitNotesRows(header: header, layout: layout, fallbackUnit: options.weightUnit)
        case .fitbod:
            return FitbodRows(header: header)
        case .strongLifts(let unit):
            return StrongLiftsRows(header: header, unit: unit)
        case .liftosaur(let isCurrent):
            return LiftosaurRows(header: header, isCurrent: isCurrent, fallbackUnit: options.weightUnit)
        case .generic:
            guard let mapping = options.mapping, mapping.isComplete, mapping.roles.count == header.count else { return nil }
            return GenericRows(header: header, mapping: mapping, fallbackUnit: options.weightUnit)
        }
    }
}

// MARK: - Rows

/// What one row of a file says, whatever the layout.
struct RowRecord {
    /// Rows with the same key belong to one workout.
    var groupKey: String
    var workoutName = ""
    var workoutNotes = ""
    /// When the workout ended, if the row says.
    var end: Date?
    /// How long the workout lasted, if the row says.
    var durationSeconds: Int?
    var exerciseName = ""
    var exerciseNote = ""
    /// The set's position within its exercise, when the file numbers sets.
    var setIndex: Int?
    var content: Content

    enum Content {
        /// One or more sets (StrongLifts rows hold a whole exercise).
        case sets([ImportedSet])
        /// A row that should have been a set but is not.
        case skip(SkipReason)
        /// A row holding only the exercise's note.
        case note
        /// A row that never holds a set (a Strong rest timer).
        case ignore
    }
}

/// Counts units found in a unit column.
struct UnitTally {
    var counts: [WeightUnit: Int] = [:]
    /// Rows with a weight but no readable unit.
    var assumed = 0
    /// The unit of the last row that had one.
    private var last: WeightUnit?

    /// The unit of a row: its own if readable; else the unit of the rows before it (exports
    /// use one unit per account), else `fallback`. Rows with a weight and no unit are counted.
    mutating func unit(_ text: String, fallback: WeightUnit, hasWeight: Bool) -> WeightUnit {
        if let unit = ImportValues.weightUnit(text) {
            if hasWeight {
                counts[unit, default: 0] += 1
                last = unit
            }
            return unit
        }
        if hasWeight { assumed += 1 }
        return last ?? fallback
    }
}

/// Reads the rows of one layout.
protocol ImportRowReader {
    /// Whether sets are ordered by ``RowRecord/setIndex`` (Hevy) rather than by row.
    var ordersBySetIndex: Bool { get }
    /// The text of the row's workout start (date and time), if any.
    func startText(of row: CSVRow) -> String?
    /// The text of the row's workout end, if the layout has one.
    func endText(of row: CSVRow) -> String?
    /// Reads the row; its start and end are already parsed.
    func record(for row: CSVRow, start: Date, end: Date?, units: inout UnitTally) -> RowRecord
}

extension ImportRowReader {
    var ordersBySetIndex: Bool { false }
    func endText(of row: CSVRow) -> String? { nil }
}

// MARK: - Assembly

/// Groups row records into workouts and exercises, in file order.
///
/// Rows join the workout of their ``RowRecord/groupKey`` wherever they are in the file.
/// Within a workout, consecutive rows of the same exercise form one exercise; a different
/// exercise in between (or, with set numbers, a number that does not increase) starts a new one.
struct WorkoutAssembler {
    let ordersBySetIndex: Bool
    /// Builders in order of their first row; mutated in place, never copied out.
    private var builders: [WorkoutBuilder] = []
    private var positions: [String: Int] = [:]
    private(set) var skipped: [SkippedRow] = []
    private(set) var ignoredCount = 0

    init(ordersBySetIndex: Bool) {
        self.ordersBySetIndex = ordersBySetIndex
    }

    struct ExerciseBuilder {
        var name: String
        var notes: [String] = []
        var sets: [(index: Int?, set: ImportedSet)] = []
        var lastIndex: Int?
    }

    struct WorkoutBuilder {
        var name = ""
        var start: Date
        var end: Date?
        var duration: Int?
        var notes: [String] = []
        var exercises: [ExerciseBuilder] = []
        /// The exercise of the previous row, set or not.
        var previousExercise: String?
        var firstLine: Int
        /// The zone a start without its own was read in (for the key).
        var wallClockZone: TimeZone?
    }

    mutating func skip(line: Int, reason: SkipReason, text: String) {
        skipped.append(SkippedRow(line: line, reason: reason, text: text))
    }

    mutating func add(_ record: RowRecord, start: Date, wallClockZone: TimeZone? = nil, line: Int, text: () -> String) {
        if case .ignore = record.content {
            ignoredCount += 1
            return
        }
        let position: Int
        if let existing = positions[record.groupKey] {
            position = existing
        } else {
            position = builders.count
            positions[record.groupKey] = position
            builders.append(WorkoutBuilder(start: start, firstLine: line, wallClockZone: wallClockZone))
        }
        if case .skip(let reason) = record.content {
            skipped.append(SkippedRow(line: line, reason: reason, text: text()))
        }
        Self.apply(record, to: &builders[position], ordersBySetIndex: ordersBySetIndex)
    }

    private static func apply(_ record: RowRecord, to builder: inout WorkoutBuilder, ordersBySetIndex: Bool) {
        if builder.name.isEmpty, !record.workoutName.isEmpty { builder.name = record.workoutName }
        append(record.workoutNotes, to: &builder.notes)
        if builder.end == nil { builder.end = record.end }
        if builder.duration == nil, let duration = record.durationSeconds, duration > 0 { builder.duration = duration }

        switch record.content {
        case .ignore:
            return
        case .skip:
            if !record.exerciseNote.isEmpty, !record.exerciseName.isEmpty {
                append("\(record.exerciseName): \(record.exerciseNote)", to: &builder.notes)
            }
            builder.previousExercise = record.exerciseName
        case .note:
            let index = exerciseIndex(for: record, in: &builder, ordersBySetIndex: ordersBySetIndex)
            append(record.exerciseNote, to: &builder.exercises[index].notes)
        case .sets(let sets):
            let index = exerciseIndex(for: record, in: &builder, ordersBySetIndex: ordersBySetIndex)
            append(record.exerciseNote, to: &builder.exercises[index].notes)
            for set in sets {
                builder.exercises[index].sets.append((record.setIndex, set))
            }
            if let setIndex = record.setIndex { builder.exercises[index].lastIndex = setIndex }
        }
    }

    /// The exercise a record continues, or a new one.
    private static func exerciseIndex(for record: RowRecord, in builder: inout WorkoutBuilder, ordersBySetIndex: Bool) -> Int {
        defer { builder.previousExercise = record.exerciseName }
        if let last = builder.exercises.indices.last,
           builder.exercises[last].name == record.exerciseName,
           builder.previousExercise == record.exerciseName {
            var restarts = false
            if ordersBySetIndex, let index = record.setIndex, let previous = builder.exercises[last].lastIndex {
                restarts = index <= previous
            }
            if !restarts { return last }
        }
        builder.exercises.append(ExerciseBuilder(name: record.exerciseName))
        return builder.exercises.count - 1
    }

    private static func append(_ note: String, to notes: inout [String]) {
        let trimmed = note.trimmed
        guard !trimmed.isEmpty, !notes.contains(trimmed) else { return }
        notes.append(trimmed)
    }

    /// The workouts in order of their first row.
    func workouts() -> [ImportedWorkout] {
        builders.map { builder in
            var notes = builder.notes
            var exercises: [ImportedExercise] = []
            for exercise in builder.exercises {
                let note = exercise.notes.joined(separator: "\n")
                guard !exercise.sets.isEmpty else {
                    if !note.isEmpty { notes.append("\(exercise.name): \(note)") }
                    continue
                }
                var sets = exercise.sets
                if ordersBySetIndex {
                    sets = sets.enumerated()
                        .sorted { lhs, rhs in
                            let left = lhs.element.index ?? Int.max
                            let right = rhs.element.index ?? Int.max
                            return left != right ? left < right : lhs.offset < rhs.offset
                        }
                        .map(\.element)
                }
                exercises.append(ImportedExercise(name: exercise.name, note: note, sets: sets.map(\.set)))
            }
            let end: Date? = if let end = builder.end, end > builder.start {
                end
            } else if let duration = builder.duration {
                builder.start.addingTimeInterval(TimeInterval(duration))
            } else {
                nil
            }
            return ImportedWorkout(
                name: builder.name,
                startedAt: builder.start,
                endedAt: end,
                notes: notes.joined(separator: "\n"),
                exercises: exercises,
                firstLine: builder.firstLine,
                wallClockZone: builder.wallClockZone
            )
        }
    }
}
