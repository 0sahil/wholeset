// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Exercise library")
struct ExerciseLibraryTests {
    private let library: ExerciseLibrary

    init() throws {
        library = try ExerciseLibrary.bundled()
    }

    @Test func hasAboutOneHundredFiftyExercises() {
        #expect((130...170).contains(library.entries.count))
    }

    @Test func creditsItsPublicDomainSource() {
        #expect(library.source.contains("free-exercise-db"))
        #expect(library.license.contains("Unlicense"))
    }

    @Test func keysAreUniqueAndNonEmpty() {
        let keys = library.entries.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(keys.allSatisfy { !$0.isEmpty })
    }

    @Test func namesAreUniqueIgnoringCase() {
        let names = library.entries.map { ExerciseName.normalized($0.name) }
        #expect(Set(names).count == names.count)
        #expect(library.entries.allSatisfy { $0.name == $0.name.trimmingCharacters(in: .whitespaces) && !$0.name.isEmpty })
    }

    @Test func aliasesNeverNameAnotherExercise() {
        var owners: [String: String] = [:]
        for entry in library.entries {
            for label in [entry.name] + entry.aliases {
                let key = ExerciseName.normalized(label)
                let owner = owners[key, default: entry.key]
                #expect(owner == entry.key, "\(label) is used by \(owner) and \(entry.key)")
                owners[key] = entry.key
            }
        }
    }

    @Test func everyStarterExerciseIsInTheLibraryWithTheSameDetails() throws {
        for item in StarterRoutines.templates.flatMap(\.items) {
            let entry = try #require(library.entry(named: item.exerciseName), "\(item.exerciseName) is missing")
            #expect(entry.name == item.exerciseName)
            #expect(entry.equipment == item.equipment, "\(item.exerciseName) equipment")
            #expect(entry.muscle == item.muscle, "\(item.exerciseName) muscle")
        }
    }

    @Test func coversEveryCommonEquipmentAndMuscleGroup() {
        let equipment = Set(library.entries.map(\.equipment))
        #expect(equipment.isSuperset(of: [.barbell, .dumbbell, .machine, .cable, .bodyweight]))
        let groups = Set(library.entries.map { MuscleGroup($0.muscle) })
        #expect(groups.isSuperset(of: [.chest, .back, .shoulders, .arms, .legs, .core]))
    }

    @Test func entriesAreSortedByName() {
        let names = library.entries.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func looksUpByKeyAndName() throws {
        let bench = try #require(library.entry(named: "  bench   PRESS "))
        #expect(library.entry(forKey: bench.key) == bench)
        #expect(library.entry(named: "Not An Exercise") == nil)
    }

    @Test func rejectsUnknownEnumValues() {
        let json = #"{"source":"s","license":"l","exercises":[{"key":"k","name":"N","equipment":"rope","muscle":"chest"}]}"#
        #expect(throws: ExerciseLibrary.LoadError.unknownValue(key: "k", value: "rope")) {
            try ExerciseLibrary.decode(Data(json.utf8))
        }
    }

    @Test func normalisesNamesForComparison() {
        #expect(ExerciseName.normalized("  Bench\tPress ") == "bench press")
        #expect(ExerciseName.normalized("Crème Brûlée Curl") == "creme brulee curl")
    }
}
