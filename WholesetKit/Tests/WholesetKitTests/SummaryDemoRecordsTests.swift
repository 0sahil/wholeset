// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

/// The Watch's `summary` demo logs this workout against this history and shows the records
/// the real code works out. The same data here, through the same engine calls and loader,
/// pins down what that screen must show: four record lines, in kilograms and in pounds.
@Suite("Summary demo data")
struct SummaryDemoRecordsTests {
    @Test(arguments: [WeightUnit.kg, .lb])
    func pushWorkoutAfterYesterdaySetsFourRecords(unit: WeightUnit) throws {
        func kilograms(_ kg: Double, _ lb: Double) -> Double {
            unit == .kg ? kg : WeightUnit.lb.kilograms(fromValue: lb)
        }
        let context = try makeInMemoryContext()
        let push = insertRoutine("Push", items: [
            ("Bench Press", .barbell, 3, 6, 10, 150),
            ("Overhead Press", .barbell, 3, 6, 10, 120),
            ("Incline Dumbbell Press", .dumbbell, 3, 8, 12, 90),
            ("Lateral Raise", .dumbbell, 3, 12, 15, 60),
            ("Triceps Pushdown", .cable, 3, 10, 15, 60),
        ], in: context)
        let bench = try exercise(named: "Bench Press", in: context)
        let press = try exercise(named: "Overhead Press", in: context)
        let raise = try exercise(named: "Lateral Raise", in: context)

        // Yesterday's Push, as the demo's canned history has it.
        let today = H.t0
        let bar = kilograms(60, 135)
        let pressWeight = kilograms(40, 85)
        let raiseWeight = kilograms(8, 17.5)
        insertSession(startedAt: today.addingTimeInterval(-H.day), name: "Push", entries: [
            (bench, [(bar, 10, false), (bar, 9, false), (bar, 8, false)]),
            (press, [(pressWeight, 8, false), (pressWeight, 8, false), (pressWeight, 7, false)]),
            (raise, [(raiseWeight, 15, false), (raiseWeight, 14, false), (raiseWeight, 12, false)]),
        ], in: context)
        try context.save()

        // Today's workout, logged the way the demo logs it.
        let engine = try WorkoutEngine.start(routine: push, in: context, defaultRestSeconds: 90, now: { today })
        func log(_ name: String, _ sets: [(Double, Int)]) throws {
            let index = try #require(engine.entries.firstIndex { $0.exercise?.name == name })
            engine.select(entryAt: index)
            for (weight, reps) in sets {
                engine.setCurrentWeight(weight)
                engine.setCurrentReps(reps)
                try engine.logCurrentSet()
            }
        }
        let benchWeight = kilograms(62.5, 140)
        try log("Bench Press", [(benchWeight, 10), (benchWeight, 8), (benchWeight, 7)])
        try log("Overhead Press", [(pressWeight, 8), (pressWeight, 8), (pressWeight, 7)])
        let incline = kilograms(22, 50)
        try log("Incline Dumbbell Press", [(incline, 10), (incline, 10), (incline, 9)])
        let raiseToday = kilograms(10, 22.5)
        try log("Lateral Raise", [(raiseToday, 12), (raiseToday, 10), (raiseToday, 8)])
        let triceps = try #require(engine.entries.first { $0.exercise?.name == "Triceps Pushdown" })
        try engine.setSkipped(true, for: triceps)
        try engine.finish()

        let result = try #require(try SessionRecords.load(sessionID: engine.session.id, in: context))
        // Bench Press: heavier, and a better estimate; its volume trails yesterday.
        // Overhead Press: same as yesterday. Incline: first time. Lateral Raise: heavier and
        // a better estimate (yesterday's 15 and 14 rep sets have none); volume trails.
        #expect(result.count == 4)
        #expect(result.records.map(\.exerciseName) == ["Bench Press", "Bench Press", "Lateral Raise", "Lateral Raise"])
        let expected: [SessionRecord.Value] = [
            .weight(kilograms: benchWeight, reps: 10),
            .estimatedOneRepMax(kilograms: benchWeight * (1 + 10.0 / 30)),
            .weight(kilograms: raiseToday, reps: 12),
            .estimatedOneRepMax(kilograms: raiseToday * (1 + 12.0 / 30)),
        ]
        #expect(result.records.map(\.value) == expected)

        // The summary's exercise lines: the four exercises with sets, the skipped one left out.
        let finished = try #require(HistorySnapshot.session(from: engine.session))
        #expect(ExerciseSummaryLine.lines(for: finished).map(\.exerciseName) == ["Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raise"])
    }
}
