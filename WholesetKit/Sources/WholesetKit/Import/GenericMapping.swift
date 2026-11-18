// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What a column of an unrecognised CSV holds.
public enum ColumnRole: String, Sendable, CaseIterable, Identifiable {
    /// The workout's date, with or without a time. Required.
    case date
    /// The exercise name. Required.
    case exercise
    /// Repetitions of the set. Required.
    case reps
    /// The set's weight.
    case weight
    /// The weight's unit on each row (`kg`, `kgs`, `lb`, `lbs`).
    case weightUnit
    /// The workout's (or routine's) name.
    case workoutName
    /// A note on the set.
    case note
    /// The set's number, or `W`/`D`/`F` for warm-up, drop and failure sets.
    case setOrder
    /// How long the workout lasted: `1h 5m`, `H:MM:SS`, or a number of minutes.
    case workoutDuration
    /// Not imported.
    case ignore

    public var id: String { rawValue }

    /// The roles a mapping must assign.
    public static let required: [ColumnRole] = [.date, .exercise, .reps]

    /// Whether a mapping must assign this role.
    public var isRequired: Bool { Self.required.contains(self) }
}

/// Which column of an unrecognised CSV holds what. Each role except
/// ``ColumnRole/ignore`` belongs to at most one column.
public struct GenericMapping: Sendable, Equatable {
    /// The role of each column, by position.
    public private(set) var roles: [ColumnRole]

    /// A mapping that ignores all `columnCount` columns.
    public init(columnCount: Int) {
        roles = Array(repeating: .ignore, count: columnCount)
    }

    /// A mapping with the given roles, by column; a repeated role keeps its first column.
    public init(roles: [ColumnRole]) {
        self.roles = Array(repeating: .ignore, count: roles.count)
        for (index, role) in roles.enumerated() where role == .ignore || !self.roles.contains(role) {
            self.roles[index] = role
        }
    }

    /// The role of column `index` (``ColumnRole/ignore`` outside the header).
    public func role(ofColumn index: Int) -> ColumnRole {
        roles.indices.contains(index) ? roles[index] : .ignore
    }

    /// The column holding `role`, if any.
    public func column(for role: ColumnRole) -> Int? {
        guard role != .ignore else { return nil }
        return roles.firstIndex(of: role)
    }

    /// Gives column `index` the role `role`; the column that had it before is ignored.
    public mutating func assign(_ role: ColumnRole, toColumn index: Int) {
        guard roles.indices.contains(index) else { return }
        if role != .ignore, let previous = roles.firstIndex(of: role) {
            roles[previous] = .ignore
        }
        roles[index] = role
    }

    /// Required roles no column holds yet, in ``ColumnRole/required`` order.
    public var missingRoles: [ColumnRole] {
        ColumnRole.required.filter { column(for: $0) == nil }
    }

    /// Whether every required role is assigned.
    public var isComplete: Bool { missingRoles.isEmpty }

    /// The unit the weight column's name gives (`Weight (lbs)`, `kg`), if any.
    public func headerWeightUnit(in header: CSVHeader) -> WeightUnit? {
        guard let index = column(for: .weight), header.names.indices.contains(index) else { return nil }
        return Self.unitWord(in: Self.words(header.names[index]))
    }

    /// Where weights' unit will come from with this mapping, given the caller's unit.
    public func weightUnitSource(in header: CSVHeader, chosen: WeightUnit) -> WeightUnitSource {
        if column(for: .weightUnit) != nil { return .column }
        if let unit = headerWeightUnit(in: header) { return .header(unit) }
        return .chosen(chosen)
    }

    // MARK: Samples

    /// The first non-empty value of each column among `rows`, trimmed (empty if none).
    public static func samples(columnCount: Int, rows: some Sequence<CSVRow>) -> [String] {
        var samples = Array(repeating: "", count: columnCount)
        var missing = columnCount
        for row in rows {
            guard missing > 0 else { break }
            for index in 0..<columnCount where samples[index].isEmpty {
                let value = row.trimmed(index)
                if !value.isEmpty {
                    samples[index] = value
                    missing -= 1
                }
            }
        }
        return samples
    }

    // MARK: Suggestions

    /// Guesses each column's role from its name and a sample value: `Date`, `Exercise`,
    /// `Reps`, `Weight`/`kg`/`lbs`, `Unit`, `Workout`/`Routine`, `Note`/`Comment`, `Set`,
    /// `Duration` and similar names. Each role goes to its best-scoring column; unclear
    /// columns are ignored.
    public static func suggested(header: CSVHeader, sampleRows: some Sequence<CSVRow>) -> GenericMapping {
        let samples = samples(columnCount: header.count, rows: sampleRows)
        var candidates: [(score: Int, column: Int, role: ColumnRole)] = []
        for (column, name) in header.names.enumerated() {
            let words = words(name)
            for role in ColumnRole.allCases where role != .ignore {
                let score = score(role, words: words, sample: samples[column])
                if score >= 50 { candidates.append((score, column, role)) }
            }
        }
        candidates.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.column < rhs.column
        }
        var mapping = GenericMapping(columnCount: header.count)
        var usedColumns: Set<Int> = []
        for candidate in candidates where !usedColumns.contains(candidate.column) && mapping.column(for: candidate.role) == nil {
            mapping.assign(candidate.role, toColumn: candidate.column)
            usedColumns.insert(candidate.column)
        }
        return mapping
    }

    /// A column name as lower-cased words, punctuation removed.
    static func words(_ name: String) -> [String] {
        let lowered = name.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let scalars = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "#" ? Character($0) : " " }
        return String(scalars).split(separator: " ").map(String.init)
    }

    private static func unitWord(in words: [String]) -> WeightUnit? {
        for word in words {
            if let unit = ImportValues.weightUnit(word) { return unit }
        }
        return nil
    }

    private static func score(_ role: ColumnRole, words: [String], sample: String) -> Int {
        let set = Set(words)
        func has(_ any: String...) -> Bool { any.contains(where: set.contains) }
        switch role {
        case .date:
            var score = 0
            if has("date", "datetime", "timestamp", "datum", "fecha", "day", "when") { score = 80 }
            else if has("time", "start", "started") { score = 45 }
            guard score > 0 else {
                return ImportDateParser.analyze(sample) != nil && sample.count >= 6 && !isNumber(sample) ? 55 : 0
            }
            if !sample.isEmpty { score += ImportDateParser.analyze(sample) != nil ? 15 : -40 }
            return score
        case .exercise:
            guard has("exercise", "exercises", "movement", "lift", "exercise_title") else { return 0 }
            return has("note", "notes", "id", "category", "type", "count", "number", "#") ? 10 : 85
        case .reps:
            guard has("reps", "rep", "repetitions", "repetition") else { return 0 }
            if has("required", "target", "planned", "goal") { return 30 }
            return isNumber(sample) || sample.isEmpty ? 90 : 40
        case .weight:
            if has("unit", "units", "body", "bodyweight") { return 0 }
            if has("weight", "wt", "load", "mass") { return isNumber(sample) || sample.isEmpty ? 85 : 40 }
            if words.count == 1, unitWord(in: words) != nil { return 75 }
            return 0
        case .weightUnit:
            guard has("unit", "units") else { return 0 }
            if has("distance") { return 0 }
            return ImportValues.weightUnit(sample) != nil ? 95 : 55
        case .workoutName:
            guard has("workout", "routine", "session", "title", "program", "template") else { return 0 }
            if has("date", "duration", "notes", "note", "#", "number", "id", "time") { return 0 }
            return has("name", "title") ? 80 : 70
        case .note:
            guard has("note", "notes", "comment", "comments", "description", "memo", "remark", "remarks") else { return 0 }
            return has("workout", "session") ? 60 : 70
        case .setOrder:
            guard has("set", "sets") else { return 0 }
            if has("order", "index", "number", "no", "#") || words.count == 1 {
                return isNumber(sample) || StrongSetOrder(sample) != .other || sample.isEmpty ? 80 : 40
            }
            return 0
        case .workoutDuration:
            return has("duration", "length") ? 70 : 0
        case .ignore:
            return 0
        }
    }

    private static func isNumber(_ text: String) -> Bool {
        ImportValues.number(text) != nil
    }
}
