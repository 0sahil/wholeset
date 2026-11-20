// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import HealthKit
import SwiftData
import Testing
@testable import WholesetKit

/// Stands in for the Watch's workout state in coordinator tests.
@MainActor
private final class FakeWatch {
    var isInWorkout = true
    var notifications = 0
}

@Suite("Sync status and coordination")
struct SyncTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ kind: SyncEvent.Kind, id: UUID = UUID(), start: TimeInterval, end: TimeInterval?, ok: Bool = true, error: String? = nil) -> SyncEvent {
        SyncEvent(
            id: id,
            kind: kind,
            startDate: t0.addingTimeInterval(start),
            endDate: end.map { t0.addingTimeInterval($0) },
            succeeded: ok,
            errorDescription: error
        )
    }

    // MARK: Activity

    @Test func recordsStartsAndEndsOfMirroringWork() {
        var activity = SyncActivity()
        let id = UUID()
        let started = activity.record(event(.import, id: id, start: 0, end: nil))
        #expect(!started)
        #expect(activity.isRunning)
        let imported = activity.record(event(.import, id: id, start: 0, end: 2))
        #expect(imported)
        #expect(!activity.isRunning)
        #expect(activity.importsFinished == 1)
        let exported = activity.record(event(.export, start: 3, end: 4))
        #expect(!exported)
        #expect(activity.lastTransfer?.kind == .export)
        #expect(activity.lastImport?.endDate == t0.addingTimeInterval(2))
    }

    // MARK: Summary

    @Test func storesWithoutCloudKitAreOff() {
        #expect(SyncStatus.summarize(mode: .local, account: .available, activity: SyncActivity()) == .off(.local))
        #expect(SyncStatus.summarize(mode: .inMemory, account: nil, activity: SyncActivity()) == .off(.inMemory))
    }

    @Test func buildsWithoutICloudSayItIsOffByDesign() {
        #expect(SyncStatus.summarize(mode: .local, account: nil, activity: SyncActivity(), iCloudEnabledInBuild: false) == .offInThisBuild)
        // A store that could only be opened in memory is the more urgent message.
        #expect(SyncStatus.summarize(mode: .inMemory, account: nil, activity: SyncActivity(), iCloudEnabledInBuild: false) == .off(.inMemory))
        #expect(SyncStatus.summarize(mode: .local, account: nil, activity: SyncActivity(), iCloudEnabledInBuild: true) == .off(.local))
    }

    @MainActor
    @Test func monitorOfABuildWithoutICloudNeverChecksTheAccount() async {
        let monitor = SyncMonitor(mode: .local, iCloudEnabledInBuild: false)
        monitor.start()
        await monitor.accountRefresh?.value
        #expect(monitor.account == nil)
        #expect(monitor.status == .offInThisBuild)
    }

    @MainActor
    @Test func monitorDefaultsToTheRunningAppsConfiguration() {
        // Package tests have no Info.plist keys, so the shipped default (iCloud on) applies.
        #expect(SyncMonitor(mode: .local).iCloudEnabledInBuild)
        #expect(SyncMonitor(mode: .local).status == .off(.local))
    }

    @Test func accountProblemsComeFirst() {
        #expect(SyncStatus.summarize(mode: .cloudKit, account: nil, activity: SyncActivity()) == .checkingAccount)
        #expect(SyncStatus.summarize(mode: .cloudKit, account: .noAccount, activity: SyncActivity()) == .accountUnavailable(.noAccount))
    }

    @Test func reportsSyncingFailureAndSuccess() {
        var activity = SyncActivity()
        #expect(SyncStatus.summarize(mode: .cloudKit, account: .available, activity: activity) == .waiting)
        let id = UUID()
        activity.record(event(.export, id: id, start: 0, end: nil))
        #expect(SyncStatus.summarize(mode: .cloudKit, account: .available, activity: activity) == .syncing)
        activity.record(event(.export, id: id, start: 0, end: 1, ok: false, error: "Network unavailable"))
        #expect(SyncStatus.summarize(mode: .cloudKit, account: .available, activity: activity) == .failed(at: t0.addingTimeInterval(1), message: "Network unavailable"))
        activity.record(event(.import, start: 5, end: 6))
        #expect(SyncStatus.summarize(mode: .cloudKit, account: .available, activity: activity) == .upToDate(at: t0.addingTimeInterval(6)))
    }

    // MARK: Debounce

    @MainActor
    @Test func debouncerRunsOnlyTheLastScheduledAction() async throws {
        let debouncer = Debouncer(delay: .milliseconds(20))
        var runs: [Int] = []
        debouncer.schedule { runs.append(1) }
        let replaced = try #require(debouncer.pending)
        debouncer.schedule { runs.append(2) }
        await replaced.value
        await debouncer.pending?.value
        #expect(runs == [2])

        debouncer.schedule { runs.append(3) }
        let cancelled = try #require(debouncer.pending)
        debouncer.cancel()
        #expect(debouncer.pending == nil)
        await cancelled.value
        #expect(runs == [2])
    }

    // MARK: Coordinator

    @MainActor
    @Test func aDeviceWithoutCloudKitSeedsAtLaunch() throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let coordinator = StoreCoordinator(container: container, sync: SyncMonitor(mode: .inMemory), policy: .automatic)
        coordinator.start()
        #expect(coordinator.lastReport?.startersSeeded == true)
        #expect(!coordinator.isWaitingForStarterDecision)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Routine>()) == 3)
    }

    @MainActor
    @Test func theIPhoneNeverSeedsOnItsOwn() throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let coordinator = StoreCoordinator(container: container, sync: SyncMonitor(mode: .inMemory), policy: .manual)
        coordinator.start()
        #expect(coordinator.lastReport?.startersSeeded == false)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Routine>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Exercise>()) > 100)
    }

    @MainActor
    @Test func aSyncingWatchWaitsForItsFirstImportThenSeeds() async throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        // The store is in memory, but the monitor is told CloudKit is on with a signed-in account.
        let sync = SyncMonitor(mode: .cloudKit) { .available }
        let coordinator = StoreCoordinator(
            container: container,
            sync: sync,
            policy: .automatic,
            debounce: .milliseconds(20),
            patience: .seconds(60)
        )
        coordinator.start()
        await sync.accountRefresh?.value
        #expect(sync.account == .available)
        #expect(coordinator.isWaitingForStarterDecision)
        #expect(coordinator.isWaitingForFirstImport)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Routine>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Exercise>()) == 0)

        sync.record(SyncEvent(id: UUID(), kind: .import, startDate: .now, endDate: .now, succeeded: true))
        await coordinator.pendingMaintenance?.value

        #expect(!coordinator.isWaitingForStarterDecision)
        #expect(!coordinator.isWaitingForFirstImport)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Routine>()) == 3)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Exercise>()) > 100)
    }

    @MainActor
    @Test func theIPhoneWaitsForItsFirstImportBeforeAddingTheLibrary() async throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let sync = SyncMonitor(mode: .cloudKit) { .available }
        let coordinator = StoreCoordinator(container: container, sync: sync, policy: .manual, debounce: .milliseconds(20), patience: .seconds(60))
        coordinator.start()
        await sync.accountRefresh?.value
        #expect(coordinator.isWaitingForFirstImport)
        #expect(!coordinator.isWaitingForStarterDecision)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Exercise>()) == 0)

        sync.record(SyncEvent(id: UUID(), kind: .import, startDate: .now, endDate: .now, succeeded: false, errorDescription: "Offline"))
        await coordinator.pendingMaintenance?.value

        #expect(!coordinator.isWaitingForFirstImport)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Exercise>()) > 100)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Routine>()) == 0)
    }

    /// An import that finished before the coordinator started (what the DEBUG demo records)
    /// counts: the library is added by the launch pass, with no wait for the patience timer.
    @MainActor
    @Test func anImportRecordedBeforeStartAddsTheLibraryAtLaunch() throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let sync = SyncMonitor(mode: .cloudKit) { .available }
        sync.record(SyncEvent(id: UUID(), kind: .import, startDate: .now, endDate: .now, succeeded: true))
        let coordinator = StoreCoordinator(container: container, sync: sync, policy: .manual, patience: .seconds(60))
        coordinator.start()
        #expect(!coordinator.isWaitingForFirstImport)
        #expect(coordinator.patienceWait == nil)
        let names = Set(try container.mainContext.fetch(FetchDescriptor<Exercise>()).map(\.name))
        #expect(names.count > 100)
        #expect(names.isSuperset(of: ["Arnold Press", "Dumbbell Shoulder Press", "Hammer Curl"]))
    }

    @MainActor
    @Test func mergesWaitWhileTheWatchIsInAWorkout() async throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let sync = SyncMonitor(mode: .inMemory)
        let coordinator = StoreCoordinator(container: container, sync: sync, policy: .automatic, debounce: .milliseconds(20))
        let watch = FakeWatch()
        coordinator.defersMaintenance = { watch.isInWorkout }
        coordinator.onMaintenance = { watch.notifications += 1 }
        coordinator.start()
        let launchReport = coordinator.lastReport

        #expect(watch.notifications == 1)

        sync.record(SyncEvent(id: UUID(), kind: .import, startDate: .now, endDate: .now, succeeded: true))
        await coordinator.pendingMaintenance?.value
        #expect(coordinator.lastReport == launchReport)
        #expect(watch.notifications == 2)

        watch.isInWorkout = false
        coordinator.resumeDeferredMaintenance()
        await coordinator.pendingMaintenance?.value
        #expect(watch.notifications == 3)
        #expect(coordinator.lastReport == MaintenanceReport())
    }

    @MainActor
    @Test func aWatchThatCannotReachICloudSeedsAfterItsPatienceRunsOut() async throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let coordinator = StoreCoordinator(
            container: container,
            sync: SyncMonitor(mode: .cloudKit) { .available },
            policy: .automatic,
            patience: .milliseconds(50)
        )
        coordinator.start()
        #expect(coordinator.isWaitingForStarterDecision)
        await coordinator.sync.accountRefresh?.value
        await coordinator.patienceWait?.value
        #expect(!coordinator.isWaitingForStarterDecision)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Routine>()) == 3)
    }

    @MainActor
    @Test func aSignedOutAccountStopsTheWait() async throws {
        let container = try WholesetStore.makeContainer(inMemory: true)
        let coordinator = StoreCoordinator(
            container: container,
            sync: SyncMonitor(mode: .cloudKit) { .noAccount },
            policy: .automatic,
            patience: .seconds(60)
        )
        coordinator.start()
        #expect(coordinator.isWaitingForStarterDecision)
        await coordinator.sync.accountRefresh?.value
        #expect(coordinator.sync.account == .noAccount)
        #expect(!coordinator.isWaitingForStarterDecision)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Routine>()) == 3)
    }

    // MARK: Health

    @Test func healthTypesMatchWhatTheWorkoutSaves() {
        #expect(HealthAccess.shareTypes.contains(HKObjectType.workoutType()))
        #expect(HealthAccess.shareTypes.contains(HKQuantityType(.heartRate)))
        #expect(HealthAccess.shareTypes.contains(HKQuantityType(.activeEnergyBurned)))
        #expect(HealthAccess.readTypes == [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)])
    }
}
