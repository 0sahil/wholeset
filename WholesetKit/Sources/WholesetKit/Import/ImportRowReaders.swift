// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Builds a row's content from its measurements, the same way for every layout.
enum SetContent {
    /// A set when the row has reps; otherwise the reason it is not one. Unreadable or
    /// negative numbers skip the row; an unreadable RPE is only dropped.
    ///
    /// - Parameters:
    ///   - weight: The weight in the file's unit.
    ///   - kilograms: Converts a positive weight to kilograms.
    ///   - distance: The distance in the file's unit.
    ///   - metresPerDistanceUnit: Converts it to metres; `nil` when the unit is unknown (the
    ///     distance then only decides whether the row is cardio).
    static func make(
        weight: FieldValue<Double>,
        kilograms: (Double) -> Double,
        reps: FieldValue<Int>,
        duration: FieldValue<Int> = .empty,
        distance: FieldValue<Double> = .empty,
        metresPerDistanceUnit: Double? = nil,
        rpe: FieldValue<Double> = .empty,
        isWarmup: Bool = false,
        kind: ImportedSet.Kind = .normal,
        note: String = "",
        line: Int
    ) -> RowRecord.Content {
        guard !weight.isInvalid, !reps.isInvalid, !duration.isInvalid, !distance.isInvalid else {
            return .skip(.unreadableNumber)
        }
        let weightKg = weight.value.flatMap { $0 > 0 ? kilograms($0) : nil }
        let seconds = duration.value.flatMap { $0 > 0 ? $0 : nil }
        let rawDistance = distance.value.flatMap { $0 > 0 ? $0 : nil }
        if let reason = ImportValues.classify(weightKg: weightKg, reps: reps.value, durationSeconds: seconds, distanceMeters: rawDistance) {
            return .skip(reason)
        }
        let metres = rawDistance.flatMap { value in metresPerDistanceUnit.map { value * $0 } }
        return .sets([ImportedSet(
            weightKg: weightKg,
            reps: reps.value,
            durationSeconds: seconds,
            distanceMeters: metres,
            isWarmup: isWarmup,
            kind: kind,
            rpe: rpe.value,
            note: note,
            line: line
        )])
    }
}

/// A non-empty string or `nil`.
private func nonEmpty(_ text: String) -> String? {
    text.isEmpty ? nil : text
}

/// Separates the parts of a grouping key.
private let keySeparator = "\u{1F}"

// MARK: - Hevy

/// Hevy: one row per set; workouts keyed by (title, start_time); `set_index` 0-based.
struct HevyRows: ImportRowReader {
    let unit: WeightUnit
    let title, start, end, description, exercise, exerciseNotes, setIndex, setType: Int?
    let weight, reps, distance, duration, rpe: Int?
    let metresPerDistanceUnit: Double

    init(header: CSVHeader, unit: WeightUnit) {
        self.unit = unit
        title = header.index(of: "title")
        start = header.index(of: "start_time")
        end = header.index(of: "end_time")
        description = header.index(of: "description")
        exercise = header.index(of: "exercise_title")
        exerciseNotes = header.index(of: "exercise_notes")
        setIndex = header.index(of: "set_index")
        setType = header.index(of: "set_type")
        weight = header.index(ofAny: unit == .kg ? ["weight_kg"] : ["weight_lbs"])
        reps = header.index(of: "reps")
        if let miles = header.index(of: "distance_miles") {
            distance = miles
            metresPerDistanceUnit = 1_609.344
        } else {
            distance = header.index(of: "distance_km")
            metresPerDistanceUnit = 1_000
        }
        duration = header.index(of: "duration_seconds")
        rpe = header.index(of: "rpe")
    }

    var ordersBySetIndex: Bool { true }

    func startText(of row: CSVRow) -> String? { nonEmpty(row.trimmed(start)) }

    func endText(of row: CSVRow) -> String? { nonEmpty(row.trimmed(end)) }

    func record(for row: CSVRow, start startDate: Date, end: Date?, units: inout UnitTally) -> RowRecord {
        let name = row.trimmed(title)
        var record = RowRecord(groupKey: name + keySeparator + row.trimmed(start), content: .ignore)
        record.workoutName = name
        record.workoutNotes = row.trimmed(description)
        record.end = end
        record.exerciseName = row.trimmed(exercise)
        record.exerciseNote = row.trimmed(exerciseNotes)
        record.setIndex = ImportValues.count(row.trimmed(setIndex)).value
        guard !record.exerciseName.isEmpty else {
            record.content = .skip(.missingExercise)
            return record
        }
        let type = row.trimmed(setType).lowercased()
        let kind: ImportedSet.Kind = switch type {
        case "dropset", "drop", "drop_set": .drop
        case "failure": .failure
        default: .normal
        }
        let unit = unit
        record.content = SetContent.make(
            weight: ImportValues.decimal(row.trimmed(weight)),
            kilograms: { unit.kilograms(fromValue: $0) },
            reps: ImportValues.count(row.trimmed(reps)),
            duration: ImportValues.duration(row.trimmed(duration)),
            distance: ImportValues.decimal(row.trimmed(distance)),
            metresPerDistanceUnit: metresPerDistanceUnit,
            rpe: ImportValues.rpe(row.trimmed(rpe)),
            isWarmup: type == "warmup" || type == "warm_up" || type == "warm-up",
            kind: kind,
            line: row.line
        )
        return record
    }
}

// MARK: - Strong

/// Strong, all four layouts: one row per set, plus rest-timer and note rows that are not sets.
struct StrongRows: ImportRowReader {
    let layout: ImportLayout
    let fallbackUnit: WeightUnit
    let workoutNumber, date, workoutName, duration, exercise, setOrder, weight, weightUnit: Int?
    let reps, distance, distanceUnit, seconds, notes, workoutNotes, rpe: Int?
    /// Metres per distance unit when the header names it.
    let headerMetres: Double?

    init(header: CSVHeader, layout: ImportLayout, fallbackUnit: WeightUnit) {
        self.layout = layout
        self.fallbackUnit = fallbackUnit
        workoutNumber = header.index(of: "workout #")
        date = header.index(of: "date")
        workoutName = header.index(of: "workout name")
        duration = header.index(ofAny: ["duration (sec)", "duration", "workout duration"])
        exercise = header.index(of: "exercise name")
        setOrder = header.index(of: "set order")
        weight = header.index(ofAny: ["weight (kg)", "weight (lbs)", "weight (lb)", "weight", "lbs", "kg"])
        weightUnit = header.index(of: "weight unit")
        reps = header.index(of: "reps")
        if let index = header.index(of: "distance (meters)") {
            distance = index
            headerMetres = 1
        } else if let index = header.index(of: "mi.") {
            distance = index
            headerMetres = 1_609.344
        } else if let index = header.index(of: "km") {
            distance = index
            headerMetres = 1_000
        } else {
            distance = header.index(of: "distance")
            headerMetres = nil
        }
        distanceUnit = header.index(of: "distance unit")
        seconds = header.index(of: "seconds")
        notes = header.index(of: "notes")
        workoutNotes = header.index(of: "workout notes")
        rpe = header.index(of: "rpe")
    }

    func startText(of row: CSVRow) -> String? { nonEmpty(row.trimmed(date)) }

    func record(for row: CSVRow, start: Date, end: Date?, units: inout UnitTally) -> RowRecord {
        let name = row.trimmed(workoutName)
        let key = workoutNumber.map { "#" + row.trimmed($0) } ?? (row.trimmed(date) + keySeparator + name)
        var record = RowRecord(groupKey: key, content: .ignore)
        record.workoutName = name
        record.workoutNotes = row.trimmed(workoutNotes).unescapingNewlines
        record.durationSeconds = ImportValues.duration(row.trimmed(duration)).value
        record.exerciseName = row.trimmed(exercise)
        record.exerciseNote = row.trimmed(notes).unescapingNewlines

        let order = StrongSetOrder(row.trimmed(setOrder))
        switch order {
        case .restTimer:
            return record
        case .note:
            record.content = record.exerciseName.isEmpty ? .ignore : .note
            return record
        case .working, .warmup, .drop, .failure, .other:
            break
        }
        guard !record.exerciseName.isEmpty else {
            record.content = .skip(.missingExercise)
            return record
        }
        let weightValue = ImportValues.decimal(row.trimmed(weight))
        let unit: WeightUnit = switch layout {
        case .strongNumbered(let unit), .strongUnitHeader(let unit): unit
        case .strongUnitColumn: units.unit(row.trimmed(weightUnit), fallback: fallbackUnit, hasWeight: (weightValue.value ?? 0) > 0)
        default: fallbackUnit
        }
        let metres = headerMetres ?? distanceUnit.flatMap { ImportValues.metres(per: row.trimmed($0)) }
        record.content = SetContent.make(
            weight: weightValue,
            kilograms: { unit.kilograms(fromValue: $0) },
            reps: ImportValues.count(row.trimmed(reps)),
            duration: ImportValues.duration(row.trimmed(seconds)),
            distance: ImportValues.decimal(row.trimmed(distance)),
            metresPerDistanceUnit: metres,
            rpe: ImportValues.rpe(row.trimmed(rpe)),
            isWarmup: order == .warmup,
            kind: order == .drop ? .drop : order == .failure ? .failure : .normal,
            line: row.line
        )
        return record
    }
}

// MARK: - FitNotes

/// FitNotes for Android: one row per set, no time and no workout name; one workout per date.
struct FitNotesRows: ImportRowReader {
    let layout: ImportLayout
    let fallbackUnit: WeightUnit
    let date, exercise, weight, weightUnit, reps, distance, distanceUnit, time, comment: Int?

    init(header: CSVHeader, layout: ImportLayout, fallbackUnit: WeightUnit) {
        self.layout = layout
        self.fallbackUnit = fallbackUnit
        date = header.index(of: "date")
        exercise = header.index(of: "exercise")
        weight = header.index(ofAny: ["weight (kgs)", "weight (kg)", "weight (lbs)", "weight"])
        weightUnit = header.index(of: "weight unit")
        reps = header.index(of: "reps")
        distance = header.index(of: "distance")
        distanceUnit = header.index(of: "distance unit")
        time = header.index(of: "time")
        comment = header.index(ofAny: ["comment", "notes"])
    }

    func startText(of row: CSVRow) -> String? { nonEmpty(row.trimmed(date)) }

    func record(for row: CSVRow, start: Date, end: Date?, units: inout UnitTally) -> RowRecord {
        var record = RowRecord(groupKey: row.trimmed(date), content: .ignore)
        record.exerciseName = row.trimmed(exercise)
        guard !record.exerciseName.isEmpty else {
            record.content = .skip(.missingExercise)
            return record
        }
        let weightValue = ImportValues.decimal(row.trimmed(weight))
        let unit: WeightUnit = if case .fitNotesUnitHeader(let unit) = layout {
            unit
        } else {
            units.unit(row.trimmed(weightUnit), fallback: fallbackUnit, hasWeight: (weightValue.value ?? 0) > 0)
        }
        record.content = SetContent.make(
            weight: weightValue,
            kilograms: { unit.kilograms(fromValue: $0) },
            reps: ImportValues.count(row.trimmed(reps)),
            duration: ImportValues.duration(row.trimmed(time)),
            distance: ImportValues.decimal(row.trimmed(distance)),
            metresPerDistanceUnit: distanceUnit.flatMap { ImportValues.metres(per: row.trimmed($0)) },
            note: row.trimmed(comment),
            line: row.line
        )
        return record
    }
}

// MARK: - Fitbod

/// Fitbod: one row per set; the UTC timestamp is the workout; weights in kilograms with
/// pound-conversion noise (see ``ImportValues/fitbodKilograms(_:)``). Identical rows are
/// real repeated sets.
struct FitbodRows: ImportRowReader {
    let date, exercise, reps, weight, duration, distance, isWarmup, note: Int?

    init(header: CSVHeader) {
        date = header.index(of: "date")
        exercise = header.index(of: "exercise")
        reps = header.index(of: "reps")
        weight = header.index(ofAny: ["weight(kg)", "weight (kg)"])
        duration = header.index(ofAny: ["duration(s)", "duration (s)"])
        distance = header.index(ofAny: ["distance(m)", "distance (m)"])
        isWarmup = header.index(of: "iswarmup")
        note = header.index(of: "note")
    }

    func startText(of row: CSVRow) -> String? { nonEmpty(row.trimmed(date)) }

    func record(for row: CSVRow, start: Date, end: Date?, units: inout UnitTally) -> RowRecord {
        var record = RowRecord(groupKey: row.trimmed(date), content: .ignore)
        record.exerciseName = row.trimmed(exercise)
        guard !record.exerciseName.isEmpty else {
            record.content = .skip(.missingExercise)
            return record
        }
        let warmup = ["true", "1", "yes"].contains(row.trimmed(isWarmup).lowercased())
        record.content = SetContent.make(
            weight: ImportValues.decimal(row.trimmed(weight)),
            kilograms: ImportValues.fitbodKilograms,
            reps: ImportValues.count(row.trimmed(reps)),
            duration: ImportValues.duration(row.trimmed(duration)),
            distance: ImportValues.decimal(row.trimmed(distance)),
            metresPerDistanceUnit: 1,
            isWarmup: warmup,
            note: row.trimmed(note),
            line: row.line
        )
        return record
    }
}

// MARK: - StrongLifts

/// StrongLifts 5×5: one row per exercise of a workout, its sets in `Set N (Reps)` /
/// `Set N (KG|LB)` column pairs (as many as the file has). Cells with 0 reps are sets that
/// were not done and are not sets.
struct StrongLiftsRows: ImportRowReader {
    let unit: WeightUnit
    let date, workout, workoutName, exercise, notes, startTime, endTime, hours, timedSets: Int?
    /// Set columns by set number: (reps column, weight column).
    let setColumns: [(reps: Int, weight: Int?)]

    init(header: CSVHeader, unit: WeightUnit) {
        self.unit = unit
        date = header.index(ofAny: ["date (yyyy/mm/dd)", "date"])
        workout = header.index(of: "workout")
        workoutName = header.index(of: "workout name")
        exercise = header.index(of: "exercise")
        notes = header.index(of: "notes")
        startTime = header.index(ofAny: ["start time (h:mm)", "start time"])
        endTime = header.index(ofAny: ["end time (h:mm)", "end time"])
        hours = header.index(of: "duration (hours)")
        timedSets = header.index(ofAny: ["sets×time", "setsxtime"])
        var repsByNumber: [Int: Int] = [:]
        var weightByNumber: [Int: Int] = [:]
        for (index, key) in header.keys.enumerated() {
            guard let (number, kind) = Self.setColumn(key) else { continue }
            if kind == "reps" { repsByNumber[number] = index } else { weightByNumber[number] = index }
        }
        setColumns = repsByNumber.keys.sorted().compactMap { number in
            repsByNumber[number].map { (reps: $0, weight: weightByNumber[number]) }
        }
    }

    /// `"set 3 (reps)"` → (3, "reps"); `"set 3 (kg)"` → (3, "kg").
    static func setColumn(_ key: String) -> (Int, String)? {
        guard key.hasPrefix("set "), key.hasSuffix(")"), let open = key.firstIndex(of: "(") else { return nil }
        let numberText = key[key.index(key.startIndex, offsetBy: 4)..<open].trimmingCharacters(in: .whitespaces)
        let kind = key[key.index(after: open)..<key.index(before: key.endIndex)].trimmingCharacters(in: .whitespaces)
        guard let number = Int(numberText), ["reps", "kg", "lb", "lbs"].contains(kind) else { return nil }
        return (number, kind)
    }

    func startText(of row: CSVRow) -> String? {
        guard let day = nonEmpty(row.trimmed(date)) else { return nil }
        guard let time = nonEmpty(row.trimmed(startTime)) else { return day }
        return day + " " + time
    }

    func endText(of row: CSVRow) -> String? {
        guard let day = nonEmpty(row.trimmed(date)), let time = nonEmpty(row.trimmed(endTime)) else { return nil }
        return day + " " + time
    }

    func record(for row: CSVRow, start: Date, end: Date?, units: inout UnitTally) -> RowRecord {
        var record = RowRecord(groupKey: row.trimmed(date) + keySeparator + row.trimmed(workout), content: .ignore)
        record.workoutName = row.trimmed(workoutName)
        // The end time has no date of its own: before the start means after midnight.
        if let end {
            record.end = end < start ? end.addingTimeInterval(86_400) : end
        }
        if case .value(let hours) = ImportValues.decimal(row.trimmed(hours)) {
            record.durationSeconds = Int((hours * 3_600).rounded())
        }
        record.exerciseName = row.trimmed(exercise)
        record.exerciseNote = row.trimmed(notes)
        guard !record.exerciseName.isEmpty else {
            record.content = .skip(.missingExercise)
            return record
        }
        var sets: [ImportedSet] = []
        for columns in setColumns {
            let reps = ImportValues.count(row.trimmed(columns.reps))
            let weight = ImportValues.decimal(row.trimmed(columns.weight))
            guard !reps.isInvalid, !weight.isInvalid else {
                record.content = .skip(.unreadableNumber)
                return record
            }
            guard let count = reps.value, count > 0 else { continue }
            sets.append(ImportedSet(weightKg: ImportValues.kilograms(weight.value, unit: unit), reps: count, line: row.line))
        }
        if sets.isEmpty {
            record.content = .skip(row.trimmed(timedSets).isEmpty ? .noSetData : .timedOrDistanceOnly)
        } else {
            record.content = .sets(sets)
        }
        return record
    }
}

// MARK: - Liftosaur

/// Liftosaur, both header generations: one row per set, the ISO timestamp is the workout,
/// a unit on every row.
struct LiftosaurRows: ImportRowReader {
    let fallbackUnit: WeightUnit
    let date, program, dayName, exercise, isWarmup, reps, rpe, weight, weightUnit, notes: Int?

    init(header: CSVHeader, isCurrent: Bool, fallbackUnit: WeightUnit) {
        self.fallbackUnit = fallbackUnit
        date = header.index(of: "workout datetime")
        program = header.index(of: "program")
        dayName = header.index(of: "day name")
        exercise = header.index(of: "exercise")
        isWarmup = header.index(of: "is warmup set?")
        reps = header.index(of: "completed reps")
        rpe = header.index(ofAny: isCurrent ? ["completed rpe", "rpe"] : ["rpe", "completed rpe"])
        weight = header.index(ofAny: isCurrent ? ["completed weight value", "weight value"] : ["weight value"])
        weightUnit = header.index(ofAny: isCurrent ? ["completed weight unit", "weight unit"] : ["weight unit"])
        notes = header.index(of: "notes")
    }

    func startText(of row: CSVRow) -> String? { nonEmpty(row.trimmed(date)) }

    func record(for row: CSVRow, start: Date, end: Date?, units: inout UnitTally) -> RowRecord {
        var record = RowRecord(groupKey: row.trimmed(date), content: .ignore)
        record.workoutName = nonEmpty(row.trimmed(dayName)) ?? row.trimmed(program)
        record.exerciseName = row.trimmed(exercise)
        record.exerciseNote = row.trimmed(notes)
        guard !record.exerciseName.isEmpty else {
            record.content = .skip(.missingExercise)
            return record
        }
        let weightValue = ImportValues.decimal(row.trimmed(weight))
        let unit = units.unit(row.trimmed(weightUnit), fallback: fallbackUnit, hasWeight: (weightValue.value ?? 0) > 0)
        record.content = SetContent.make(
            weight: weightValue,
            kilograms: { unit.kilograms(fromValue: $0) },
            reps: ImportValues.count(row.trimmed(reps)),
            rpe: ImportValues.rpe(row.trimmed(rpe)),
            isWarmup: ["1", "true", "yes"].contains(row.trimmed(isWarmup).lowercased()),
            line: row.line
        )
        return record
    }
}

// MARK: - Generic

/// Any CSV, read with a ``GenericMapping``. Rows with the same date (and time) and workout
/// name form one workout; a date without a time and no name column makes one workout per day.
struct GenericRows: ImportRowReader {
    let mapping: GenericMapping
    let unitSource: WeightUnitSource
    let fallbackUnit: WeightUnit

    init(header: CSVHeader, mapping: GenericMapping, fallbackUnit: WeightUnit) {
        self.mapping = mapping
        self.fallbackUnit = fallbackUnit
        self.unitSource = mapping.weightUnitSource(in: header, chosen: fallbackUnit)
    }

    func startText(of row: CSVRow) -> String? { nonEmpty(row.trimmed(mapping.column(for: .date))) }

    func record(for row: CSVRow, start: Date, end: Date?, units: inout UnitTally) -> RowRecord {
        let name = row.trimmed(mapping.column(for: .workoutName))
        var record = RowRecord(groupKey: ImportKey.externalKey(start: start, name: name), content: .ignore)
        record.workoutName = name
        if case .value(let seconds) = ImportValues.duration(row.trimmed(mapping.column(for: .workoutDuration)), bareNumberUnit: 60) {
            record.durationSeconds = seconds
        }
        record.exerciseName = row.trimmed(mapping.column(for: .exercise))
        guard !record.exerciseName.isEmpty else {
            record.content = .skip(.missingExercise)
            return record
        }
        let weightValue = ImportValues.decimal(row.trimmed(mapping.column(for: .weight)))
        let unit: WeightUnit = switch unitSource {
        case .header(let unit), .chosen(let unit): unit
        case .column:
            units.unit(row.trimmed(mapping.column(for: .weightUnit)), fallback: fallbackUnit, hasWeight: (weightValue.value ?? 0) > 0)
        }
        let order = StrongSetOrder(row.trimmed(mapping.column(for: .setOrder)))
        record.content = SetContent.make(
            weight: weightValue,
            kilograms: { unit.kilograms(fromValue: $0) },
            reps: ImportValues.count(row.trimmed(mapping.column(for: .reps))),
            isWarmup: order == .warmup,
            kind: order == .drop ? .drop : order == .failure ? .failure : .normal,
            note: row.trimmed(mapping.column(for: .note)),
            line: row.line
        )
        return record
    }
}
