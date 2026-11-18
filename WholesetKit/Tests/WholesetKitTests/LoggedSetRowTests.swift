// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Logged set rows")
struct LoggedSetRowTests {
    private let posix = Locale(identifier: "en_US_POSIX")
    private let logged = Date(timeIntervalSince1970: 1_000)

    private func set(order: Int, _ weight: Double?, _ reps: Int?, warmup: Bool = false, isLogged: Bool = true) -> SetLog {
        let set = SetLog(order: order, weightKg: weight, reps: reps, isWarmup: warmup)
        set.completedAt = isLogged ? logged : nil
        return set
    }

    @Test func onlyLoggedSetsGetRowsNumberedByPosition() {
        let sets = [
            set(order: 0, 20, 10, warmup: true),
            set(order: 1, 60, 10),
            set(order: 2, 60, 9),
            set(order: 3, 60, nil, isLogged: false),
        ]
        let rows = LoggedSetRow.rows(for: sets)
        #expect(rows.map(\.number) == [1, 2, 3])
        #expect(rows.map(\.isWarmup) == [true, false, false])
        #expect(rows.map(\.id) == sets.prefix(3).map(\.id))
        #expect(rows[2].reps == 9)
    }

    @Test func aSkippedSetStillCountsTowardsLaterNumbers() {
        let rows = LoggedSetRow.rows(for: [
            set(order: 0, 60, 10),
            set(order: 1, 60, 10, isLogged: false),
            set(order: 2, 60, 8),
        ])
        #expect(rows.map(\.number) == [1, 3])
    }

    @Test func noLoggedSetsMeansNoRows() {
        #expect(LoggedSetRow.rows(for: [set(order: 0, 60, 10, isLogged: false)]).isEmpty)
        #expect(LoggedSetRow.rows(for: []).isEmpty)
    }

    @Test func valueTextUsesTheDisplayUnit() {
        let row = LoggedSetRow(id: UUID(), number: 1, isWarmup: false, weightKg: 60, reps: 10)
        #expect(row.valueText(scale: WeightScale(unit: .kg), locale: posix) == "60 kg × 10")
        let pounds = LoggedSetRow(id: UUID(), number: 1, isWarmup: false, weightKg: WeightUnit.lb.kilograms(fromValue: 135), reps: 8)
        #expect(pounds.valueText(scale: WeightScale(unit: .lb), locale: posix) == "135 lb × 8")
    }

    @Test func valueTextKeepsHalfStepsAndTheLocaleSeparator() {
        let row = LoggedSetRow(id: UUID(), number: 2, isWarmup: false, weightKg: 62.5, reps: 5)
        #expect(row.valueText(scale: WeightScale(unit: .kg), locale: posix) == "62.5 kg × 5")
        #expect(row.valueText(scale: WeightScale(unit: .kg), locale: Locale(identifier: "de_DE")) == "62,5 kg × 5")
    }

    @Test func valueTextWithoutWeightOrReps() {
        let bodyweight = LoggedSetRow(id: UUID(), number: 1, isWarmup: false, weightKg: nil, reps: 12)
        #expect(bodyweight.weightText(scale: WeightScale(unit: .kg), locale: posix) == nil)
        #expect(bodyweight.valueText(scale: WeightScale(unit: .kg), locale: posix) == "× 12")
        let noReps = LoggedSetRow(id: UUID(), number: 1, isWarmup: false, weightKg: 60, reps: nil)
        #expect(noReps.repsText == "–")
        #expect(noReps.valueText(scale: WeightScale(unit: .kg), locale: posix) == "60 kg × –")
    }
}
