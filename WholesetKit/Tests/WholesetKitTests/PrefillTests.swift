// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Pre-fill")
struct PrefillTests {
    private typealias S = Prefill.SetState

    private func last(_ sets: [PerformedSet]) -> LastPerformance {
        LastPerformance(sessionID: UUID(), date: .distantPast, sets: sets)
    }

    private func working(_ weight: Double?, _ reps: Int?) -> PerformedSet {
        PerformedSet(weightKg: weight, reps: reps, isWarmup: false)
    }

    private func warmup(_ weight: Double?, _ reps: Int?) -> PerformedSet {
        PerformedSet(weightKg: weight, reps: reps, isWarmup: true)
    }

    private func logged(_ weight: Double?, _ reps: Int?, warmup: Bool = false) -> S {
        S(isWarmup: warmup, weightKg: weight, reps: reps, isLogged: true)
    }

    private func values(_ index: Int, _ sets: [S], _ last: LastPerformance?, floor: Int? = 8) -> SetValues {
        Prefill.values(at: index, in: sets, last: last, repFloor: floor)
    }

    // MARK: Last performance matching

    @Test func workingSetNMatchesWorkingSetN() {
        let history = last([warmup(20, 10), working(60, 10), working(60, 9), working(57.5, 8)])
        #expect(history.matchingSet(isWarmup: false, index: 0) == working(60, 10))
        #expect(history.matchingSet(isWarmup: false, index: 2) == working(57.5, 8))
        #expect(history.matchingSet(isWarmup: true, index: 0) == warmup(20, 10))
    }

    @Test func extraSetsCopyTheLastOfTheirKind() {
        let history = last([warmup(20, 10), working(60, 10), working(62.5, 8)])
        #expect(history.matchingSet(isWarmup: false, index: 5) == working(62.5, 8))
        #expect(history.matchingSet(isWarmup: true, index: 3) == warmup(20, 10))
    }

    @Test func warmupsNeverTakeWorkingValues() {
        let history = last([working(60, 10)])
        #expect(history.matchingSet(isWarmup: true, index: 0) == nil)
        #expect(last([warmup(20, 10)]).matchingSet(isWarmup: false, index: 0) == nil)
    }

    @Test func topSetIsHeaviestThenMostReps() {
        #expect(last([warmup(100, 1), working(60, 10), working(62.5, 6), working(62.5, 8)]).topSet == working(62.5, 8))
        #expect(last([warmup(20, 10)]).topSet == warmup(20, 10))
        #expect(last([working(nil, 12), working(nil, 15)]).topSet == working(nil, 15))
        #expect(last([]).topSet == nil)
    }

    // MARK: Precedence

    @Test func noHistoryStartsAtTheRepFloorWithoutWeight() {
        #expect(values(0, [S(), S()], nil) == SetValues(weightKg: nil, reps: 8))
        #expect(values(0, [S()], nil, floor: nil) == SetValues(weightKg: nil, reps: nil))
    }

    @Test func eachSetTakesTheSameSetOfLastSession() {
        let history = last([working(60, 10), working(60, 9), working(57.5, 8)])
        let sets = [S(), S(), S()]
        #expect(values(0, sets, history) == SetValues(weightKg: 60, reps: 10))
        #expect(values(1, sets, history) == SetValues(weightKg: 60, reps: 9))
        #expect(values(2, sets, history) == SetValues(weightKg: 57.5, reps: 8))
    }

    @Test func historyBeatsALoggedSetThatWasNotChanged() {
        let history = last([working(60, 10), working(65, 6)])
        // Set 1 logged exactly as suggested: set 2 follows last session, not set 1.
        #expect(values(1, [logged(60, 10), S()], history) == SetValues(weightKg: 65, reps: 6))
    }

    @Test func aChangedSetCarriesOnBeforeHistory() {
        let history = last([working(60, 10), working(60, 10), working(60, 10)])
        let sets = [logged(62.5, 8), S(), S()]
        #expect(values(1, sets, history) == SetValues(weightKg: 62.5, reps: 8))
        // Set 2 logged as carried: the carry continues to set 3 instead of snapping back.
        #expect(values(2, [logged(62.5, 8), logged(62.5, 8), S()], history) == SetValues(weightKg: 62.5, reps: 8))
        // Logging set 2 differently carries that instead.
        #expect(values(2, [logged(62.5, 8), logged(62.5, 7), S()], history) == SetValues(weightKg: 62.5, reps: 7))
    }

    @Test func aChangeOfRepsAloneCarriesTheWholeSet() {
        let history = last([working(60, 10), working(65, 8)])
        #expect(values(1, [logged(60, 9), S()], history) == SetValues(weightKg: 60, reps: 9))
    }

    @Test func typedValuesWinFieldByField() {
        let history = last([working(60, 10)])
        #expect(values(0, [S(weightKg: 70)], history) == SetValues(weightKg: 70, reps: 10))
        #expect(values(0, [S(reps: 5)], history) == SetValues(weightKg: 60, reps: 5))
        #expect(values(1, [logged(62.5, 8), S(weightKg: 65)], history) == SetValues(weightKg: 65, reps: 8))
    }

    @Test func loggedSetsShowWhatWasRecorded() {
        #expect(values(0, [logged(nil, 12)], last([working(60, 10)])) == SetValues(weightKg: nil, reps: 12))
    }

    /// Without history every logged set differs from its rep-floor suggestion, so the M1
    /// behaviour (the next set copies the previous one) is kept.
    @Test func withoutHistoryTheDeviceTestedCarryIsKept() {
        #expect(values(1, [logged(60, 10), S()], nil) == SetValues(weightKg: 60, reps: 10))
        // Logged as suggested: nothing deviated, so the last set today is used.
        #expect(values(1, [logged(nil, 8), S()], nil) == SetValues(weightKg: nil, reps: 8))
    }

    @Test func warmupsAndWorkingSetsCarrySeparately() {
        let sets = [logged(40, 12, warmup: true), logged(60, 8), S(isWarmup: true), S()]
        #expect(values(2, sets, nil) == SetValues(weightKg: 40, reps: 12))
        #expect(values(3, sets, nil) == SetValues(weightKg: 60, reps: 8))
        // A working set after only a warm-up falls back to the warm-up (M1 behaviour).
        #expect(values(1, [logged(40, 12, warmup: true), S()], nil) == SetValues(weightKg: 40, reps: 12))
    }

    @Test func warmupsMapToWarmupsOfLastSession() {
        let history = last([warmup(20, 10), warmup(40, 5), working(60, 10)])
        let sets = [S(isWarmup: true), S(isWarmup: true), S()]
        #expect(values(0, sets, history) == SetValues(weightKg: 20, reps: 10))
        #expect(values(1, sets, history) == SetValues(weightKg: 40, reps: 5))
        #expect(values(2, sets, history) == SetValues(weightKg: 60, reps: 10))
    }

    @Test func aWarmupWithoutHistoryUsesTodayThenThePlan() {
        let history = last([working(60, 10)])
        #expect(values(0, [S(isWarmup: true)], history) == SetValues(weightKg: nil, reps: 8))
        #expect(values(1, [logged(60, 10), S(isWarmup: true)], history) == SetValues(weightKg: 60, reps: 10))
    }

    @Test func historySetsWithoutRepsFallBackToTheFloor() {
        #expect(values(0, [S()], last([working(60, nil)])) == SetValues(weightKg: 60, reps: 8))
    }

    @Test func suggestionsReportTheirSource() {
        let history = last([working(60, 10)])
        let sources = Prefill.suggestions(for: [logged(62.5, 8), S(), S(isWarmup: true)], last: history, repFloor: 8).map(\.source)
        #expect(sources == [.lastSession, .carried, .today])
        #expect(Prefill.suggestions(for: [S()], last: nil, repFloor: 8).map(\.source) == [.plan])
    }

    @Test func outOfRangeIndexIsHarmless() {
        #expect(values(3, [S()], nil) == SetValues(weightKg: nil, reps: 8))
        #expect(Prefill.kindIndex(of: 5, in: []) == 0)
    }

    @Test func weightsWithinToleranceMatch() {
        #expect(Prefill.matches(SetValues(weightKg: 60, reps: 10), SetValues(weightKg: 60.000_000_1, reps: 10)))
        #expect(!Prefill.matches(SetValues(weightKg: 60, reps: 10), SetValues(weightKg: nil, reps: 10)))
        #expect(!Prefill.matches(SetValues(weightKg: 60, reps: 10), SetValues(weightKg: 60, reps: 9)))
    }
}

@Suite("Progression")
struct ProgressionTests {
    private func last(_ sets: [(Double?, Int?, Bool)]) -> LastPerformance {
        LastPerformance(sessionID: UUID(), date: .distantPast, sets: sets.map { PerformedSet(weightKg: $0.0, reps: $0.1, isWarmup: $0.2) })
    }

    private func hint(_ last: LastPerformance?, low: Int? = 8, high: Int? = 12, _ equipment: Equipment = .barbell, step: Double? = 2.5) -> ProgressionHint? {
        Progression.hint(last: last, repLow: low, repHigh: high, equipment: equipment, stepKg: step)
    }

    @Test func firesWhenEveryWorkingSetHitTheTop() {
        let history = last([(20, 5, true), (60, 12, false), (60, 13, false), (60, 12, false)])
        #expect(hint(history) == ProgressionHint(weightKg: 62.5, reps: 8))
    }

    @Test func doesNotFireWhenOneSetFellShort() {
        #expect(hint(last([(60, 12, false), (60, 11, false)])) == nil)
        #expect(hint(last([(60, 12, false), (60, nil, false)])) == nil)
    }

    @Test func doesNotFireWhenWeightsDiffer() {
        #expect(hint(last([(60, 12, false), (62.5, 12, false)])) == nil)
        #expect(hint(last([(60, 12, false), (nil, 12, false)])) == nil)
    }

    @Test func warmupsNeverCount() {
        // A short warm-up does not block; warm-ups alone never fire.
        #expect(hint(last([(20, 3, true), (60, 12, false)])) == ProgressionHint(weightKg: 62.5, reps: 8))
        #expect(hint(last([(60, 12, true)])) == nil)
    }

    @Test func needsHistoryRangeWeightAndStep() {
        #expect(hint(nil) == nil)
        #expect(hint(last([])) == nil)
        #expect(hint(last([(60, 12, false)]), high: nil) == nil)
        #expect(hint(last([(nil, 12, false)])) == nil)
        #expect(hint(last([(60, 12, false)]), step: nil) == nil)
        #expect(hint(last([(60, 12, false)]), step: 0) == nil)
    }

    @Test func missingLowUsesHigh() {
        #expect(hint(last([(60, 12, false)]), low: nil) == ProgressionHint(weightKg: 62.5, reps: 12))
    }

    @Test func bodyweightAddsARepAtTheSameWeight() {
        let history = last([(nil, 12, false), (nil, 14, false)])
        #expect(hint(history, .bodyweight, step: nil) == ProgressionHint(weightKg: nil, reps: 13))
        #expect(hint(last([(10, 12, false), (10, 12, false)]), .bodyweight) == ProgressionHint(weightKg: 10, reps: 13))
        #expect(hint(last([(nil, 11, false)]), .bodyweight) == nil)
    }

    // MARK: Steps

    @Test func builtInStepsFollowTheUnit() {
        let kg: [Equipment: Double] = [.barbell: 2.5, .dumbbell: 2, .machine: 5, .cable: 5, .other: 2.5]
        let lb: [Equipment: Double] = [.barbell: 5, .dumbbell: 5, .machine: 10, .cable: 10, .other: 5]
        for (equipment, value) in kg {
            #expect(ProgressionStep.builtInDefault(for: equipment, unit: .kg) == value)
        }
        for (equipment, value) in lb {
            #expect(ProgressionStep.builtInDefault(for: equipment, unit: .lb) == value * WeightUnit.kilogramsPerPound)
        }
        #expect(ProgressionStep.builtInDefault(for: .bodyweight, unit: .kg) == nil)
        #expect(ProgressionStep.builtInDefault(for: .bodyweight, unit: .lb) == nil)
    }

    @Test func stepResolutionPrefersExerciseThenUserThenBuiltIn() {
        let settings = ProgressionSettings(unit: .kg, stepsKg: [.barbell: 1.25])
        #expect(settings.step(for: .barbell, exerciseStepKg: 5) == 5)
        #expect(settings.step(for: .barbell, exerciseStepKg: nil) == 1.25)
        #expect(settings.step(for: .barbell, exerciseStepKg: 0) == 1.25)
        #expect(settings.step(for: .dumbbell, exerciseStepKg: nil) == 2)
        #expect(settings.step(for: .bodyweight, exerciseStepKg: 2.5) == nil)
        let pounds = ProgressionSettings(unit: .lb)
        #expect(pounds.step(for: .machine, exerciseStepKg: nil) == 10 * WeightUnit.kilogramsPerPound)
        #expect(ProgressionSettings(unit: .kg, stepsKg: [.cable: -1]).defaultStep(for: .cable) == 5)
    }

    @Test func choicesPerUnit() {
        #expect(ProgressionStepChoices.values(for: .kg) == [0.5, 1, 1.25, 2, 2.5, 5, 7.5, 10])
        #expect(ProgressionStepChoices.values(for: .lb) == [1, 2, 2.5, 5, 10, 15, 20])
        #expect(ProgressionStepChoices.kilograms(for: .lb).first == WeightUnit.kilogramsPerPound)
        // Every built-in default is offered as a choice in its unit.
        for unit in WeightUnit.allCases {
            for equipment in Equipment.allCases {
                guard let step = ProgressionStep.builtInDefault(for: equipment, unit: unit) else { continue }
                #expect(ProgressionStepChoices.matching(step, unit: unit) != nil, "\(equipment) in \(unit)")
            }
        }
    }

    @Test func pickerOptionsKeepAnOffGridValue() {
        // 2.5 kg chosen, then the unit switched to pounds: still shown, in order.
        let options = ProgressionStepChoices.options(for: .lb, including: 2.5)
        #expect(options.count == 8)
        #expect(options.contains(2.5))
        #expect(options == options.sorted())
        #expect(ProgressionStepChoices.options(for: .kg, including: 2.5).count == 8)
        #expect(ProgressionStepChoices.options(for: .kg, including: nil).count == 8)
        // Conversion noise snaps to the matching choice.
        let fivePounds = 5 * WeightUnit.kilogramsPerPound
        #expect(ProgressionStepChoices.tag(for: fivePounds + 1e-9, unit: .lb) == fivePounds)
        #expect(ProgressionStepChoices.tag(for: 3.3, unit: .kg) == 3.3)
    }
}
