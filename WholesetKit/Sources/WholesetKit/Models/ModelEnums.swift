// SPDX-License-Identifier: GPL-3.0-or-later

/// A `String`-backed enum whose values are persisted as their raw value.
///
/// Models store enums as plain `String` attributes and expose a typed computed
/// accessor. A newer app version on another device may sync a raw value this
/// version does not know; the accessor then reads ``fallback`` and leaves the
/// stored string untouched until the property is explicitly set.
public protocol PersistedEnum: RawRepresentable, CaseIterable, Sendable where RawValue == String {
    /// The value reported for raw strings this version does not recognise.
    static var fallback: Self { get }
}

extension PersistedEnum {
    /// Decodes a stored raw value, falling back to ``fallback`` for unknown strings.
    public init(persisted rawValue: String) {
        self = Self(rawValue: rawValue) ?? Self.fallback
    }
}

/// The kind of equipment an exercise uses. Drives default progression steps.
public enum Equipment: String, PersistedEnum {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case other

    public static var fallback: Equipment { .other }
}

/// The main muscle group an exercise trains.
public enum Muscle: String, PersistedEnum {
    case abdominals
    case abductors
    case adductors
    case biceps
    case calves
    case chest
    case forearms
    case glutes
    case hamstrings
    case lats
    case lowerBack
    case middleBack
    case neck
    case quadriceps
    case shoulders
    case traps
    case triceps
    case other

    public static var fallback: Muscle { .other }
}

/// Where a session was recorded or imported from.
public enum Source: String, PersistedEnum {
    case watch
    case phone
    case importStrong
    case importHevy

    public static var fallback: Source { .watch }
}

/// The unit used to show and enter weights. Storage is always kilograms.
public enum WeightUnit: String, PersistedEnum {
    case kg
    case lb

    public static var fallback: WeightUnit { .kg }
}
