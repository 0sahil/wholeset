// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Reads a progression step the user typed in the display unit, for steps that none of
/// the ``ProgressionStepChoices`` fit.
///
/// The text may use a comma or a point as the decimal separator (or the locale's own
/// separator), and the locale's digits (see ``DecimalInput``). A valid step is positive, at most
/// ``maximumKilograms``, and is rounded to ``fractionDigits`` decimals in the display unit
/// before it is converted to kilograms for storage.
public enum ProgressionStepInput {
    /// The largest step accepted, in kilograms (shown as its equivalent in pounds).
    public static let maximumKilograms: Double = 100

    /// Decimals kept in the display unit.
    public static let fractionDigits = 2

    /// Why typed text is not a valid step.
    public enum Problem: Error, Equatable, Sendable {
        /// Nothing but whitespace.
        case empty
        /// Not a plain decimal number.
        case notANumber
        /// Zero or negative, or so small it rounds to zero.
        case notPositive
        /// More than ``ProgressionStepInput/maximumValue(for:)``.
        case tooLarge
    }

    /// The largest step accepted in `unit`, rounded down to ``fractionDigits`` decimals
    /// (100 kg, or 220.46 lb).
    public static func maximumValue(for unit: WeightUnit) -> Double {
        let scale = pow(10, Double(fractionDigits))
        return (unit.value(fromKilograms: maximumKilograms) * scale).rounded(.down) / scale
    }

    /// The step in `unit` that `text` describes, rounded to ``fractionDigits`` decimals.
    ///
    /// - Parameters:
    ///   - text: What the user typed, for example "2.5", "2,5" or "1.25".
    ///   - unit: The display unit the text is in.
    ///   - locale: Supplies an extra decimal separator to accept besides "." and ",".
    public static func value(from text: String, unit: WeightUnit, locale: Locale = .current) -> Result<Double, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let parsed = DecimalInput.parse(trimmed, locale: locale), parsed.isFinite else { return .failure(.notANumber) }
        let rounded = round(parsed)
        guard rounded > 0 else { return .failure(.notPositive) }
        guard rounded <= maximumValue(for: unit) else { return .failure(.tooLarge) }
        return .success(rounded)
    }

    /// The step in kilograms that `text` (in `unit`) describes; see ``value(from:unit:locale:)``.
    public static func kilograms(from text: String, unit: WeightUnit, locale: Locale = .current) -> Result<Double, Problem> {
        value(from: text, unit: unit, locale: locale).map(unit.kilograms(fromValue:))
    }

    /// A stored step as editable text in `unit`: up to ``fractionDigits`` decimals, no
    /// grouping, the locale's decimal separator (for example "2.5", "2,5" or "11.02").
    /// Empty for a missing or invalid step.
    public static func text(kilograms: Double?, unit: WeightUnit, locale: Locale = .current) -> String {
        guard let kilograms, kilograms.isFinite, kilograms > 0 else { return "" }
        return DecimalInput.text(round(unit.value(fromKilograms: kilograms)), maximumFractionDigits: fractionDigits, locale: locale)
    }

    private static func round(_ value: Double) -> Double {
        DecimalInput.rounded(value, fractionDigits: fractionDigits)
    }
}
