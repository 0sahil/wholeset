// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Import: numbers, durations, units, keys and plans")
struct ImportValuesTests {
    @Test("Numbers: trimmed, decimal comma when unambiguous, nothing negative or invalid", arguments: [
        ("80", 80.0), (" 5", 5), ("62.5", 62.5), ("62,5", 62.5), ("0", 0), ("1e2", 100),
    ])
    func numbers(text: String, expected: Double) {
        #expect(ImportValues.number(text) == expected)
    }

    @Test("Absurdly large values are invalid rather than overflowing", arguments: [
        "1e19", "99999999999999999999", "9999999999999999:00:00", "9999999999999999h", "1e16",
    ])
    func huge(text: String) {
        #expect(ImportValues.durationSeconds(text) == nil)
        #expect(ImportValues.duration(text, bareNumberUnit: 60) == .invalid)
        #expect(ImportValues.count(text) != .value(0))
    }

    @Test("Invalid numbers", arguments: ["-5", "NaN", "inf", "1,234.5", "1.234,5", "1,2,3", "lots", "5 kg", "1e12"])
    func invalidNumbers(text: String) {
        #expect(ImportValues.number(text) == nil)
        #expect(ImportValues.decimal(text) == .invalid)
    }

    @Test("Counts accept 5.0 but not 7.5; RPE outside 0–10 is dropped")
    func counts() {
        #expect(ImportValues.count("5.0") == .value(5))
        #expect(ImportValues.count(" 12") == .value(12))
        #expect(ImportValues.count("") == .empty)
        #expect(ImportValues.count("7.5") == .invalid)
        #expect(ImportValues.rpe("8.5") == .value(8.5))
        #expect(ImportValues.rpe("0") == .empty)
        #expect(ImportValues.rpe("12") == .empty)
    }

    @Test("Durations in Strong's and clock formats", arguments: [
        ("35m", 2_100), ("1h 5m", 3_900), ("2h", 7_200), ("38min", 2_280), ("2h 38m", 9_480), ("42h 13m", 151_980),
        ("4419", 4_419), ("60.0", 60), ("0:10:00", 600), ("30:00", 1_800), ("45s", 45), ("1h 5m 30s", 3_930),
    ])
    func durations(text: String, seconds: Int) {
        #expect(ImportValues.durationSeconds(text) == seconds)
    }

    @Test("Unreadable durations", arguments: ["soon", "1h x", "m5", "1:2:3:4", "-5"])
    func badDurations(text: String) {
        #expect(ImportValues.durationSeconds(text) == nil)
    }

    @Test("A bare generic duration can be read as minutes")
    func minutes() {
        #expect(ImportValues.duration("45", bareNumberUnit: 60) == .value(2_700))
    }

    @Test("Weight units as files write them")
    func units() {
        #expect(["kg", "KGS", " kgs ", "kilograms"].allSatisfy { ImportValues.weightUnit($0) == .kg })
        #expect(["lb", "lbs", "LBS", "pounds"].allSatisfy { ImportValues.weightUnit($0) == .lb })
        #expect(ImportValues.weightUnit("km") == nil)
        #expect(ImportValues.weightUnit("") == nil)
    }

    @Test("Fitbod weights: whole quarter-kilograms stay, pound noise snaps to the exact pounds, else 0.01 kg")
    func fitbodSnapping() {
        let pound = WeightUnit.kilogramsPerPound
        #expect(ImportValues.fitbodKilograms(61.235042773811365) == 135 * pound)
        #expect(ImportValues.fitbodKilograms(43.0913264) == 95 * pound)
        #expect(ImportValues.fitbodKilograms(7.937875915123695) == 17.5 * pound)
        #expect(ImportValues.fitbodKilograms(20) == 20)
        #expect(ImportValues.fitbodKilograms(2.5) == 2.5)
        #expect(ImportValues.fitbodKilograms(22.5) == 22.5)
        #expect(ImportValues.fitbodKilograms(21.3) == 21.3)
        #expect(ImportValues.fitbodKilograms(30.123) == 30.12)
    }

    @Test("No half-pound weight up to 1,000 lb looks like a whole quarter-kilogram")
    func quarterKilogramsAreNotPounds() {
        for halfPounds in 1...2_000 {
            let kilograms = Double(halfPounds) / 2 * WeightUnit.kilogramsPerPound
            let quarters = kilograms / 0.25
            let isQuarter = abs(quarters - quarters.rounded()) < 1e-6
            #expect(!isQuarter, "\(Double(halfPounds) / 2) lb")
        }
    }

    @Test("Rows without reps are classified")
    func classify() {
        #expect(ImportValues.classify(weightKg: 50, reps: 5, durationSeconds: nil, distanceMeters: nil) == nil)
        #expect(ImportValues.classify(weightKg: nil, reps: 8, durationSeconds: nil, distanceMeters: nil) == nil)
        #expect(ImportValues.classify(weightKg: nil, reps: 0, durationSeconds: 60, distanceMeters: nil) == .timedOrDistanceOnly)
        #expect(ImportValues.classify(weightKg: 40, reps: nil, durationSeconds: nil, distanceMeters: 50) == .timedOrDistanceOnly)
        #expect(ImportValues.classify(weightKg: 40, reps: 0, durationSeconds: nil, distanceMeters: nil) == .weightWithoutReps)
        #expect(ImportValues.classify(weightKg: nil, reps: nil, durationSeconds: nil, distanceMeters: nil) == .noSetData)
    }

    @Test("Strong's set order column")
    func setOrder() {
        #expect(StrongSetOrder("3") == .working(3))
        #expect(StrongSetOrder("w") == .warmup)
        #expect(StrongSetOrder("D") == .drop)
        #expect(StrongSetOrder("F") == .failure)
        #expect(StrongSetOrder("Rest Timer") == .restTimer)
        #expect(StrongSetOrder("Note") == .note)
        #expect(StrongSetOrder("Pausentimer") == .other)
    }

    // MARK: Keys and plans

    @Test("The key is the UTC start to the second and the normalised name")
    func key() {
        let start = Date(timeIntervalSince1970: 1_760_000_000.9)
        #expect(ImportKey.externalKey(start: start, name: "  Push   DAY ") == "2025-10-09T08:53:20Z|push day")
        #expect(ImportKey.externalKey(start: start, name: "") == "2025-10-09T08:53:20Z|")
        let kolkata = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        #expect(ImportKey.externalKey(start: start, name: "Push", wallClockZone: kolkata) == "2025-10-09T14:23:20|push")
    }

    @Test("Planning skips workouts already imported, repeated in the file, or empty")
    func plan() throws {
        let result = try ImportFixture.parse("hevy-us-lbs")
        let all = result.allWorkouts
        let fresh = ImportPlan(workouts: all, existingKeys: [])
        #expect(fresh.insertCount == 2)
        #expect(fresh.emptyWorkouts == 1)
        #expect(fresh.alreadyImported == 0)

        let again = ImportPlan(workouts: all, existingKeys: Set(fresh.toInsert.map(\.externalKey)))
        #expect(again.insertCount == 0)
        #expect(again.alreadyImported == 2)

        let doubled = ImportPlan(workouts: all + all, existingKeys: [])
        #expect(doubled.insertCount == 2)
        #expect(doubled.repeatedInFile == 2)
        #expect(doubled.emptyWorkouts == 2)
    }

    @Test("A newer export adds only the new workouts")
    func newerExport() throws {
        let older = try ImportFixture.parse("hevy-en-kg")
        let existing = Set(older.workouts.dropFirst().map(\.externalKey))
        let plan = ImportPlan(workouts: older.allWorkouts, existingKeys: existing)
        #expect(plan.toInsert.map(\.name) == ["Upper Power"])
        #expect(plan.toInsert.first?.startedAt == ImportFixture.date(2026, 10, 7, 18, 5))
        #expect(plan.alreadyImported == 3)
    }
}
