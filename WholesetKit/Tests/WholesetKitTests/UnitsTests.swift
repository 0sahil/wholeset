// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Units")
struct UnitsTests {
    private let posix = Locale(identifier: "en_US_POSIX")

    @Test func poundFactorIsExact() {
        #expect(WeightUnit.kilogramsPerPound == 0.45359237)
        #expect(WeightUnit.lb.kilograms(fromValue: 100) == 45.359237)
        #expect(WeightUnit.kg.value(fromKilograms: 62.5) == 62.5)
        #expect(abs(WeightUnit.lb.value(fromKilograms: 45.359237) - 100) < 1e-12)
    }

    @Test func inputStepsAndSymbols() {
        #expect(WeightUnit.kg.inputStep == 0.5)
        #expect(WeightUnit.lb.inputStep == 1)
        #expect(WeightUnit.kg.symbol == "kg")
        #expect(WeightUnit.lb.symbol == "lb")
    }

    @Test(arguments: [
        (60.0, WeightUnit.kg, "60"),
        (62.5, .kg, "62.5"),
        (62.49, .kg, "62.5"),
        (99.99, .kg, "100"),
        (0.2, .kg, "0"),
        (45.359237, .lb, "100"),
        (61.2, .lb, "135"),
        (20, .lb, "44"),
        (1000, .kg, "1000"),
    ])
    func displayRoundsToStepWithoutTrailingZero(kilograms: Double, unit: WeightUnit, expected: String) {
        let text = WeightFormat.string(kilograms: kilograms, scale: WeightScale(unit: unit), locale: posix)
        #expect(text == expected)
    }

    @Test func displayUsesLocaleDecimalSeparator() {
        let text = WeightFormat.string(kilograms: 62.5, scale: WeightScale(unit: .kg), locale: Locale(identifier: "de_DE"))
        #expect(text == "62,5")
    }

    @Test(arguments: [
        (60.0, WeightUnit.kg, "60.0"),
        (62.5, .kg, "62.5"),
        (0, .kg, "0.0"),
        (61.2, .lb, "135"),
    ])
    func allFractionDigitsKeepTheTrailingZero(kilograms: Double, unit: WeightUnit, expected: String) {
        let text = WeightFormat.string(kilograms: kilograms, scale: WeightScale(unit: unit), showsAllFractionDigits: true, locale: posix)
        #expect(text == expected)
    }

    /// While stepping with all fraction digits, every kg value has the same characters in
    /// the same places, so no character appears or disappears between detents.
    @Test func allFractionDigitsKeepTheShapeWhileStepping() {
        let scale = WeightScale(unit: .kg)
        // 50.0 kg through 99.5 kg.
        let shapes = Set((100...199).map { steps in
            WeightFormat.string(kilograms: scale.kilograms(forSteps: steps), scale: scale, showsAllFractionDigits: true, locale: posix)
                .map { $0.isWholeNumber ? "8" : $0 }
        })
        #expect(shapes == [Array("88.8")])
    }

    @Test func stringWithUnitAddsSymbol() {
        #expect(WeightFormat.stringWithUnit(kilograms: 62.5, scale: WeightScale(unit: .kg), locale: posix) == "62.5 kg")
    }

    @Test func volumeIsWholeAndGrouped() {
        let us = Locale(identifier: "en_US")
        #expect(WeightFormat.volume(kilograms: 6240.4, unit: .kg, locale: us) == "6,240")
        #expect(WeightFormat.volume(kilograms: 453.59237, unit: .lb, locale: us) == "1,000")
        #expect(WeightFormat.volume(kilograms: 0, unit: .kg, locale: us) == "0")
    }

    @Test func customStepControlsFractionDigits() {
        #expect(WeightScale(unit: .kg).fractionDigits == 1)
        #expect(WeightScale(unit: .lb).fractionDigits == 0)
        #expect(WeightScale(unit: .kg, step: 1.25).fractionDigits == 2)
        #expect(WeightScale(unit: .kg, step: 2.5).fractionDigits == 1)
        #expect(WeightScale(unit: .kg, step: 0).step == 0.5)
        #expect(WeightScale(unit: .lb, step: -1).step == 1)
    }

    @Test(arguments: [WeightUnit.kg, .lb])
    func crownRoundTripNeverDrifts(unit: WeightUnit) {
        let scale = WeightScale(unit: unit)
        var stored = scale.kilograms(forSteps: 120)
        let original = stored
        // Many up/down edits, each going through the stored kilograms.
        for round in 0..<500 {
            let delta = round.isMultiple(of: 2) ? 7 : -7
            stored = scale.kilograms(forSteps: scale.steps(forKilograms: stored) + delta)
        }
        #expect(stored == original)
        #expect(scale.steps(forKilograms: stored) == 120)
    }

    @Test func everyStepRoundTripsExactly() {
        for unit in WeightUnit.allCases {
            let scale = WeightScale(unit: unit)
            for steps in 0...scale.maximumSteps {
                #expect(scale.steps(forKilograms: scale.kilograms(forSteps: steps)) == steps)
            }
        }
    }

    @Test func switchingUnitsSnapsToTheNewGrid() {
        let kgScale = WeightScale(unit: .kg)
        let lbScale = WeightScale(unit: .lb)
        let stored = kgScale.kilograms(forSteps: 125) // 62.5 kg
        #expect(lbScale.displayValue(forKilograms: stored) == 138)
        let edited = lbScale.kilograms(forSteps: lbScale.steps(forKilograms: stored) + 1) // 139 lb
        #expect(lbScale.displayValue(forKilograms: edited) == 139)
        #expect(kgScale.displayValue(forKilograms: edited) == 63)
    }

    @Test func stepsClampToBounds() {
        let scale = WeightScale(unit: .kg)
        #expect(scale.maximumSteps == 1000)
        #expect(scale.kilograms(forSteps: -3) == 0)
        #expect(scale.kilograms(forSteps: 5000) == 500)
        #expect(scale.steps(forKilograms: -10) == 0)
        #expect(scale.steps(forKilograms: .nan) == 0)
        #expect(WeightScale(unit: .lb).maximumSteps == 1102)
    }

    @Test func startingWeightsFollowEquipmentAndUnit() {
        #expect(Equipment.barbell.startingWeightKilograms(in: .kg) == 20)
        #expect(Equipment.dumbbell.startingWeightKilograms(in: .kg) == 10)
        #expect(Equipment.machine.startingWeightKilograms(in: .kg) == 20)
        #expect(Equipment.cable.startingWeightKilograms(in: .kg) == 20)
        #expect(Equipment.bodyweight.startingWeightKilograms(in: .kg) == nil)
        #expect(Equipment.other.startingWeightKilograms(in: .lb) == nil)
        let bar = Equipment.barbell.startingWeightKilograms(in: .lb) ?? 0
        #expect(WeightScale(unit: .lb).displayValue(forKilograms: bar) == 45)
        let dumbbell = Equipment.dumbbell.startingWeightKilograms(in: .lb) ?? 0
        #expect(WeightScale(unit: .lb).displayValue(forKilograms: dumbbell) == 20)
    }
}
