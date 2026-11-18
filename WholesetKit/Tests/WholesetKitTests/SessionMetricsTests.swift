// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Estimated one-rep max")
struct OneRepMaxTests {
    @Test func singleRepIsTheWeightItself() {
        #expect(OneRepMax.estimate(weightKg: 100, reps: 1) == 100)
    }

    @Test func usesEpleyFromTwoToTwelveReps() throws {
        let ten = try #require(OneRepMax.estimate(weightKg: 60, reps: 10))
        #expect(abs(ten - 80) < 1e-9)
        let two = try #require(OneRepMax.estimate(weightKg: 90, reps: 2))
        #expect(abs(two - 96) < 1e-9)
        let twelve = try #require(OneRepMax.estimate(weightKg: 50, reps: 12))
        #expect(abs(twelve - 70) < 1e-9)
    }

    @Test(arguments: [13, 20, 0, -1])
    func noEstimateOutsideOneToTwelveReps(reps: Int) {
        #expect(OneRepMax.estimate(weightKg: 60, reps: reps) == nil)
    }

    @Test func noEstimateWithoutWeight() {
        #expect(OneRepMax.estimate(weightKg: nil, reps: 5) == nil)
        #expect(OneRepMax.estimate(weightKg: 0, reps: 5) == nil)
        #expect(OneRepMax.estimate(weightKg: -10, reps: 5) == nil)
        #expect(OneRepMax.estimate(weightKg: .nan, reps: 5) == nil)
        #expect(OneRepMax.estimate(weightKg: 60, reps: nil) == nil)
    }

    @Test func warmupsHaveNoEstimate() {
        #expect(H.set(60, 5, warmup: true).estimatedOneRepMaxKg == nil)
        #expect(H.set(60, 1).estimatedOneRepMaxKg == 60)
    }
}

@Suite("Session metrics")
struct SessionMetricsTests {
    private let bench = UUID()
    private let dips = UUID()

    @Test func volumeCountsOnlyWorkingSetsWithWeightAndReps() {
        let session = H.session(day: 0, [
            H.entry(bench, [
                H.set(40, 10, warmup: true),
                H.set(60, 10),
                H.set(60, 8),
                H.set(60, nil),
            ]),
            H.entry(dips, name: "Dips", [H.set(nil, 12), H.set(0, 10)]),
        ])
        #expect(SessionMetrics.volume(of: session) == 60 * 10 + 60 * 8)
        #expect(SessionMetrics.volumeByExercise(of: session) == [bench: 1_080, dips: 0])
    }

    @Test func workingSetCountExcludesWarmupsButCountsSkippedEntries() {
        let session = H.session(day: 0, [
            H.entry(bench, [H.set(40, 10, warmup: true), H.set(60, 10)]),
            H.entry(dips, name: "Dips", skipped: true, [H.set(nil, 12)]),
        ])
        #expect(SessionMetrics.workingSetCount(of: session) == 2)
        #expect(SessionMetrics.volume(of: session) == 600)
    }

    @Test func exerciseInTwoEntriesAddsUp() {
        let session = H.session(day: 0, [
            H.entry(bench, [H.set(60, 10)]),
            H.entry(dips, name: "Dips", [H.set(nil, 10)]),
            H.entry(bench, [H.set(50, 10)]),
        ])
        #expect(SessionMetrics.volumeByExercise(of: session)[bench] == 1_100)
    }

    @Test func durationIsEndMinusStartAndMissingWhenNotPositive() {
        let start = H.t0
        let normal = HistorySession(name: "A", startedAt: start, endedAt: start.addingTimeInterval(3_660), entries: [])
        #expect(SessionMetrics.duration(of: normal) == 3_660)
        let instant = HistorySession(name: "A", startedAt: start, endedAt: start, entries: [])
        #expect(SessionMetrics.duration(of: instant) == nil)
        let backwards = HistorySession(name: "A", startedAt: start, endedAt: start.addingTimeInterval(-5), entries: [])
        #expect(SessionMetrics.duration(of: backwards) == nil)
    }

    @Test func restIsTheGapToThePreviousLoggedSet() {
        let sets = [
            H.set(40, 10, warmup: true, at: H.t0),
            H.set(60, 10, at: H.t0.addingTimeInterval(124)),
            H.set(60, 9, at: H.t0.addingTimeInterval(124 + 131)),
        ]
        #expect(SessionMetrics.restBefore(sets) == [nil, 124, 131])
    }

    @Test func restIgnoresNonsenseGaps() {
        let sets = [
            H.set(60, 10, at: H.t0),
            H.set(60, 10, at: H.t0.addingTimeInterval(-30)),        // edited out of order
            H.set(60, 10, at: H.t0.addingTimeInterval(-30)),        // same timestamp (imported / added)
            H.set(60, 10, at: H.t0.addingTimeInterval(-30 + 1_800)), // exactly 30 min: shown
            H.set(60, 10, at: H.t0.addingTimeInterval(-30 + 3_601)), // over 30 min: hidden
        ]
        #expect(SessionMetrics.restBefore(sets) == [nil, nil, nil, 1_800, nil])
        #expect(SessionMetrics.restBefore([]) == [])
    }

    @Test func importedSources() {
        #expect(Source.importStrong.isImported)
        #expect(Source.importHevy.isImported)
        #expect(!Source.watch.isImported)
        #expect(!Source.phone.isImported)
        #expect(H.session(day: 0, source: .importHevy, []).isImported)
    }

    @Test func weightsBelowOneHundredthCountAsUnweighted() {
        #expect(H.set(0.004, 10).effectiveWeightKg == nil)
        #expect(H.set(0.004, 10).volumeKg == 0)
        #expect(H.set(0.005, 10).effectiveWeightKg == 0.005)
    }

    @Test func displayNameFallsBackToRoutineName() {
        let start = H.t0
        #expect(HistorySession(name: " Push ", routineName: "Old", startedAt: start, endedAt: start, entries: []).displayName == "Push")
        #expect(HistorySession(name: "", routineName: "Legs", startedAt: start, endedAt: start, entries: []).displayName == "Legs")
        #expect(HistorySession(name: "", startedAt: start, endedAt: start, entries: []).displayName == "")
    }
}

@Suite("Session detail")
struct SessionDetailTests {
    private let bench = UUID()
    private let dbBench = UUID()
    private let fly = UUID()
    private let curl = UUID()

    @Test func notesTellAddedSwappedAndSkippedEntries() {
        let slotA = UUID()
        let slotB = UUID()
        let entries = [
            H.entry(bench, slot: slotA, [H.set(60, 10)]),
            H.entry(dbBench, slot: slotA, [H.set(26, 10)]),
            H.entry(fly, slot: slotB, skipped: true, []),
            H.entry(curl, [H.set(12, 12)]),
        ]
        #expect(SessionDetail.notes(for: entries) == [nil, .swappedIn, .skipped, .added])
    }

    @Test func sessionsWithoutSlotsGetNoNotes() {
        let entries = [H.entry(bench, [H.set(60, 10)]), H.entry(curl, [H.set(12, 12)])]
        #expect(SessionDetail.notes(for: entries) == [nil, nil])
    }

    @Test func numbersWorkingSetsAndListsRestAndRecords() throws {
        let first = H.session(day: 0, [H.entry(bench, [H.set(60, 8)])])
        let pr = UUID()
        let second = H.session(day: 7, [
            H.entry(bench, [
                H.set(40, 10, warmup: true, at: H.t0),
                H.set(62.5, 10, id: pr, at: H.t0.addingTimeInterval(90)),
                H.set(62.5, 9, at: H.t0.addingTimeInterval(90 + 124)),
            ]),
            H.entry(fly, name: "Cable Fly", skipped: true, []),
            H.entry(curl, name: "Curl", []),
        ])
        let records = PersonalRecords.compute(from: [first, second])
        let detail = SessionDetail(session: second, records: records)
        #expect(detail.sections.map(\.exerciseName) == ["Bench Press", "Cable Fly"])
        let rows = try #require(detail.sections.first?.rows)
        #expect(rows.map(\.number) == [nil, 1, 2])
        #expect(rows.map(\.restBefore) == [nil, 90, 124])
        #expect(rows[1].id == pr)
        #expect(rows[1].records == [.weight, .estimatedOneRepMax])
        #expect(detail.sections.first?.isVolumeRecord == true)
        #expect(detail.workingSets == 2)
        #expect(detail.volumeKg == 62.5 * 19)
        #expect(detail.duration == 3_600)
    }
}
