// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Custom progression step input")
struct ProgressionStepInputTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")
    private let arabic = Locale(identifier: "ar_EG")

    @Test(arguments: ["2.5", "2,5", " 2.5 ", "2.50", "02.5"])
    func acceptsPointOrCommaInAnyLocale(text: String) {
        #expect(ProgressionStepInput.value(from: text, unit: .kg, locale: english) == .success(2.5))
        #expect(ProgressionStepInput.value(from: text, unit: .kg, locale: german) == .success(2.5))
    }

    @Test func acceptsLocaleDigitsAndSeparator() {
        // Arabic-Indic "٢٫٥": two, Arabic decimal separator, five.
        #expect(ProgressionStepInput.value(from: "\u{0662}\u{066B}\u{0665}", unit: .kg, locale: arabic) == .success(2.5))
    }

    @Test func acceptsMissingIntegerOrFraction() {
        #expect(ProgressionStepInput.value(from: ".5", unit: .kg, locale: english) == .success(0.5))
        #expect(ProgressionStepInput.value(from: "3.", unit: .kg, locale: english) == .success(3))
        #expect(ProgressionStepInput.value(from: "3", unit: .lb, locale: english) == .success(3))
    }

    @Test func roundsToHundredths() {
        #expect(ProgressionStepInput.value(from: "1.234", unit: .kg, locale: english) == .success(1.23))
        #expect(ProgressionStepInput.value(from: "1.235", unit: .kg, locale: english) == .success(1.24))
        #expect(ProgressionStepInput.value(from: "0.004", unit: .kg, locale: english) == .failure(.notPositive))
        #expect(ProgressionStepInput.value(from: "0.005", unit: .kg, locale: english) == .success(0.01))
    }

    @Test(arguments: [
        ("", ProgressionStepInput.Problem.empty),
        ("   ", .empty),
        (".", .notANumber),
        ("abc", .notANumber),
        ("2.5 kg", .notANumber),
        ("1.2.3", .notANumber),
        ("1,2,3", .notANumber),
        ("1e3", .notANumber),
        ("+2", .notANumber),
        ("2-", .notANumber),
        ("\u{00B2}", .notANumber),
        ("0", .notPositive),
        ("0,00", .notPositive),
        ("-2.5", .notPositive),
        ("\u{2212}1", .notPositive),
    ])
    func rejectsInvalidText(text: String, problem: ProgressionStepInput.Problem) {
        #expect(ProgressionStepInput.value(from: text, unit: .kg, locale: english) == .failure(problem))
    }

    @Test func limitsToOneHundredKilograms() {
        #expect(ProgressionStepInput.maximumValue(for: .kg) == 100)
        #expect(ProgressionStepInput.maximumValue(for: .lb) == 220.46)
        #expect(ProgressionStepInput.value(from: "100", unit: .kg, locale: english) == .success(100))
        #expect(ProgressionStepInput.value(from: "100.01", unit: .kg, locale: english) == .failure(.tooLarge))
        #expect(ProgressionStepInput.value(from: "220.46", unit: .lb, locale: english) == .success(220.46))
        #expect(ProgressionStepInput.value(from: "220.47", unit: .lb, locale: english) == .failure(.tooLarge))
        #expect(ProgressionStepInput.value(from: "99999999999999999999", unit: .kg, locale: english) == .failure(.tooLarge))
        let heaviest = try? ProgressionStepInput.kilograms(from: "220.46", unit: .lb, locale: english).get()
        #expect((heaviest ?? .infinity) <= ProgressionStepInput.maximumKilograms)
    }

    @Test func convertsToKilogramsForStorage() throws {
        let kg = try ProgressionStepInput.kilograms(from: "3,75", unit: .kg, locale: german).get()
        #expect(kg == 3.75)
        let lb = try ProgressionStepInput.kilograms(from: "7.5", unit: .lb, locale: english).get()
        #expect(ProgressionStep.isSame(lb, 7.5 * WeightUnit.kilogramsPerPound))
        #expect(ProgressionStepInput.kilograms(from: "x", unit: .lb, locale: english) == .failure(.notANumber))
    }

    @Test func editingTextUsesTheLocaleSeparator() {
        #expect(ProgressionStepInput.text(kilograms: 2.5, unit: .kg, locale: english) == "2.5")
        #expect(ProgressionStepInput.text(kilograms: 2.5, unit: .kg, locale: german) == "2,5")
        #expect(ProgressionStepInput.text(kilograms: 5, unit: .kg, locale: english) == "5")
        #expect(ProgressionStepInput.text(kilograms: 1.25, unit: .kg, locale: english) == "1.25")
        #expect(ProgressionStepInput.text(kilograms: 5 * WeightUnit.kilogramsPerPound, unit: .lb, locale: english) == "5")
        #expect(ProgressionStepInput.text(kilograms: 5, unit: .lb, locale: english) == "11.02")
        #expect(ProgressionStepInput.text(kilograms: 100, unit: .kg, locale: english) == "100")
        #expect(ProgressionStepInput.text(kilograms: nil, unit: .kg, locale: english) == "")
        #expect(ProgressionStepInput.text(kilograms: 0, unit: .kg, locale: english) == "")
        #expect(ProgressionStepInput.text(kilograms: .nan, unit: .kg, locale: english) == "")
    }

    @Test(arguments: [WeightUnit.kg, .lb], [0.5, 1.25, 3.75, 2 * WeightUnit.kilogramsPerPound, 7.5 * WeightUnit.kilogramsPerPound])
    func editingTextReadsBack(unit: WeightUnit, kilograms: Double) throws {
        for locale in [english, german, arabic] {
            let text = ProgressionStepInput.text(kilograms: kilograms, unit: unit, locale: locale)
            let value = try ProgressionStepInput.value(from: text, unit: unit, locale: locale).get()
            #expect(abs(value - unit.value(fromKilograms: kilograms)) < 0.0051, "\(text) in \(locale.identifier)")
        }
    }

    // MARK: Storing a typed step

    @Test func typedBuiltInDefaultStillClearsTheOverride() throws {
        let context = try makeInMemoryContext()
        let settings = try AppSettings.current(in: context)
        SettingsEditing.setUnit(.lb, on: settings)

        let custom = try ProgressionStepInput.kilograms(from: "7.5", unit: .lb, locale: english).get()
        SettingsEditing.setProgressionStep(kilograms: custom, for: .barbell, on: settings)
        #expect(ProgressionSettings(settings).defaultStep(for: .barbell) == custom)
        #expect(ProgressionStepChoices.matching(custom, unit: .lb) == nil)
        #expect(ProgressionStepChoices.options(for: .lb, including: custom).contains(custom))

        // 5 lb is the built-in barbell step for pounds.
        let builtIn = try ProgressionStepInput.kilograms(from: "5", unit: .lb, locale: english).get()
        SettingsEditing.setProgressionStep(kilograms: builtIn, for: .barbell, on: settings)
        #expect(settings.progressionSteps[.barbell] == nil)
    }

    @Test func typedPresetSelectsThePreset() throws {
        let typed = try ProgressionStepInput.kilograms(from: "2,5", unit: .lb, locale: german).get()
        #expect(ProgressionStepChoices.tag(for: typed, unit: .lb) == 2.5 * WeightUnit.kilogramsPerPound)
        #expect(ProgressionStepChoices.options(for: .lb, including: typed).count == ProgressionStepChoices.values(for: .lb).count)
    }

    @Test func typedStepIsStoredOnAnExercise() throws {
        let context = try makeInMemoryContext()
        let exercise = Exercise(name: "Row")
        context.insert(exercise)
        let typed = try ProgressionStepInput.kilograms(from: "3.33", unit: .kg, locale: english).get()
        ExerciseEditing.setProgressionStep(kilograms: typed, on: exercise)
        #expect(exercise.progressionStepKg == 3.33)
        #expect(ProgressionStepChoices.options(for: .kg, including: exercise.progressionStepKg).contains(3.33))
    }
}
