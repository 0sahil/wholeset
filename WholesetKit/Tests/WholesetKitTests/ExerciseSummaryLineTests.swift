// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Per-exercise summary lines")
struct ExerciseSummaryLineTests {
    private let bench = UUID()
    private let raise = UUID()
    private let dips = UUID()

    @Test func oneLinePerEntryWithWorkingSetsInWorkoutOrder() throws {
        let benchEntry = H.entry(bench, [H.set(20, 10, warmup: true)] + H.sets([(60, 10), (62.5, 8), (62.5, 8)]))
        let raiseEntry = H.entry(raise, name: "Lateral Raise", H.sets([(10, 12), (10, 12)]))
        let session = H.session(day: 0, [raiseEntry, benchEntry])
        let lines = ExerciseSummaryLine.lines(for: session)
        #expect(lines.map(\.exerciseName) == ["Lateral Raise", "Bench Press"])
        let benchLine = try #require(lines.last)
        #expect(benchLine.id == benchEntry.id)
        #expect(benchLine.exerciseID == bench)
        // The warm-up is not a working set and adds no volume.
        #expect(benchLine.workingSets == 3)
        #expect(benchLine.volumeKg == 600 + 500 + 500)
        #expect(benchLine.topSetWeightKg == 62.5)
        #expect(benchLine.topSetReps == 8)
    }

    @Test func entriesWithoutLoggedWorkingSetsAreLeftOut() {
        let session = H.session(day: 0, [
            H.entry(bench, skipped: true, []),
            H.entry(raise, name: "Lateral Raise", []),
            H.entry(dips, name: "Dips", [H.set(nil, 10, warmup: true)]),
        ])
        #expect(ExerciseSummaryLine.lines(for: session).isEmpty)
    }

    @Test func skippedEntryWithSetsKeepsItsLine() {
        let session = H.session(day: 0, [H.entry(bench, skipped: true, H.sets([(60, 10)]))])
        #expect(ExerciseSummaryLine.lines(for: session).map(\.workingSets) == [1])
    }

    @Test func topSetIsTheHeaviestThenMostReps() {
        let session = H.session(day: 0, [H.entry(bench, H.sets([(60, 10), (65, 5), (65, 6), (62.5, 12)]))])
        let line = ExerciseSummaryLine.lines(for: session).first
        #expect(line?.topSetWeightKg == 65)
        #expect(line?.topSetReps == 6)
    }

    @Test func fullTieTakesTheEarlierSet() {
        // Two sets that round to the same 0.01 kg: the first one's weight is kept.
        let session = H.session(day: 0, [H.entry(bench, H.sets([(61.231, 8), (61.234, 8)]))])
        #expect(ExerciseSummaryLine.lines(for: session).first?.topSetWeightKg == 61.231)
    }

    @Test func unweightedSetsHaveNoTopWeightNorVolume() {
        let session = H.session(day: 0, [H.entry(dips, name: "Dips", H.sets([(nil, 10), (nil, 12), (nil, 11)]))])
        let line = ExerciseSummaryLine.lines(for: session).first
        #expect(line?.topSetWeightKg == nil)
        #expect(line?.topSetReps == 12)
        #expect(line?.volumeKg == 0)
        #expect(line?.workingSets == 3)
    }

    @Test func swappedBackExerciseGetsALinePerEntry() {
        let session = H.session(day: 0, [
            H.entry(bench, H.sets([(60, 10)])),
            H.entry(raise, name: "Lateral Raise", H.sets([(10, 12)])),
            H.entry(bench, H.sets([(60, 8), (60, 8)])),
        ])
        let lines = ExerciseSummaryLine.lines(for: session)
        #expect(lines.map(\.exerciseName) == ["Bench Press", "Lateral Raise", "Bench Press"])
        #expect(lines.map(\.volumeKg) == [600, 120, 960])
    }

    @Test func linesAddUpToTheSessionTotals() {
        let session = H.session(day: 0, [
            H.entry(bench, [H.set(20, 10, warmup: true)] + H.sets([(60, 10), (60, 9)])),
            H.entry(dips, name: "Dips", H.sets([(nil, 10), (10, 8)])),
        ])
        let lines = ExerciseSummaryLine.lines(for: session)
        #expect(lines.reduce(0) { $0 + $1.workingSets } == SessionMetrics.workingSetCount(of: session))
        #expect(lines.reduce(0) { $0 + $1.volumeKg } == SessionMetrics.volume(of: session))
    }
}
