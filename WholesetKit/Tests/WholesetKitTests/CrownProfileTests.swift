// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Crown sensitivity")
struct CrownProfileTests {
    @Test func normalReproducesTheDeviceTestedSettings() {
        #expect(CrownProfile.weight(.normal) == CrownProfile(rate: .low, detentsPerStep: 1))
        #expect(CrownProfile.reps(.normal) == CrownProfile(rate: .medium, detentsPerStep: 1))
        #expect(CrownProfile.weight(.normal).usesSystemHaptics)
        #expect(CrownProfile.reps(.normal).usesSystemHaptics)
        #expect(CrownProfile.exerciseNavigation == CrownProfile(rate: .low))
    }

    @Test func slowIsSlowerThanNormalIsSlowerThanFast() {
        for profile in [CrownProfile.weight, CrownProfile.reps] {
            #expect(profile(.slow).isSlower(than: profile(.normal)))
            #expect(profile(.normal).isSlower(than: profile(.fast)))
            #expect(profile(.slow).isSlower(than: profile(.fast)))
            #expect(!profile(.fast).isSlower(than: profile(.normal)))
            #expect(!profile(.normal).isSlower(than: profile(.normal)))
        }
    }

    @Test func onlySlowWeightUsesAppHaptics() {
        #expect(!CrownProfile.weight(.slow).usesSystemHaptics)
        #expect(CrownProfile.weight(.slow).detentsPerStep == 2)
        #expect(CrownProfile.weight(.fast).usesSystemHaptics)
        for sensitivity in CrownSensitivity.allCases {
            #expect(CrownProfile.reps(sensitivity).usesSystemHaptics)
        }
        #expect(CrownProfile(rate: .high, detentsPerStep: 0).detentsPerStep == 1)
    }

    // MARK: CrownEdit with several detents per step

    private func weightEdit(_ value: Int = 120) -> CrownEdit {
        CrownEdit(value: value, isStored: true, bounds: 0...1000, span: 100, detentsPerStep: 2)
    }

    @Test func theDetentWindowKeepsItsWidth() {
        let edit = weightEdit()
        #expect(edit.position == 240)
        #expect(edit.crownRange == 190...290)
        #expect(edit.crownRange.upperBound - edit.crownRange.lowerBound == 100)
        #expect(edit.window.span == 50)
    }

    @Test func twoDetentsMakeOneStepInEitherDirection() {
        var edit = weightEdit()
        // (position, whether the value changes, value afterwards)
        let turns: [(Int, Bool, Int)] = [
            (241, false, 120), (242, true, 121), (241, false, 121), (240, true, 120),
            (239, false, 120), (238, true, 119), (250, true, 125),
        ]
        for (position, changes, value) in turns {
            let changed = edit.crownMoved(to: position)
            #expect(changed == changes, "at \(position)")
            #expect(edit.value == value, "at \(position)")
            #expect(edit.position == position)
        }
        #expect(edit.hasMoved)
    }

    @Test func aFullTurnMovesHalfAsFarAsNormal() {
        var slow = weightEdit()
        var normal = CrownEdit(value: 120, isStored: true, bounds: 0...1000, span: 100)
        slow.crownMoved(to: slow.position + 40)
        normal.crownMoved(to: normal.value + 40)
        #expect(slow.value - 120 == 20)
        #expect(normal.value - 120 == 40)
    }

    @Test func positionsAreClampedToTheWindowAndBounds() {
        var edit = weightEdit()
        edit.crownMoved(to: 10_000)
        #expect(edit.position == 290)
        #expect(edit.value == 145)
        var low = CrownEdit(value: 1, isStored: true, bounds: 0...1000, span: 100, detentsPerStep: 2)
        low.crownMoved(to: -50)
        #expect(low.value == 0)
        #expect(low.position == 0)
    }

    @Test func recentringDropsAHalfStepAndRecentresTheWindow() {
        var edit = weightEdit()
        edit.crownMoved(to: 262)
        edit.crownMoved(to: 263)
        #expect(edit.value == 131)
        edit.recentre()
        #expect(edit.position == 262)
        #expect(edit.anchor == 131)
        #expect(edit.crownRange == 212...312)
    }

    @Test func voiceOverStepsMoveTheValueAndPosition() {
        var edit = weightEdit()
        let small = edit.step(by: 3)
        #expect(small)
        #expect(edit.value == 123)
        #expect(edit.position == 246)
        let large = edit.step(by: 200)
        #expect(large)
        #expect(edit.anchor == 323)
        #expect(edit.crownRange.contains(edit.position))
    }

    @Test func oneDetentPerStepKeepsPositionEqualToValue() {
        var edit = CrownEdit(value: 60, isStored: false, bounds: 0...100, span: 100)
        for target in [61, 75, 74, 0, 100, 50] {
            edit.crownMoved(to: target)
            #expect(edit.position == edit.value)
            #expect(edit.value == target)
        }
        edit.step(by: -5)
        #expect(edit.position == edit.value)
    }

    @Test func weightRoundTripsStayExactAtEverySensitivity() {
        let scale = WeightScale(unit: .lb)
        for sensitivity in CrownSensitivity.allCases {
            let profile = CrownProfile.weight(sensitivity)
            let start = scale.steps(forKilograms: WeightUnit.lb.kilograms(fromValue: 135))
            var edit = CrownEdit(value: start, isStored: true, bounds: 0...scale.maximumSteps, span: 100, detentsPerStep: profile.detentsPerStep)
            edit.crownMoved(to: edit.position + 10 * profile.detentsPerStep)
            let kilograms = scale.kilograms(forSteps: edit.value)
            #expect(scale.displayValue(forKilograms: kilograms) == 145)
            #expect(scale.steps(forKilograms: kilograms) == edit.value)
        }
    }
}
