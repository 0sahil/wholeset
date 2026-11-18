// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Workout recovery")
struct WorkoutRecoveryTests {
    private func insertSession(
        startedAt: TimeInterval,
        source: Source = .watch,
        ended: Bool = false,
        loggedAt: [TimeInterval] = [],
        in context: ModelContext
    ) -> Session {
        let session = Session(name: "S\(Int(startedAt))", startedAt: Date(timeIntervalSince1970: startedAt), source: source)
        context.insert(session)
        if ended { session.endedAt = Date(timeIntervalSince1970: startedAt + 3600) }
        let entry = SessionExercise(order: 0)
        context.insert(entry)
        entry.session = session
        for (index, time) in loggedAt.enumerated() {
            let set = SetLog(order: index, weightKg: 50, reps: 5)
            context.insert(set)
            set.entry = entry
            set.completedAt = Date(timeIntervalSince1970: time)
        }
        return session
    }

    @Test func findsOnlyUnfinishedWatchSessionsNewestFirst() throws {
        let context = try makeInMemoryContext()
        let older = insertSession(startedAt: 100, in: context)
        let newer = insertSession(startedAt: 200, in: context)
        _ = insertSession(startedAt: 300, ended: true, in: context)
        _ = insertSession(startedAt: 400, source: .phone, in: context)
        _ = insertSession(startedAt: 500, source: .importHevy, in: context)
        try context.save()
        let found = try WorkoutRecovery.inProgressWatchSessions(in: context)
        #expect(found.map(\.id) == [newer.id, older.id])
    }

    @Test func noSessionToRecover() throws {
        let context = try makeInMemoryContext()
        _ = insertSession(startedAt: 100, ended: true, in: context)
        try context.save()
        #expect(try WorkoutRecovery.resolveInProgressSession(in: context) == nil)
    }

    @Test func keepsNewestAndClosesOrDeletesOlderOnes() throws {
        let context = try makeInMemoryContext()
        let withSets = insertSession(startedAt: 100, loggedAt: [150, 180], in: context)
        let empty = insertSession(startedAt: 200, in: context)
        let newest = insertSession(startedAt: 300, loggedAt: [320], in: context)
        let emptyID = empty.id
        try context.save()

        let recovered = try WorkoutRecovery.resolveInProgressSession(in: context)

        #expect(recovered === newest)
        #expect(newest.endedAt == nil)
        #expect(withSets.endedAt == Date(timeIntervalSince1970: 180))
        #expect(!context.hasChanges)
        let remaining = try context.all(Session.self).map(\.id)
        #expect(!remaining.contains(emptyID))
        #expect(remaining.count == 2)
        #expect(try WorkoutRecovery.inProgressWatchSessions(in: context).map(\.id) == [newest.id])
    }

    @Test func lastLoggedDate() throws {
        let context = try makeInMemoryContext()
        let session = insertSession(startedAt: 0, loggedAt: [30, 90, 60], in: context)
        #expect(WorkoutRecovery.lastLoggedDate(in: session) == Date(timeIntervalSince1970: 90))
        let none = insertSession(startedAt: 0, in: context)
        #expect(WorkoutRecovery.lastLoggedDate(in: none) == nil)
    }

    @Test func healthKitMetadataKeys() {
        #expect(HealthKitMetadataKey.routineName == "wholeset.routine")
        #expect(HealthKitMetadataKey.sessionID == "wholeset.sessionID")
    }

    @Test func applyingHealthSummaryKeepsMissingValues() throws {
        let context = try makeInMemoryContext()
        let session = insertSession(startedAt: 0, in: context)
        session.maxHR = 170
        let workoutID = UUID()
        session.apply(HealthWorkoutSummary(workoutID: workoutID, averageHeartRate: 128, activeKilocalories: 410))
        #expect(session.healthKitWorkoutID == workoutID)
        #expect(session.avgHR == 128)
        #expect(session.maxHR == 170)
        #expect(session.activeKcal == 410)
    }
}

@Suite("Active workout state store")
struct ActiveWorkoutStateStoreTests {
    private func makeStore() throws -> (ActiveWorkoutStateStore, UserDefaults) {
        let suite = "WholesetKitTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (ActiveWorkoutStateStore(defaults: defaults), defaults)
    }

    @Test func savesAndLoadsForTheSameSession() throws {
        let (store, _) = try makeStore()
        let sessionID = UUID()
        var clock = WorkoutClock(startedAt: Date(timeIntervalSince1970: 1000))
        clock.pause(at: Date(timeIntervalSince1970: 1100))
        let state = ActiveWorkoutState(
            sessionID: sessionID,
            clock: clock,
            rest: RestTimer.start(duration: 90, now: Date(timeIntervalSince1970: 1050)),
            currentEntryID: UUID()
        )
        store.save(state)
        #expect(store.load(sessionID: sessionID) == state)
        #expect(store.load(sessionID: UUID()) == nil)
        store.clear()
        #expect(store.load(sessionID: sessionID) == nil)
    }

    @Test func ignoresUndecodableData() throws {
        let (store, defaults) = try makeStore()
        defaults.set(Data("nope".utf8), forKey: ActiveWorkoutStateStore.defaultKey)
        #expect(store.load(sessionID: UUID()) == nil)
    }
}
