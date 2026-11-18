// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The app a workout export comes from.
public enum ImportFormat: String, Sendable, CaseIterable, Identifiable {
    case strong
    case hevy
    case fitNotes
    case fitbod
    case strongLifts
    case liftosaur
    /// Any other CSV: the user says what each column holds (see ``GenericMapping``).
    case generic

    public var id: String { rawValue }

    /// The app's name (a brand name, the same in every language). Empty for ``generic``.
    public var appName: String {
        switch self {
        case .strong: "Strong"
        case .hevy: "Hevy"
        case .fitNotes: "FitNotes"
        case .fitbod: "Fitbod"
        case .strongLifts: "StrongLifts 5×5"
        case .liftosaur: "Liftosaur"
        case .generic: ""
        }
    }

    /// Whether the format is read from little evidence and labelled "beta".
    public var isBeta: Bool {
        switch self {
        case .fitbod, .strongLifts, .liftosaur: true
        case .strong, .hevy, .fitNotes, .generic: false
        }
    }

    /// The ``Source`` imported sessions get.
    public var source: Source {
        switch self {
        case .strong: .importStrong
        case .hevy: .importHevy
        case .fitNotes: .importFitNotes
        case .fitbod: .importFitbod
        case .strongLifts: .importStrongLifts
        case .liftosaur: .importLiftosaur
        case .generic: .importCSV
        }
    }
}

/// The header layout of a recognised export: which app, which generation of its export,
/// and where its weight unit is.
public enum ImportLayout: Sendable, Equatable {
    /// Hevy: the unit is in the weight column's name (`weight_kg` or `weight_lbs`).
    case hevy(weight: WeightUnit)
    /// Strong, comma-separated with a `Duration` column and no unit anywhere (layout 1a).
    case strongNoUnit
    /// Strong with a `Weight Unit` column, `;` or `,` separated (layout 1b).
    case strongUnitColumn
    /// Strong 6.x with `Workout #` and the unit in the weight column's name (layout 1c).
    case strongNumbered(weight: WeightUnit)
    /// Strong 2018: a column named after the unit (`lbs` or `kg`) (layout 1d).
    case strongUnitHeader(weight: WeightUnit)
    /// FitNotes for Android: the unit in the weight column's name (older exports).
    case fitNotesUnitHeader(weight: WeightUnit)
    /// FitNotes for Android: a `Weight Unit` column (`kgs` / `lbs`).
    case fitNotesUnitColumn
    /// Fitbod `WorkoutExport.csv`: always kilograms.
    case fitbod
    /// StrongLifts 5×5: one row per exercise, sets in `Set N (Reps)` / `Set N (KG|LB)` pairs.
    case strongLifts(weight: WeightUnit)
    /// Liftosaur, either header generation; the unit is in a column on every row.
    case liftosaur(isCurrent: Bool)
    /// Not recognised: columns are matched by the user.
    case generic

    /// The app the layout belongs to.
    public var format: ImportFormat {
        switch self {
        case .hevy: .hevy
        case .strongNoUnit, .strongUnitColumn, .strongNumbered, .strongUnitHeader: .strong
        case .fitNotesUnitHeader, .fitNotesUnitColumn: .fitNotes
        case .fitbod: .fitbod
        case .strongLifts: .strongLifts
        case .liftosaur: .liftosaur
        case .generic: .generic
        }
    }

    /// A short, stable identifier for reports and logs, e.g. `strong-1c`.
    public var identifier: String {
        switch self {
        case .hevy(let unit): "hevy-\(unit.rawValue)"
        case .strongNoUnit: "strong-1a"
        case .strongUnitColumn: "strong-1b"
        case .strongNumbered(let unit): "strong-1c-\(unit.rawValue)"
        case .strongUnitHeader(let unit): "strong-1d-\(unit.rawValue)"
        case .fitNotesUnitHeader(let unit): "fitnotes-header-\(unit.rawValue)"
        case .fitNotesUnitColumn: "fitnotes-unit-column"
        case .fitbod: "fitbod"
        case .strongLifts(let unit): "stronglifts-\(unit.rawValue)"
        case .liftosaur(let isCurrent): isCurrent ? "liftosaur-current" : "liftosaur-2024"
        case .generic: "generic"
        }
    }

    /// The unit named by the header, if the layout has one for the whole file.
    public var headerWeightUnit: WeightUnit? {
        switch self {
        case .hevy(let unit), .strongNumbered(let unit), .strongUnitHeader(let unit),
             .fitNotesUnitHeader(let unit), .strongLifts(let unit):
            unit
        case .fitbod:
            .kg
        case .strongNoUnit, .strongUnitColumn, .fitNotesUnitColumn, .liftosaur, .generic:
            nil
        }
    }

    /// Whether every row says its own unit.
    public var hasUnitColumn: Bool {
        switch self {
        case .strongUnitColumn, .fitNotesUnitColumn, .liftosaur: true
        default: false
        }
    }
}

/// Recognises an export from its header row. The file name is never used.
public enum ImportFormatDetector {
    /// The layout `header` belongs to, or ``ImportLayout/generic``.
    public static func detect(_ header: CSVHeader) -> ImportLayout {
        if let layout = hevy(header) { return layout }
        if let layout = strong(header) { return layout }
        if let layout = liftosaur(header) { return layout }
        if let layout = strongLifts(header) { return layout }
        if header.containsAll(["date", "exercise", "reps", "iswarmup"]),
           header.index(ofAny: ["weight(kg)", "weight (kg)"]) != nil {
            return .fitbod
        }
        if let layout = fitNotes(header) { return layout }
        return .generic
    }

    private static func hevy(_ header: CSVHeader) -> ImportLayout? {
        guard header.containsAll(["title", "start_time", "exercise_title", "reps"]),
              header.contains("set_index") || header.contains("set_type") else { return nil }
        if header.contains("weight_kg") { return .hevy(weight: .kg) }
        if header.contains("weight_lbs") { return .hevy(weight: .lb) }
        return nil
    }

    private static func strong(_ header: CSVHeader) -> ImportLayout? {
        guard header.containsAll(["date", "exercise name", "set order", "reps"]) else { return nil }
        if header.contains("workout #") {
            if header.contains("weight (kg)") { return .strongNumbered(weight: .kg) }
            if header.contains("weight (lbs)") || header.contains("weight (lb)") { return .strongNumbered(weight: .lb) }
            return nil
        }
        guard header.contains("workout name") else { return nil }
        if header.containsAll(["weight", "weight unit"]) { return .strongUnitColumn }
        if header.contains("weight") { return .strongNoUnit }
        if header.contains("lbs") { return .strongUnitHeader(weight: .lb) }
        if header.contains("kg") { return .strongUnitHeader(weight: .kg) }
        return nil
    }

    private static func liftosaur(_ header: CSVHeader) -> ImportLayout? {
        guard header.containsAll(["workout datetime", "exercise", "completed reps"]) else { return nil }
        if header.containsAll(["completed weight value", "completed weight unit"]) { return .liftosaur(isCurrent: true) }
        if header.containsAll(["weight value", "weight unit"]) { return .liftosaur(isCurrent: false) }
        return nil
    }

    private static func strongLifts(_ header: CSVHeader) -> ImportLayout? {
        guard header.containsAll(["workout", "exercise", "set 1 (reps)"]),
              header.index(ofAny: ["date (yyyy/mm/dd)", "date"]) != nil else { return nil }
        if header.contains("set 1 (kg)") { return .strongLifts(weight: .kg) }
        if header.contains("set 1 (lb)") || header.contains("set 1 (lbs)") { return .strongLifts(weight: .lb) }
        return nil
    }

    private static func fitNotes(_ header: CSVHeader) -> ImportLayout? {
        guard header.containsAll(["date", "exercise", "category", "reps"]),
              !header.contains("kind") else { return nil }
        let kilograms = header.index(ofAny: ["weight (kgs)", "weight (kg)"]) != nil
        let pounds = header.contains("weight (lbs)")
        if kilograms && pounds { return nil }
        if kilograms { return .fitNotesUnitHeader(weight: .kg) }
        if pounds { return .fitNotesUnitHeader(weight: .lb) }
        if header.containsAll(["weight", "weight unit"]) { return .fitNotesUnitColumn }
        return nil
    }
}
