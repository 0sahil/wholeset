// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Rest timer")
struct RestTimerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func countsDownFromTheEndDate() {
        let timer = RestTimer.start(duration: 90, now: t0)
        #expect(timer.endDate == t0.addingTimeInterval(90))
        #expect(timer.remaining(at: t0) == 90)
        #expect(timer.remaining(at: t0.addingTimeInterval(30)) == 60)
        #expect(!timer.isFinished(at: t0.addingTimeInterval(89.9)))
        #expect(timer.isFinished(at: t0.addingTimeInterval(90)))
        #expect(timer.remaining(at: t0.addingTimeInterval(500)) == 0)
    }

    @Test func survivesALongGapBecauseItIsDateBased() throws {
        let timer = RestTimer.start(duration: 120, now: t0)
        let data = try JSONEncoder().encode(timer)
        let restored = try JSONDecoder().decode(RestTimer.self, from: data)
        #expect(restored == timer)
        #expect(restored.remaining(at: t0.addingTimeInterval(100)) == 20)
    }

    @Test func extendAddsThirtySeconds() {
        var timer = RestTimer.start(duration: 60, now: t0)
        timer.extend(now: t0.addingTimeInterval(10))
        #expect(timer.endDate == t0.addingTimeInterval(90))
        #expect(timer.totalDuration == 90)
        #expect(timer.remaining(at: t0.addingTimeInterval(10)) == 80)
    }

    @Test func extendAfterTheEndCountsFromNow() {
        var timer = RestTimer.start(duration: 60, now: t0)
        timer.extend(now: t0.addingTimeInterval(100))
        #expect(timer.endDate == t0.addingTimeInterval(130))
        #expect(!timer.isFinished(at: t0.addingTimeInterval(100)))
    }

    @Test func skipEndsNow() {
        var timer = RestTimer.start(duration: 60, now: t0)
        timer.skip(now: t0.addingTimeInterval(5))
        #expect(timer.isFinished(at: t0.addingTimeInterval(5)))
        #expect(timer.remaining(at: t0.addingTimeInterval(5)) == 0)
        timer.skip(now: t0.addingTimeInterval(50))
        #expect(timer.endDate == t0.addingTimeInterval(5))
    }

    @Test func fractionRemaining() {
        let timer = RestTimer.start(duration: 100, now: t0)
        #expect(timer.fractionRemaining(at: t0) == 1)
        #expect(timer.fractionRemaining(at: t0.addingTimeInterval(25)) == 0.75)
        #expect(timer.fractionRemaining(at: t0.addingTimeInterval(200)) == 0)
        #expect(RestTimer.start(duration: 0, now: t0).fractionRemaining(at: t0) == 0)
        #expect(RestTimer.start(duration: -5, now: t0).totalDuration == 0)
    }

    @Test(arguments: [
        (Int?(120), Int?(60), Int?(90), 120.0),
        (nil, 60, 90, 60),
        (nil, nil, 75, 75),
        (nil, nil, nil, 90),
        (-1, nil, 45, 45),
        (0, 60, 90, 0),
    ])
    func durationFallsBackRoutineThenExerciseThenSettings(item: Int?, exercise: Int?, app: Int?, expected: Double) {
        #expect(RestTimer.duration(routineItemSeconds: item, exerciseSeconds: exercise, appDefaultSeconds: app) == expected)
    }
}

@Suite("Workout clock")
struct WorkoutClockTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func runsFromTheStart() {
        let clock = WorkoutClock(startedAt: t0)
        #expect(clock.elapsed(at: t0.addingTimeInterval(65)) == 65)
        #expect(clock.elapsed(at: t0.addingTimeInterval(-5)) == 0)
        #expect(clock.effectiveStart == t0)
    }

    @Test func pausesAreExcluded() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(at: t0.addingTimeInterval(60))
        #expect(clock.isPaused)
        #expect(clock.elapsed(at: t0.addingTimeInterval(200)) == 60)
        clock.pause(at: t0.addingTimeInterval(100))
        clock.resume(at: t0.addingTimeInterval(120))
        #expect(!clock.isPaused)
        #expect(clock.pausedDuration == 60)
        #expect(clock.elapsed(at: t0.addingTimeInterval(180)) == 120)
        #expect(clock.effectiveStart == t0.addingTimeInterval(60))
        clock.resume(at: t0.addingTimeInterval(500))
        #expect(clock.pausedDuration == 60)
    }

    @Test func roundTripsThroughCoding() throws {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(at: t0.addingTimeInterval(10))
        let restored = try JSONDecoder().decode(WorkoutClock.self, from: JSONEncoder().encode(clock))
        #expect(restored == clock)
    }
}
