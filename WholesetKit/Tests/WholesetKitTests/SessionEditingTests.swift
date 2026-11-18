// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Typed set values")
struct SetInputTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    @Test func weightIsOptionalAndLocaleAware() {
        #expect(SetInput.weightKilograms(from: "", unit: .kg, locale: english) == .success(nil))
        #expect(SetInput.weightKilograms(from: "  ", unit: .kg, locale: english) == .success(nil))
        #expect(SetInput.weightKilograms(from: "62,5", unit: .kg, locale: english) == .success(62.5))
        #expect(SetInput.weightKilograms(from: "62.5", unit: .kg, locale: german) == .success(62.5))
        #expect(SetInput.weightKilograms(from: "0", unit: .kg, locale: english) == .success(0))
        #expect(SetInput.weightKilograms(from: "-0", unit: .kg, locale: english) == .success(0))
        #expect(SetInput.weightKilograms(from: "62.555", unit: .kg, locale: english) == .success(62.56))
    }

    @Test func weightLimits() {
        #expect(SetInput.weightKilograms(from: "1000", unit: .kg, locale: english) == .success(1_000))
        #expect(SetInput.weightKilograms(from: "1000.01", unit: .kg, locale: english) == .failure(.tooHeavy))
        #expect(SetInput.maximumWeight(in: .lb) == 2_204.62)
        #expect(SetInput.weightKilograms(from: "2204.63", unit: .lb, locale: english) == .failure(.tooHeavy))
        #expect(SetInput.weightKilograms(from: "-1", unit: .kg, locale: english) == .failure(.negative))
        #expect(SetInput.weightKilograms(from: "6O", unit: .kg, locale: english) == .failure(.notANumber))
        #expect(SetInput.weightKilograms(from: "1,000.5", unit: .kg, locale: english) == .failure(.notANumber))
    }

    @Test func repsAreRequiredWholeNumbers() {
        #expect(SetInput.reps(from: "10") == .success(10))
        #expect(SetInput.reps(from: " 999 ") == .success(999))
        #expect(SetInput.reps(from: "\u{0661}\u{0662}") == .success(12))
        #expect(SetInput.reps(from: "") == .failure(.empty))
        #expect(SetInput.reps(from: "0") == .failure(.outOfRange))
        #expect(SetInput.reps(from: "1000") == .failure(.outOfRange))
        #expect(SetInput.reps(from: "99999999999999") == .failure(.notANumber))
        #expect(SetInput.reps(from: "8.5") == .failure(.notANumber))
        #expect(SetInput.reps(from: "-3") == .failure(.notANumber))
    }

    @Test(arguments: ["135", "132.5", "102.55", "45", "0.5", "2204.62"])
    func poundsReadBackAsTyped(text: String) throws {
        let kilograms = try #require(try SetInput.weightKilograms(from: text, unit: .lb, locale: english).get())
        #expect(SetInput.weightText(kilograms: kilograms, unit: .lb, locale: english) == text)
        #expect(WeightFormat.preciseString(kilograms: kilograms, unit: .lb, locale: english) == text)
    }

    @Test func storedWeightsAsText() {
        #expect(SetInput.weightText(kilograms: 62.5, unit: .kg, locale: english) == "62.5")
        #expect(SetInput.weightText(kilograms: 62.5, unit: .kg, locale: german) == "62,5")
        #expect(SetInput.weightText(kilograms: 60, unit: .lb, locale: english) == "132.28")
        #expect(SetInput.weightText(kilograms: 1_234, unit: .kg, locale: english) == "1234")
        #expect(SetInput.weightText(kilograms: nil, unit: .kg, locale: english) == "")
        #expect(SetInput.repsText(8) == "8")
        #expect(SetInput.repsText(nil) == "")
        #expect(WeightFormat.preciseStringWithUnit(kilograms: 62.5, unit: .kg, locale: english) == "62.5 kg")
    }
}

@Suite("Editing a past session")
struct SessionEditingTests {
    private let english = Locale(identifier: "en_US")
    private let t1 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A finished session: bench (warm-up + 2 working sets logged, 1 planned) and a row
    /// (1 logged, 1 planned). Every `updatedAt` is set to ``H/t0``.
    private func makeSession() throws -> (ModelContext, Session) {
        let context = try makeInMemoryContext()
        let bench = Exercise(name: "Bench Press")
        let row = Exercise(name: "Barbell Row")
        context.insertAll(bench, row)
        let session = insertSession(startedAt: H.t0, entries: [
            (bench, [(40, 10, true), (60, 10, false), (60, 9, false)]),
            (row, [(50, 10, false)]),
        ], in: context)
        session.notes = "Old note"
        for (entry, order) in zip(session.sortedEntries, [3, 1]) {
            let planned = SetLog(order: order, weightKg: 60, reps: 8)
            context.insert(planned)
            planned.entry = entry
        }
        try context.save()
        session.updatedAt = H.t0
        for entry in session.entries ?? [] {
            entry.updatedAt = H.t0
            for set in entry.sets ?? [] { set.updatedAt = H.t0 }
        }
        try context.save()
        return (context, session)
    }

    private func allUpdatedAt(_ session: Session) -> [Date] {
        [session.updatedAt] + (session.entries ?? []).flatMap { [$0.updatedAt] + ($0.sets ?? []).map(\.updatedAt) }
    }

    @Test func draftListsLoggedSetsOnly() throws {
        let (_, session) = try makeSession()
        let draft = SessionDraft(session: session, unit: .kg, locale: english)
        #expect(draft.entries.map(\.exerciseName) == ["Bench Press", "Barbell Row"])
        #expect(draft.entries[0].sets.map(\.weightText) == ["40", "60", "60"])
        #expect(draft.entries[0].sets.map(\.repsText) == ["10", "10", "9"])
        #expect(draft.entries[0].sets.map { draft.entries[0].number(ofSet: $0.id) } == [nil, 1, 2])
        #expect(draft.notes == "Old note")
        #expect(!draft.hasChanges)
        #expect(draft.canSave)
    }

    @Test func unchangedApplyChangesNothing() throws {
        let (context, session) = try makeSession()
        let before = allUpdatedAt(session)
        let draft = SessionDraft(session: session, unit: .lb, locale: english)
        #expect(try draft.apply(in: context, now: t1) == false)
        #expect(allUpdatedAt(session) == before)
        #expect(!context.hasChanges)
    }

    @Test func cancelledDraftLeavesTheSessionAlone() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .kg, locale: english)
        let id = draft.entries[0].sets[1].id
        draft.setWeightText("100", forSet: id)
        draft.notes = "Changed"
        #expect(draft.hasChanges)
        // Never applied: the store is untouched.
        #expect(session.notes == "Old note")
        #expect(!context.hasChanges)
    }

    @Test func appliesChangedValuesAndTouchesOnlyThem() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .kg, locale: english)
        let warmup = draft.entries[0].sets[0].id
        let second = draft.entries[0].sets[2].id
        draft.setWeightText("62,5", forSet: second)
        draft.setRepsText("8", forSet: second)
        draft.setWarmup(false, forSet: warmup)
        #expect(try draft.apply(in: context, now: t1))
        try context.save()

        let sets = session.sortedEntries[0].sortedSets
        #expect(sets[2].weightKg == 62.5)
        #expect(sets[2].reps == 8)
        #expect(sets[2].updatedAt == t1)
        #expect(!sets[0].isWarmup)
        #expect(sets[0].updatedAt == t1)
        #expect(sets[1].updatedAt == H.t0)
        #expect(session.updatedAt == t1)
        #expect(session.sortedEntries[0].updatedAt == H.t0)
        #expect(session.sortedEntries[1].sortedSets.allSatisfy { $0.updatedAt == H.t0 })
        #expect(session.notes == "Old note")
    }

    @Test func untouchedPoundWeightsKeepTheirExactKilograms() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .lb, locale: english)
        // 60 kg shows as 132.28 lb; changing only the reps must not turn it into 60.0003 kg.
        let id = draft.entries[0].sets[1].id
        draft.setRepsText("11", forSet: id)
        try draft.apply(in: context, now: t1)
        #expect(session.sortedEntries[0].sortedSets[1].weightKg == 60)
        #expect(session.sortedEntries[0].sortedSets[1].reps == 11)
    }

    @Test func typedPoundsReadBackAsTyped() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .lb, locale: english)
        let id = draft.entries[0].sets[1].id
        draft.setWeightText("135", forSet: id)
        try draft.apply(in: context, now: t1)
        try context.save()
        let reopened = SessionDraft(session: session, unit: .lb, locale: english)
        #expect(reopened.set(id: id)?.weightText == "135")
        #expect(abs((session.sortedEntries[0].sortedSets[1].weightKg ?? 0) - 61.234_969_95) < 1e-6)
    }

    @Test func notesAreSaved() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .kg, locale: english)
        draft.notes = "New note"
        #expect(try draft.apply(in: context, now: t1))
        #expect(session.notes == "New note")
        #expect(session.updatedAt == t1)
        #expect(session.sortedEntries.allSatisfy { $0.updatedAt == H.t0 })
    }

    @Test func deletingASetRenumbersTheRest() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .kg, locale: english)
        let first = draft.entries[0].sets[1].id
        draft.deleteSet(id: first)
        try draft.apply(in: context, now: t1)
        try context.save()
        let entry = session.sortedEntries[0]
        let sets = entry.sortedSets
        #expect(sets.map(\.order) == [0, 1, 2])
        #expect(sets.map(\.reps) == [10, 9, 8])
        #expect(sets.last?.completedAt == nil)
        #expect(!sets.contains { $0.id == first })
        #expect(entry.updatedAt == t1)
        #expect(sets[0].updatedAt == H.t0)
        #expect(try context.count(SetLog.self) == 5)
    }

    @Test func deletingTheLastLoggedSetRemovesTheExercise() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .kg, locale: english)
        let rowEntry = draft.entries[1]
        draft.deleteSets(atOffsets: IndexSet(integer: 0), inEntry: rowEntry.id)
        #expect(draft.entries[1].sets.isEmpty)
        try draft.apply(in: context, now: t1)
        try context.save()
        #expect(session.sortedEntries.map { $0.exercise?.name } == ["Bench Press"])
        // The row's planned set went with it.
        #expect(try context.count(SessionExercise.self) == 1)
        #expect(try context.count(SetLog.self) == 4)
        #expect(session.updatedAt == t1)
    }

    @Test func addedSetsFollowTheLastLoggedSet() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .kg, locale: english)
        let entryID = draft.entries[0].id
        let addedID = draft.addSet(toEntry: entryID)
        let added = try #require(addedID)
        #expect(draft.set(id: added)?.weightText == "60")
        #expect(draft.set(id: added)?.repsText == "9")
        #expect(draft.entries[0].number(ofSet: added) == 3)
        let anotherID = draft.addSet(toEntry: entryID)
        let another = try #require(anotherID)
        draft.setRepsText("7", forSet: another)
        try draft.apply(in: context, now: t1)
        try context.save()

        let entry = session.sortedEntries[0]
        let sets = entry.sortedSets
        #expect(sets.map(\.order) == [0, 1, 2, 3, 4, 5])
        #expect(sets.map(\.reps) == [10, 10, 9, 9, 7, 8])
        let lastLogged = sets[2].completedAt
        #expect(sets[3].completedAt == lastLogged)
        #expect(sets[4].completedAt == lastLogged)
        #expect(sets[5].completedAt == nil)
        #expect(sets[3].updatedAt == t1)
        #expect(sets[5].updatedAt == t1) // the planned set moved from 3 to 5
        #expect(entry.updatedAt == t1)
        // Logged at the same moment as the set before: no rest is shown for it.
        let value = try #require(HistorySnapshot.session(from: session))
        #expect(SessionMetrics.restBefore(value.entries[0].sets).suffix(2) == [nil, nil])
    }

    @Test func setsAddedToAnEmptiedExerciseUseTheEndTime() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .kg, locale: english)
        let rowEntry = draft.entries[1].id
        draft.deleteSet(id: draft.entries[1].sets[0].id)
        let addedID = draft.addSet(toEntry: rowEntry)
        let added = try #require(addedID)
        draft.setWeightText("55", forSet: added)
        draft.setRepsText("10", forSet: added)
        try draft.apply(in: context, now: t1)
        try context.save()
        let sets = session.sortedEntries[1].sortedSets
        #expect(sets.count == 2)
        #expect(sets[0].weightKg == 55)
        #expect(sets[0].completedAt == session.endedAt)
        #expect(sets[1].completedAt == nil)
    }

    @Test func invalidFieldsBlockDone() throws {
        let (context, session) = try makeSession()
        var draft = SessionDraft(session: session, unit: .kg, locale: english)
        let id = draft.entries[0].sets[1].id
        draft.setRepsText("", forSet: id)
        #expect(draft.repsProblem(forSet: id) == .empty)
        #expect(!draft.canSave)
        draft.setRepsText("12", forSet: id)
        draft.setWeightText("abc", forSet: id)
        #expect(draft.weightProblem(forSet: id) == .notANumber)
        #expect(!draft.canSave)
        #expect(throws: SessionDraft.ApplyError.invalid) { try draft.apply(in: context, now: t1) }
        draft.setWeightText("", forSet: id)
        #expect(draft.weightProblem(forSet: id) == nil)
        #expect(draft.canSave)
        try draft.apply(in: context, now: t1)
        #expect(session.sortedEntries[0].sortedSets[1].weightKg == nil)
    }

    @Test func missingSessionIsReported() throws {
        let (context, session) = try makeSession()
        let draft = SessionDraft(session: session, unit: .kg, locale: english)
        SessionEditing.delete(session, in: context)
        try context.save()
        #expect(throws: SessionDraft.ApplyError.sessionMissing) { try draft.apply(in: context, now: t1) }
    }

    @Test func deletingASessionCascades() throws {
        let (context, session) = try makeSession()
        let other = insertSession(startedAt: H.t0.addingTimeInterval(H.day), entries: [], in: context)
        try context.save()
        #expect(try SessionEditing.deleteSession(id: session.id, in: context))
        try context.save()
        #expect(try context.all(Session.self).map(\.id) == [other.id])
        #expect(try context.count(SessionExercise.self) == 0)
        #expect(try context.count(SetLog.self) == 0)
        #expect(try context.count(Exercise.self) == 2)
        #expect(try SessionEditing.deleteSession(id: UUID(), in: context) == false)
    }

    @Test func recordsFollowEdits() throws {
        let (context, session) = try makeSession()
        let bench = try exercise(named: "Bench Press", in: context)
        insertSession(startedAt: H.t0.addingTimeInterval(-H.day), entries: [(bench, [(55, 10, false)])], in: context)
        try context.save()
        var index = HistoryIndex(sessions: try HistorySnapshot.load(in: context))
        #expect(index.records.count(forSession: session.id) == 3)

        var draft = SessionDraft(session: session, unit: .kg, locale: english)
        // 20 kg × 19 reps is below the earlier 55 kg × 10 on every count.
        for set in draft.entries[0].sets where !set.isWarmup {
            draft.setWeightText("20", forSet: set.id)
        }
        try draft.apply(in: context, now: t1)
        try context.save()
        index = HistoryIndex(sessions: try HistorySnapshot.load(in: context))
        #expect(index.records.count(forSession: session.id) == 0)
        #expect(index.records.records(forExercise: bench.id)?.heaviest?.weightKg == 55)
    }
}
