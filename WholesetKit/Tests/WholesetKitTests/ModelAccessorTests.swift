// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Model accessors")
struct ModelAccessorTests {
    @Test func enumAccessorsWriteRawValues() {
        let exercise = Exercise()
        exercise.equipment = .dumbbell
        exercise.primaryMuscle = .lowerBack
        #expect(exercise.equipmentRaw == "dumbbell")
        #expect(exercise.primaryMuscleRaw == "lowerBack")

        let session = Session(source: .phone)
        #expect(session.sourceRaw == "phone")
        session.source = .importStrong
        #expect(session.sourceRaw == "importStrong")

        let settings = AppSettings()
        settings.unit = .lb
        #expect(settings.unitRaw == "lb")
    }

    @Test(arguments: [
        ("", []),
        ("Bench", ["Bench"]),
        ("  Bench \n\nIncline Bench\r\n", ["Bench", "Incline Bench"]),
    ] as [(String, [String])])
    func aliasDecoding(text: String, expected: [String]) {
        #expect(AliasList.decode(text) == expected)
    }

    @Test func aliasEncodingCleansInput() {
        let encoded = AliasList.encode(["  Bench Press ", "", "bench press", "Two\nLines", "Flat Bench"])
        #expect(encoded == "Bench Press\nTwo Lines\nFlat Bench")
        #expect(AliasList.decode(encoded) == ["Bench Press", "Two Lines", "Flat Bench"])
    }

    @Test func aliasesPropertyUsesTextStorage() {
        let exercise = Exercise(name: "Squat")
        #expect(exercise.aliases.isEmpty)
        exercise.aliases = ["Back Squat", "Squat (Barbell)"]
        #expect(exercise.aliasesText == "Back Squat\nSquat (Barbell)")
        #expect(exercise.aliases == ["Back Squat", "Squat (Barbell)"])
    }

    @Test func sortedByOrderBreaksTiesByCreationThenID() throws {
        let early = Date(timeIntervalSince1970: 10)
        let late = Date(timeIntervalSince1970: 20)
        let a = SetLog(order: 1)
        a.createdAt = late
        let b = SetLog(order: 1)
        b.createdAt = early
        let c = SetLog(order: 0)
        c.createdAt = late
        let d = SetLog(order: 1)
        d.createdAt = late
        d.id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        a.id = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))

        let sorted = [a, b, c, d].sortedByOrder()

        #expect(sorted.map(\.id) == [c.id, b.id, d.id, a.id])
    }
}
