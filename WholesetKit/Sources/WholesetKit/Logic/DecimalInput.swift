// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Reads and writes the numbers people type on a keypad, whatever their locale.
///
/// Typed decimals may use a point or a comma as the separator (or the locale's own
/// separator) and the digits of any script, because the decimal pad shows the locale's
/// separator while people often type the one they are used to.
public enum DecimalInput {
    /// The number `text` describes: an optional leading minus, digits of any script and at
    /// most one decimal separator ("." or ",", or `locale`'s). Surrounding whitespace is
    /// ignored. `nil` for anything else: grouping, exponents, letters, signs elsewhere, or
    /// no digit at all.
    public static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators: Set<Character> = Set([".", ","] + Array(locale.decimalSeparator ?? "."))
        var sign = ""
        var integerPart = ""
        var fractionPart = ""
        var hasSeparator = false
        for (index, character) in text.enumerated() {
            if let digit = decimalDigit(character) {
                if hasSeparator {
                    fractionPart.append(String(digit))
                } else {
                    integerPart.append(String(digit))
                }
            } else if separators.contains(character), !hasSeparator {
                hasSeparator = true
            } else if index == 0, character == "-" || character == "\u{2212}" {
                sign = "-"
            } else {
                return nil
            }
        }
        guard !(integerPart.isEmpty && fractionPart.isEmpty) else { return nil }
        let integer = integerPart.isEmpty ? "0" : integerPart
        let fraction = fractionPart.isEmpty ? "0" : fractionPart
        return Double("\(sign)\(integer).\(fraction)")
    }

    /// The whole number `text` describes: digits of any script only, surrounding whitespace
    /// ignored. `nil` for anything else, including signs, separators and numbers with more
    /// than nine digits (so the result always fits).
    public static func parseWholeNumber(_ text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 9 else { return nil }
        var value = 0
        for character in text {
            guard let digit = decimalDigit(character) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    /// `value` rounded half away from zero to `fractionDigits` decimals.
    public static func rounded(_ value: Double, fractionDigits: Int) -> Double {
        let scale = pow(10, Double(fractionDigits))
        return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    /// `value` as editable text: up to `maximumFractionDigits` decimals, no grouping, the
    /// locale's decimal separator and digits (for example "2.5", "2,5" or "135").
    public static func text(_ value: Double, maximumFractionDigits: Int, locale: Locale = .current) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...max(0, maximumFractionDigits)))
                .grouping(.never)
                .locale(locale)
        )
    }

    /// The value of a single decimal digit in any script ("5", "٥", "５"), else `nil`.
    private static func decimalDigit(_ character: Character) -> Int? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.properties.numericType == .decimal else { return nil }
        return character.wholeNumberValue
    }
}
