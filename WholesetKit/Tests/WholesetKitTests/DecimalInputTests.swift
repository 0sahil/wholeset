// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Decimal input")
struct DecimalInputTests {
    private let english = Locale(identifier: "en_US")
    private let arabic = Locale(identifier: "ar_EG")

    @Test func parsesPointOrCommaAndAnyDigits() {
        #expect(DecimalInput.parse("62.5", locale: english) == 62.5)
        #expect(DecimalInput.parse(" 62,5 ", locale: english) == 62.5)
        #expect(DecimalInput.parse("\u{0666}\u{0662}\u{066B}\u{0665}", locale: arabic) == 62.5)
        #expect(DecimalInput.parse("-3", locale: english) == -3)
        #expect(DecimalInput.parse(".5", locale: english) == 0.5)
    }

    @Test(arguments: ["", " ", ".", "1.2.3", "1e3", "+2", "2-", "abc", "1,000.5"])
    func rejectsAnythingElse(text: String) {
        #expect(DecimalInput.parse(text, locale: english) == nil)
    }

    @Test func wholeNumbers() {
        #expect(DecimalInput.parseWholeNumber("12") == 12)
        #expect(DecimalInput.parseWholeNumber(" 007 ") == 7)
        #expect(DecimalInput.parseWholeNumber("\u{FF11}\u{FF10}") == 10)
        #expect(DecimalInput.parseWholeNumber("123456789") == 123_456_789)
        #expect(DecimalInput.parseWholeNumber("1234567890") == nil)
        #expect(DecimalInput.parseWholeNumber("1.0") == nil)
        #expect(DecimalInput.parseWholeNumber("") == nil)
        #expect(DecimalInput.parseWholeNumber("-1") == nil)
    }

    @Test func roundsAndFormats() {
        #expect(DecimalInput.rounded(1.235, fractionDigits: 2) == 1.24)
        #expect(DecimalInput.rounded(-1.235, fractionDigits: 2) == -1.24)
        #expect(DecimalInput.text(2.5, maximumFractionDigits: 2, locale: Locale(identifier: "de_DE")) == "2,5")
        #expect(DecimalInput.text(1_234.5, maximumFractionDigits: 2, locale: english) == "1234.5")
        #expect(DecimalInput.text(3, maximumFractionDigits: 2, locale: english) == "3")
    }
}
