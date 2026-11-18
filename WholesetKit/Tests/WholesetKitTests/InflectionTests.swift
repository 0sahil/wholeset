// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import WholesetKit

@Suite("Inflection")
struct InflectionTests {
    private let english = Locale(identifier: "en_US")

    @Test(arguments: [
        (1, "1 exercise"),
        (5, "5 exercises"),
        (0, "0 exercises"),
    ])
    func exerciseCountAgreesInEnglish(count: Int, expected: String) {
        #expect(inflectedString("^[\(count) exercise](inflect: true)", locale: english) == expected)
    }

    @Test func inflectsInsideLongerText() {
        let completed = 3
        let total = 8
        let reps = 1
        #expect(inflectedString("\(completed) of ^[\(total) set](inflect: true) logged", locale: english) == "3 of 8 sets logged")
        #expect(inflectedString("^[\(reps) rep](inflect: true)", locale: english) == "1 rep")
    }

    @Test func leavesPlainTextAlone() {
        #expect(inflectedString("Rest", locale: english) == "Rest")
    }
}
