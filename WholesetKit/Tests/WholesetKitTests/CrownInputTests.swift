// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Crown input")
struct CrownInputTests {
    private let posix = Locale(identifier: "en_US_POSIX")

    // MARK: CrownWindow

    @Test func windowIsCentredOnTheAnchor() {
        let window = CrownWindow(bounds: 0...1000, span: 100)
        #expect(window.range(around: 120) == 70...170)
    }

    @Test func windowShiftsToStayInsideBounds() {
        let window = CrownWindow(bounds: 0...1000, span: 100)
        #expect(window.range(around: 10) == 0...100)
        #expect(window.range(around: 990) == 900...1000)
        #expect(window.range(around: -40) == 0...100)
        #expect(window.range(around: 5000) == 900...1000)
    }

    @Test func narrowBoundsAreUsedAsTheyAre() {
        let window = CrownWindow(bounds: 0...60, span: 100)
        #expect(window.range(around: 30) == 0...60)
    }

    @Test(arguments: [0, 1, 37, 500, 999, 1000])
    func windowAlwaysHasTheSameSpanAndContainsTheAnchor(anchor: Int) {
        let window = CrownWindow(bounds: 0...1000, span: 100)
        let range = window.range(around: anchor)
        #expect(range.upperBound - range.lowerBound == 100)
        #expect(range.contains(anchor))
    }

    @Test func clampKeepsValuesInsideBounds() {
        let window = CrownWindow(bounds: 0...1000, span: 100)
        #expect(window.clamp(-5) == 0)
        #expect(window.clamp(500) == 500)
        #expect(window.clamp(1001) == 1000)
    }

    // MARK: CrownEdit

    private func weightEdit(at value: Int, isStored: Bool = true) -> CrownEdit {
        CrownEdit(value: value, isStored: isStored, bounds: 0...1000, span: 100)
    }

    @Test func editStartsCentredOnTheValue() {
        let edit = weightEdit(at: 120)
        #expect(edit.value == 120)
        #expect(edit.anchor == 120)
        #expect(edit.crownRange == 70...170)
        #expect(edit.savedValue == 120)
        #expect(!edit.hasMoved)
        #expect(!edit.hasUnsavedChange)
        #expect(edit.showsValue)
    }

    @Test func editClampsTheStartIntoBounds() {
        let edit = CrownEdit(value: 140, isStored: true, bounds: 0...100, span: 100)
        #expect(edit.value == 100)
        #expect(edit.crownRange == 0...100)
    }

    /// The Crown's position is the value: every reported detent shows up as-is and the
    /// range does not move during the turn.
    @Test func crownPositionIsTheValueAndTheRangeHoldsStill() {
        var edit = weightEdit(at: 120)
        let range = edit.crownRange
        for position in [121, 125, 140, 133, 170] {
            let changed = edit.crownMoved(to: position)
            #expect(changed)
            #expect(edit.value == position)
            #expect(edit.crownRange == range)
        }
        #expect(edit.hasUnsavedChange)
    }

    @Test func crownPositionsOutsideTheWindowAreClamped() {
        var edit = weightEdit(at: 120)
        edit.turn(to: 400)
        #expect(edit.value == 170)
        let pastTheEdge = edit.crownMoved(to: 171)
        #expect(!pastTheEdge)
        edit.crownMoved(to: -20)
        #expect(edit.value == 70)
    }

    @Test func repeatedPositionIsNotAChange() {
        var edit = weightEdit(at: 120)
        let changed = edit.crownMoved(to: 120)
        #expect(!changed)
        #expect(!edit.hasMoved)
    }

    @Test func recentreMovesOnlyTheRange() {
        var edit = weightEdit(at: 120)
        edit.turn(to: 170)
        edit.recentre()
        #expect(edit.value == 170)
        #expect(edit.crownRange == 120...220)
    }

    /// Turning one detent at a time, re-centring whenever the Crown would stop (as when it
    /// goes idle between turns), reaches every value in order in both directions: no step is
    /// skipped, doubled or blocked.
    @Test func turnsSeparatedByIdleReachTheWholeRange() {
        var edit = weightEdit(at: 40)
        var turns = 0
        while edit.value < 1000 {
            let before = edit.value
            if !edit.crownMoved(to: before + 1) {
                edit.recentre()
                turns += 1
                let changed = edit.crownMoved(to: before + 1)
                #expect(changed)
            }
            #expect(edit.value == before + 1)
        }
        while edit.value > 0 {
            let before = edit.value
            if !edit.crownMoved(to: before - 1) {
                edit.recentre()
                let changed = edit.crownMoved(to: before - 1)
                #expect(changed)
            }
            #expect(edit.value == before - 1)
        }
        // The first window is 0...100; after that one turn per half window (50 steps):
        // the Crown stops at 100, 150, ..., 950.
        #expect(turns == 18)
    }

    @Test func narrowBoundsNeverMoveTheRange() {
        var reps = CrownEdit(value: 8, isStored: true, bounds: 0...100, span: 100)
        #expect(reps.crownRange == 0...100)
        reps.turn(to: 95)
        reps.recentre()
        #expect(reps.crownRange == 0...100)
        reps.turn(to: 101)
        #expect(reps.value == 100)
    }

    @Test func untouchedEmptyValueKeepsItsPlaceholderAndIsNotSaved() {
        var edit = weightEdit(at: 40, isStored: false)
        #expect(edit.savedValue == nil)
        #expect(!edit.showsValue)
        #expect(!edit.hasUnsavedChange)
        edit.crownMoved(to: 41)
        edit.crownMoved(to: 40)
        // Moved back to the starting point: still a value the user chose, so it is saved.
        #expect(edit.showsValue)
        #expect(edit.hasUnsavedChange)
    }

    @Test func movingBackToTheSavedValueNeedsNoSave() {
        var edit = weightEdit(at: 120)
        edit.turn(to: 125)
        edit.crownMoved(to: 120)
        #expect(edit.hasMoved)
        #expect(!edit.hasUnsavedChange)
    }

    @Test func markSavedClearsTheUnsavedChange() {
        var edit = weightEdit(at: 120)
        edit.turn(to: 130)
        edit.markSaved()
        #expect(edit.savedValue == 130)
        #expect(!edit.hasUnsavedChange)
        edit.crownMoved(to: 131)
        #expect(edit.hasUnsavedChange)
    }

    @Test func voiceOverStepsMoveOneStepAndCarryTheWindow() {
        var edit = weightEdit(at: 120)
        edit.turn(to: 170)
        let up = edit.step(by: 1)
        #expect(up)
        #expect(edit.value == 171)
        #expect(edit.crownRange.contains(171))
        #expect(edit.crownRange.contains(172))
        let down = edit.step(by: -2)
        #expect(down)
        #expect(edit.value == 169)
        #expect(edit.hasUnsavedChange)
    }

    @Test func voiceOverStepsStopAtTheBounds() {
        var edit = weightEdit(at: 0)
        let belowZero = edit.step(by: -1)
        #expect(!belowZero)
        #expect(edit.value == 0)
        let toTheTop = edit.step(by: .max)
        #expect(toTheTop)
        #expect(edit.value == 1000)
        let pastTheTop = edit.step(by: 1)
        #expect(!pastTheTop)
    }

    // MARK: StableNumberWidth

    @Test(arguments: [
        ("60", "888.8", "8.8"),
        ("60.5", "888.8", "8"),
        ("100", "888.8", ".8"),
        ("102.5", "888.8", ""),
        ("8", "8888", "888"),
        ("1102", "8888", ""),
        ("62,5", "888,8", "8"),
        ("–", "888.8", "88.8"),
    ])
    func fillerCompletesTheTemplate(value: String, template: String, expected: String) {
        #expect(StableNumberWidth.filler(for: value, toMatch: template) == expected)
    }

    @Test func valueWiderThanTheTemplateGetsNoFiller() {
        #expect(StableNumberWidth.filler(for: "12345", toMatch: "888") == "")
    }

    /// Every weight the kg and lb scales can show, padded, has the same digit and
    /// separator counts as the template, so it renders at the same width.
    @Test(arguments: [WeightUnit.kg, .lb])
    func everyWeightPadsToTheTemplateShape(unit: WeightUnit) {
        let scale = WeightScale(unit: unit)
        let template = WeightFormat.widestString(scale: scale, locale: posix)
        for steps in 0...scale.maximumSteps {
            let value = WeightFormat.string(kilograms: scale.kilograms(forSteps: steps), scale: scale, locale: posix)
            let padded = value + StableNumberWidth.filler(for: value, toMatch: template)
            #expect(padded.count { $0.isWholeNumber } == template.count { $0.isWholeNumber })
            #expect(padded.count { !$0.isWholeNumber } == template.count { !$0.isWholeNumber })
        }
    }

    // MARK: WeightFormat.widestString

    @Test func widestStringCoversTheScale() {
        #expect(WeightFormat.widestString(scale: WeightScale(unit: .kg), locale: posix) == "888.8")
        #expect(WeightFormat.widestString(scale: WeightScale(unit: .lb), locale: posix) == "8888")
        #expect(WeightFormat.widestString(scale: WeightScale(unit: .kg, step: 1.25), locale: posix) == "888.88")
        #expect(WeightFormat.widestString(scale: WeightScale(unit: .kg, step: 2), locale: posix) == "888")
    }

    @Test func widestStringUsesTheLocaleSeparator() {
        #expect(WeightFormat.widestString(scale: WeightScale(unit: .kg), locale: Locale(identifier: "de_DE")) == "888,8")
    }
}
