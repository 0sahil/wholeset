// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("History snapshot")
struct HistorySnapshotTests {
    /// A store with a finished session (warm-up, logged and unlogged sets, a skipped and a
    /// swapped entry), an older imported session and a session still running.
    private func makeStore() throws -> (ModelContainer, finished: Session, imported: Session) {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let bench = Exercise(name: "Bench Press")
        let fly = Exercise(name: "Cable Fly", equipment: .cable)
        let dbBench = Exercise(name: "Dumbbell Bench Press", equipment: .dumbbell)
        context.insertAll(bench, fly, dbBench)
        let routine = Routine(name: "Push")
        context.insert(routine)

        let finished = insertSession(startedAt: H.t0, name: "Push", entries: [
            (bench, [(40, 10, true), (60, 10, false), (60, 9, false)]),
            (fly, []),
            (dbBench, [(26, 10, false)]),
        ], in: context)
        finished.routine = routine
        finished.notes = "Felt strong"
        finished.avgHR = 128
        finished.maxHR = 161
        finished.activeKcal = 412
        let entries = finished.sortedEntries
        let slot = UUID()
        entries[0].routineItemID = slot
        entries[2].routineItemID = slot
        entries[1].routineItemID = UUID()
        entries[1].isSkipped = true
        // A planned set that was never logged.
        let planned = SetLog(order: 3, weightKg: 60, reps: 8)
        context.insert(planned)
        planned.entry = entries[0]

        let imported = insertSession(startedAt: H.t0.addingTimeInterval(-30 * H.day), name: "Old", entries: [
            (bench, [(55, 10, false)]),
        ], in: context)
        imported.source = .importStrong
        insertSession(startedAt: H.t0.addingTimeInterval(H.day), ended: false, name: "Running", entries: [(bench, [(70, 5, false)])], in: context)
        try context.save()
        return (container, finished, imported)
    }

    @Test func keepsOnlyFinishedSessionsAndLoggedSets() throws {
        let (container, finished, imported) = try makeStore()
        let sessions = try HistorySnapshot.load(in: ModelContext(container))
        #expect(sessions.map(\.id) == [imported.id, finished.id])
        let value = try #require(sessions.last)
        #expect(value.name == "Push")
        #expect(value.routineName == "Push")
        #expect(value.notes == "Felt strong")
        #expect(value.averageHeartRate == 128)
        #expect(value.maximumHeartRate == 161)
        #expect(value.activeKilocalories == 412)
        #expect(value.entries.map(\.exerciseName) == ["Bench Press", "Cable Fly", "Dumbbell Bench Press"])
        #expect(value.entries[0].sets.map(\.weightKg) == [40, 60, 60])
        #expect(value.entries[0].sets.map(\.isWarmup) == [true, false, false])
        #expect(value.entries[1].sets.isEmpty)
        #expect(value.entries[1].isSkipped)
        #expect(SessionDetail.notes(for: value.entries) == [nil, .skipped, .swappedIn])
        #expect(sessions.first?.isImported == true)
    }

    @Test func bulkLoadMatchesFollowingRelationships() throws {
        let (container, _, _) = try makeStore()
        let context = ModelContext(container)
        let loaded = try HistorySnapshot.load(in: context)
        let followed = HistorySnapshot.sessions(from: try context.fetch(FetchDescriptor<Session>()))
        #expect(loaded == followed)
    }

    @Test func emptyStoreHasNoHistory() throws {
        let context = try makeInMemoryContext()
        #expect(try HistorySnapshot.load(in: context).isEmpty)
    }

    @Test func orderTiesResolveByID() {
        let a = HistorySession(id: H.id(2), name: "A", startedAt: H.t0, endedAt: H.t0, entries: [])
        let b = HistorySession(id: H.id(1), name: "B", startedAt: H.t0, endedAt: H.t0, entries: [])
        let c = HistorySession(id: H.id(0), name: "C", startedAt: H.t0.addingTimeInterval(1), endedAt: H.t0, entries: [])
        #expect([c, a, b].sorted(by: HistorySnapshot.isEarlier).map(\.name) == ["B", "A", "C"])
    }

    @Test func indexLoadsOffTheCallersActor() async throws {
        let (container, finished, _) = try makeStore()
        let index = try await HistoryIndex.load(from: container)
        #expect(index.rows.map(\.id).first == finished.id)
        let detail = try #require(index.detail(forSession: finished.id))
        #expect(detail.sections.map(\.note) == [nil, .skipped, .swappedIn])
        #expect(index.progress.values.contains { $0.sessionCount == 2 })
        #expect(index.detail(forSession: UUID()) == nil)
        #expect(HistoryIndex.empty.rows.isEmpty)
    }

    /// Guards the cost of the index without timing it: a store of several hundred sessions is
    /// read whole, and records visit each logged working set exactly once (no per-session
    /// re-reads, nothing quadratic), with planned sets and warm-ups left out.
    @Test func aStoreOfSeveralHundredSessionsIsIndexedInOnePass() async throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let exercises = (0..<5).map { Exercise(name: "Exercise \($0)") }
        exercises.forEach(context.insert)
        let sessionCount = 250
        for index in 0..<sessionCount {
            let weight = 40 + Double(index) * 0.25
            let session = insertSession(
                startedAt: H.t0.addingTimeInterval(Double(index) * 2 * H.day),
                entries: exercises.map { ($0, [(20, 10, true), (weight, 8, false), (weight, 8, false), (weight, 7, false)]) },
                in: context
            )
            // A planned set that was never logged, on every exercise.
            for entry in session.sortedEntries {
                let planned = SetLog(order: 4, weightKg: weight, reps: 8)
                context.insert(planned)
                planned.entry = entry
            }
        }
        try context.save()

        let snapshot = try HistorySnapshot.load(in: ModelContext(container))
        #expect(snapshot.count == sessionCount)
        #expect(snapshot.allSatisfy { $0.entries.count == 5 && $0.entries.allSatisfy { $0.sets.count == 4 } })
        var statistics = PersonalRecords.Statistics()
        _ = PersonalRecords.compute(from: snapshot, statistics: &statistics)
        #expect(statistics.sessions == sessionCount)
        #expect(statistics.setVisits == sessionCount * 5 * 3)

        let index = try await HistoryIndex.load(from: container)
        #expect(index.rows.count == sessionCount)
        #expect(index.progress.count == 5)
        #expect(index.progress.values.allSatisfy { $0.sessionCount == sessionCount })
    }

    @Test func indexSeesWhatWasSavedSinceTheLastLoad() async throws {
        let (container, finished, _) = try makeStore()
        let before = try await HistoryIndex.load(from: container)
        #expect(before.session(id: finished.id) != nil)
        let context = ModelContext(container)
        #expect(try SessionEditing.deleteSession(id: finished.id, in: context))
        try context.save()
        let after = try await HistoryIndex.load(from: container)
        #expect(after.session(id: finished.id) == nil)
        #expect(after.rows.count == before.rows.count - 1)
    }
}
