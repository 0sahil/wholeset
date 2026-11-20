// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import WholesetKit

/// One Crown view serves exercise navigation and both tiles. When it switches from one to
/// another it can report its old position, clamped into the new range, before the user turns.
@Suite("Crown context switches")
struct CrownContextTests {
    private func repsEdit(at value: Int, isStored: Bool = false) -> CrownEdit {
        CrownEdit(value: value, isStored: isStored, bounds: 0...100, span: 100)
    }

    private func weightEdit(at value: Int, detentsPerStep: Int = 1) -> CrownEdit {
        CrownEdit(value: value, isStored: true, bounds: 0...1000, span: 100, detentsPerStep: detentsPerStep)
    }

    // MARK: Stale reports

    /// The on-device bug: weight set to 60 kg (step 120), then reps selected without turning.
    /// The Crown still held 120 and reported it clamped into the reps range: 100.
    @Test func staleWeightReportLeavesAFreshRepsEditUntouched() {
        var reps = repsEdit(at: 0)
        #expect(reps.isStaleReport(100))
        let changed = reps.crownMoved(to: 100)
        #expect(!changed)
        #expect(reps.value == 0)
        #expect(reps.position == 0)
        #expect(!reps.hasMoved)
        #expect(!reps.showsValue)
        #expect(!reps.hasUnsavedChange)
    }

    @Test func staleReportLeavesABlankRepsEditAtItsStart() {
        var reps = repsEdit(at: CrownEdit.repsStart(shown: nil, repFloor: nil))
        let changed = reps.crownMoved(to: 100)
        #expect(!changed)
        #expect(reps.value == CrownEdit.blankRepsStart)
        #expect(!reps.showsValue)
    }

    /// Reps (8) then weight: the old position clamps to the bottom of the weight window.
    @Test func staleRepsReportLeavesAFreshWeightEditUntouched() {
        var weight = weightEdit(at: 600)
        #expect(weight.crownRange == 550...650)
        let changed = weight.crownMoved(to: 550)
        #expect(!changed)
        #expect(weight.value == 600)
        #expect(!weight.hasMoved)
        #expect(!weight.hasUnsavedChange)
    }

    @Test func aTurnAfterAStaleReportStartsFromTheShownValue() {
        var reps = repsEdit(at: 8, isStored: true)
        reps.crownMoved(to: 100)
        let up = reps.crownMoved(to: 9)
        #expect(up)
        #expect(reps.value == 9)
        reps.crownMoved(to: 12)
        #expect(reps.value == 12)
    }

    @Test func aFirstReportOneDetentAwayIsATurnEitherWay() {
        var up = weightEdit(at: 120)
        #expect(!up.isStaleReport(121))
        let movedUp = up.crownMoved(to: 121)
        #expect(movedUp)
        #expect(up.value == 121)
        var down = weightEdit(at: 120)
        let movedDown = down.crownMoved(to: 119)
        #expect(movedDown)
        #expect(down.value == 119)
    }

    /// Once a turn has started, a fast turn may skip detents between reports.
    @Test func aStartedTurnMaySkipDetents() {
        var edit = weightEdit(at: 120)
        edit.crownMoved(to: 121)
        #expect(!edit.isStaleReport(140))
        edit.crownMoved(to: 140)
        #expect(edit.value == 140)
    }

    @Test func eachTurnAfterIdleMustStartWhereTheEditStands() {
        var edit = weightEdit(at: 120)
        edit.turn(to: 170)
        edit.recentre()
        #expect(edit.crownRange == 120...220)
        let stale = edit.crownMoved(to: 120)
        #expect(!stale)
        #expect(edit.value == 170)
        let real = edit.crownMoved(to: 171)
        #expect(real)
        #expect(edit.value == 171)
    }

    /// With two detents per step, re-centring drops a part step, so the Crown can be one
    /// detent further than the edit: its next detent must still count.
    @Test func theDetentAfterADroppedPartStepIsATurn() {
        var edit = weightEdit(at: 120, detentsPerStep: 2)
        edit.crownMoved(to: 241)
        edit.recentre()
        #expect(edit.position == 240)
        let changed = edit.crownMoved(to: 242)
        #expect(changed)
        #expect(edit.value == 121)
        var far = weightEdit(at: 120, detentsPerStep: 2)
        #expect(far.crownRange == 190...290)
        #expect(far.isStaleReport(270))
        let farMoved = far.crownMoved(to: 270)
        #expect(!farMoved)
        #expect(far.value == 120)
    }

    @Test func voiceOverStepsAreNotCrownReports() {
        var reps = repsEdit(at: 8, isStored: true)
        reps.step(by: 5)
        #expect(reps.value == 13)
        #expect(!reps.isStaleReport(14))
        #expect(!reps.isStaleReport(8))
        #expect(reps.isStaleReport(13 + CrownReportGate.defaultStaleDistance))
    }

    // MARK: Fast first turns

    /// A fast turn has passed several detents by its first report; it applies at once.
    @Test(arguments: [2, 3, 5, 8, 10, -2, -5, -10])
    func aFastFirstRepsReportIsATurn(detents: Int) {
        var reps = repsEdit(at: 10)
        #expect(!reps.isStaleReport(10 + detents))
        let changed = reps.crownMoved(to: 10 + detents)
        #expect(changed)
        #expect(reps.value == 10 + detents)
        #expect(reps.showsValue)
    }

    @Test(arguments: [2, 3, 5, 8, 10, -2, -5, -10])
    func aFastFirstWeightReportIsATurn(detents: Int) {
        var weight = weightEdit(at: 120)
        let changed = weight.crownMoved(to: 120 + detents)
        #expect(changed)
        #expect(weight.value == 120 + detents)
    }

    /// Slow weight: two detents per step, so 2 to 10 detents move 1 to 5 steps.
    @Test(arguments: [2, 4, 6, 10, -2, -6, -10])
    func aFastFirstSlowWeightReportIsATurn(detents: Int) {
        var weight = weightEdit(at: 120, detentsPerStep: 2)
        #expect(!weight.isStaleReport(240 + detents))
        let changed = weight.crownMoved(to: 240 + detents)
        #expect(changed)
        #expect(weight.value == 120 + detents / 2)
        #expect(weight.position == 240 + detents)
    }

    /// Every turn after idle is checked again, and a fast one still applies at once.
    @Test func aFastTurnAfterIdleIsATurn() {
        var reps = repsEdit(at: 10, isStored: true)
        reps.crownMoved(to: 16)
        reps.recentre()
        let changed = reps.crownMoved(to: 24)
        #expect(changed)
        #expect(reps.value == 24)
    }

    @Test(arguments: [100, 120])
    func aFarStaleReportFromTenIsStillIgnored(report: Int) {
        var reps = repsEdit(at: 10)
        #expect(reps.isStaleReport(report))
        let changed = reps.crownMoved(to: report)
        #expect(!changed)
        #expect(reps.value == 10)
        #expect(reps.position == 10)
        #expect(!reps.showsValue)
    }

    /// The stale reading is rejected once; the next report, from the fresh Crown view,
    /// applies even when it is a fast turn.
    @Test func aFastTurnAfterAStaleReportIsATurn() {
        var reps = repsEdit(at: 10)
        reps.crownMoved(to: 100)
        let changed = reps.crownMoved(to: 15)
        #expect(changed)
        #expect(reps.value == 15)
    }

    /// Even if the Crown view kept reporting from its stale reading, only one report is lost.
    @Test func aStaleReportIsRejectedOnlyOncePerTurn() {
        var reps = repsEdit(at: 10)
        let first = reps.crownMoved(to: 100)
        #expect(!first)
        #expect(!reps.isStaleReport(99))
        let second = reps.crownMoved(to: 99)
        #expect(second)
        #expect(reps.value == 99)
    }

    // MARK: CrownReportGate

    /// Exercise navigation: released with the Crown still at weight step 120, while the
    /// workout is on exercise 2 of 30 (range 0...29); the reading clamps to 29.
    @Test func gateRejectsAStaleNavigationReportOnce() {
        var gate = CrownReportGate()
        let stale = gate.admit(29, at: 2)
        #expect(!stale)
        let turn = gate.admit(3, at: 2)
        #expect(turn)
        #expect(gate.isOpen)
        let fast = gate.admit(5, at: 3)
        #expect(fast)
    }

    /// A fast navigation turn passes several exercises before its first report.
    @Test(arguments: [2, 5, 10, -2])
    func aFastFirstNavigationReportIsATurn(exercises: Int) {
        var gate = CrownReportGate()
        let turn = gate.admit(12 + exercises, at: 12)
        #expect(turn)
        #expect(gate.isOpen)
    }

    @Test func aReportAtTheStartDoesNotOpenTheGate() {
        var gate = CrownReportGate()
        let repeated = gate.admit(4, at: 4)
        #expect(repeated)
        #expect(!gate.isOpen)
        let stale = gate.admit(40, at: 4)
        #expect(!stale)
    }

    @Test func closingTheGateStartsANewContext() {
        var gate = CrownReportGate()
        let turn = gate.admit(1, at: 0)
        #expect(turn)
        #expect(gate.isOpen)
        gate.close()
        #expect(!gate.isOpen)
        #expect(gate.isStale(30, at: 1))
        #expect(!gate.isStale(10, at: 1))
    }

    @Test func closingTheGateAfterARejectionChecksTheNextTurnAgain() {
        var gate = CrownReportGate()
        let stale = gate.admit(100, at: 10)
        #expect(!stale)
        #expect(gate.isOpen)
        gate.close()
        #expect(gate.isStale(100, at: 10))
    }

    @Test func staleDistanceIsTwentyDetentsByDefault() {
        let gate = CrownReportGate()
        #expect(gate.staleDistance == 20)
        #expect(!gate.isStale(29, at: 10))
        #expect(gate.isStale(30, at: 10))
        #expect(!gate.isStale(-9, at: 10))
        #expect(gate.isStale(-10, at: 10))
    }

    @Test func staleDistanceIsAtLeastTwoDetents() {
        #expect(CrownReportGate(staleDistance: 0).staleDistance == 2)
        #expect(CrownReportGate(staleDistance: -3).staleDistance == 2)
        let narrow = CrownReportGate(staleDistance: 2)
        #expect(!narrow.isStale(11, at: 10))
        #expect(narrow.isStale(12, at: 10))
    }

    @Test func extremeReportsAreStaleWithoutOverflow() {
        let gate = CrownReportGate()
        #expect(gate.isStale(.min, at: 1))
        #expect(gate.isStale(.max, at: -1))
    }
}

@Suite("Reps Crown start")
struct RepsCrownStartTests {
    @Test func blankRepsStartAtTen() {
        #expect(CrownEdit.blankRepsStart == 10)
        #expect(CrownEdit.repsStart(shown: nil, repFloor: nil) == 10)
    }

    @Test(arguments: [
        (Int?.some(0), Int?.none, 0),
        (8, nil, 8),
        (nil, 6, 6),
        (12, 6, 12),
    ])
    func repsWithAValueStartThere(shown: Int?, repFloor: Int?, expected: Int) {
        #expect(CrownEdit.repsStart(shown: shown, repFloor: repFloor) == expected)
    }

    private func blankEdit() -> CrownEdit {
        CrownEdit(value: CrownEdit.repsStart(shown: nil, repFloor: nil), isStored: false, bounds: 0...100, span: 100)
    }

    @Test func blankRepsKeepThePlaceholderAndWriteNothingUntilTurned() {
        let edit = blankEdit()
        #expect(!edit.showsValue)
        #expect(!edit.hasUnsavedChange)
        #expect(edit.savedValue == nil)
    }

    @Test(arguments: [(11, 11), (9, 9)])
    func firstDetentFromBlankShowsElevenOrNine(position: Int, expected: Int) {
        var edit = blankEdit()
        let changed = edit.crownMoved(to: position)
        #expect(changed)
        #expect(edit.value == expected)
        #expect(edit.showsValue)
        #expect(edit.hasUnsavedChange)
    }

    @Test(arguments: [(1, 11), (-1, 9)])
    func voiceOverStepFromBlankGivesElevenOrNine(delta: Int, expected: Int) {
        var edit = blankEdit()
        let changed = edit.step(by: delta)
        #expect(changed)
        #expect(edit.value == expected)
        #expect(edit.hasUnsavedChange)
    }
}
