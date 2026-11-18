// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import WholesetKit

@Suite("Rest wheels")
struct RestComponentsTests {
    @Test func wheelsOfferTenMinutesAndQuarterMinutes() {
        #expect(RestComponents.minuteChoices == Array(0...10))
        #expect(RestComponents.secondChoices == [0, 15, 30, 45])
    }

    @Test func splitsTotalSeconds() {
        let rest = RestComponents(totalSeconds: 90)
        #expect(rest.minutes == 1)
        #expect(rest.seconds == 30)
        #expect(rest.totalSeconds == 90)
        #expect(RestComponents(totalSeconds: 45) == RestComponents(minutes: 0, seconds: 45))
        #expect(RestComponents(totalSeconds: 600) == RestComponents(minutes: 10, seconds: 0))
    }

    @Test(arguments: [
        (0, 15), (-30, 15), (7, 15), (97, 90), (98, 105), (601, 600), (10_000, 600), (Int.max, 600), (Int.min, 15),
    ])
    func totalIsAlwaysAValidRest(input: Int, expected: Int) {
        let rest = RestComponents(totalSeconds: input)
        #expect(rest.totalSeconds == expected)
        #expect(rest.totalSeconds == RoutineRules.normalizedRest(expected))
    }

    @Test func zeroSnapsToFifteenSeconds() {
        #expect(RestComponents(minutes: 0, seconds: 0).totalSeconds == 15)
        #expect(RestComponents(totalSeconds: 60).settingMinutes(0).totalSeconds == 15)
        #expect(RestComponents(totalSeconds: 15).settingSeconds(0).totalSeconds == 15)
    }

    @Test func tenMinutesForcesZeroSeconds() {
        let rest = RestComponents(totalSeconds: 90).settingMinutes(10)
        #expect(rest.minutes == 10)
        #expect(rest.seconds == 0)
        #expect(RestComponents(totalSeconds: 600).settingSeconds(45).totalSeconds == 600)
    }

    @Test func oneWheelKeepsTheOther() {
        let rest = RestComponents(totalSeconds: 135)
        #expect(rest.settingMinutes(4) == RestComponents(minutes: 4, seconds: 15))
        #expect(rest.settingSeconds(45) == RestComponents(minutes: 2, seconds: 45))
    }

    @Test func outOfRangeWheelValuesAreClamped() {
        #expect(RestComponents(minutes: -3, seconds: 30).totalSeconds == 30)
        #expect(RestComponents(minutes: 99, seconds: 0).totalSeconds == 600)
        #expect(RestComponents(minutes: Int.max, seconds: Int.max).totalSeconds == 600)
        #expect(RestComponents(minutes: 1, seconds: 20).totalSeconds == 75)
    }

    @Test func everyWheelPairIsValid() {
        for minutes in RestComponents.minuteChoices {
            for seconds in RestComponents.secondChoices {
                let rest = RestComponents(minutes: minutes, seconds: seconds)
                #expect(RoutineRules.restRange.contains(rest.totalSeconds))
                #expect(RestComponents.minuteChoices.contains(rest.minutes))
                #expect(RestComponents.secondChoices.contains(rest.seconds))
            }
        }
    }
}
