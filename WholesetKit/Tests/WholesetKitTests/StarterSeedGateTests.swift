// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Starter seed gate")
struct StarterSeedGateTests {
    @Test func withoutCloudKitNothingCanArrive() {
        for mode in [WholesetStore.Mode.local, .inMemory] {
            #expect(StarterSeedGate.readiness(storeMode: mode, account: .available, firstImportFinished: false, waitedLongEnough: false) == .noCloudSync)
        }
    }

    @Test func signedOutOrRestrictedAccountsCannotSync() {
        for account in [CloudAccountStatus.noAccount, .restricted] {
            #expect(StarterSeedGate.readiness(storeMode: .cloudKit, account: account, firstImportFinished: false, waitedLongEnough: false) == .noCloudSync)
        }
    }

    @Test func aSyncingDeviceWaitsForItsFirstImport() {
        for account in [CloudAccountStatus.available, .couldNotDetermine, .temporarilyUnavailable, nil] {
            #expect(StarterSeedGate.readiness(storeMode: .cloudKit, account: account, firstImportFinished: false, waitedLongEnough: false) == .waitingForFirstImport)
            #expect(StarterSeedGate.readiness(storeMode: .cloudKit, account: account, firstImportFinished: true, waitedLongEnough: false) == .firstImportFinished)
            #expect(StarterSeedGate.readiness(storeMode: .cloudKit, account: account, firstImportFinished: false, waitedLongEnough: true) == .gaveUpWaiting)
        }
    }

    @Test func seedsOnlyAnUndecidedEmptyStoreOnceReady() {
        let ready: [StarterSeedGate.Readiness] = [.noCloudSync, .firstImportFinished, .gaveUpWaiting]
        for readiness in ready {
            #expect(StarterSeedGate.shouldSeed(decidedAt: nil, routineCount: 0, readiness: readiness))
            #expect(!StarterSeedGate.shouldSeed(decidedAt: .now, routineCount: 0, readiness: readiness))
            #expect(!StarterSeedGate.shouldSeed(decidedAt: nil, routineCount: 1, readiness: readiness))
            #expect(!StarterSeedGate.isWaiting(decidedAt: nil, routineCount: 0, readiness: readiness))
        }
        #expect(!StarterSeedGate.shouldSeed(decidedAt: nil, routineCount: 0, readiness: .waitingForFirstImport))
        #expect(StarterSeedGate.isWaiting(decidedAt: nil, routineCount: 0, readiness: .waitingForFirstImport))
        #expect(!StarterSeedGate.isWaiting(decidedAt: nil, routineCount: 2, readiness: .waitingForFirstImport))
    }

    @Test func patienceIsShortEnoughForTheGym() {
        #expect(StarterSeedGate.patience <= .seconds(60))
        #expect(StarterSeedGate.patience >= .seconds(10))
    }
}
