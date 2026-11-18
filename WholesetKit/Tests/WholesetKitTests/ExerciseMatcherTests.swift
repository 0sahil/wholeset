// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Import: exercise matching")
struct ExerciseMatcherTests {
    private let bench = ExerciseCandidate(reference: .stored(H.id(1)), name: "Bench Press", equipment: .barbell, aliases: ["Bench Press (Barbell)"], libraryKey: "Barbell_Bench_Press_-_Medium_Grip")
    private let dumbbellBench = ExerciseCandidate(reference: .stored(H.id(2)), name: "Dumbbell Bench Press", equipment: .dumbbell)
    private let hipThrust = ExerciseCandidate(reference: .stored(H.id(3)), name: "Hip Thrust", equipment: .barbell)
    private let cableFly = ExerciseCandidate(reference: .stored(H.id(4)), name: "Cable Fly", equipment: .cable)
    private let pullUp = ExerciseCandidate(reference: .stored(H.id(5)), name: "Pull-up", equipment: .bodyweight)
    private let frontSquat = ExerciseCandidate(reference: .stored(H.id(6)), name: "Front Squat", equipment: .barbell, libraryKey: "Front_Barbell_Squat")
    private let squat = ExerciseCandidate(reference: .stored(H.id(7)), name: "Squat", equipment: .barbell)
    private let overheadCable = ExerciseCandidate(reference: .stored(H.id(8)), name: "Overhead Cable Triceps Extension", equipment: .cable)
    private let oldCurl = ExerciseCandidate(reference: .stored(H.id(9)), name: "Spider Curl", equipment: .barbell, isArchived: true)
    private let legPress = ExerciseCandidate(reference: .library("Leg_Press"), name: "Leg Press", equipment: .machine, libraryKey: "Leg_Press")

    private var matcher: ExerciseMatcher {
        ExerciseMatcher(
            candidates: [bench, dumbbellBench, hipThrust, cableFly, pullUp, frontSquat, squat, overheadCable, oldCurl, legPress],
            knownNames: ["Flat Barbell Bench Press": "Barbell_Bench_Press_-_Medium_Grip", "Barbell Front Squat Deep": "Front_Barbell_Squat"]
        )
    }

    @Test("Exact names match, ignoring case, spacing, hyphens and diacritics")
    func exact() {
        #expect(matcher.match("bench  press") == .matched(bench, .exactName))
        #expect(matcher.match("Pull Up") == .matched(pullUp, .exactName))
        #expect(matcher.match("  PULL-UP ") == .matched(pullUp, .exactName))
    }

    @Test("Aliases match next")
    func alias() {
        #expect(matcher.match("Bench Press (Barbell)") == .matched(bench, .alias))
    }

    @Test("The built-in table of other apps' names matches by library key")
    func known() {
        #expect(matcher.match("Flat Barbell Bench Press") == .matched(bench, .knownName))
        #expect(matcher.match("barbell front squat deep") == .matched(frontSquat, .knownName))
    }

    @Test("Name plus equipment: same equipment matches, other equipment asks")
    func equipment() {
        #expect(matcher.match("Hip Thrust (Barbell)") == .matched(hipThrust, .nameAndEquipment))
        #expect(matcher.match("Hip Thrust (Machine)") == .check(hipThrust, .differentEquipment(.machine)))
        #expect(matcher.match("Bench Press (Dumbbell)") == .matched(dumbbellBench, .nameAndEquipment))
        #expect(matcher.match("Barbell Front Squat") == .matched(frontSquat, .nameAndEquipment))
        #expect(matcher.match("Squat (Single Leg)") == .check(squat, .differentEquipment(nil)))
        #expect(matcher.match("Leg Press Machine") == .matched(legPress, .nameAndEquipment))
    }

    @Test("Similar names are offered for a check")
    func similar() {
        #expect(matcher.match("Triceps Extension (Cable)") == .check(overheadCable, .similarName))
        #expect(matcher.match("Overhead Triceps Extensions on Cable") == .check(overheadCable, .similarName))
        #expect(matcher.match("Cable Flyes") == .check(cableFly, .similarName))
        // Shared equipment words or one shared word of several are not similar.
        #expect(matcher.match("Landmine Press (Barbell)").candidate == nil)
        #expect(matcher.match("Zercher Squat").candidate == nil)
    }

    @Test("Everything else becomes a custom exercise with guessed equipment")
    func custom() {
        #expect(matcher.match("Zercher Squat") == .newCustom(name: "Zercher Squat", equipment: .other))
        #expect(matcher.match("Landmine Press (Barbell)") == .newCustom(name: "Landmine Press (Barbell)", equipment: .barbell))
        #expect(matcher.match("Smith Machine Shrug") == .newCustom(name: "Smith Machine Shrug", equipment: .machine))
        #expect(matcher.match("Panca Piana (Bilanciere)") == .newCustom(name: "Panca Piana (Bilanciere)", equipment: .other))
        #expect(matcher.match("Running").needsLook)
    }

    @Test("Archived exercises match too and say so")
    func archived() {
        let match = matcher.match("Spider Curl")
        #expect(match == .matched(oldCurl, .exactName))
        #expect(match.candidate?.isArchived == true)
    }

    @Test("An active exercise wins over an archived one with the same name; stored over library")
    func preference() {
        let archived = ExerciseCandidate(reference: .stored(H.id(20)), name: "Leg Press", equipment: .machine, isArchived: true)
        let stored = ExerciseCandidate(reference: .stored(H.id(21)), name: "Leg Press", equipment: .machine, libraryKey: "Leg_Press")
        let matcher = ExerciseMatcher(candidates: [archived, legPress, stored])
        #expect(matcher.match("Leg Press") == .matched(stored, .exactName))
    }

    @Test("Candidates: stored exercises plus library entries the store lacks")
    func candidates() throws {
        let context = try makeInMemoryContext()
        let library = ExerciseLibrary(entries: [
            .init(key: "Leg_Press", name: "Leg Press", equipment: .machine, muscle: .quadriceps),
            .init(key: "Plank", name: "Plank", equipment: .bodyweight, muscle: .abdominals),
        ])
        let stored = Exercise(name: "Leg Press", equipment: .machine)
        stored.libraryKey = "Leg_Press"
        context.insert(stored)
        let all = ExerciseCandidate.all(exercises: [stored], library: library)
        #expect(all.map(\.reference) == [.stored(stored.id), .library("Plank")])
    }

    @Test("The built-in table points at library entries and adds names the library lacks")
    func builtInTable() throws {
        let library = try ExerciseLibrary.bundled()
        let table = ImportAliasTable.builtIn
        #expect(table.count >= 80)
        var known: Set<String> = []
        for entry in library.entries {
            known.insert(ExerciseMatcher.looseKey(entry.name))
            for alias in entry.aliases { known.insert(ExerciseMatcher.looseKey(alias)) }
        }
        for (name, key) in table {
            #expect(library.entry(forKey: key) != nil, "\(name) → \(key)")
            #expect(!known.contains(ExerciseMatcher.looseKey(name)), "\(name) is already known to the library")
        }
        #expect(Set(table.keys.map(ExerciseMatcher.looseKey)).count == table.count)
    }

    @Test("With the real library, common names from each app match", arguments: [
        ("Bench Press (Barbell)", "Bench Press"), ("Squat (Barbell)", "Squat"), ("Lat Pulldown (Cable)", "Lat Pulldown"),
        ("Flat Barbell Bench Press", "Bench Press"), ("Barbell Squat", "Squat"), ("Dumbbell Bench Press", "Dumbbell Bench Press"),
        ("Seated Cable Row - V Grip (Cable)", "Seated Cable Row"), ("Leg Extension (Machine)", "Leg Extension"),
        ("Back Squat", "Squat"), ("Triceps Rope Pushdown", "Rope Pushdown"), ("Hip Adduction (Machine)", "Hip Adduction"),
        ("Pull Up (Band)", "Assisted Pull-up"), ("Trap-Bar Deadlift", "Trap Bar Deadlift"), ("Dumbbell Bent Over Row", "Bent-Over Dumbbell Row"),
    ])
    func realLibrary(name: String, expected: String) throws {
        let library = try ExerciseLibrary.bundled()
        let matcher = ExerciseMatcher(candidates: ExerciseCandidate.all(exercises: [], library: library))
        let match = matcher.match(name)
        #expect(!match.needsLook)
        #expect(match.candidate?.name == expected)
    }

    @Test("Tokens fold plurals and common spellings")
    func tokens() {
        #expect(ExerciseMatcher.tokens("DB Curls") == ["dumbbell", "curl"])
        #expect(ExerciseMatcher.tokens("Pull Ups") == ["pullup"])
        #expect(ExerciseMatcher.tokens("Tricep Pressdown") == ExerciseMatcher.tokens("Triceps Pushdown"))
    }
}
