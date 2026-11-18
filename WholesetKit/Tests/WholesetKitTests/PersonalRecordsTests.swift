// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Personal records and PRs")
struct PersonalRecordsTests {
    private let bench = UUID()
    private let dips = UUID()

    @Test func firstSessionSetsABaselineWithoutBadges() {
        let only = H.session(day: 0, [H.entry(bench, H.sets([(60, 10), (62.5, 8), (65, 5)]))])
        let records = PersonalRecords.compute(from: [only])
        #expect(records.count(forSession: only.id) == 0)
        #expect(only.entries[0].sets.allSatisfy { records.kinds(forSet: $0.id).isEmpty })
        #expect(!records.hasVolumeRecord(session: only.id, exercise: bench))
        #expect(records.records(forExercise: bench)?.heaviest?.weightKg == 65)
    }

    @Test func heavierWeightAndBetterEstimateAreRecords() throws {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10), (60, 10)]))])
        let heavier = H.set(65, 6)
        let second = H.session(day: 3, [H.entry(bench, [H.set(62.5, 8), heavier])])
        let records = PersonalRecords.compute(from: [first, second])
        // 65 × 6 is heavier than 60 but its estimate (78) is below 60 × 10 (80).
        #expect(records.kinds(forSet: heavier.id) == [.weight])
        // Volume 62.5×8 + 65×6 = 890 < 1200: no volume PR.
        #expect(records.count(forSession: second.id) == 1)
        let heaviest = try #require(records.records(forExercise: bench)?.heaviest)
        #expect(heaviest.weightKg == 65)
        #expect(heaviest.reps == 6)
        #expect(heaviest.sessionID == second.id)
        #expect(heaviest.date == second.startedAt)
        #expect(records.records(forExercise: bench)?.bestOneRepMax?.set.sessionID == first.id)
    }

    @Test func onlyTheBestSetOfASessionEarnsEachKind() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 8)]))])
        let a = H.set(62.5, 8)
        let b = H.set(65, 5)
        let c = H.set(65, 6)
        let d = H.set(65, 6)
        let second = H.session(day: 2, [H.entry(bench, [a, b, c, d])])
        let records = PersonalRecords.compute(from: [first, second])
        // Weight: heaviest 65, most reps at it 6, earliest of the tie (c).
        // Estimate: 62.5 × 8 (79.2) beats 65 × 6 (78) and 65 × 5 (75.8).
        #expect(records.kinds(forSet: a.id) == [.estimatedOneRepMax])
        #expect(records.kinds(forSet: b.id).isEmpty)
        #expect(records.kinds(forSet: c.id) == [.weight])
        #expect(records.kinds(forSet: d.id).isEmpty)
        #expect(records.hasVolumeRecord(session: second.id, exercise: bench))
        #expect(records.count(forSession: second.id) == 3)
    }

    @Test func repPROnlyAtAWeightDoneBefore() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 8), (50, 12)]))])
        let moreAt60 = H.set(60, 9)
        let newWeight = H.set(55, 15)
        let second = H.session(day: 2, [H.entry(bench, [newWeight, moreAt60])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.kinds(forSet: moreAt60.id).contains(.reps))
        #expect(!records.kinds(forSet: newWeight.id).contains(.reps))
    }

    @Test func repPRGoesToTheHeaviestOfSeveralWeights() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 8), (50, 10)]))])
        let at50 = H.set(50, 12)
        let at60 = H.set(60, 9)
        let second = H.session(day: 2, [H.entry(bench, [at50, at60])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.kinds(forSet: at60.id).contains(.reps))
        #expect(!records.kinds(forSet: at50.id).contains(.reps))
        // Both weights still update the table.
        let table = records.records(forExercise: bench)?.repsByWeight.map { ($0.weightKg, $0.reps) }
        #expect(table?.map(\.0) == [60, 50])
        #expect(table?.map(\.1) == [9, 12])
    }

    @Test func equalIsNotAPR() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        let second = H.session(day: 2, [H.entry(bench, H.sets([(60, 10)]))])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.count(forSession: second.id) == 0)
        // The earlier set keeps the record on a tie.
        #expect(records.records(forExercise: bench)?.heaviest?.sessionID == first.id)
        #expect(records.records(forExercise: bench)?.bestSessionVolume?.sessionID == first.id)
        #expect(records.records(forExercise: bench)?.repsByWeight.first?.record.sessionID == first.id)
    }

    @Test func warmupsNeverCount() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        let warmup = H.set(100, 5, warmup: true)
        let second = H.session(day: 2, [H.entry(bench, [warmup, H.set(50, 10)])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.kinds(forSet: warmup.id).isEmpty)
        #expect(records.count(forSession: second.id) == 0)
        #expect(records.records(forExercise: bench)?.heaviest?.weightKg == 60)
        // A session with only warm-ups does not start the exercise's history either.
        let onlyWarmups = H.session(day: 0, [H.entry(dips, [H.set(20, 10, warmup: true)])])
        #expect(PersonalRecords.compute(from: [onlyWarmups]).records(forExercise: dips) == nil)
    }

    @Test func skippedEntriesLoggedSetsStillCount() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        let set = H.set(70, 5)
        let second = H.session(day: 2, [H.entry(bench, skipped: true, [set])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.kinds(forSet: set.id).contains(.weight))
    }

    @Test func importedSessionsCountAsHistory() {
        let imported = H.session(day: 0, source: .importStrong, [H.entry(bench, H.sets([(80, 5)]))])
        let set = H.set(75, 5)
        let logged = H.session(day: 2, [H.entry(bench, [set])])
        let records = PersonalRecords.compute(from: [logged, imported])
        #expect(records.kinds(forSet: set.id).isEmpty)
        #expect(records.records(forExercise: bench)?.heaviest?.sessionID == imported.id)
    }

    @Test func sameStartTimeTiesResolveByID() {
        let early = H.id(1)
        let late = H.id(2)
        let a = H.set(60, 10)
        let b = H.set(65, 10)
        let sessionA = H.session(day: 0, id: early, [H.entry(bench, [a])])
        let sessionB = H.session(day: 0, id: late, [H.entry(bench, [b])])
        for input in [[sessionA, sessionB], [sessionB, sessionA]] {
            let records = PersonalRecords.compute(from: input)
            #expect(records.kinds(forSet: a.id).isEmpty)
            #expect(records.kinds(forSet: b.id) == [.weight, .estimatedOneRepMax])
            #expect(records.hasVolumeRecord(session: late, exercise: bench))
        }
    }

    @Test func poundsDoNotMakePRsOutOfRoundingNoise() {
        let pounds = WeightUnit.lb
        let first = H.session(day: 0, [H.entry(bench, H.sets([(pounds.kilograms(fromValue: 135), 8)]))])
        // The same 135 lb converted another way, a hair heavier in kilograms.
        let noisy = H.set(61.234_995_001, 8)
        let second = H.session(day: 2, [H.entry(bench, [noisy])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.kinds(forSet: noisy.id).isEmpty)
        #expect(records.count(forSession: second.id) == 0)
        #expect(records.records(forExercise: bench)?.repsByWeight.count == 1)
    }

    @Test func unweightedSetsHaveMostRepsAndRepPRs() {
        let first = H.session(day: 0, [H.entry(dips, name: "Dips", H.sets([(nil, 10), (nil, 8)]))])
        let more = H.set(nil, 12)
        let weighted = H.set(10, 6)
        let second = H.session(day: 2, [H.entry(dips, name: "Dips", [more, weighted])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.kinds(forSet: more.id) == [.reps])
        // The first weighted set is a baseline for weight: no weight PR.
        #expect(records.kinds(forSet: weighted.id).isEmpty)
        #expect(records.records(forExercise: dips)?.mostReps?.reps == 12)
        #expect(records.records(forExercise: dips)?.repsByWeight.map(\.weightKg) == [10])
        #expect(records.records(forExercise: dips)?.bestSessionVolume?.volumeKg == 60)
        // No volume PR on the first session that had volume.
        #expect(!records.hasVolumeRecord(session: second.id, exercise: dips))
    }

    @Test func weightedRepPRRanksAboveUnweighted() {
        let first = H.session(day: 0, [H.entry(dips, H.sets([(nil, 10), (10, 5)]))])
        let unweighted = H.set(nil, 11)
        let weighted = H.set(10, 6)
        let second = H.session(day: 2, [H.entry(dips, [unweighted, weighted])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.kinds(forSet: weighted.id).contains(.reps))
        #expect(!records.kinds(forSet: unweighted.id).contains(.reps))
    }

    @Test func thirteenRepSetsHaveNoEstimate() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(40, 12)]))])
        let high = H.set(50, 13)
        let second = H.session(day: 2, [H.entry(bench, [high])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.kinds(forSet: high.id) == [.weight])
        #expect(records.records(forExercise: bench)?.bestOneRepMax?.set.weightKg == 40)
    }

    @Test func oneRepSetUsesItsWeightAsEstimate() throws {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(80, 5)]))]) // 93.33
        let single = H.set(95, 1)
        let second = H.session(day: 2, [H.entry(bench, [single])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.kinds(forSet: single.id) == [.weight, .estimatedOneRepMax])
        let best = try #require(records.records(forExercise: bench)?.bestOneRepMax)
        #expect(best.estimateKg == 95)
    }

    @Test func countIsDistinctExerciseKindPairs() {
        let first = H.session(day: 0, [
            H.entry(bench, H.sets([(60, 8)])),
            H.entry(dips, name: "Dips", H.sets([(nil, 10)])),
        ])
        let second = H.session(day: 2, [
            H.entry(bench, H.sets([(65, 8), (65, 8)])),  // weight, e1RM, volume
            H.entry(dips, name: "Dips", H.sets([(nil, 12), (nil, 11)])), // reps
        ])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.count(forSession: second.id) == 4)
    }

    @Test func swappedBackExerciseIsOneGroupPerSession() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        let late = H.set(60, 10)
        let second = H.session(day: 2, [
            H.entry(bench, H.sets([(60, 10)])),
            H.entry(dips, name: "Dips", H.sets([(nil, 10)])),
            H.entry(bench, [late]),
        ])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.hasVolumeRecord(session: second.id, exercise: bench))
        #expect(records.records(forExercise: bench)?.bestSessionVolume?.volumeKg == 1_200)
    }

    @Test func recordsListRepsByWeightHeaviestFirst() {
        let sessions = [
            H.session(day: 0, [H.entry(bench, H.sets([(50, 12), (60, 8)]))]),
            H.session(day: 2, [H.entry(bench, H.sets([(55, 10), (60, 9), (50, 11)]))]),
        ]
        let table = PersonalRecords.compute(from: sessions).records(forExercise: bench)?.repsByWeight ?? []
        #expect(table.map(\.weightKg) == [60, 55, 50])
        #expect(table.map(\.reps) == [9, 10, 12])
        #expect(table.map(\.record.sessionID) == [sessions[1].id, sessions[1].id, sessions[0].id])
    }

    @Test func setsWithoutRepsOrExerciseAreIgnored() {
        let first = H.session(day: 0, [H.entry(bench, H.sets([(60, 10)]))])
        let noReps = H.set(100, nil)
        let zeroReps = H.set(100, 0)
        let orphan = H.set(200, 5)
        let second = H.session(day: 2, [H.entry(bench, [noReps, zeroReps]), H.entry(nil, [orphan])])
        let records = PersonalRecords.compute(from: [first, second])
        #expect(records.count(forSession: second.id) == 0)
        #expect(records.records(forExercise: bench)?.heaviest?.weightKg == 60)
    }

    /// Years of history are read in one pass: every logged working set exactly once.
    @Test func computesInOnePassOverTheHistory() {
        let exercises = (0..<6).map { _ in UUID() }
        var sessions: [HistorySession] = []
        for index in 0..<500 {
            let weight = 40 + Double(index) * 0.5
            let entries = exercises.map { exercise in
                H.entry(exercise, [H.set(20, 10, warmup: true)] + H.sets([(weight, 8), (weight, 8), (weight, 7), (weight, 6)]))
            }
            sessions.append(H.session(day: Double(index) * 2, entries))
        }
        var statistics = PersonalRecords.Statistics()
        let records = PersonalRecords.compute(from: sessions.shuffled(), statistics: &statistics)
        #expect(statistics.sessions == 500)
        #expect(statistics.setVisits == 500 * 6 * 4)
        // Each later session is heavier: weight, estimate and volume PRs on every exercise.
        #expect(records.count(forSession: sessions[0].id) == 0)
        #expect(sessions.dropFirst().allSatisfy { records.count(forSession: $0.id) == 18 })
        #expect(records.records(forExercise: exercises[0])?.repsByWeight.count == 500)
    }
}
